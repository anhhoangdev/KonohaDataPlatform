# Use the official Apache Spark image (Kubernetes-ready)
FROM apache/spark:3.5.0

USER root

# Install required JARs for Iceberg and S3/MinIO support
RUN curl -L https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.4.2/iceberg-spark-runtime-3.5_2.12-1.4.2.jar \
     -o /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.4.2.jar && \
    curl -L https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-hive-metastore/1.4.2/iceberg-hive-metastore-1.4.2.jar \
     -o /opt/spark/jars/iceberg-hive-metastore-1.4.2.jar && \
    curl -L https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar \
     -o /opt/spark/jars/hadoop-aws-3.3.4.jar && \
    curl -L https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.262/aws-java-sdk-bundle-1.12.262.jar \
     -o /opt/spark/jars/aws-java-sdk-bundle-1.12.262.jar

# Add Kyuubi Spark SQL Engine
RUN mkdir -p /opt/kyuubi/externals/engines/spark && \
    curl -L https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.13/1.10.0/kyuubi-spark-sql-engine_2.13-1.10.0.jar \
     -o /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar

# Verify JARs are present
RUN echo "=== Iceberg JARs ===" && ls -la /opt/spark/jars/ | grep -i iceberg
RUN echo "=== Kyuubi Engine JARs ===" && ls -la /opt/kyuubi/externals/engines/spark/ | grep kyuubi

# Fix permissions
RUN chown -R 1000:1000 /opt/kyuubi /opt/spark && chmod -R 755 /opt/kyuubi /opt/spark

USER 1000