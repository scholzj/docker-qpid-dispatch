#!/usr/bin/env bats

IMAGE="scholzj/qpid-dispatch"
VERSION="devel"

IFSBAK=$IFS
IFS=""
#SERVER_PUBLIC_KEY=$(cat ./test/localhost.crt)
#SERVER_PRIVATE_KEY=$(cat ./test/localhost.pem)
#CLIENT_KEY_DB=$(cat ./test/crt.db)
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
