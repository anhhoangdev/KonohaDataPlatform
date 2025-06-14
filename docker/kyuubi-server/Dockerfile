FROM apache/spark:3.5.0

ENV KYUUBI_VERSION=1.10.0
ENV KYUUBI_HOME=/opt/kyuubi
ENV SPARK_HOME=/opt/spark

USER root

RUN apt-get update && apt-get install -y openjdk-8-jdk curl wget && rm -rf /var/lib/apt/lists/* && \
    wget https://downloads.apache.org/kyuubi/kyuubi-${KYUUBI_VERSION}/apache-kyuubi-${KYUUBI_VERSION}-bin.tgz -O /tmp/kyuubi.tgz && \
    tar -xzf /tmp/kyuubi.tgz -C /opt && \
    mv /opt/apache-kyuubi-${KYUUBI_VERSION}-bin /opt/kyuubi && \
    rm /tmp/kyuubi.tgz && \
    wget https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.12/1.10.0/kyuubi-spark-sql-engine_2.12-1.10.0.jar -O ${KYUUBI_HOME}/externals/engines/spark/kyuubi-spark-sql-engine.jar

ENV PATH="${KYUUBI_HOME}/bin:$PATH"

# Copy entrypoint script
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

EXPOSE 10009 10099

ENTRYPOINT ["/opt/entrypoint.sh"]
