#!/usr/bin/env bats

IMAGE="scholzj/qpid-dispatch"
VERSION="travis"

IFSBAK=$IFS
IFS=""
SERVER_PUBLIC_KEY=$(cat ./tests/localhost.crt)
SERVER_PRIVATE_KEY=$(cat ./tests/localhost.key)
CLIENT_KEY_DB=$(cat ./tests/certs.db)
AUTH_POLICY=$(cat ./tests/authorization-policy.json)
CONFIG_ANONYMOUS=$(cat ./tests/qdrouterd-anonymous.conf)
IFS=$IFSBAK

teardown() {
    docker stop $cont
    docker rm $cont
}

tcpPort() {
    docker port $cont 5672 | cut -f 2 -d ":"
}

sslPort() {
    docker port $cont 5671 | cut -f 2 -d ":"
}

@test "Worker threads" {
    cont=$(docker run -P -e QDROUTERD_WORKER_THREADS="10" -d $IMAGE:$VERSION)
    sleep 5 # give the image time to start
    wt=$(docker exec -i $cont cat /var/lib/qdrouterd/etc/qdrouterd.conf | grep "workerThreads: 10" | wc -l)
    [ "$wt" -eq "1" ]
}

@test "Maximum number of connections" {
    cont=$(docker run -P -e QDROUTERD_MAX_CONNECTIONS="13" -d $IMAGE:$VERSION)
    sleep 5 # give the image time to start
    mc=$(docker exec -i $cont cat /var/lib/qdrouterd/etc/qdrouterd.conf | grep "maximumConnections: 13" | wc -l)
    [ "$mc" -eq "1" ]
}

@test "Config file through env variable" {
    cont=$(docker run -P -e QDROUTERD_CONFIG_OPTIONS="$CONFIG_ANONYMOUS" -d $IMAGE:$VERSION)
    port=$(tcpPort)
    sleep 5 # give the image time to start
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5672
    [ "$status" -eq "0" ]
}

@test "Username/password connections" {
    cont=$(docker run -P -e QDROUTERD_ADMIN_USERNAME=admin -e QDROUTERD_ADMIN_PASSWORD=123456 -d $IMAGE:$VERSION)
    port=$(tcpPort)
    sleep 5 # give the image time to start
    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5672
    [ "$status" -eq "0" ]
}

