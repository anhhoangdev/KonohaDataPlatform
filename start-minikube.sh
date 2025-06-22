#!/bin/bash

# LocalDataPlatform Minikube Management Script
# This script handles Minikube cluster lifecycle management:
# - Cluster setup with proper resources and addons
# - Basic image management for local development
# - Cluster status and cleanup

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
MINIKUBE_CPUS=16
MINIKUBE_MEMORY=32768
MINIKUBE_DISK=50g
MINIKUBE_DRIVER=docker

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
    ║               LocalDataPlatform Minikube                     ║
    ║                 Cluster Management                           ║
    ║                                                              ║
    ║     🐳 Setup → 🔧 Configure → 📊 Status → 🧹 Cleanup       ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_prerequisites() {
    log_header "CHECKING PREREQUISITES"
    
    local missing_tools=()
    
    # Check if required tools are installed
    for tool in minikube kubectl docker; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        else
            log_success "$tool is installed"
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        echo ""
        echo "Please install the missing tools:"
        echo "  • minikube: https://minikube.sigs.k8s.io/docs/start/"
        echo "  • kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  • docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check system resources
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7/1024}')
    if [ "$available_memory" -lt 20 ]; then
        log_warning "Low available memory (${available_memory}GB). Recommended: 20GB+ for full platform"
        echo "Consider reducing MINIKUBE_MEMORY if needed"
    fi
    
    log_success "All prerequisites are met ✅"
}

setup_minikube() {
    log_header "SETTING UP MINIKUBE CLUSTER"
    
    # Check if minikube is already running
    if minikube status &> /dev/null; then
        log_warning "Minikube is already running."
        read -p "Do you want to recreate the cluster? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Stopping and deleting existing cluster..."
            minikube stop || true
            minikube delete || true
        else
            log_info "Using existing cluster"
            return 0
        fi
    fi
    
    # Start minikube with proper resources
    log_info "Starting Minikube cluster..."
    log_info "Configuration: ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_MEMORY}MB memory, ${MINIKUBE_DISK} disk"
    
    minikube start \
        --cpus=${MINIKUBE_CPUS} \
        --memory=${MINIKUBE_MEMORY} \
        --disk-size=${MINIKUBE_DISK} \
        --driver=${MINIKUBE_DRIVER} \
        --mount \
        --mount-type=sshfs \
        --mount-string="$HOME/Documents/LocalDataPlatform:/hosthome/anhhoangdev/Documents/LocalDataPlatform" \
        --embed-certs
    
    # Enable required addons
    log_info "Enabling Minikube addons..."
    minikube addons enable ingress
    minikube addons enable metrics-server
    minikube addons enable registry
    
    # Wait for addons to be ready
    log_info "Waiting for ingress controller to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx --timeout=300s || log_warning "Ingress controller not ready yet"
    
    log_success "✅ Minikube cluster is ready"
    
    # Show cluster info
    echo ""
    log_info "📋 Cluster Information:"
    echo "  • Kubernetes version: $(kubectl version --short --client=false | grep Server | awk '{print $3}')"
    echo "  • Cluster IP: $(minikube ip)"
    echo "  • Dashboard: minikube dashboard"
    echo "  • Docker daemon: eval \$(minikube docker-env)"
}

configure_docker_env() {
    log_header "CONFIGURING DOCKER ENVIRONMENT"
    
    log_info "Setting up Minikube Docker environment..."
    
    # Check if we can connect to Minikube Docker
    if ! eval $(minikube docker-env 2>/dev/null); then
        log_error "Failed to set up Minikube Docker environment"
        return 1
    fi
    
    # Test Docker connection
    if ! docker info &>/dev/null; then
        log_error "Cannot connect to Minikube Docker daemon"
        return 1
    fi
    
    log_success "✅ Docker environment configured for Minikube"
    echo ""
    log_info "💡 To use Minikube's Docker daemon in your current shell:"
    echo "     eval \$(minikube docker-env)"
}

show_status() {
    log_header "MINIKUBE CLUSTER STATUS"
    
    echo ""
    log_info "🏠 Cluster Status:"
    minikube status
    
    echo ""
    log_info "📊 Node Information:"
    kubectl get nodes -o wide
    
    echo ""
    log_info "🔧 Enabled Addons:"
    minikube addons list | grep enabled
    
    echo ""
    log_info "📦 System Pods:"
    kubectl get pods -n kube-system
    
    echo ""
    log_info "🌐 Services:"
    kubectl get svc --all-namespaces
    
    echo ""
    log_info "📋 Cluster Resources:"
    kubectl top nodes 2>/dev/null || echo "  Metrics not available (enable metrics-server addon)"
    
    echo ""
    log_info "🔗 Access Information:"
    echo "  • Cluster IP: $(minikube ip)"
    echo "  • Dashboard: minikube dashboard"
    echo "  • Registry: $(minikube ip):5000"
}

