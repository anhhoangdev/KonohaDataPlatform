#!/bin/bash

# LocalDataPlatform End-to-End Deployment Script
# Deploys services in proper order: Custom Images → Vault → Flux → Ingress → MinIO + MariaDB → Hive Metastore → Kyuubi

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
TERRAFORM_DIR="terraform"
VAULT_NAMESPACE="vault-system"
KYUUBI_NAMESPACE="kyuubi"
FLUX_NAMESPACE="flux-system"
INGRESS_NAMESPACE="ingress-nginx"
MINIO_NAMESPACE="kyuubi"
MARIADB_NAMESPACE="kyuubi"

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
    ║                   LocalDataPlatform                          ║
    ║              Minikube Deployment Script                      ║
    ║                                                              ║
    ║  🐳 Custom Images → 🔐 Vault → 🚀 Flux → 🌐 Ingress        ║
    ║  📦 MinIO + 🗄️ MariaDB → 🐝 Hive → 📊 Kyuubi              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check if we can connect to Minikube Docker
check_minikube_docker() {
    log_info "Checking Minikube Docker connection..."
    
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
    
    # Use absolute paths to avoid path issues
    local abs_dockerfile_dir=$(realpath "${dockerfile_dir}")
    local abs_context_dir=$(realpath "${context_dir}")
    
    if docker build --no-cache -t "${image_name}" -f "${abs_dockerfile_dir}/Dockerfile" "${abs_context_dir}" 2>&1 | tee "/tmp/docker-build-${image_name//[^a-zA-Z0-9]/-}.log"; then
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
        echo "Build log saved to: /tmp/docker-build-${image_name//[^a-zA-Z0-9]/-}.log"
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

check_prerequisites() {
    log_header "CHECKING PREREQUISITES"
    
    local missing_tools=()
    
    # Check if required tools are installed
    for tool in terraform kubectl helm vault flux minikube docker; do
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
        echo "  📖 See README.md for detailed installation instructions"
        exit 1
    fi
    
    # Check if minikube is running
    if ! minikube status &> /dev/null; then
        log_error "Minikube is not running!"
        echo ""
        echo "Please start Minikube first:"
        echo "  minikube start --driver=docker --cpus=6 --memory=12288 --disk-size=40g"
        echo "  minikube addons enable ingress"
        echo "  minikube addons enable metrics-server"
        echo "  minikube addons enable registry"
        exit 1
    fi
    
    # Check if kubectl can connect to minikube
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "Please check your kubectl configuration and ensure minikube is running"
        exit 1
    fi
    
    # Check if we can connect to Minikube Docker
    if ! check_minikube_docker; then
        exit 1
    fi
    
    # Check system resources
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7/1024}')
    if [ "$available_memory" -lt 8 ]; then
        log_warning "Low available memory (${available_memory}GB). Recommended: 8GB+ for full platform"
    fi
    
    log_success "All prerequisites are met ✅"
}

