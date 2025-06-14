FROM apache/spark:3.5.0

USER root

RUN apt-get update && apt-get install -y openjdk-8-jdk curl wget && \
    rm -rf /var/lib/apt/lists/* && \
    wget https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.5.0/iceberg-spark-runtime-3.5_2.12-1.5.0.jar -O /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.5.0.jar && \
    wget https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.12/1.10.0/kyuubi-spark-sql-engine_2.12-1.10.0.jar -O /opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar && \
    mkdir -p /opt/kyuubi/externals/engines/spark && \
    cp /opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar && \
    chown -R 1000:1000 /opt/kyuubi && \
    chmod -R 755 /opt/kyuubi && \
    mkdir -p /opt/spark/work-dir && \
    chown -R 1000:1000 /opt/spark/work-dir && \
    chmod -R 755 /opt/spark/work-dir

USER 1000
