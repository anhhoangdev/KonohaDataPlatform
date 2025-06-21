FROM apache/spark:3.5.0

USER root

ENV SPARK_HOME /opt/spark
ENV SPARK_VERSION 3.5.0
ENV HADOOP_VERSION 3
ENV PATH $SPARK_HOME/bin:$PATH

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy pre-downloaded Spark
COPY downloads/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz /tmp/

# Extract Spark
RUN tar -xzvf /tmp/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz -C /opt && \
    mv /opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} $SPARK_HOME && \
    rm /tmp/*.tgz

# Copy JARs
COPY downloads/iceberg-spark-runtime-3.5_2.12-1.4.2.jar $SPARK_HOME/jars/
COPY downloads/iceberg-aws-bundle-1.4.2.jar $SPARK_HOME/jars/
COPY downloads/bundle-2.17.230.jar $SPARK_HOME/jars/
COPY downloads/url-connection-client-2.17.230.jar $SPARK_HOME/jars/
COPY downloads/hadoop-aws-3.3.4.jar $SPARK_HOME/jars/
COPY downloads/aws-java-sdk-bundle-1.11.901.jar $SPARK_HOME/jars/
COPY downloads/iceberg-hive-metastore-1.4.2.jar $SPARK_HOME/jars/

RUN mkdir -p /opt/kyuubi/externals/engines/Spark

COPY downloads/kyuubi-spark-sql-engine_2.12-1.10.0.jar /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar


# Verify JARs are present
RUN echo "=== Iceberg JARs ===" && ls -la /opt/spark/jars/ | grep -i iceberg
RUN echo "=== Kyuubi Engine JARs ===" && ls -la /opt/kyuubi/externals/engines/spark/ | grep kyuubi

# Fix permissions
RUN chown -R 1000:1000 /opt/kyuubi /opt/spark && chmod -R 755 /opt/kyuubi /opt/spark

USER 1000