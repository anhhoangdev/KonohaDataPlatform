#!/bin/bash

# Kyuubi LocalDataPlatform Setup Script
# This script handles the complete setup from scratch including:
# - Minikube cluster setup with proper resources
# - Docker image building
# - Kubernetes deployment
# - Port forwarding setup

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MINIKUBE_CPUS=16
MINIKUBE_MEMORY=32768
MINIKUBE_DISK=50g
KYUUBI_NAMESPACE=kyuubi

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

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if required tools are installed
    for tool in minikube kubectl docker; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    log_success "All prerequisites are installed"
}

setup_minikube() {
    log_info "Setting up Minikube cluster..."
    
    # Check if minikube is already running
    if minikube status &> /dev/null; then
        log_warning "Minikube is already running. Stopping and recreating..."
        minikube stop
        minikube delete
    fi
    
    # Start minikube with proper resources
    log_info "Starting Minikube with ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_MEMORY}MB memory, ${MINIKUBE_DISK} disk..."
    minikube start \
        --cpus=${MINIKUBE_CPUS} \
        --memory=${MINIKUBE_MEMORY} \
        --disk-size=${MINIKUBE_DISK} \
        --driver=docker \
        --mount \
        --mount-type=sshfs \
        --mount-string="$HOME/Documents/LocalDataPlatform:/hosthome/anhhoangdev/Documents/LocalDataPlatform" \
        --embed-certs \
        
        # Enable required addons
    log_info "Enabling Minikube addons..."
    minikube addons enable ingress
    minikube addons enable metrics-server
    
    log_success "Minikube cluster is ready"
}

build_images() {
    log_info "Building Docker images locally..."
    
    # Define image names and tags
    local images=(
        "hive-metastore:3.1.3"
        "kyuubi-server:1.10.0" 
        "spark-engine-iceberg:1.5.0"
        "dbt-spark:latest"
        "kafka-connect-iceberg:latest"
    )
    
    local directories=(
        "docker/hive-metastore"
        "docker/kyuubi-server"
        "docker/spark-engine-iceberg"
        "docker/dbt-spark"
        "docker/kafka-connect-iceberg"
    )
    
    # Check if images already exist locally
    local build_needed=false
    for image in "${images[@]}"; do
        if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "^${image}$"; then
            log_info "Image ${image} not found locally, will build"
            build_needed=true
        else
            log_info "Image ${image} already exists locally"
        fi
    done
    
    # Build images locally if needed
    if [ "$build_needed" = true ] || [ "${FORCE_BUILD:-false}" = "true" ]; then
        log_info "Building Docker images locally..."
        
        # Build Hive Metastore image
        log_info "Building Hive Metastore image..."
        (cd docker/hive-metastore && docker build -t hive-metastore:3.1.3 .)
        
        # Build Kyuubi Server image  
        log_info "Building Kyuubi Server image..."
        (cd docker/kyuubi-server && docker build -t kyuubi-server:1.10.0 .)
        
        # Build Spark Engine image
        log_info "Building Spark Engine with Iceberg image..."
        (cd docker/spark-engine-iceberg && docker build -t spark-engine-iceberg:1.5.0 .)
        
        # Build Kafka Connect Iceberg image
        log_info "Building Kafka Connect Iceberg image..."
        (cd docker/kafka-connect-iceberg && docker build -t kafka-connect-iceberg:latest .)
        
        log_success "All Docker images built locally"
    else
        log_info "All images exist locally, skipping build (use FORCE_BUILD=true to rebuild)"
    fi
    
    # Load images into Minikube
    log_info "Loading images into Minikube..."
    for image in "${images[@]}"; do
        log_info "Loading ${image} into Minikube..."
        minikube image load ${image}
    done
    
    log_success "All images loaded into Minikube"
    
    # List images in Minikube
    log_info "Images available in Minikube:"
    minikube image ls | grep -E "(hive-metastore|kyuubi-server|spark-engine-iceberg|kafka-connect-iceberg)" || echo "No custom images found in Minikube"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure components..."
    
    # Deploy Hive Metastore (which includes MariaDB)
    log_info "Deploying Hive Metastore and MariaDB..."
    kubectl apply -k infrastructure/apps/hive-metastore/
    
    # Wait for MariaDB to be ready
    log_info "Waiting for MariaDB to be ready..."
    kubectl wait --for=condition=ready pod -l app=mariadb -n kyuubi --timeout=300s
    
    # Wait for Hive Metastore to be ready
    log_info "Waiting for Hive Metastore to be ready..."
    kubectl wait --for=condition=ready pod -l app=hive-metastore -n kyuubi --timeout=300s
    
    log_success "Infrastructure components deployed successfully"
}

