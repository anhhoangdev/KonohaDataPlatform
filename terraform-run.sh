#!/bin/bash

# Kyuubi LocalDataPlatform Terraform Setup Script
# This script handles the complete Infrastructure as Code setup including:
# - Minikube cluster setup with proper resources
# - Terraform infrastructure deployment
# - HashiCorp Vault for secrets management
# - FluxCD for GitOps deployment
# - Docker image building and deployment

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MINIKUBE_CPUS=12
MINIKUBE_MEMORY=24576
MINIKUBE_DISK=50g
TERRAFORM_DIR="terraform"
VAULT_NAMESPACE="vault-system"
FLUX_NAMESPACE="flux-system"
KYUUBI_NAMESPACE="kyuubi"

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
    for tool in minikube kubectl docker terraform flux vault; do
        if ! command -v $tool &> /dev/null; then
            log_error "$tool is not installed. Please install it first."
            echo "Installation guides:"
            echo "  - Minikube: https://minikube.sigs.k8s.io/docs/start/"
            echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
            echo "  - Docker: https://docs.docker.com/get-docker/"
            echo "  - Terraform: https://learn.hashicorp.com/tutorials/terraform/install-cli"
            echo "  - FluxCD CLI: https://fluxcd.io/flux/installation/"
            echo "  - Vault CLI: https://learn.hashicorp.com/tutorials/vault/getting-started-install"
            exit 1
        fi
    done
    
    # Check if GitHub token is set
    if [[ -z "${GITHUB_TOKEN}" ]]; then
        log_error "GITHUB_TOKEN environment variable is not set."
        echo "Please set your GitHub personal access token:"
        echo "export GITHUB_TOKEN=your_github_token_here"
        exit 1
    fi
    
    # Check if GitHub owner is set
    if [[ -z "${GITHUB_OWNER}" ]]; then
        log_warning "GITHUB_OWNER not set, using default 'your-github-username'"
        export GITHUB_OWNER="your-github-username"
    fi
    
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
        --driver=docker
    
    # Enable required addons
    log_info "Enabling Minikube addons..."
    minikube addons enable ingress
    minikube addons enable metrics-server
    
    log_success "Minikube cluster is ready"
}

build_images() {
    log_info "Building Docker images..."
    
    # Set Docker environment to use Minikube's Docker daemon
    eval $(minikube docker-env)
    
    # Build Hive Metastore image
    log_info "Building Hive Metastore image..."
    docker build -t hive-metastore:3.1.3 -f docker/hive-metastore/Dockerfile .
    
    # Build Kyuubi Server image
    log_info "Building Kyuubi Server image..."
    docker build -t kyuubi-server:1.10.0 -f docker/kyuubi-server/Dockerfile .
    
    # Build Spark Engine image
    log_info "Building Spark Engine with Iceberg image..."
    docker build -t spark-engine-iceberg:1.5.0 -f docker/spark-engine-iceberg/Dockerfile .
    
    log_success "All Docker images built successfully"
    
    # List built images
    log_info "Built images:"
    docker images | grep -E "(hive-metastore|kyuubi-server|spark-engine-iceberg)"
}

setup_terraform() {
    log_info "Setting up Terraform..."
    
    cd ${TERRAFORM_DIR}
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f terraform.tfvars ]]; then
        log_info "Creating terraform.tfvars..."
        cat > terraform.tfvars <<EOF
github_token = "${GITHUB_TOKEN}"
github_owner = "${GITHUB_OWNER}"
github_repository = "LocalDataPlatform"

minikube_cpus = ${MINIKUBE_CPUS}
minikube_memory = ${MINIKUBE_MEMORY}
minikube_disk_size = "${MINIKUBE_DISK}"

enable_vault_ui = true
vault_dev_mode = true
enable_monitoring = false

