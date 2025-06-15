#!/bin/bash

# LocalDataPlatform Docker Image Builder
# Builds custom Docker images for Minikube deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Custom Docker images
HIVE_METASTORE_IMAGE="hive-metastore-custom:3.1.3"
KYUUBI_SERVER_IMAGE="kyuubi-server:1.10.0"
SPARK_ENGINE_ICEBERG_IMAGE="spark-engine-iceberg:3.5.0-1.4.2"

# Docker image directories
DOCKER_BASE_DIR="docker"
HIVE_METASTORE_DIR="${DOCKER_BASE_DIR}/hive-metastore"
KYUUBI_SERVER_DIR="${DOCKER_BASE_DIR}/kyuubi-server"
SPARK_ENGINE_ICEBERG_DIR="${DOCKER_BASE_DIR}/spark-engine-iceberg"

# Helper functions
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

log_header() {
    echo -e "${PURPLE}========================================${NC}"
    echo -e "${PURPLE}$1${NC}"
    echo -e "${PURPLE}========================================${NC}"
}

show_banner() {
    echo -e "${PURPLE}"
    cat << "EOF"
    ╔══════════════════════════════════════════════════════════════╗
    ║                LocalDataPlatform                             ║
    ║                Docker Image Builder                          ║
    ║                                                              ║
    ║  🐝 Hive Metastore + 📊 Kyuubi + ⚡ Spark + 🧊 Iceberg     ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check if we can connect to Minikube Docker
check_minikube_docker() {
    log_info "Checking Minikube Docker connection..."
    
    # Check if minikube is running
    if ! minikube status &> /dev/null; then
        log_error "Minikube is not running!"
        echo "Please start Minikube first: minikube start"
        return 1
    fi
    
    # Set up Minikube Docker environment
    eval $(minikube docker-env 2>/dev/null) || {
        log_error "Failed to set up Minikube Docker environment"
        echo "Make sure Minikube is running: minikube start"
        return 1
    }
    
    # Test Docker connection
    if ! docker info &>/dev/null; then
        log_error "Cannot connect to Minikube Docker daemon"
        return 1
    fi
    
    log_success "Successfully connected to Minikube Docker daemon"
    return 0
}

# Build a single Docker image with proper error handling
build_single_image() {
    local image_name="$1"
    local dockerfile_dir="$2"
    local context_dir="${3:-$dockerfile_dir}"
    
    log_info "🐳 Building image: ${image_name}"
    log_info "📁 Using Dockerfile from: ${dockerfile_dir}"
    log_info "📁 Using build context: ${context_dir}"
    
    # Check if Dockerfile exists
    if [[ ! -f "${dockerfile_dir}/Dockerfile" ]]; then
        log_error "Dockerfile not found in ${dockerfile_dir}"
        return 1
    fi
    
    # Build the image with proper error handling
    log_info "Building ${image_name}... (this may take several minutes)"
    local build_log="/tmp/docker-build-${image_name//[^a-zA-Z0-9]/-}.log"
    
    # Use absolute paths to avoid path issues
    local abs_dockerfile_dir=$(realpath "${dockerfile_dir}")
    local abs_context_dir=$(realpath "${context_dir}")
    
    if docker build --no-cache -t "${image_name}" -f "${abs_dockerfile_dir}/Dockerfile" "${abs_context_dir}" 2>&1 | tee "${build_log}"; then
        log_success "✅ Successfully built ${image_name}"
        
        # Verify the image exists
        if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$"; then
            log_success "✅ Image ${image_name} is available in Minikube Docker registry"
            
            # Show image size
            local image_size=$(docker images --format "{{.Size}}" "${image_name}" | head -1)
            log_info "📏 Image size: ${image_size}"
        else
            log_error "❌ Image ${image_name} was not found after build"
            return 1
        fi
    else
        log_error "❌ Failed to build ${image_name}"
        echo "Build log saved to: ${build_log}"
        echo "Last 20 lines of build log:"
        tail -20 "${build_log}" || true
        return 1
    fi
    
    return 0
}

# Verify image exists in Minikube
verify_image_exists() {
    local image_name="$1"
    
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${image_name}$"; then
        log_success "✅ Image ${image_name} is available"
        return 0
    else
        log_error "❌ Image ${image_name} is not available"
        return 1
    fi
}

# Clean up old images to save space
cleanup_old_images() {
    log_info "🧹 Cleaning up old/unused Docker images to save space..."
    
    # Remove dangling images
    docker image prune -f &>/dev/null || true
    
    # Remove old versions of our custom images (keep only latest)
    docker images --format "{{.Repository}}:{{.Tag}}" | grep -E "^(hive-metastore-custom|kyuubi-server|spark-engine-iceberg)" | tail -n +4 | xargs -r docker rmi &>/dev/null || true
    
    log_info "✅ Docker cleanup completed"
}

# Build all custom images
build_all_images() {
    log_header "BUILDING ALL CUSTOM DOCKER IMAGES"
    
    # Set up Minikube Docker environment
    log_info "Setting up Minikube Docker environment..."
    if ! check_minikube_docker; then
        log_error "Failed to set up Minikube Docker environment"
        exit 1
    fi
    
    # Track build success
    local build_errors=0
    
    # Clean up old images first
    cleanup_old_images
    
    # Build Hive Metastore custom image
    if [[ -d "${HIVE_METASTORE_DIR}" ]]; then
        if ! build_single_image "${HIVE_METASTORE_IMAGE}" "${HIVE_METASTORE_DIR}"; then
            ((build_errors++))
        fi
    else
        log_warning "Hive Metastore Docker directory not found: ${HIVE_METASTORE_DIR}"
        ((build_errors++))
    fi
    
    # Build Kyuubi Server custom image
    if [[ -d "${KYUUBI_SERVER_DIR}" ]]; then
        if ! build_single_image "${KYUUBI_SERVER_IMAGE}" "${KYUUBI_SERVER_DIR}"; then
            ((build_errors++))
        fi
    else
        log_warning "Kyuubi Server Docker directory not found: ${KYUUBI_SERVER_DIR}"
        ((build_errors++))
    fi
    
    # Build Spark Engine Iceberg custom image
    if [[ -d "${SPARK_ENGINE_ICEBERG_DIR}" ]]; then
        if ! build_single_image "${SPARK_ENGINE_ICEBERG_IMAGE}" "${SPARK_ENGINE_ICEBERG_DIR}"; then
            ((build_errors++))
        fi
    else
        log_warning "Spark Engine Iceberg Docker directory not found: ${SPARK_ENGINE_ICEBERG_DIR}"
        ((build_errors++))
    fi
    
    # Check if we had any build errors
    if [ $build_errors -gt 0 ]; then
        log_error "❌ ${build_errors} image(s) failed to build"
        echo ""
        echo "🔍 Troubleshooting tips:"
        echo "  • Check build logs in /tmp/docker-build-*.log"
        echo "  • Ensure Docker has enough disk space"
        echo "  • Try running with more memory: minikube start --memory=16384"
        echo "  • Check internet connection for downloading dependencies"
        exit 1
    fi
    
    # Final verification of all images
    log_info "🔍 Final verification of all custom images..."
    local verification_errors=0
    
    for image in "${HIVE_METASTORE_IMAGE}" "${KYUUBI_SERVER_IMAGE}" "${SPARK_ENGINE_ICEBERG_IMAGE}"; do
        if ! verify_image_exists "$image"; then
            ((verification_errors++))
        fi
    done
    
    if [ $verification_errors -gt 0 ]; then
        log_error "❌ ${verification_errors} image(s) are not available for deployment"
        exit 1
    fi
    
    # Show final status
    echo ""
    log_info "📋 Successfully built custom images:"
    docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep -E "(hive-metastore-custom|kyuubi-server|spark-engine-iceberg)" || true
    echo ""
    
    log_success "✅ All custom Docker images built and verified successfully"
}

# Verify all images exist
verify_all_images() {
    log_header "VERIFYING CUSTOM IMAGES"
    
    if ! check_minikube_docker; then
        exit 1
    fi
    
    local verification_errors=0
    
    for image in "${HIVE_METASTORE_IMAGE}" "${KYUUBI_SERVER_IMAGE}" "${SPARK_ENGINE_ICEBERG_IMAGE}"; do
        if ! verify_image_exists "$image"; then
            ((verification_errors++))
        fi
    done
    
    if [ $verification_errors -eq 0 ]; then
        log_success "✅ All custom images are available for deployment"
        echo ""
        log_info "📋 Available custom images:"
        docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | grep -E "(hive-metastore-custom|kyuubi-server|spark-engine-iceberg)" || true
    else
        log_error "❌ ${verification_errors} image(s) are missing"
        echo "Run: $0 build"
        exit 1
    fi
}

# Clean up all custom images
cleanup_all_images() {
    log_header "CLEANING UP CUSTOM IMAGES"
    
    if ! check_minikube_docker; then
        exit 1
    fi
    
    log_info "🧹 Removing custom Docker images..."
    for image in "${HIVE_METASTORE_IMAGE}" "${KYUUBI_SERVER_IMAGE}" "${SPARK_ENGINE_ICEBERG_IMAGE}"; do
        if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
            log_info "Removing image: ${image}"
            docker rmi "${image}" || true
        else
            log_info "Image not found: ${image}"
        fi
    done
    
    # Clean up dangling images
    cleanup_old_images
    
    log_success "✅ Custom images cleanup complete"
}

# Main execution
main() {
    show_banner
    
    case "${1:-build}" in
        "build")
            build_all_images
            ;;
        "verify")
            verify_all_images
            ;;
        "cleanup")
            cleanup_all_images
            ;;
        "hive")
            check_minikube_docker || exit 1
            build_single_image "${HIVE_METASTORE_IMAGE}" "${HIVE_METASTORE_DIR}"
            ;;
        "kyuubi")
            check_minikube_docker || exit 1
            build_single_image "${KYUUBI_SERVER_IMAGE}" "${KYUUBI_SERVER_DIR}"
            ;;
        "spark")
            check_minikube_docker || exit 1
            build_single_image "${SPARK_ENGINE_ICEBERG_IMAGE}" "${SPARK_ENGINE_ICEBERG_DIR}"
            ;;
        *)
            echo "Usage: $0 [build|verify|cleanup|hive|kyuubi|spark]"
            echo ""
            echo "Commands:"
            echo "  build   - Build all custom Docker images (default)"
            echo "  verify  - Verify that all custom images are available"
            echo "  cleanup - Clean up all custom Docker images"
            echo "  hive    - Build only the Hive Metastore image"
            echo "  kyuubi  - Build only the Kyuubi Server image"
            echo "  spark   - Build only the Spark Engine Iceberg image"
            echo ""
            echo "🐳 Custom Images:"
            echo "  • ${HIVE_METASTORE_IMAGE} - Hive Metastore with S3/MinIO support"
            echo "  • ${KYUUBI_SERVER_IMAGE} - Kyuubi SQL Gateway"
            echo "  • ${SPARK_ENGINE_ICEBERG_IMAGE} - Spark with Iceberg support"
            echo ""
            echo "🚀 Requirements:"
            echo "  • Minikube must be running"
            echo "  • Docker must be available"
            echo "  • Internet connection for downloading dependencies"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 