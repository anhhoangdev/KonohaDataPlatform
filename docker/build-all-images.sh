#!/bin/bash
set -e

# LocalDataPlatform Docker Image Build Script
# Builds all custom Docker images using pre-downloaded dependencies

# Colors for output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if downloads directory exists
DOWNLOAD_DIR="$(dirname "$0")/downloads"
if [ ! -d "$DOWNLOAD_DIR" ]; then
    log_error "Downloads directory not found: $DOWNLOAD_DIR"
    echo "Please run: ./download-dependencies.sh first"
    exit 1
fi

# Check if we have the required files
required_files=(
    "apache-hive-3.1.3-bin.tar.gz"
    "hadoop-3.3.4.tar.gz"
    "postgresql-42.2.24.jar"
    "aws-java-sdk-bundle-1.11.901.jar"
    "hadoop-aws-3.3.4.jar"
    "iceberg-hive-metastore-1.4.2.jar"
    "apache-kyuubi-1.10.0-bin.tgz"
    "spark-3.5.0-bin-hadoop3.tgz"
    "iceberg-spark-runtime-3.5_2.12-1.4.2.jar"
    "iceberg-aws-bundle-1.4.2.jar"
    "bundle-2.17.230.jar"
    "url-connection-client-2.17.230.jar"
    "kyuubi-spark-sql-engine_2.12-1.10.0.jar"
    "debezium-connector-postgres-2.4.2.Final-plugin.tar.gz"
    "iceberg-kafka-connect-runtime-1.5.0.jar"
    "aws-java-sdk-bundle-1.12.500.jar"
    "iceberg-aws-bundle-1.5.0.jar"
    "kafka-schema-registry-client-7.5.0.jar"
)

log_info "Checking for required download files..."
missing_files=()
for file in "${required_files[@]}"; do
    if [ ! -f "$DOWNLOAD_DIR/$file" ]; then
        missing_files+=("$file")
    fi
done

if [ ${#missing_files[@]} -ne 0 ]; then
    log_error "Missing required files:"
    for file in "${missing_files[@]}"; do
        echo "  - $file"
    done
    echo ""
    echo "Please run: ./download-dependencies.sh"
    exit 1
fi

log_success "All required files are available"

# Build images
DOCKER_BASE_DIR="$(dirname "$0")"

build_image() {
    local image_name="$1"
    local dockerfile_dir="$2"
    local context_dir="${3:-$DOCKER_BASE_DIR}"
    
    log_info "🐳 Building $image_name..."
    if docker build -t "$image_name" -f "$dockerfile_dir/Dockerfile" "$context_dir"; then
        log_success "✅ Successfully built $image_name"
        return 0
    else
        log_error "❌ Failed to build $image_name"
        return 1
    fi
}

# Track build results
build_errors=0

# Build Hive Metastore
if ! build_image "hive-metastore:3.1.3" "$DOCKER_BASE_DIR/hive-metastore" "$DOCKER_BASE_DIR"; then
    ((build_errors++))
fi

# Build Kyuubi Server
if ! build_image "kyuubi-server:1.10.0" "$DOCKER_BASE_DIR/kyuubi-server" "$DOCKER_BASE_DIR"; then
    ((build_errors++))
fi

# Build Spark Engine Iceberg
if ! build_image "spark-engine-iceberg:3.5.0-1.4.2" "$DOCKER_BASE_DIR/spark-engine-iceberg" "$DOCKER_BASE_DIR"; then
    ((build_errors++))
fi

# Build DBT Spark
if ! build_image "dbt-spark:latest" "$DOCKER_BASE_DIR/dbt-spark" "$DOCKER_BASE_DIR"; then
    ((build_errors++))
fi

# Build Kafka Connect Full
if ! build_image "local-kafka-connect-full:latest" "$DOCKER_BASE_DIR/kafka-connect" "$DOCKER_BASE_DIR"; then
    ((build_errors++))
fi

# Build Postgres CDC
if ! build_image "local-postgres-cdc:v2" "$DOCKER_BASE_DIR/postgres" "$DOCKER_BASE_DIR"; then
    ((build_errors++))
fi

# Summary
echo ""
if [ $build_errors -eq 0 ]; then
    log_success "🎉 All Docker images built successfully!"
    echo ""
    log_info "📋 Built images:"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep -E "(hive-metastore|kyuubi-server|spark-engine-iceberg|dbt-spark|local-kafka-connect-full|local-postgres-cdc)" || true
else
    log_error "❌ $build_errors image(s) failed to build"
    exit 1
fi

echo ""
log_success "✅ Ready for LocalDataPlatform deployment!"
echo "Run: ./deploy.sh deploy" 