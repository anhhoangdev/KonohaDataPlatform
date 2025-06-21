#!/bin/bash
set -e

# LocalDataPlatform Dependency Download Script
# Downloads all necessary JAR files and dependencies for custom Docker images

# Directory to store downloads
DOWNLOAD_DIR="$(dirname "$0")/downloads"
mkdir -p "$DOWNLOAD_DIR"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

usage() {
    echo "LocalDataPlatform Dependency Download Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Downloads all necessary dependencies for:"
    echo "  • Hive Metastore (with Iceberg support)"
    echo "  • Kyuubi Server"
    echo "  • Spark Engine (with Iceberg support)"
    echo "  • Flink CDC (with Iceberg support)"
    echo "  • Kafka Connect (with S3, Debezium, and Iceberg connectors)"
    echo "  • Iceberg REST Catalog"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo "  --clean       Remove downloads directory before downloading"
    echo ""
    echo "Downloaded files will be stored in: $DOWNLOAD_DIR"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        --clean)
            log_info "Cleaning downloads directory..."
            rm -rf "$DOWNLOAD_DIR"
            mkdir -p "$DOWNLOAD_DIR"
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
    shift
done

download_file() {
    local url=$1
    local filename=$(basename "$url")
    local filepath="$DOWNLOAD_DIR/$filename"

    if [ -f "$filepath" ]; then
        log_info "File already exists: $filename"
    else
        log_info "Downloading: $filename"
        wget -q --show-progress -O "$filepath" "$url"
        log_success "Downloaded: $filename"
    fi
}

# Hive Metastore Dependencies
log_info "--- Downloading Hive Metastore Dependencies ---"
download_file "https://archive.apache.org/dist/hive/hive-3.1.3/apache-hive-3.1.3-bin.tar.gz"
download_file "https://archive.apache.org/dist/hadoop/common/hadoop-3.3.4/hadoop-3.3.4.tar.gz"
download_file "https://jdbc.postgresql.org/download/postgresql-42.2.24.jar"
download_file "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.901/aws-java-sdk-bundle-1.11.901.jar"
download_file "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar"
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-hive-metastore/1.4.2/iceberg-hive-metastore-1.4.2.jar"

# Kyuubi Server Dependencies
log_info "--- Downloading Kyuubi Server Dependencies ---"
download_file "https://archive.apache.org/dist/kyuubi/kyuubi-1.10.0/apache-kyuubi-1.10.0-bin.tgz"
download_file "https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.12/1.10.0/kyuubi-spark-sql-engine_2.12-1.10.0.jar"

# Spark Engine Dependencies
log_info "--- Downloading Spark Engine Dependencies ---"
download_file "https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz"
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.4.2/iceberg-spark-runtime-3.5_2.12-1.4.2.jar"
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.4.2/iceberg-aws-bundle-1.4.2.jar"
download_file "https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.17.230/bundle-2.17.230.jar"
download_file "https://repo1.maven.org/maven2/software/amazon/awssdk/url-connection-client/2.17.230/url-connection-client-2.17.230.jar"

# Flink CDC & Iceberg Dependencies
log_info "--- Downloading Flink CDC & Iceberg Dependencies ---"
# Flink binary (for optional image build based on tarball)
download_file "https://archive.apache.org/dist/flink/flink-1.17.1/flink-1.17.1-bin-scala_2.12.tgz"
# Iceberg Flink runtime for Flink 1.17
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-flink-runtime-1.17/1.4.2/iceberg-flink-runtime-1.17-1.4.2.jar"
# Flink Hive connector (connects Flink to Hive Metastore 3.1.3)
download_file "https://repo1.maven.org/maven2/org/apache/flink/flink-sql-connector-hive-3.1.3_2.12/1.17.1/flink-sql-connector-hive-3.1.3_2.12-1.17.1.jar"
# Postgres CDC connector (Debezium-powered)
download_file "https://repo1.maven.org/maven2/com/ververica/flink-sql-connector-postgres-cdc/2.4.1/flink-sql-connector-postgres-cdc-2.4.1.jar"

# Kafka Connect Dependencies (S3, Debezium, Iceberg)
log_info "--- Downloading Kafka Connect Dependencies ---"
# Iceberg Kafka Connect runtime (main connector)
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-kafka-connect-runtime/1.5.0/iceberg-kafka-connect-runtime-1.5.0.jar"
# Debezium PostgreSQL Connector
download_file "https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/2.4.2.Final/debezium-connector-postgres-2.4.2.Final-plugin.tar.gz"
# AWS SDK for S3 support (updated version)
download_file "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.500/aws-java-sdk-bundle-1.12.500.jar"
# Iceberg AWS bundle for S3 integration
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.5.0/iceberg-aws-bundle-1.5.0.jar"
# Schema Registry client for AVRO support
download_file "https://repo1.maven.org/maven2/io/confluent/kafka-schema-registry-client/7.5.0/kafka-schema-registry-client-7.5.0.jar"
# AVRO converter for Schema Registry integration
download_file "https://repo1.maven.org/maven2/io/confluent/kafka-connect-avro-converter/7.5.0/kafka-connect-avro-converter-7.5.0.jar"

# Iceberg REST Catalog Dependencies
log_info "--- Downloading Iceberg REST Catalog Dependencies ---"
# Iceberg REST catalog server
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-rest-server/1.5.0/iceberg-rest-server-1.5.0.jar"
# Additional Iceberg core libraries
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-core/1.5.0/iceberg-core-1.5.0.jar"
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-api/1.5.0/iceberg-api-1.5.0.jar"

log_success "All dependencies downloaded successfully to $DOWNLOAD_DIR"

# Show summary
echo ""
log_info "📋 Download Summary:"
echo "  Directory: $DOWNLOAD_DIR"
if command -v du &> /dev/null; then
    echo "  Total size: $(du -sh "$DOWNLOAD_DIR" 2>/dev/null | cut -f1 || echo "Unknown")"
fi
echo "  Files downloaded: $(find "$DOWNLOAD_DIR" -type f | wc -l)"
echo ""
log_info "🐳 Ready for Docker image builds:"
echo "  • Hive Metastore: docker build -t hive-metastore:3.1.3 docker/hive-metastore/"
echo "  • Kyuubi Server: docker build -t kyuubi-server:1.10.0 docker/kyuubi-server/"
echo "  • Spark Engine: docker build -t spark-engine-iceberg:3.5.0-1.4.2 docker/spark-engine-iceberg/"
echo "  • Kafka Connect: docker build -t local-kafka-connect-full:latest docker/kafka-connect/"
echo ""
log_success "✅ All dependencies ready for LocalDataPlatform deployment!" 