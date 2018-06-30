#!/bin/bash
set -e

# if command starts with an option, prepend qdrouterd
if [ "${1:0:1}" = '-' ]; then
    set -- qdrouterd "$@"
fi

if [ "$1" = "qdrouterd" ]; then
    sasl_external=0
    have_mapping=0
    sasl_plain=0
    have_ssl=0
    have_policy=0
    have_sasl=0
    have_sslauthpeer=0

    #####
    # Home dir
    #####
    if [ -z "$QDROUTERD_HOME" ]; then
        QDROUTERD_HOME="/var/lib/qdrouterd"
    fi

    if [ ! -d "$QDROUTERD_HOME" ]; then
        mkdir -p "$QDROUTERD_HOME"
        chown -R qdrouterd:qdrouterd "$QDROUTERD_HOME"
    fi

    #####
    # Router ID
    #####
    if [ -z "$QDROUTERD_ID" ]; then
        QDROUTERD_ID="$(date +%s | sha256sum | base64 | head -c 32 ; echo)"
    fi

    #####
    # SSL
    #####
    if [[ "$QDROUTERD_SSL_SERVER_PUBLIC_KEY" && "$QDROUTERD_SSL_SERVER_PRIVATE_KEY" ]]; then
        if [ -z "$QDROUTERD_SSL_DB_DIR" ]; then
            QDROUTERD_SSL_DB_DIR="$QDROUTERD_HOME/etc/ssl"
        fi

        mkdir -p "$QDROUTERD_SSL_DB_DIR"

        if [ "$QDROUTERD_SSL_DB_PASSWORD" ]; then
            # Password file
            touch $QDROUTERD_SSL_DB_DIR/pwdfile
            echo "$QDROUTERD_SSL_DB_PASSWORD" > $QDROUTERD_SSL_DB_DIR/pwdfile
            QDROUTERD_SSL_DB_PASSWORD_FILE="$QDROUTERD_SSL_DB_DIR/pwdfile"
        fi

        # Server key
        echo "$QDROUTERD_SSL_SERVER_PUBLIC_KEY" > $QDROUTERD_SSL_DB_DIR/serverKey.crt
        echo "$QDROUTERD_SSL_SERVER_PRIVATE_KEY" > $QDROUTERD_SSL_DB_DIR/serverKey.pem

        if [ "$QDROUTERD_SSL_CERT_DB" ]; then
             echo "$QDROUTERD_SSL_CERT_DB" > $QDROUTERD_SSL_DB_DIR/certDb.crt
             if [ "$QDROUTERD_SSL_TRUSTED_CERTS" ]; then
                 echo "$QDROUTERD_SSL_TRUSTED_CERTS" > $QDROUTERD_SSL_DB_DIR/trustedCerts.crt
             fi

             if [ "$QDROUTERD_SSL_AUTHENTICATE_PEER" ]; then
                 have_sslauthpeer=1
             fi

             #####
             # Display name mapping
             #####
             if [ "$QDROUTERD_DISPLAY_NAME_FILE" ]; then
                 have_mapping=1
             elif [ "$QDROUTERD_DISPLAY_NAME_MAPPING" ]; then
                 QDROUTERD_DISPLAY_NAME_FILE="$QDROUTERD_HOME/etc/display-name-mapping/mapping.json"

                 mkdir -p "$(dirname $QDROUTERD_DISPLAY_NAME_FILE)"
                 echo "$QDROUTERD_DISPLAY_NAME_MAPPING" > "${QDROUTERD_DISPLAY_NAME_FILE}"
                 have_mapping=1
             fi

             sasl_external=1
        fi

        have_ssl=1
    fi

    #####
    # If SASL database already exists, change the password only when it was provided from outside.
    #####
    if [ -z "$QDROUTERD_SASL_DB" ]; then
        QDROUTERD_SASL_DB="$QDROUTERD_HOME/etc/sasl/qdrouterd.sasldb"
    fi

    mkdir -p "$(dirname $QDROUTERD_SASL_DB)"

    if [[ "$QDROUTERD_ADMIN_USERNAME" && "$QDROUTERD_ADMIN_PASSWORD" ]]; then
        echo "$QDROUTERD_ADMIN_PASSWORD" | saslpasswd2 -f "$QDROUTERD_SASL_DB" -p "$QDROUTERD_ADMIN_USERNAME"
        sasl_plain=1
    fi

    #####
    # Create SASL config if it doesn't exist, create it
    #####
    if [ -z "$QDROUTERD_SASL_CONFIG_DIR" ]; then
        QDROUTERD_SASL_CONFIG_DIR="$QDROUTERD_HOME/etc/sasl/"
    fi

    if [ -z "$QDROUTERD_SASL_CONFIG_NAME" ]; then
        QDROUTERD_SASL_CONFIG_NAME="qdrouterd"
    fi

    if [ ! -f "$QDROUTERD_SASL_CONFIG_DIR/$QDROUTERD_SASL_CONFIG_NAME.conf" ]; then
        if [[ $sasl_plain -eq 1 || $sasl_external -eq 1 ]]; then
            mkdir -p "$QDROUTERD_SASL_CONFIG_DIR"

            mechs=""

            if [ $sasl_plain -eq 1 ]; then
                mechs="PLAIN DIGEST-MD5 CRAM-MD5 $mechs"
            fi

            if [ $sasl_external -eq 1 ]; then
                mechs="EXTERNAL $mechs"
            fi

            cat > $QDROUTERD_SASL_CONFIG_DIR/$QDROUTERD_SASL_CONFIG_NAME.conf <<-EOS
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
    # Create policy file
    #####
    if [ -z "$QDROUTERD_POLICY_DIR" ]; then
        QDROUTERD_POLICY_DIR="$QDROUTERD_HOME/etc/auth-policy/"
    fi

    if [ "$QDROUTERD_POLICY_RULES" ]; then
        mkdir -p "$QDROUTERD_POLICY_DIR"
        echo "$QDROUTERD_POLICY_RULES" > "${QDROUTERD_POLICY_DIR}/default-policy.json"
        have_policy=1
    fi

    #####
    # Maximum number of connections
    #####
    if [ -z "$QDROUTERD_MAX_CONNECTIONS" ]; then
        QDROUTERD_MAX_CONNECTIONS="65535"
    fi

    #####
    # Worker threads
    #####
    if [ -z "$QDROUTERD_WORKER_THREADS" ]; then
        QDROUTERD_WORKER_THREADS="4"
    fi

    #####
    # Listener link capacity
    #####
    if [ -z "$QDROUTERD_LISTENER_LINK_CAPACITY" ]; then
        QDROUTERD_LISTENER_LINK_CAPACITY="1000"
    fi

    #####
    # Log level
    #####
    if [ -z "$QDROUTERD_LOG_LEVEL" ]; then
        QDROUTERD_LOG_LEVEL="info+"
    fi

    #####
    # Generate broker config file if it doesn`t exist
    #####
    if [ -z "$QDROUTERD_CONFIG_FILE" ]; then
        QDROUTERD_CONFIG_FILE="$QDROUTERD_HOME/etc/qdrouterd.conf"
    fi

    if [ "$QDROUTERD_CONFIG_OPTIONS" ]; then
	    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
