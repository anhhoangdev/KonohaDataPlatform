#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if kubectl is available
check_prerequisites() {
    log_step "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed or not in PATH"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warn "jq is not installed - some features may not work properly"
        log_info "Install jq with: sudo apt-get install jq (Ubuntu/Debian) or brew install jq (macOS)"
    fi
    
    log_info "Prerequisites check completed"
}

# Deploy all components
deploy_infrastructure() {
    log_step "Deploying infrastructure components..."
    
    cd "$(dirname "$0")/../../../"
    
    log_info "Applying Kustomization..."
    kubectl apply -k apps/
    
    log_info "Infrastructure deployment initiated"
}

# Wait for components to be ready
wait_for_components() {
    log_step "Waiting for components to be ready..."
    
    local max_wait=300  # 5 minutes
    local wait_interval=10
    local elapsed=0
    
    log_info "Waiting for Kafka platform components..."
    while [ $elapsed -lt $max_wait ]; do
        local ready_pods=$(kubectl get pods -n kafka-platform --no-headers 2>/dev/null | grep -c "1/1.*Running" || echo "0")
        local total_pods=$(kubectl get pods -n kafka-platform --no-headers 2>/dev/null | wc -l || echo "0")
        
        if [ "$ready_pods" -eq 4 ] && [ "$total_pods" -eq 4 ]; then
            log_info "All Kafka platform components are ready!"
            break
        fi
        
        log_info "Kafka platform: $ready_pods/$total_pods pods ready. Waiting..."
        sleep $wait_interval
        elapsed=$((elapsed + wait_interval))
    done
    
    if [ $elapsed -ge $max_wait ]; then
        log_error "Timeout waiting for Kafka platform components"
        kubectl get pods -n kafka-platform
        return 1
    fi
    
    log_info "Waiting for PostgreSQL CDC source..."
    kubectl wait --for=condition=ready pod -l app=postgres-cdc -n source-data --timeout=60s
    
    log_info "Waiting for MinIO..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=minio -n kyuubi --timeout=60s
    
    log_info "All components are ready!"
}

# Setup connectors
setup_connectors() {
    log_step "Setting up Kafka Connect connectors..."
    
    local script_dir="$(dirname "$0")"
    "$script_dir/setup-connectors.sh" setup
}

# Show status
show_status() {
    log_step "Deployment Summary"
    
    echo ""
    echo "=== Component Status ==="
    kubectl get pods -n kafka-platform -o wide
    kubectl get pods -n source-data -o wide  
    kubectl get pods -n kyuubi -l app.kubernetes.io/name=minio -o wide
    
    echo ""
    echo "=== Services ==="
    kubectl get svc -n kafka-platform
    
    echo ""
    echo "=== Next Steps ==="
    echo "1. Wait a few minutes for connectors to initialize"
    echo "2. Check connector status:"
    echo "   ./infrastructure/apps/kafka/scripts/setup-connectors.sh status"
    echo ""
    echo "3. Test CDC by connecting to PostgreSQL:"
    echo "   kubectl exec -it -n source-data deployment/postgres-cdc -- psql -U cdc_user -d inventory"
    echo ""
    echo "4. View MinIO console:"
    echo "   kubectl port-forward -n kyuubi svc/minio 9001:9001"
    echo "   Open: http://localhost:9001 (minioadmin/minioadmin)"
    echo ""
    echo "5. View Schema Registry:"
    echo "   kubectl port-forward -n kafka-platform svc/schema-registry 8081:8081"
    echo "   curl http://localhost:8081/subjects"
}

# Main execution
main() {
    echo "🚀 Kafka Connect CDC Deployment Script"
    echo "======================================"
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            deploy_infrastructure
            wait_for_components
            setup_connectors
            show_status
            ;;
        "status")
            show_status
            ;;
        "clean")
            log_step "Cleaning up deployment..."
            kubectl delete -k infrastructure/apps/kafka/ || true
            kubectl delete -k infrastructure/apps/postgres-cdc/ || true
            log_info "Cleanup completed"
            ;;
        *)
            echo "Usage: $0 {deploy|status|clean}"
            echo "  deploy  - Full deployment of CDC pipeline"
            echo "  status  - Show current deployment status"  
            echo "  clean   - Remove Kafka and PostgreSQL components"
            exit 1
            ;;
    esac
}

main "$@" 