# Use an official OpenJDK runtime as a parent image
FROM eclipse-temurin:8-jre-focal

ENV KYUUBI_HOME /opt/kyuubi
ENV SPARK_HOME /opt/spark
ENV SPARK_VERSION 3.5.0
ENV KYUUBI_VERSION 1.10.0
ENV PATH $KYUUBI_HOME/bin:$PATH

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends tini && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy pre-downloaded Kyuubi
COPY downloads/apache-kyuubi-${KYUUBI_VERSION}-bin.tgz /tmp/

# Extract Kyuubi
RUN tar -xzvf /tmp/apache-kyuubi-${KYUUBI_VERSION}-bin.tgz -C /opt && \
    mv /opt/apache-kyuubi-${KYUUBI_VERSION}-bin $KYUUBI_HOME && \
    rm /tmp/*.tgz

# Copy pre-downloaded Spark distribution
COPY downloads/spark-${SPARK_VERSION}-bin-hadoop3.tgz /tmp/

# Extract Spark distribution
RUN tar -xzvf /tmp/spark-${SPARK_VERSION}-bin-hadoop3.tgz -C /opt && \
    mv /opt/spark-${SPARK_VERSION}-bin-hadoop3 $SPARK_HOME && \
    rm /tmp/*.tgz

# Copy entrypoint
COPY kyuubi-server/entrypoint.sh /
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["start-kyuubi"]