kyuubi_user_timeout = "PT30S"
kyuubi_server_timeout = "PT15M"
spark_executor_memory = "12g"
spark_executor_cores = 2
spark_max_executors = 9
EOF
        log_success "Created terraform.tfvars"
    fi
    
    cd ..
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd ${TERRAFORM_DIR}
    
    # Plan the deployment
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Apply the deployment
    log_info "Applying Terraform deployment..."
    terraform apply tfplan
    
    log_success "Infrastructure deployed successfully"
    
    cd ..
}

wait_for_vault() {
    log_info "Waiting for Vault to be ready..."
    
    # Wait for Vault pod to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s
    
    # Port forward Vault for local access
    log_info "Setting up Vault port forwarding..."
    pkill -f "kubectl.*port-forward.*vault" || true
    kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 &
    
    # Wait for port forwarding to establish
    sleep 5
    
    # Set Vault address
    export VAULT_ADDR=http://localhost:8200
    
    # Get Vault root token (in dev mode)
    if kubectl get secret vault-keys -n ${VAULT_NAMESPACE} &> /dev/null; then
        VAULT_TOKEN=$(kubectl get secret vault-keys -n ${VAULT_NAMESPACE} -o jsonpath='{.data.root-token}' | base64 -d)
        export VAULT_TOKEN
        log_success "Vault is ready and configured"
    else
        log_warning "Vault keys not found, using dev mode token"
        export VAULT_TOKEN="root"
    fi
}

