#!/bin/bash
set -e

# if command starts with an option, prepend qpidd
if [ "${1:0:1}" = '-' ]; then
    set -- qdrouterd "$@"
fi

if [ "$1" = "qpidd" ]; then
    sasl_external=0
    sasl_plain=0
    have_ssl=0
    have_acl=0
    have_sasl=0
    have_store=0
    have_paging=0
    have_sslnodict=0

    have_config=0

    # Home dir
    if [ -z "$QDROUTERD_HOME" ]; then
        QDROUTERD_HOME="/var/lib/qdrouterd"
    fi

    if [ ! -d "$QDROUTERD_HOME" ]; then
        mkdir -p "$QDROUTERD_HOME"
        chown -R qdrouterd:qdrouterd "$QDROUTERD_HOME"
    fi

    #####
    # If SASL database already exists, change the password only when it was provided from outside.
    # If it doesn't exist, create it either with password from env or with default password
    #####
    if [ -z "$QDROUTERD_SASL_DB"]; then
        QDROUTERD_SASL_DB="$QDROUTERD_HOME/etc/sasl/qpidd.sasldb"
    fi
    
    mkdir -p "$(dirname $QDROUTERD_SASL_DB)"

    if [[ "$QDROUTERD_ADMIN_USERNAME" && "$QDROUTERD_ADMIN_PASSWORD" ]]; then
        echo "$QDROUTERD_ADMIN_PASSWORD" | saslpasswd2 -f "$QDROUTERD_SASL_DB" -u QPID -p "$QDROUTERD_ADMIN_USERNAME"
        sasl_plain=1
    fi

    #####
    # SSL
    #####
    if [[ "$QDROUTERD_SSL_SERVER_PUBLIC_KEY" && "$QDROUTERD_SSL_SERVER_PRIVATE_KEY" ]]; then
        tempDir="$(mktemp -d)"
        
        if [ -z "$QDROUTERD_SSL_DB_DIR" ]; then
            QDROUTERD_SSL_DB_DIR="$QDROUTERD_HOME/etc/ssl"
        fi

        mkdir -p "$QDROUTERD_SSL_DB_DIR"

        if [ -z "$QDROUTERD_SSL_DB_PASSWORD" ]; then
            QDROUTERD_SSL_DB_PASSWORD="$(date +%s | sha256sum | base64 | head -c 32 ; echo)"
        fi

        # Password file
        touch $QDROUTERD_SSL_DB_DIR/pwdfile
        echo "$QDROUTERD_SSL_DB_PASSWORD" > $QDROUTERD_SSL_DB_DIR/pwdfile
        QDROUTERD_SSL_DB_PASSWORD_FILE="$QDROUTERD_SSL_DB_DIR/pwdfile"

        # Server key
        echo "DEBUG: Server key"
        echo "$QDROUTERD_SSL_SERVER_PUBLIC_KEY" > $tempDir/serverKey.crt
        echo "$QDROUTERD_SSL_SERVER_PRIVATE_KEY" > $tempDir/serverKey.pem
        openssl pkcs12 -export -in $tempDir/serverKey.crt -inkey $tempDir/serverKey.pem -out $tempDir/serverKey.p12 -passout pass:$(cat $QDROUTERD_SSL_DB_PASSWORD_FILE)

        # Does the database already exist?
        echo "DEBUG: NSS DB"
        #certutil -L -d sql:$QDROUTERD_SSL_DB_DIR >> /dev/null
        if [[ ! -f $QDROUTERD_SSL_DB_DIR/cert9.db || ! -f $QDROUTERD_SSL_DB_DIR/key4.db ]] ; then
            certutil -N -d sql:$QDROUTERD_SSL_DB_DIR -f $QDROUTERD_SSL_DB_PASSWORD_FILE
        fi

        # Delete old server keys
        exists=$(certutil -L -d sql:$QDROUTERD_SSL_DB_DIR | grep serverKey | wc -l)
        while [ "$exists" -gt 0 ]; do
            certutil -D -d sql:$QDROUTERD_SSL_DB_DIR -n serverKey
            res=$?
        done

        # Load server certificate
        echo "DEBUG: Loading keys"
        certutil -A -d sql:$QDROUTERD_SSL_DB_DIR -n serverKey -t ",," -i $tempDir/serverKey.crt -f $QDROUTERD_SSL_DB_PASSWORD_FILE
        pk12util -i $tempDir/serverKey.p12 -d sql:$QDROUTERD_SSL_DB_DIR -w $QDROUTERD_SSL_DB_PASSWORD_FILE -k $QDROUTERD_SSL_DB_PASSWORD_FILE
        
        if [ "$QDROUTERD_SSL_TRUSTED_CA" ]; then
             pushd $tempDir
             echo "$QDROUTERD_SSL_TRUSTED_CA" > db.ca
             csplit db.ca '/^-----END CERTIFICATE-----$/1' '{*}' --elide-empty-files --silent --prefix=ca_
             
             counter=1
             for cert in $(ls ca_*); do
                 certutil -A -d sql:$QDROUTERD_SSL_DB_DIR -f $QDROUTERD_SSL_DB_PASSWORD_FILE -t "T,," -i $cert -n ca_$counter
                 let counter=$counter+1
             done

             rm ca_*
             rm db.ca
             popd
             
             sasl_external=1
        fi 

        if [ "$QDROUTERD_SSL_TRUSTED_PEER" ]; then
             pushd $tempDir
             echo "$QDROUTERD_SSL_TRUSTED_PEER" > db.peer
             csplit db.peer '/^-----END CERTIFICATE-----$/1' '{*}' --elide-empty-files --silent --prefix=peer_
             
             counter=1
             for cert in $(ls peer_*); do
                 certutil -A -d sql:$QDROUTERD_SSL_DB_DIR -f $QDROUTERD_SSL_DB_PASSWORD_FILE -t "P,," -i $cert -n peer_$counter
                 let counter=$counter+1
             done

             if [ -z "$QDROUTERD_SSL_TRUSTED_CA" ]; then
                  openssl req -subj '/CN=dummy_CA' -new -newkey rsa:2048 -days 365 -nodes -x509 -keyout server.key -out server.crt
                  certutil -A -d sql:$QDROUTERD_SSL_DB_DIR -f $QDROUTERD_SSL_DB_PASSWORD_FILE -t "T,," -i server.crt -n dummy_CA
             fi

             rm peer_*
             rm db.peer
             popd

             sasl_external=1
        fi 

        if [ "$QDROUTERD_SSL_NO_DICT" ]; then
            have_sslnodict=1
        fi

        have_ssl=1
    fi

    #####
    # Create SASL config if it doesn't exist, create it
    #]####
    if [ -z "$QDROUTERD_SASL_CONFIG_DIR" ]; then
        QDROUTERD_SASL_CONFIG_DIR="$QDROUTERD_HOME/etc/sasl/"
    fi
    
    if [ ! -f "$QDROUTERD_SASL_CONFIG_DIR/qpidd.conf" ]; then
        if [[ $sasl_plain -eq 1 || $sasl_external -eq 1 ]]; then
            mkdir -p "$(dirname $QDROUTERD_SASL_CONFIG_DIR)"
        
            mechs=""
    
            if [ $sasl_plain -eq 1 ]; then
                mechs="PLAIN DIGEST-MD5 CRAM-MD5 $mechs"
            fi
        
            if [ $sasl_external -eq 1 ]; then
                mechs="EXTERNAL $mechs"
            fi
    
            cat > $QDROUTERD_SASL_CONFIG_DIR/qpidd.conf <<-EOS
mech_list: $mechs
pwcheck_method: auxprop
auxprop_plugin: sasldb
sasldb_path: $QDROUTERD_SASL_DB
sql_select: dummy select
EOS
            have_sasl=1
        fi
    fi

    #####
    # Create ACL file - if user was set and the ACL env var not, generate it.
    #####
    if [ -z "$QDROUTERD_ACL_FILE" ]; then
        QDROUTERD_ACL_FILE="$QDROUTERD_HOME/etc/qpidd.acl"
    fi

    if [ "$QDROUTERD_ACL_RULES" ]; then
        echo $QDROUTERD_ACL_RULES > $QDROUTERD_ACL_FILE
        have_acl=1
    elif [ $QDROUTERD_ADMIN_USERNAME ]; then
        if [ ! -f "$QDROUTERD_ACL_FILE" ]; then
            cat > $QDROUTERD_ACL_FILE <<-EOS
acl allow $QDROUTERD_ADMIN_USERNAME@QPID all
acl deny-log all all
EOS
            have_acl=1
        fi
    fi

    #####
    # Store dir configuration
    #####
    if [ -z $QDROUTERD_STORE_DIR ]; then
        QDROUTERD_STORE_DIR="$QDROUTERD_HOME/store"
    fi
    
    mkdir -p "$QDROUTERD_STORE_DIR"
    have_store=1

    #####
    # Paging dir configuration
    #####
    if [ -z $QDROUTERD_PAGING_DIR ]; then
        QDROUTERD_PAGING_DIR="$QDROUTERD_HOME/paging"
    fi
    
    mkdir -p "$QDROUTERD_PAGING_DIR"
    have_paging=1

    #####
    # Generate broker config file if it doesn`t exist
    #####
    if [ -z "$QDROUTERD_CONFIG_FILE" ]; then
        QDROUTERD_CONFIG_FILE="$QDROUTERD_HOME/etc/qpidd.conf"
    fi

    if [ "$QDROUTERD_CONFIG_OPTIONS" ]; then
        echo $QDROUTERD_CONFIG_OPTIONS > $QDROUTERD_CONFIG_FILE
    else
        if [ ! -f "$QDROUTERD_CONFIG_FILE" ]; then
            if [ $have_sasl -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
sasl-config=$QDROUTERD_SASL_CONFIG_DIR
EOS
                have_config=1
            fi

            if [ $have_acl -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
acl-file=$QDROUTERD_ACL_FILE
EOS
                have_config=1
            fi

            if [ $have_store -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
store-dir=$QDROUTERD_STORE_DIR
EOS
                have_config=1
            fi

            if [ $have_paging -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
paging-dir=$QDROUTERD_PAGING_DIR
EOS
                have_config=1
            fi
               
            if [ $have_ssl -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
ssl-cert-password-file=$QDROUTERD_SSL_DB_PASSWORD_FILE
ssl-cert-name=serverKey
ssl-cert-db=sql:$QDROUTERD_SSL_DB_DIR
EOS
                have_config=1

                if [ $sasl_external -eq "1" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
ssl-require-client-authentication=yes
EOS
                fi

                if [ $sasl_sslnodict -eq "1" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
--ssl-sasl-no-dict=yes
EOS
                fi
            fi
        fi
    fi

    if [ $have_config -eq "1" ]; then
        set -- "$@" "--config" "$QDROUTERD_CONFIG_FILE"
    fi

    chown -R qdrouterd:qdrouterd "$QDROUTERD_HOME"
fi

# else default to run whatever the user wanted like "bash"
exec "$@"