@test "Username/password connections with SSL" {
    cont=$(docker run -P -e QDROUTERD_ADMIN_USERNAME=admin -e QDROUTERD_ADMIN_PASSWORD=123456 -e QDROUTERD_SSL_SERVER_PUBLIC_KEY="$SERVER_PUBLIC_KEY"  -e QDROUTERD_SSL_SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY" -d $IMAGE:$VERSION)
    port=$(sslPort)
    sleep 5 # give the image time to start

    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5672
    [ "$status" -eq "0" ]

    docker cp ./tests/localhost.crt ${cont}:/var/lib/qdrouterd/localhost.crt
    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt
    [ "$status" -eq "0" ]
}

@test "Username/password connections with SSL client authentication" {
    cont=$(docker run -P -e QDROUTERD_ADMIN_USERNAME=admin -e QDROUTERD_ADMIN_PASSWORD=123456 -e QDROUTERD_SSL_SERVER_PUBLIC_KEY="$SERVER_PUBLIC_KEY"  -e QDROUTERD_SSL_SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY" -e QDROUTERD_SSL_CERT_DB="$CLIENT_KEY_DB" -d $IMAGE:$VERSION)
    port=$(sslPort)
    sleep 5 # give the image time to start

    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5672
    [ "$status" -eq "0" ]

    docker cp ./tests/localhost.crt ${cont}:/var/lib/qdrouterd/localhost.crt
    docker cp ./tests/user1.crt ${cont}:/var/lib/qdrouterd/user1.crt
    docker cp ./tests/user1.key ${cont}:/var/lib/qdrouterd/user1.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/user1.crt --ssl-key=/var/lib/qdrouterd/user1.key
    echo "Output1: $output"
    docker logs $cont
    [ "$status" -eq "0" ]

    docker cp ./tests/wrong_user.crt ${cont}:/var/lib/qdrouterd/wrong_user.crt
    docker cp ./tests/wrong_user.key ${cont}:/var/lib/qdrouterd/wrong_user.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/wrong_user.crt --ssl-key=/var/lib/qdrouterd/wrong_user.key
    echo "Output2: $output"
    [ "$status" -ne "0" ]
}

@test "SSL client authentication without username / password" {
    cont=$(docker run -P -e QDROUTERD_SSL_SERVER_PUBLIC_KEY="$SERVER_PUBLIC_KEY"  -e QDROUTERD_SSL_SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY" -e QDROUTERD_SSL_CERT_DB="$CLIENT_KEY_DB" -d $IMAGE:$VERSION)
    port=$(sslPort)
    sleep 5 # give the image time to start

    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5672
    [ "$status" -ne "0" ]

    docker cp ./tests/localhost.crt ${cont}:/var/lib/qdrouterd/localhost.crt
    docker cp ./tests/user1.crt ${cont}:/var/lib/qdrouterd/user1.crt
    docker cp ./tests/user1.key ${cont}:/var/lib/qdrouterd/user1.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/user1.crt --ssl-key=/var/lib/qdrouterd/user1.key
    echo "Output1: $output"
    docker logs $cont
    [ "$status" -eq "0" ]

    docker cp ./tests/wrong_user.crt ${cont}:/var/lib/qdrouterd/wrong_user.crt
    docker cp ./tests/wrong_user.key ${cont}:/var/lib/qdrouterd/wrong_user.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/wrong_user.crt --ssl-key=/var/lib/qdrouterd/wrong_user.key
    echo "Output2: $output"
    [ "$status" -ne "0" ]
}

@test "Authorization policy" {
    cont=$(docker run -P -e QDROUTERD_ADMIN_USERNAME=admin -e QDROUTERD_ADMIN_PASSWORD=123456 -e QDROUTERD_SSL_SERVER_PUBLIC_KEY="$SERVER_PUBLIC_KEY"  -e QDROUTERD_SSL_SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY" -e QDROUTERD_SSL_CERT_DB="$CLIENT_KEY_DB" -e QDROUTERD_POLICY_RULES="$AUTH_POLICY" -d $IMAGE:$VERSION)
    port=$(sslPort)
    sleep 5 # give the image time to start

    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5672
    # admin is allowed to access management
    [ "$status" -eq "0" ]

    docker cp ./tests/localhost.crt ${cont}:/var/lib/qdrouterd/localhost.crt
    docker cp ./tests/user1.crt ${cont}:/var/lib/qdrouterd/user1.crt
    docker cp ./tests/user1.key ${cont}:/var/lib/qdrouterd/user1.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/user1.crt --ssl-key=/var/lib/qdrouterd/user1.key
    echo "Output1: $output"
    docker logs $cont
    # user1 is not allowed to access management
    [ "$status" -ne "0" ]
}

@test "UID format" {
    cont=$(docker run -P -e QDROUTERD_ADMIN_USERNAME=admin -e QDROUTERD_ADMIN_PASSWORD=123456 -e QDROUTERD_SSL_SERVER_PUBLIC_KEY="$SERVER_PUBLIC_KEY"  -e QDROUTERD_SSL_SERVER_PRIVATE_KEY="$SERVER_PRIVATE_KEY" -e QDROUTERD_SSL_CERT_DB="$CLIENT_KEY_DB" -e QDROUTERD_POLICY_RULES="$AUTH_POLICY" -e QDROUTERD_SSL_UID_FORMAT="1" -d $IMAGE:$VERSION)
    port=$(sslPort)
    sleep 5 # give the image time to start

    run docker exec -i $cont qdstat -g -b admin:123456@127.0.0.1:5672
    [ "$status" -eq "0" ]

    docker cp ./tests/localhost.crt ${cont}:/var/lib/qdrouterd/localhost.crt
    docker cp ./tests/user1.crt ${cont}:/var/lib/qdrouterd/user1.crt
    docker cp ./tests/user1.key ${cont}:/var/lib/qdrouterd/user1.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/user1.crt --ssl-key=/var/lib/qdrouterd/user1.key
    echo "Output1: $output"
    docker logs $cont
    # user1 is not allowed to access management
    [ "$status" -ne "0" ]

    docker cp ./tests/localhost.crt ${cont}:/var/lib/qdrouterd/localhost.crt
    docker cp ./tests/user2.crt ${cont}:/var/lib/qdrouterd/user2.crt
    docker cp ./tests/user2.key ${cont}:/var/lib/qdrouterd/user2.key
    run docker exec -i $cont qdstat -g -b 127.0.0.1:5671 --ssl-trustfile=/var/lib/qdrouterd/localhost.crt --ssl-certificate=/var/lib/qdrouterd/user2.crt --ssl-key=/var/lib/qdrouterd/user2.key
    echo "Output1: $output"
    docker logs $cont
    # user2 is allowed to access management
    [ "$status" -eq "0" ]
}