wait_for_flux() {
    log_info "Waiting for FluxCD to be ready..."
    
    # Wait for FluxCD controllers to be ready
    kubectl wait --for=condition=ready pod -l app=source-controller -n ${FLUX_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=kustomize-controller -n ${FLUX_NAMESPACE} --timeout=300s
    
    # Check FluxCD status
    flux check
    
    log_success "FluxCD is ready"
}

setup_port_forwarding() {
    log_info "Setting up port forwarding..."
    
    # Kill any existing port forwarding processes
    pkill -f "kubectl.*port-forward.*kyuubi" || true
    
    # Wait for Kyuubi deployments to be ready
    log_info "Waiting for Kyuubi deployments..."
    kubectl wait --for=condition=available deployment/kyuubi-dbt -n ${KYUUBI_NAMESPACE} --timeout=600s
    kubectl wait --for=condition=available deployment/kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --timeout=600s
    
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
    
    # Test Vault
    if timeout 5 bash -c "</dev/tcp/localhost/8200" 2>/dev/null; then
        log_success "Vault UI accessible at http://localhost:8200"
    else
        log_warning "Vault UI not accessible"
    fi
    
    # Test Kyuubi ports
    for port in 10009 10010; do
        if timeout 5 bash -c "</dev/tcp/localhost/${port}" 2>/dev/null; then
            log_success "Kyuubi port ${port} is accessible"
        else
            log_warning "Kyuubi port ${port} is not accessible yet"
        fi
    done
}

show_status() {
    log_info "Deployment Status:"
    echo
    
    # Show Terraform outputs
    echo "=== Terraform Outputs ==="
    cd ${TERRAFORM_DIR}
    terraform output
    cd ..
    echo
    
    # Show cluster info
    echo "=== Minikube Status ==="
    minikube status
    echo
    
    # Show all pods
    echo "=== All Pods ==="
    kubectl get pods --all-namespaces -o wide
    echo
    
    # Show FluxCD status
    echo "=== FluxCD Status ==="
    flux get all -A
    echo
    
    # Show Vault status
    echo "=== Vault Status ==="
    export VAULT_ADDR=http://localhost:8200
    vault status || echo "Vault not accessible"
    echo
    
    # Show port forwarding processes
    echo "=== Port Forwarding Processes ==="
    ps aux | grep "kubectl.*port-forward" | grep -v grep || echo "No port forwarding processes found"
    echo
}

show_connection_info() {
    log_success "=== Kyuubi LocalDataPlatform with Terraform + Vault + FluxCD is Ready! ==="
    echo
    echo "🔗 Connection Information:"
    echo "  📊 DataGrip/JDBC Connections:"
    echo "    • SERVER-level (shared, 15min timeout): jdbc:hive2://localhost:10009/default"
    echo "    • USER-level (individual, 30s timeout): jdbc:hive2://localhost:10010/default"
    echo
    echo "🔐 Vault UI:"
    echo "  • Vault UI: http://localhost:8200/ui"
    echo "  • Token: \$VAULT_TOKEN (check terraform output)"
    echo
    echo "🚀 Services:"
    echo "  • Kyuubi Server (shared): http://localhost:10009"
    echo "  • Kyuubi Server (user-level): http://localhost:10010"
    echo "  • Hive Metastore: thrift://localhost:9083 (internal)"
    echo
    echo "📋 Useful Commands:"
    echo "  • Check all resources: kubectl get all -A"
    echo "  • Check FluxCD: flux get all -A"
    echo "  • Check Vault secrets: vault kv list kyuubi"
    echo "  • Terraform status: cd terraform && terraform show"
    echo "  • Restart services: ./terraform-run.sh restart"
    echo
    echo "⚡ Performance:"
    echo "  • Minikube: ${MINIKUBE_CPUS} CPUs, ${MINIKUBE_MEMORY}MB RAM"
    echo "  • Dynamic Spark executors: 0-9 (12GB RAM, 2 cores each)"
    echo "  • Timeout: USER=30s, SERVER=15min"
    echo "  • Secrets: Managed by HashiCorp Vault"
    echo "  • GitOps: Managed by FluxCD"
    echo
}

cleanup() {
    log_info "Cleaning up..."
    
    # Kill port forwarding processes
    pkill -f "kubectl.*port-forward" || true
    
    # Destroy Terraform infrastructure
    if [[ -d ${TERRAFORM_DIR} ]]; then
        cd ${TERRAFORM_DIR}
        terraform destroy -auto-approve || true
        cd ..
    fi
    
    # Stop minikube
    minikube stop || true
    
    log_success "Cleanup complete"
}

# Main execution logic
case "${1:-full}" in
    "full")
        log_info "Starting full Kyuubi LocalDataPlatform deployment with Terraform..."
        check_prerequisites
        setup_minikube
        build_images
        setup_terraform
        deploy_infrastructure
        wait_for_vault
        wait_for_flux
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
        eval $(minikube docker-env)
        build_images
        ;;
    
    "terraform")
        log_info "Running Terraform deployment only..."
        check_prerequisites
        setup_terraform
        deploy_infrastructure
        log_success "Terraform deployment complete"
        ;;
    
    "vault")
        log_info "Setting up Vault access..."
        wait_for_vault
        log_success "Vault setup complete"
        ;;
    
    "flux")
        log_info "Checking FluxCD status..."
        wait_for_flux
        flux get all -A
        log_success "FluxCD status check complete"
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
        echo "Kyuubi LocalDataPlatform Terraform Setup Script"
        echo
        echo "Usage: $0 [command]"
        echo
        echo "Commands:"
        echo "  full         Complete setup (default) - Minikube + Build + Terraform + Vault + FluxCD"
        echo "  minikube     Setup Minikube cluster only"
        echo "  build        Build Docker images only"
        echo "  terraform    Run Terraform deployment only"
        echo "  vault        Setup Vault access"
        echo "  flux         Check FluxCD status"
        echo "  port-forward Setup port forwarding only"
        echo "  status       Show deployment status and connection info"
        echo "  test         Test connectivity"
        echo "  restart      Restart Kyuubi services"
        echo "  cleanup      Destroy infrastructure and cleanup"
        echo "  help         Show this help message"
        echo
        echo "Prerequisites:"
        echo "  - Set GITHUB_TOKEN environment variable"
        echo "  - Set GITHUB_OWNER environment variable (optional)"
        echo "  - Install: minikube, kubectl, docker, terraform, flux, vault"
        echo
        echo "Examples:"
        echo "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
        echo "  export GITHUB_OWNER=your-username"
        echo "  $0           # Full setup"
        echo "  $0 terraform # Just run Terraform"
        echo "  $0 status    # Check status"
        echo "  $0 cleanup   # Destroy everything"
        ;;
    
    *)
        log_error "Unknown command: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac 