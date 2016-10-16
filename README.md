[![Build Status](https://travis-ci.org/scholzj/docker-qpid-dispatch.svg?branch=master)](https://travis-ci.org/scholzj/docker-qpid-dispatch)

# Apache Qpid Dispatch Docker image

Docker image for Apache Qpid Dispatch router. The image is based on CentOS 7.

## Using the image

The Docker image can be configured using following environment variables:

- `QDROUTERD_HOME` defines the main directory where all data are stored. By default `/var/lib/qdrouterd/`
- `QDROUTERD_ID` defines the ID of the Dispatch router instance. If not specified, it will be randomly generated.
- `QDROUTERD_WORKER_THREADS` defines the number of worker threads used by the router. By default `4` threads are used.
- `QDROUTERD_LISTENER_LINK_CAPACITY` defines the detaul link capacity which will be configured for all listeners. By default is set to `1000`
- `QDROUTERD_LOG_LEVEL` defines the default log level which will be used. By default `info+`.
- `QDROUTERD_CONFIG_FILE` defines the location of the main configuration file. By default `$QDROUTERD_HOME/etc/qdrouterd.conf`
- `QDROUTERD_CONFIG_OPTIONS` allows user to pass the complete content of the configuration file which should be used. If specified, the configuration file will not be generated by the image it self.
- `QDROUTERD_CONFIG_INSET` allows to pass some additional configuration into the `qdrouterd.conf` file. The content of this variable will be simply added into the generated configuration file.

### SSL configuration

- `QDROUTERD_SSL_DB_DIR` defines the directory where all SSL related files are stored. By default `$QDROUTERD_HOME/etc/ssl`
- `QDROUTERD_SSL_SERVER_PUBLIC_KEY` contains the public key of router's own certificate.
- `QDROUTERD_SSL_SERVER_PRIVATE_KEY` contains the private key of router's own certificate.
- `QDROUTERD_SSL_DB_PASSWORD` should contain the password to the private key (in case it is needed).
- `QDROUTERD_SSL_CERT_DB` should contain the database of clients certificates (public keys) which will be used for client authentication.
- `QDROUTERD_SSL_TRUSTED_CERTS` list of supported CAs which will be presented to the SSL clients. If not specified, `QDROUTERD_SSL_CERT_DB` will be used.
- `QDROUTERD_SSL_AUTHENTICATE_PEER` defines whether peer authentication is required or not.
- `QDROUTERD_SSL_UID_FORMAT` configures the mechanism which is used to create the username based on the certificate (e.g. based on CN, SHA signature etc.). For more details about the different options visit the Qpid Dispatch documentation.
- `QDROUTERD_DISPLAY_NAME_MAPPING` configures the display name mapping file, which maps SSL certificates against usernames based on a JSON file with mapping. This variable should contain the JSON mapping as text. Do not use at the same time `QDROUTERD_DISPLAY_NAME_FILE`.
- `QDROUTERD_DISPLAY_NAME_FILE` configures the display name mapping file, which maps SSL certificates against usernames based on a JSON file with mapping. This variable should contain the path to the mapping file, which has to be included into the image on external volume. Do not use at the same time `QDROUTERD_DISPLAY_NAME_MAPPING`.

### SASL configuration

- `QDROUTERD_SASL_DB` defines the path to the SASL database containing the usernames and passwords. By default `$QDROUTERD_HOME/etc/sasl/qdrouterd.sasldb`
- `QDROUTERD_ADMIN_USERNAME` specifies the username of the admin user which will be added to the ŚASL database.
- `QDROUTERD_ADMIN_PASSWORD` specifies the password of the admin user.
- `QDROUTERD_SASL_CONFIG_DIR` defines the directory where the SASL configuration will be stored, By default `$QDROUTERD_HOME/etc/sasl/`.
- `QDROUTERD_SASL_CONFIG_NAME` defines the SASL configuration name, which is used to name the SASL configuration file. By default `qdrouterd`.

### Policy configuration

- `QDROUTERD_MAX_CONNECTIONS` defines the maximal number of connections per router. By default `65535` (max integer).
- `QDROUTERD_POLICY_DIR` defines the directory where security policies will be stored. By default `$QDROUTERD_HOME/etc/auth-policy/`.
- `QDROUTERD_POLICY_RULES` might contain one set of policy rules in JSON format. The content of this variable will be placed into a file in the `QDROUTERD_POLICY_DIR` directory.
