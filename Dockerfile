FROM	centos:centos7
LABEL   maintainer="www@scholzj.com" 

# Add qpidd group / user
RUN groupadd -r qdrouterd && useradd -r -d /var/lib/qdrouterd -m -g qdrouterd qdrouterd

# Install all dependencies
RUN curl -o /etc/yum.repos.d/qpid-proton-devel.repo http://repo.effectivemessaging.com/qpid-proton-stable.repo \
        && curl -o /etc/yum.repos.d/qpid-dispatch-devel.repo http://repo.effectivemessaging.com/qpid-dispatch-stable.repo \
        && yum -y --setopt=tsflag=nodocs install cyrus-sasl cyrus-sasl-plain cyrus-sasl-md5 openssl qpid-dispatch-router qpid-dispatch-router-docs qpid-dispatch-tools \
        && yum clean all

ENV QDROUTERD_VERSION 1.10.0

VOLUME /var/lib/qdrouterd

# Add entrypoint
COPY ./docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]

USER qdrouterd:qdrouterd

# Expose port and run
EXPOSE 5671 5672 5673 5674 5675 5676 5677 5678 5679 5680 
CMD ["qdrouterd"]