$QDROUTERD_CONFIG_OPTIONS
EOS
    else
        if [ ! -f "$QDROUTERD_CONFIG_FILE" ]; then
            cat >> $QDROUTERD_CONFIG_FILE <<-EOS
router {
    mode: standalone
    id: $QDROUTERD_ID
    workerThreads: $QDROUTERD_WORKER_THREADS
EOS

            if [ $have_sasl -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    saslConfigDir: $QDROUTERD_SASL_CONFIG_DIR
    saslConfigName: $QDROUTERD_SASL_CONFIG_NAME
EOS
            fi

            cat >> $QDROUTERD_CONFIG_FILE <<-EOS
}
EOS

            cat >> $QDROUTERD_CONFIG_FILE <<-EOS
policy {
    maxConnections: $QDROUTERD_MAX_CONNECTIONS
EOS
            if [ $have_policy -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    enableVhostPolicy: true
    policyDir: $QDROUTERD_POLICY_DIR
    defaultVhost: default
EOS
            fi
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
}
EOS

            if [ $sasl_plain -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
listener {
    role: normal
    host: 0.0.0.0
    port: amqp
    saslMechanisms: PLAIN DIGEST-MD5 CRAM-MD5
    linkCapacity: $QDROUTERD_LISTENER_LINK_CAPACITY
    authenticatePeer: yes
}
EOS
            fi

            if [ $have_ssl -eq "1" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
sslProfile {
    name: ssl-listener
    certFile: $QDROUTERD_SSL_DB_DIR/serverKey.crt
    keyFile: $QDROUTERD_SSL_DB_DIR/serverKey.pem
EOS

                if [ "$QDROUTERD_SSL_DB_PASSWORD_FILE" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    passwordFile: $QDROUTERD_SSL_DB_PASSWORD_FILE
EOS
                fi

                if [ "$QDROUTERD_SSL_CERT_DB" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    certDb: $QDROUTERD_SSL_DB_DIR/certDb.crt
EOS
                fi

                if [ "$QDROUTERD_SSL_TRUSTED_CERTS" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    trustedCerts: $QDROUTERD_SSL_DB_DIR/trustedCerts.crt
EOS
                fi

                if [ "$QDROUTERD_SSL_UID_FORMAT" ]; then
                  cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    uidFormat: $QDROUTERD_SSL_UID_FORMAT
EOS
                fi

                if [ $have_mapping -eq "1" ]; then
                  cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    displayNameFile: $QDROUTERD_DISPLAY_NAME_FILE
EOS
                fi

                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
}
listener {
    role: normal
    host: 0.0.0.0
    port: amqps
    requireSsl: yes
    sslProfile: ssl-listener
    linkCapacity: $QDROUTERD_LISTENER_LINK_CAPACITY
EOS

                if [ $sasl_external -eq "1" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    saslMechanisms: EXTERNAL PLAIN DIGEST-MD5 CRAM-MD5
    authenticatePeer: yes
EOS
                elif [ $have_sslauthpeer -eq "1" ]; then
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    saslMechanisms: EXTERNAL
    authenticatePeer: yes
EOS
                    cat >> $QDROUTERD_CONFIG_FILE <<-EOS
    saslMechanisms: PLAIN DIGEST-MD5 CRAM-MD5
    authenticatePeer: yes
EOS
                fi

                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
}
EOS
            fi

            cat >> $QDROUTERD_CONFIG_FILE <<-EOS
log {
     module: DEFAULT
     enable: $QDROUTERD_LOG_LEVEL
     includeTimestamp: true
}
EOS

            if [ "$QDROUTERD_CONFIG_INSET" ]; then
                cat >> $QDROUTERD_CONFIG_FILE <<-EOS
$QDROUTERD_CONFIG_INSET
EOS
            fi
        fi
    fi

    set -- "$@" "--config" "$QDROUTERD_CONFIG_FILE"
fi

# else default to run whatever the user wanted like "bash"
exec "$@"