# Phase 0: Build and deploy custom Docker images
build_custom_images() {
    log_header "PHASE 0: BUILDING CUSTOM DOCKER IMAGES"
    
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

# Phase 1: Deploy Vault
deploy_vault() {
    log_header "PHASE 1: DEPLOYING VAULT"
    
    cd ${TERRAFORM_DIR}
    
    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f terraform.tfvars ]]; then
        log_info "Creating terraform.tfvars from example..."
        cp terraform.tfvars.example terraform.tfvars
        
        # Update git repository URL automatically if possible
        if git remote get-url origin &> /dev/null; then
            local git_url=$(git remote get-url origin)
            log_info "Auto-detected Git repository: $git_url"
            sed -i "s|git_repository_url = \".*\"|git_repository_url = \"$git_url\"|" terraform.tfvars
        fi
        
        log_warning "📝 terraform.tfvars created. Please review the configuration!"
        echo "Press Enter to continue or Ctrl+C to exit and edit the file..."
        read -r
    fi
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    terraform validate
    
    # Deploy basic infrastructure
    log_info "Deploying namespaces and service accounts..."
    terraform apply -target=kubernetes_namespace.vault -auto-approve
    terraform apply -target=kubernetes_namespace.kyuubi -auto-approve
    terraform apply -target=kubernetes_service_account.vault -auto-approve
    terraform apply -target=kubernetes_service_account.kyuubi -auto-approve
    terraform apply -target=kubernetes_service_account.kyuubi_dbt -auto-approve
    terraform apply -target=kubernetes_service_account.kyuubi_dbt_shared -auto-approve
    terraform apply -target=kubernetes_secret.vault_auth -auto-approve
    
    # Deploy Vault
    log_info "Deploying Vault..."
    terraform apply -target=helm_release.vault -auto-approve
    terraform apply -target=time_sleep.wait_for_vault -auto-approve
    
    # Deploy Vault Secrets Operator
    log_info "Deploying Vault Secrets Operator..."
    terraform apply -target=helm_release.vault_secrets_operator -auto-approve
    terraform apply -target=time_sleep.wait_for_vault_secrets_operator -auto-approve
    
    cd ..
    
    # Wait for Vault to be ready
    log_info "⏳ Waiting for Vault to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s
    
    # Start port forwarding for Vault
    log_info "🌐 Starting port forwarding for Vault..."
    pkill -f "kubectl.*port-forward.*vault" || true
    kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 > /dev/null 2>&1 &
    sleep 10  # Give port forwarding time to establish
    
    # Configure Vault
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN="root"
    
    cd ${TERRAFORM_DIR}
    log_info "Configuring Vault authentication and secrets..."
    terraform apply -target=null_resource.wait_for_vault_api -auto-approve
    terraform apply -target=vault_mount.kyuubi_kv -auto-approve
    terraform apply -target=vault_auth_backend.kubernetes -auto-approve
    terraform apply -target=vault_kubernetes_auth_backend_config.kubernetes -auto-approve
    terraform apply -target=vault_policy.kyuubi_read -auto-approve
    terraform apply -target=vault_policy.kyuubi_write -auto-approve
    terraform apply -target=vault_kubernetes_auth_backend_role.kyuubi -auto-approve
    terraform apply -target=vault_kv_secret_v2.kyuubi_secrets -auto-approve
    cd ..
    
    log_success "✅ Vault deployed and configured successfully"
}

