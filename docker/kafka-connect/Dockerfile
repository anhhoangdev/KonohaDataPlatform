FROM confluentinc/cp-kafka-connect:7.4.1

# Install connectors using confluent-hub
USER root

# Install S3 Sink Connector
RUN confluent-hub install --no-prompt confluentinc/kafka-connect-s3:10.5.13

# Copy and install Debezium PostgreSQL Connector from downloads
COPY downloads/debezium-connector-postgres-2.4.2.Final-plugin.tar.gz /tmp/
RUN mkdir -p /usr/share/confluent-hub-components/debezium-postgres && \
    tar -xzf /tmp/debezium-connector-postgres-2.4.2.Final-plugin.tar.gz -C /usr/share/confluent-hub-components/debezium-postgres --strip-components=1 && \
    rm /tmp/debezium-connector-postgres-2.4.2.Final-plugin.tar.gz

# Copy and install Iceberg Kafka Connect Sink Connector from downloads
RUN mkdir -p /usr/share/confluent-hub-components/iceberg-kafka-connect
COPY downloads/iceberg-kafka-connect-1.5.0.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/iceberg-core-1.5.0.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/iceberg-api-1.5.0.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/iceberg-aws-bundle-1.5.0.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/aws-java-sdk-bundle-1.12.500.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/guava-31.1-jre.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/iceberg-spark-runtime-3.5_2.12-1.4.2.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/iceberg-common-1.5.0.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/
COPY downloads/iceberg-hive-runtime-1.5.0.jar /usr/share/confluent-hub-components/iceberg-kafka-connect/

USER appuser    