deploy_kyuubi() {
    log_info "Deploying Kyuubi services..."
    
    # Deploy Kyuubi
    kubectl apply -k infrastructure/apps/kyuubi/
    
    # Wait for Kyuubi deployments to be ready
    log_info "Waiting for Kyuubi deployments to be ready..."
    kubectl wait --for=condition=available deployment/kyuubi-dbt -n ${KYUUBI_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=available deployment/kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --timeout=300s
    
    log_success "Kyuubi services deployed successfully"
}

setup_port_forwarding() {
    log_info "Setting up port forwarding..."
    
    # Kill any existing port forwarding processes
    pkill -f "kubectl.*port-forward.*kyuubi" || true
    
    # Start port forwarding in background
    log_info "Starting port forwarding for kyuubi-dbt-shared (SERVER-level) on port 10009..."
    kubectl port-forward -n ${KYUUBI_NAMESPACE} svc/kyuubi-dbt-shared 10009:10009 &
    
    log_info "Starting port forwarding for kyuubi-dbt (USER-level) on port 10010..."
    kubectl port-forward -n ${KYUUBI_NAMESPACE} svc/kyuubi-dbt 10010:10009 &
    
    # Wait a moment for port forwarding to establish
    sleep 5
    
    log_success "Port forwarding setup complete"
}

test_connectivity() {
    log_info "Testing connectivity..."
    
    # Test port accessibility
    for port in 10009 10010; do
        if timeout 5 bash -c "</dev/tcp/localhost/${port}" 2>/dev/null; then
            log_success "Port ${port} is accessible"
        else
            log_warning "Port ${port} is not accessible yet"
        fi
    done
}

show_status() {
    log_info "Deployment Status:"
    echo
    
    # Show cluster info
    echo "=== Minikube Status ==="
    minikube status
    echo
    
    # Show all pods
    echo "=== All Pods ==="
    kubectl get pods --all-namespaces -o wide
    echo
    
    # Show Kyuubi specific resources
    echo "=== Kyuubi Resources ==="
    kubectl get all -n ${KYUUBI_NAMESPACE}
    echo
    
    # Show services
    echo "=== Services ==="
    kubectl get svc --all-namespaces
    echo
    
    # Show port forwarding processes
    echo "=== Port Forwarding Processes ==="
    ps aux | grep "kubectl.*port-forward" | grep -v grep || echo "No port forwarding processes found"
    echo
}

show_connection_info() {
    log_success "=== Kyuubi LocalDataPlatform is Ready! ==="
    echo
    echo "🔗 Connection Information:"
    echo "  📊 DataGrip/JDBC Connections:"
    echo "    • SERVER-level (shared, 15min timeout): jdbc:hive2://localhost:10009/default"
    echo "    • USER-level (individual, 30s timeout): jdbc:hive2://localhost:10010/default"
    echo
    echo "🚀 Services:"
    echo "  • Kyuubi Server (shared): http://localhost:10009"
    echo "  • Kyuubi Server (user-level): http://localhost:10010"
    echo "  • Hive Metastore: thrift://localhost:9083 (internal)"
    echo
    echo "📋 Useful Commands:"
    echo "  • Check pods: kubectl get pods -n ${KYUUBI_NAMESPACE}"
    echo "  • Check logs: kubectl logs <pod-name> -n ${KYUUBI_NAMESPACE}"
    echo "  • Restart port forwarding: ./run.sh port-forward"
    echo "  • Full status: ./run.sh status"
    echo
    echo "⚡ Performance:"
    echo "  • Minikube: ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_MEMORY}MB RAM"
    echo "  • Dynamic Spark executors: 0-9 (12GB RAM, 2 cores each)"
    echo "  • Timeout: USER=30s, SERVER=15min"
    echo
}

cleanup() {
    log_info "Cleaning up..."
    
    # Kill port forwarding processes
    pkill -f "kubectl.*port-forward.*kyuubi" || true
    
    # Stop minikube
    minikube stop || true
    
    log_success "Cleanup complete"
}

# Main execution logic
case "${1:-full}" in
    "full")
        log_info "Starting full Kyuubi LocalDataPlatform deployment..."
        check_prerequisites
        setup_minikube
        build_images
        deploy_infrastructure
        deploy_kyuubi
        setup_port_forwarding
        test_connectivity
        show_status
        show_connection_info
        ;;
    
    "minikube")
        log_info "Setting up Minikube only..."
        check_prerequisites
        setup_minikube
        log_success "Minikube setup complete"
        ;;
    
    "build")
        log_info "Building images only..."
        build_images
        ;;
    
    "force-build")
        log_info "Force building all images..."
        FORCE_BUILD=true build_images
        ;;
    
    "deploy")
        log_info "Deploying applications only..."
        deploy_infrastructure
        deploy_kyuubi
        log_success "Deployment complete"
        ;;
    
    "port-forward")
        log_info "Setting up port forwarding only..."
        setup_port_forwarding
        test_connectivity
        log_success "Port forwarding setup complete"
        ;;
    
    "status")
        show_status
        show_connection_info
        ;;
    
    "test")
        log_info "Testing connectivity..."
        test_connectivity
        ;;
    
    "cleanup")
        cleanup
        ;;
    
    "restart")
        log_info "Restarting Kyuubi services..."
        kubectl rollout restart deployment/kyuubi-dbt -n ${KYUUBI_NAMESPACE}
        kubectl rollout restart deployment/kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE}
        kubectl rollout status deployment/kyuubi-dbt -n ${KYUUBI_NAMESPACE}
        kubectl rollout status deployment/kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE}
        setup_port_forwarding
        log_success "Kyuubi services restarted"
        ;;
    
    "help"|"-h"|"--help")
        echo "Kyuubi LocalDataPlatform Setup Script"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  full         Complete setup (default) - Minikube + Build + Deploy + Port Forward"
        echo "  minikube     Setup Minikube cluster only"
        echo "  build        Build Docker images locally and load into Minikube (smart caching)"
        echo "  force-build  Force rebuild all Docker images (ignores existing images)"
        echo "  deploy       Deploy applications only"
        echo "  port-forward Setup port forwarding only"
        echo "  status       Show deployment status and connection info"
        echo "  test         Test connectivity"
        echo "  restart      Restart Kyuubi services"
        echo "  cleanup      Stop services and cleanup"
        echo "  help         Show this help message"
        echo
        echo "Examples:"
        echo "  $0           # Full setup"
        echo "  $0 build     # Build images (uses cache if images exist)"
        echo "  $0 force-build # Force rebuild all images"
        echo "  $0 status    # Check status"
        echo "  $0 cleanup   # Stop everything"
        echo
        echo "Image Building:"
        echo "  • Images are built locally first, then loaded into Minikube"
        echo "  • Existing images are reused unless force-build is used"
        echo "  • Use FORCE_BUILD=true ./run.sh build to force rebuild"
        ;;
    
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac 