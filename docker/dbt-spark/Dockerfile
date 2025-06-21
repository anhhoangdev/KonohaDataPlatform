FROM python:3.11-slim

# Install system dependencies including SASL development libraries
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    default-jdk \
    unzip \
    procps \
    netcat-openbsd \
    libsasl2-dev \
    libsasl2-modules \
    && rm -rf /var/lib/apt/lists/*

# Set Java environment
ENV JAVA_HOME=/usr/lib/jvm/default-java
ENV PATH=$PATH:$JAVA_HOME/bin

# Install DBT with Spark adapter (minimal version without SASL)
RUN pip install --no-cache-dir \
    dbt-spark==1.9.2 \
    dbt-core==1.9.2 \
    pyspark==3.5.0 \
    py4j==0.10.9.7 \
    dbt-spark[PyHive]

# Install S3/AWS packages separately  
RUN pip install --no-cache-dir \
    boto3 \
    s3fs \
    pandas \
    pyarrow

# Create directories
RUN mkdir -p /opt/dbt /tmp/dbt_profiles /tmp/spark-events

# Set working directory
WORKDIR /opt/dbt

# Create entrypoint script
COPY dbt-spark/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set environment variables for Spark
ENV SPARK_HOME=/usr/local/lib/python3.11/site-packages/pyspark
ENV PYSPARK_PYTHON=python3
ENV PYSPARK_DRIVER_PYTHON=python3

# Default command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["--help"] 