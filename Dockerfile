# Start with Centos 7
FROM centos:7
MAINTAINER Gregory Grubbs <gregoryg@cloudera.com>

# The following environment variables must be set at build time
ENV CM_HOST=<<LOCALHOST>>
# Change port for TLS
ENV CM_PORT=7180
ENV CM_USER=admin
ENV CM_PASSWORD=admin
ENV CLUSTER_NAME=<<MYCLUSTER>>

# Set locale
RUN localedef -i en_US -f UTF-8 en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Update CentOS and install basics
RUN yum update -y && \
    yum install -y bzip2 cyrus-sasl-* krb5-libs krb5-workstation unzip which wget
RUN curl -o /usr/bin/jq -LO https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 && \
    chmod a+rx /usr/bin/jq

# # Add Cloudera security config
# RUN curl -o /etc/krb5.conf http://<<URI to security files for this cluster>>/master/kerberos/files/mycluster/krb5.conf
# RUN chmod 644 /etc/krb5.conf

# Install Oracle Java 8
RUN yum -y install 'http://archive.cloudera.com/director/redhat/7/x86_64/director/2.6.1/RPMS/x86_64/oracle-j2sdk1.8-1.8.0+update121-1.x86_64.rpm'
RUN update-alternatives --install /usr/bin/java java /usr/java/jdk1.8.0_121-cloudera/jre/bin/java 10
RUN update-alternatives --set java /usr/java/jdk1.8.0_121-cloudera/jre/bin/java
ENV JAVA_HOME /usr/java/jdk1.8.0_121-cloudera

RUN update-alternatives --install /usr/bin/java java ${JAVA_HOME}/jre/bin/java 10
RUN update-alternatives --set java ${JAVA_HOME}/jre/bin/java

# Install JCE unlimited strength policy files
RUN curl -O -j -k -L -H "Cookie: oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jce/7/UnlimitedJCEPolicyJDK7.zip
RUN unzip UnlimitedJCEPolicyJDK7.zip && \
    rm -f ${JAVA_HOME}/jre/lib/security/{local_policy,US_export_policy}.jar && \
    mv UnlimitedJCEPolicy/*.jar ${JAVA_HOME}/jre/lib/security/ && \
    rm -rf UnlimitedJCEPolicy*

# Install the CDH 5 parcel
ENV CDH_VERSION 5.13.1
ENV CDH_RELEASE CDH-${CDH_VERSION}-1.cdh${CDH_VERSION}.p0.2
ENV CDH_PARCEL ${CDH_RELEASE}-el7.parcel
RUN curl -O http://archive.cloudera.com/cdh5/parcels/${CDH_VERSION}/${CDH_PARCEL}
RUN tar xvf ${CDH_PARCEL} && \
    mkdir -p /opt/cloudera/parcels && \
    mv ${CDH_RELEASE} /opt/cloudera/parcels/ && \
    ln -s /opt/cloudera/parcels/${CDH_RELEASE} /opt/cloudera/parcels/CDH && \
    rm -f ${CDH_PARCEL}

# Install Spark2 parcel
ENV SPARK2_VERSION 2.2.0
ENV SPARK2_RELEASE SPARK2-${SPARK2_VERSION}.cloudera2-1.cdh5.12.0.p0.232957
ENV SPARK2_PARCEL ${SPARK2_RELEASE}-el7.parcel
RUN curl -O http://archive.cloudera.com/spark2/parcels/${SPARK2_VERSION}/${SPARK2_PARCEL}
RUN tar xvf ${SPARK2_PARCEL} && \
    mkdir -p /opt/cloudera/parcels && \
    mv ${SPARK2_RELEASE} /opt/cloudera/parcels/ && \
    ln -s /opt/cloudera/parcels/${SPARK2_RELEASE} /opt/cloudera/parcels/SPARK2 && \
    rm -f ${SPARK2_PARCEL}

# Add CDH client config
ENV CM_API_URL=http://${CM_HOST}:${CM_PORT}/api/v18/clusters/${CLUSTER_NAME}
RUN curl -u ${CM_USER}:${CM_PASSWORD} -o cluster-services.json ${CM_API_URL}/services

# Hive client config is a superset of Hive, HDFS, and YARN
RUN curl -u ${CM_USER}:${CM_PASSWORD} -o hive-conf.zip ${CM_API_URL}/services/$(jq -r '.items[] | select(.type == "HIVE") .name' cluster-services.json)/clientConfig
RUN unzip hive-conf.zip && \
    mkdir -p /etc/hadoop/conf && \
    mv hive-conf/* /etc/hadoop/conf/ && \
    rm -rf hive-conf && \
    rm -f hive-conf.zip

# HBase client config
RUN curl -u ${CM_USER}:${CM_PASSWORD} -o hbase-conf.zip ${CM_API_URL}/services/$(jq -r '.items[] | select(.type == "HIVE") .name' cluster-services.json)/clientConfig
COPY bin/move-configs.sh /usr/local/bin/move-configs.sh
RUN /usr/local/bin/move-configs.sh hbase

# Solr client config
RUN curl -u ${CM_USER}:${CM_PASSWORD} -o hbase-conf.zip ${CM_API_URL}/services/$(jq -r '.items[] | select(.type == "SOLR") .name' cluster-services.json)/clientConfig
RUN /usr/local/bin/move-configs.sh solr
RUN usr/local/bin/move-configs.sh solr

# Set recommended values for CDH gateways
ENV HADOOP_HOME=/opt/cloudera/parcels/CDH \
    HIVE_HOME=/opt/cloudera/parcels/CDH \
    HBASE_HOME=/opt/cloudera/parcels/CDH \
    SPARK2_HOME=/opt/cloudera/parcels/SPARK2/lib/spark2 \
    YARN_CONF_DIR=/etc/hadoop/conf \
    HADOOP_CONF_DIR=/etc/hadoop/conf \
    HIVE_AUX_JARS_PATH=/opt/cloudera/parcels/CDH/lib/hbase/lib/metrics-core-2.2.0.jar
ENV CDH_MR2_HOME=${HADOOP_HOME}/lib/hadoop-mapreduce \
    PATH=${PATH}:${JAVA_HOME}/bin:${HADOOP_HOME}/bin:/opt/cloudera/parcels/SPARK2/bin

RUN echo 'export SPARK_DIST_CLASSPATH=/opt/cloudera/parcels/CDH/lib/spark/../../jars/spark-*.jar:$(hadoop classpath)' >> ~/.bashrc 

#TODO: set up .beeline/properties and .impalarc

# Finish up
RUN echo export TERM=xterm >> /etc/bash.bashrc

CMD ["bash"]