show_connection_info() {
    log_header "CONNECTION INFORMATION"
    
    echo ""
    echo "🔗 Minikube Access:"
    echo "  • Cluster IP: $(minikube ip)"
    echo "  • Dashboard: minikube dashboard"
    echo "  • SSH into node: minikube ssh"
    echo ""
    echo "🐳 Docker Environment:"
    echo "  • Use Minikube Docker: eval \$(minikube docker-env)"
    echo "  • Registry: $(minikube ip):5000"
    echo ""
    echo "📋 Useful Commands:"
    echo "  • Check cluster: kubectl cluster-info"
    echo "  • Get all resources: kubectl get all --all-namespaces"
    echo "  • Port forward: kubectl port-forward -n <namespace> svc/<service> <local-port>:<remote-port>"
    echo "  • Check logs: kubectl logs <pod-name> -n <namespace>"
    echo ""
    echo "⚡ Cluster Configuration:"
    echo "  • CPUs: ${MINIKUBE_CPUS}"
    echo "  • Memory: ${MINIKUBE_MEMORY}MB"
    echo "  • Disk: ${MINIKUBE_DISK}"
    echo "  • Driver: ${MINIKUBE_DRIVER}"
}

cleanup() {
    log_header "CLEANING UP MINIKUBE"
    
    log_info "🧹 Stopping Minikube cluster..."
    minikube stop || true
    
    read -p "Do you want to delete the cluster completely? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "🗑️  Deleting Minikube cluster..."
        minikube delete || true
        log_success "✅ Cluster deleted completely"
    else
        log_info "Cluster stopped but preserved"
    fi
    
    log_success "✅ Cleanup complete"
}

restart_cluster() {
    log_header "RESTARTING MINIKUBE CLUSTER"
    
    log_info "Stopping cluster..."
    minikube stop || true
    
    log_info "Starting cluster..."
    minikube start
    
    log_success "✅ Cluster restarted"
}

# Main execution logic
main() {
    show_banner
    
    case "${1:-help}" in
        "start"|"setup")
            check_prerequisites
            setup_minikube
            configure_docker_env
            show_connection_info
            ;;
        
        "stop")
            log_info "Stopping Minikube cluster..."
            minikube stop
            log_success "✅ Cluster stopped"
            ;;
        
        "restart")
            restart_cluster
            show_connection_info
            ;;
        
        "delete"|"destroy")
            cleanup
            ;;
        
        "status"|"info")
            show_status
            show_connection_info
            ;;
        
        "docker-env")
            configure_docker_env
            echo ""
            echo "Run the following to configure your shell:"
            echo "eval \$(minikube docker-env)"
            ;;
        
        "dashboard")
            log_info "Opening Minikube dashboard..."
            minikube dashboard
            ;;
        
        "ip")
            echo "Minikube IP: $(minikube ip)"
            ;;
        
        "ssh")
            log_info "Connecting to Minikube node..."
            minikube ssh
            ;;
        
        "help"|"-h"|"--help")
            echo "LocalDataPlatform Minikube Management Script"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  start, setup    Setup and start Minikube cluster with proper configuration"
            echo "  stop            Stop the Minikube cluster (preserves data)"
            echo "  restart         Restart the Minikube cluster"
            echo "  delete, destroy Delete the Minikube cluster completely"
            echo "  status, info    Show cluster status and connection information"
            echo "  docker-env      Configure Docker to use Minikube's Docker daemon"
            echo "  dashboard       Open Minikube dashboard in browser"
            echo "  ip              Show Minikube cluster IP address"
            echo "  ssh             SSH into the Minikube node"
            echo "  help            Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 start        # Setup and start cluster"
            echo "  $0 status       # Check cluster status"
            echo "  $0 docker-env   # Configure Docker environment"
            echo "  $0 stop         # Stop cluster"
            echo "  $0 delete       # Delete cluster completely"
            echo ""
            echo "Configuration:"
            echo "  • CPUs: ${MINIKUBE_CPUS} (modify MINIKUBE_CPUS variable)"
            echo "  • Memory: ${MINIKUBE_MEMORY}MB (modify MINIKUBE_MEMORY variable)"
            echo "  • Disk: ${MINIKUBE_DISK} (modify MINIKUBE_DISK variable)"
            echo "  • Driver: ${MINIKUBE_DRIVER} (modify MINIKUBE_DRIVER variable)"
            echo ""
            echo "For service deployment, use: ./deploy.sh"
            ;;
        
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 