# Phase 2: Deploy FluxCD
deploy_flux() {
    log_header "PHASE 2: DEPLOYING FLUXCD"
    
    # Install FluxCD
    log_info "Installing FluxCD components..."
    if ! kubectl get ns flux-system &>/dev/null; then
        flux install \
            --namespace=flux-system \
            --network-policy=false \
            --components-extra=image-reflector-controller,image-automation-controller
    else
        log_info "FluxCD is already installed"
    fi
    
    # Wait for FluxCD CRDs
    log_info "Waiting for FluxCD CRDs to be available..."
    local required_crds=(
        "gitrepositories.source.toolkit.fluxcd.io"
        "kustomizations.kustomize.toolkit.fluxcd.io"
        "helmrepositories.source.toolkit.fluxcd.io"
        "helmreleases.helm.toolkit.fluxcd.io"
    )
    
    for crd in "${required_crds[@]}"; do
        for i in {1..60}; do
            if kubectl get crd "$crd" &>/dev/null; then
                log_success "CRD $crd is available"
                break
            fi
            if [ $i -eq 60 ]; then
                log_error "Timeout waiting for CRD $crd"
                exit 1
            fi
            log_info "Waiting for CRD $crd... ($i/60)"
            sleep 5
        done
    done
    
    # Wait for FluxCD controllers
    log_info "⏳ Waiting for FluxCD controllers to be ready..."
    kubectl wait --for=condition=ready pod -l app=source-controller -n ${FLUX_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=kustomize-controller -n ${FLUX_NAMESPACE} --timeout=300s
    kubectl wait --for=condition=ready pod -l app=helm-controller -n ${FLUX_NAMESPACE} --timeout=300s
    
    log_success "✅ FluxCD deployed successfully"
}

# Phase 3: Deploy Ingress
deploy_ingress() {
    log_header "PHASE 3: DEPLOYING INGRESS"
    
    # Apply FluxCD configuration for ingress
    log_info "Applying FluxCD system configuration..."
    if [ -d "infrastructure/apps/flux-system/base" ]; then
        kubectl apply -k infrastructure/apps/flux-system/base/ --timeout=300s
    fi
    
    # First, deploy just the ingress controller (base configuration)
    log_info "Deploying Ingress Controller (base)..."
    if [ -d "infrastructure/apps/ingress-nginx/base" ]; then
        kubectl apply -k infrastructure/apps/ingress-nginx/base/ --timeout=600s
    fi
    # Now apply the ingress resources separately
    log_info "Deploying Ingress resources (vault and kyuubi ingresses)..."
    if [ -f "infrastructure/apps/ingress-nginx/overlays/minikube/vault-ingress.yaml" ]; then
        kubectl apply -f infrastructure/apps/ingress-nginx/overlays/minikube/vault-ingress.yaml --timeout=300s
    fi
    
    if [ -f "infrastructure/apps/ingress-nginx/overlays/minikube/kyuubi-ingress.yaml" ]; then
        kubectl apply -f infrastructure/apps/ingress-nginx/overlays/minikube/kyuubi-ingress.yaml --timeout=300s
    fi
    
    log_success "✅ Ingress deployed successfully"
}

# Phase 4: Deploy MinIO and MariaDB
deploy_storage_databases() {
    log_header "PHASE 4: DEPLOYING MINIO + MARIADB"
    
    # Deploy VaultAuth first (required for secrets)
    log_info "Deploying VaultAuth configuration..."
    if [ -f "infrastructure/apps/vault-auth.yaml" ]; then
        kubectl apply -f infrastructure/apps/vault-auth.yaml --timeout=300s
        
        # Wait for VaultAuth to be ready
        log_info "⏳ Waiting for VaultAuth to be ready..."
        for i in {1..30}; do
            if kubectl get vaultauth vault-auth -n kyuubi &>/dev/null; then
                log_success "VaultAuth is ready"
                break
            fi
            if [ $i -eq 30 ]; then
                log_warning "VaultAuth not ready yet, continuing..."
                break
            fi
            log_info "Waiting for VaultAuth... ($i/30)"
            sleep 2
        done
    fi
    
    # Deploy MinIO
    log_info "Deploying MinIO via GitOps..."
    if [ -d "infrastructure/apps/minio" ]; then
        kubectl apply -k infrastructure/apps/minio/ --timeout=600s
    fi
    
    # Deploy MariaDB
    log_info "Deploying MariaDB via GitOps..."
    if [ -d "infrastructure/apps/mariadb" ]; then
        kubectl apply -k infrastructure/apps/mariadb/ --timeout=600s
    fi
    
    # Wait for secrets to be created by Vault Secrets Operator
    log_info "⏳ Waiting for Vault secrets to be created..."
    for i in {1..60}; do
        if kubectl get secret minio-vault-secret -n kyuubi &>/dev/null && \
           kubectl get secret mariadb-vault-secret -n kyuubi &>/dev/null; then
            log_success "Vault secrets are ready"
            break
        fi
        if [ $i -eq 60 ]; then
            log_warning "Vault secrets not ready yet, continuing..."
            break
        fi
        log_info "Waiting for Vault secrets... ($i/60)"
        sleep 5
    done
    
    # Wait for MinIO
    log_info "⏳ Waiting for MinIO to be ready..."
    for i in {1..60}; do
        if kubectl get pods -n ${MINIO_NAMESPACE} -l app=minio &>/dev/null; then
            kubectl wait --for=condition=ready pod -l app=minio -n ${MINIO_NAMESPACE} --timeout=300s
            break
        fi
        if [ $i -eq 60 ]; then
            log_warning "MinIO not ready yet, continuing..."
            break
        fi
        log_info "Waiting for MinIO pods to appear... ($i/60)"
        sleep 5
    done
    
    # Wait for MariaDB
    log_info "⏳ Waiting for MariaDB to be ready..."
    for i in {1..60}; do
        if kubectl get pods -n ${MARIADB_NAMESPACE} -l app=mariadb &>/dev/null; then
            kubectl wait --for=condition=ready pod -l app=mariadb -n ${MARIADB_NAMESPACE} --timeout=300s
            break
        fi
        if [ $i -eq 60 ]; then
            log_warning "MariaDB not ready yet, continuing..."
            break
        fi
        log_info "Waiting for MariaDB pods to appear... ($i/60)"
        sleep 5
    done
    
    log_success "✅ MinIO and MariaDB deployed successfully"
}

# Phase 5: Deploy Hive Metastore
deploy_hive() {
    log_header "PHASE 5: DEPLOYING HIVE METASTORE"
    
    # Clean up any conflicting deployments first
    log_info "Cleaning up conflicting Hive Metastore deployments..."
    kubectl delete deployment hive-metastore -n ${KYUUBI_NAMESPACE} --ignore-not-found=true
    
    # Deploy Hive Metastore
    log_info "Deploying Hive Metastore via GitOps..."
    if [ -d "infrastructure/apps/hive-metastore" ]; then
        kubectl apply -k infrastructure/apps/hive-metastore/ --timeout=600s
    fi
    
    # Wait for Hive Metastore
    log_info "⏳ Waiting for Hive Metastore to be ready..."
    for i in {1..120}; do
        if kubectl get pods -n ${KYUUBI_NAMESPACE} -l app=hive-metastore &>/dev/null; then
            kubectl wait --for=condition=ready pod -l app=hive-metastore -n ${KYUUBI_NAMESPACE} --timeout=600s
            break
        fi
        if [ $i -eq 120 ]; then
            log_warning "Hive Metastore not ready yet, continuing..."
            break
        fi
        log_info "Waiting for Hive Metastore pods to appear... ($i/120)"
        sleep 10
    done
    
    log_success "✅ Hive Metastore deployed successfully"
}

# Phase 6: Deploy Kyuubi
deploy_kyuubi() {
    log_header "PHASE 6: DEPLOYING KYUUBI"
    
    # Clean up any conflicting deployments first
    log_info "Cleaning up conflicting Kyuubi deployments..."
    kubectl delete helmrelease kyuubi-dbt kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --ignore-not-found=true || true
    kubectl delete deployment kyuubi-dbt kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --ignore-not-found=true || true
    
    # Deploy Kyuubi via direct Kubernetes manifests (instead of Helm)
    log_info "Deploying Kyuubi via Kubernetes manifests..."
    if [ -d "infrastructure/apps/kyuubi/base" ]; then
        kubectl apply -k infrastructure/apps/kyuubi/base/ --timeout=600s
    fi
    
    # Wait for Kyuubi deployments
    log_info "⏳ Waiting for Kyuubi deployments to be ready..."
    
    # Wait for kyuubi-dbt
    for i in {1..120}; do
        if kubectl get pods -n ${KYUUBI_NAMESPACE} -l app.kubernetes.io/name=kyuubi-dbt &>/dev/null; then
            kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyuubi-dbt -n ${KYUUBI_NAMESPACE} --timeout=600s || log_warning "kyuubi-dbt not ready yet"
            break
        fi
        if [ $i -eq 120 ]; then
            log_warning "kyuubi-dbt not ready yet, continuing..."
            break
        fi
        log_info "Waiting for kyuubi-dbt pods to appear... ($i/120)"
        sleep 10
    done
    
    # Wait for kyuubi-dbt-shared
    for i in {1..120}; do
        if kubectl get pods -n ${KYUUBI_NAMESPACE} -l app.kubernetes.io/name=kyuubi-dbt-shared &>/dev/null; then
            kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --timeout=600s || log_warning "kyuubi-dbt-shared not ready yet"
            break
        fi
        if [ $i -eq 120 ]; then
            log_warning "kyuubi-dbt-shared not ready yet, continuing..."
            break
        fi
        log_info "Waiting for kyuubi-dbt-shared pods to appear... ($i/120)"
        sleep 10
    done
    
    log_success "✅ Kyuubi deployed successfully"
}

# Setup access and ingress
setup_access() {
    log_header "SETTING UP ACCESS"
    
    # Setup ingress hosts
    local minikube_ip=$(minikube ip 2>/dev/null || echo "127.0.0.1")
    log_info "Setting up local DNS entries for Minikube IP: $minikube_ip"
    
    local hosts_entries="vault.local kyuubi.local minio.local mariadb.local hive.local"
    
    if ! grep -q "vault.local" /etc/hosts; then
        echo "$minikube_ip $hosts_entries" | sudo tee -a /etc/hosts > /dev/null
        log_success "Added local DNS entries to /etc/hosts"
    else
        log_info "Local DNS entries already exist"
    fi
    
    # Test Vault connection
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN="root"
    
    if timeout 10 vault status &> /dev/null; then
        log_success "Vault is accessible ✅"
    else
        log_warning "Vault connection test failed, but continuing..."
    fi
}

# Show comprehensive status
show_status() {
    log_header "DEPLOYMENT STATUS"
    
    echo ""
    log_info "📊 Checking all services status..."
    echo ""
    
    # Show Vault status
    echo "🔐 Vault (${VAULT_NAMESPACE}):"
    kubectl get pods -n ${VAULT_NAMESPACE} 2>/dev/null || echo "  Vault: Not deployed"
    echo ""
    
    # Show Vault Secrets Operator status
    echo "🔑 Vault Secrets Operator:"
    kubectl get pods -n vault-secrets-operator-system 2>/dev/null || echo "  VSO: Not deployed"
    echo ""
    
    # Show FluxCD status
    echo "🚀 FluxCD (${FLUX_NAMESPACE}):"
    kubectl get pods -n ${FLUX_NAMESPACE} 2>/dev/null || echo "  FluxCD: Not deployed"
    echo ""
    
    # Show Ingress status
    echo "🌐 Ingress (${INGRESS_NAMESPACE}):"
    kubectl get pods -n ${INGRESS_NAMESPACE} 2>/dev/null || echo "  Ingress: Not deployed"
    echo ""
    
    # Show MinIO status
    echo "📦 MinIO (${MINIO_NAMESPACE}):"
    kubectl get pods -n ${MINIO_NAMESPACE} 2>/dev/null || echo "  MinIO: Not deployed"
    echo ""
    
    # Show MariaDB status
    echo "🗄️  MariaDB (${MARIADB_NAMESPACE}):"
    kubectl get pods -n ${MARIADB_NAMESPACE} 2>/dev/null || echo "  MariaDB: Not deployed"
    echo ""
    
    # Show Hive Metastore status
    echo "🐝 Hive Metastore (${KYUUBI_NAMESPACE}):"
    kubectl get pods -n ${KYUUBI_NAMESPACE} -l app=hive-metastore 2>/dev/null || echo "  Hive Metastore: Not deployed"
    echo ""
    
    # Show Kyuubi status
    echo "📊 Kyuubi (${KYUUBI_NAMESPACE}):"
    kubectl get pods -n ${KYUUBI_NAMESPACE} -l app.kubernetes.io/name=kyuubi 2>/dev/null || echo "  Kyuubi: Not deployed"
    echo ""
    
    # Show services
    echo "🌐 Services:"
    kubectl get svc --all-namespaces | grep -E "(vault|kyuubi|ingress|hive|minio|mariadb)" 2>/dev/null || echo "  No services found"
    echo ""
    
    # Show HelmReleases
    echo "📦 Helm Releases:"
    kubectl get helmreleases --all-namespaces 2>/dev/null || echo "  No Helm releases found"
    echo ""
    
    # Show any failed pods
    echo "❌ Failed Pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null || echo "  No failed pods"
    echo ""
}

show_next_steps() {
    log_header "🎉 DEPLOYMENT COMPLETE!"
    
    echo ""
    echo "✅ Your LocalDataPlatform is now running on Minikube!"
    echo ""
    echo "🔗 Access URLs:"
    echo "  • Vault UI: http://localhost:8200 (token: root)"
    echo "  • Vault (Ingress): http://vault.local"
    echo "  • Kyuubi (Ingress): http://kyuubi.local"
    echo "  • MinIO (Ingress): http://minio.local"
    echo ""
    echo "📊 Deployment Order Completed:"
    echo "  ✅ Phase 1: Vault (secrets management)"
    echo "  ✅ Phase 2: FluxCD (GitOps)"
    echo "  ✅ Phase 3: Ingress (external access)"
    echo "  ✅ Phase 4: MinIO + MariaDB (storage)"
    echo "  ✅ Phase 5: Hive Metastore (metadata)"
    echo "  ✅ Phase 6: Kyuubi (Spark SQL with Iceberg)"
    echo ""
    echo "🛠️  Test Iceberg Functionality:"
    echo "  • Connect to Kyuubi: beeline -u 'jdbc:hive2://kyuubi.local:10009'"
    echo "  • Create Iceberg table: CREATE TABLE iceberg.test_table (id INT, name STRING) USING ICEBERG"
    echo "  • Insert data: INSERT INTO iceberg.test_table VALUES (1, 'test')"
    echo "  • Query data: SELECT * FROM iceberg.test_table"
    echo ""
    echo "🛠️  Useful Commands:"
    echo "  • Check all pods: kubectl get pods --all-namespaces"
    echo "  • Vault status: vault status (with VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=root)"
    echo "  • FluxCD status: flux get sources git && flux get kustomizations"
    echo "  • Check Helm releases: kubectl get helmreleases --all-namespaces"
    echo "  • Port forward services: kubectl port-forward -n <namespace> svc/<service> <local-port>:<remote-port>"
    echo "  • Check deployment status: ./deploy-vault.sh status"
    echo ""
    echo "📚 Architecture:"
    echo "  • Vault: Secrets management and authentication"
    echo "  • FluxCD: GitOps continuous deployment"
    echo "  • Ingress: External access to services"
    echo "  • MinIO: S3-compatible object storage"
    echo "  • MariaDB: Relational database for Hive Metastore"
    echo "  • Hive Metastore: Metadata service for Iceberg tables"
    echo "  • Kyuubi: Spark SQL gateway with Iceberg support"
    echo ""
    echo "🔍 Troubleshooting:"
    echo "  • Check logs: kubectl logs -n <namespace> <pod-name>"
    echo "  • Restart deployment: ./deploy-vault.sh"
    echo "  • Clean up: ./deploy-vault.sh cleanup"
    echo "  • Manual Helm release apply: kubectl apply -f infrastructure/apps/kyuubi/helm-release*.yaml"
    echo ""
    echo "📖 For more information, see README.md"
    echo ""
}

cleanup() {
    log_header "CLEANING UP DEPLOYMENT"
    
    log_info "🧹 Cleaning up all resources..."
    
    # Kill port forwarding
    pkill -f "kubectl.*port-forward" || true
    
    # Clean up Kyuubi first
    log_info "Cleaning up Kyuubi..."
    kubectl delete helmrelease kyuubi-dbt kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --ignore-not-found=true || true
    kubectl delete deployment kyuubi-dbt kyuubi-dbt-shared -n ${KYUUBI_NAMESPACE} --ignore-not-found=true || true
    
    # Clean up Hive
    log_info "Cleaning up Hive Metastore..."
    kubectl delete deployment hive-metastore -n ${KYUUBI_NAMESPACE} --ignore-not-found=true || true
    
    # Clean up storage and databases
    log_info "Cleaning up MinIO and MariaDB..."
    kubectl delete -k infrastructure/apps/minio/ --ignore-not-found=true || true
    kubectl delete -k infrastructure/apps/mariadb/ --ignore-not-found=true || true
    
    # Clean up ingress
    log_info "Cleaning up Ingress..."
    kubectl delete -f infrastructure/apps/ingress-nginx/overlays/minikube/vault-ingress.yaml --ignore-not-found=true || true
    kubectl delete -f infrastructure/apps/ingress-nginx/overlays/minikube/kyuubi-ingress.yaml --ignore-not-found=true || true
    kubectl delete -k infrastructure/apps/ingress-nginx/base/ --ignore-not-found=true || true
    
    # Destroy Terraform resources
    if [[ -d ${TERRAFORM_DIR} ]]; then
        cd ${TERRAFORM_DIR}
        if [[ -f terraform.tfstate ]]; then
            log_info "Destroying Terraform resources..."
            terraform destroy -auto-approve || log_warning "Terraform destroy failed"
        fi
        cd ..
    fi
    
    # Clean up FluxCD
    log_info "Cleaning up FluxCD..."
    flux uninstall --namespace=flux-system --silent || true
    
    # Clean up namespaces (remove duplicates since MinIO and MariaDB are in kyuubi namespace)
    local namespaces_to_delete=(${VAULT_NAMESPACE} ${FLUX_NAMESPACE} ${KYUUBI_NAMESPACE} ${INGRESS_NAMESPACE} vault-secrets-operator-system)
    for ns in "${namespaces_to_delete[@]}"; do
        if kubectl get namespace $ns &> /dev/null; then
            log_info "Deleting namespace: $ns"
            kubectl delete namespace $ns --ignore-not-found=true || true
        fi
    done
    
    log_success "Cleanup complete ✅"
}

# Main execution
main() {
    show_banner
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            build_custom_images
            deploy_vault
            deploy_flux
            deploy_ingress
            deploy_storage_databases
            deploy_hive
            deploy_kyuubi
            setup_access
            show_status
            show_next_steps
            ;;
        "build-images")
            check_prerequisites
            build_custom_images
            ;;
        "verify-images")
            check_prerequisites
            log_header "VERIFYING CUSTOM IMAGES"
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
                echo "Run: $0 build-images"
                exit 1
            fi
            ;;
        "cleanup")
            cleanup
            ;;
        "cleanup-images")
            check_prerequisites
            log_header "CLEANING UP CUSTOM IMAGES"
            
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
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 [deploy|build-images|verify-images|cleanup|cleanup-images|status]"
            echo ""
            echo "Commands:"
            echo "  deploy        - Deploy the entire platform in proper order (default)"
            echo "    • Phase 0: Build custom Docker images"
            echo "    • Phase 1: Vault (secrets management)"
            echo "    • Phase 2: FluxCD (GitOps)"
            echo "    • Phase 3: Ingress (external access)"
            echo "    • Phase 4: MinIO + MariaDB (storage)"
            echo "    • Phase 5: Hive Metastore (metadata)"
            echo "    • Phase 6: Kyuubi (Spark SQL with Iceberg)"
            echo "  build-images  - Build only the custom Docker images"
            echo "  verify-images - Verify that all custom images are available"
            echo "  cleanup       - Clean up all Kubernetes resources"
            echo "  cleanup-images- Clean up all custom Docker images"
            echo "  status        - Show deployment status"
            echo ""
            echo "🐳 Custom Images:"
            echo "  • ${HIVE_METASTORE_IMAGE} - Hive Metastore with S3/MinIO support"
            echo "  • ${KYUUBI_SERVER_IMAGE} - Kyuubi SQL Gateway"
            echo "  • ${SPARK_ENGINE_ICEBERG_IMAGE} - Spark with Iceberg support"
            echo ""
            echo "🚀 Minikube Requirements:"
            echo "  • 6+ CPUs, 12GB+ RAM, 40GB+ disk"
            echo "  • Addons: ingress, metrics-server, registry"
            echo ""
            echo "🔧 Troubleshooting:"
            echo "  • If image build fails: $0 build-images"
            echo "  • To verify images: $0 verify-images"
            echo "  • To rebuild images: $0 cleanup-images && $0 build-images"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 