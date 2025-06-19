#!/bin/bash
set -e

# Directory to store downloads
DOWNLOAD_DIR="$(dirname "$0")/downloads"
mkdir -p "$DOWNLOAD_DIR"

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

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

# Kyuubi Server Dependencies
log_info "--- Downloading Kyuubi Server Dependencies ---"
download_file "https://archive.apache.org/dist/kyuubi/kyuubi-1.10.0/apache-kyuubi-1.10.0-bin.tgz"

# Spark Engine Dependencies
log_info "--- Downloading Spark Engine Dependencies ---"
download_file "https://archive.apache.org/dist/spark/spark-3.5.0/spark-3.5.0-bin-hadoop3.tgz"
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.4.2/iceberg-spark-runtime-3.5_2.12-1.4.2.jar"
download_file "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws-bundle/1.4.2/iceberg-aws-bundle-1.4.2.jar"
download_file "https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/2.17.230/bundle-2.17.230.jar"
download_file "https://repo1.maven.org/maven2/software/amazon/awssdk/url-connection-client/2.17.230/url-connection-client-2.17.230.jar"

log_success "All dependencies downloaded successfully to $DOWNLOAD_DIR" 