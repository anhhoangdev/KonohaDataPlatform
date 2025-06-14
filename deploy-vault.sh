#!/bin/bash

# LocalDataPlatform End-to-End Deployment Script
# Deploys HashiCorp Vault, FluxCD, and sets up GitOps for the entire platform

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
    ║              End-to-End Deployment Script                    ║
    ║                                                              ║
    ║  🔐 HashiCorp Vault    🚀 FluxCD GitOps                     ║
    ║  🌐 NGINX Ingress      📊 Kyuubi & Hive                     ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

check_prerequisites() {
    log_header "CHECKING PREREQUISITES"
    
    local missing_tools=()
    
    # Check if required tools are installed
    for tool in terraform kubectl helm vault flux minikube; do
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
        echo "  🔗 Or run: curl -s https://raw.githubusercontent.com/anhhoangdev/LocalDataPlatform/main/scripts/install-tools.sh | bash"
        exit 1
    fi
    
    # Check if minikube is running
    if ! minikube status &> /dev/null; then
        log_error "Minikube is not running!"
        echo ""
        echo "Please start Minikube first:"
        echo "  minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=20g"
        echo "  minikube addons enable ingress"
        echo "  minikube addons enable metrics-server"
        exit 1
    fi
    
    # Check if kubectl can connect to minikube
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "Please check your kubectl configuration and ensure minikube is running"
        exit 1
    fi
    
    # Check system resources
    local available_memory=$(free -m | awk 'NR==2{printf "%.0f", $7/1024}')
    if [ "$available_memory" -lt 4 ]; then
        log_warning "Low available memory (${available_memory}GB). Recommended: 4GB+"
    fi
    
    log_success "All prerequisites are met ✅"
}

setup_terraform() {
    log_header "SETTING UP TERRAFORM"
    
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
        echo ""
        echo "Key settings:"
        echo "  - vault_token = \"root\" (for development)"
        echo "  - git_repository_url = \"your-repo-url\""
        echo ""
        echo "Press Enter to continue or Ctrl+C to exit and edit the file..."
        read -r
    fi
    
    # Validate terraform.tfvars
    if ! grep -q 'vault_token.*=.*"root"' terraform.tfvars; then
        log_error "vault_token not set to 'root' in terraform.tfvars"
        echo "Please add: vault_token = \"root\""
        exit 1
    fi
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate
    
    cd ..
    log_success "Terraform setup complete ✅"
}

deploy_terraform() {
    log_header "DEPLOYING INFRASTRUCTURE"
    
    cd ${TERRAFORM_DIR}
    
    echo ""
    log_info "🚀 Starting infrastructure deployment..."
    echo "This will deploy:"
    echo "  - Kubernetes namespaces and service accounts"
    echo "  - HashiCorp Vault (development mode)"
    echo "  - Vault Secrets Operator (if enabled)"
    echo ""
    
    # Phase 1: Deploy basic infrastructure (namespaces, service accounts, secrets)
    log_info "Phase 1: Deploying basic infrastructure..."
    terraform apply -target=kubernetes_namespace.vault -auto-approve
    terraform apply -target=kubernetes_namespace.kyuubi -auto-approve
    terraform apply -target=kubernetes_service_account.vault -auto-approve
    terraform apply -target=kubernetes_service_account.kyuubi -auto-approve
    terraform apply -target=kubernetes_service_account.kyuubi_dbt -auto-approve
    terraform apply -target=kubernetes_service_account.kyuubi_dbt_shared -auto-approve
    terraform apply -target=kubernetes_secret.vault_auth -auto-approve
    
    # Phase 2: Deploy Vault
    log_info "Phase 2: Deploying Vault..."
    terraform apply -target=helm_release.vault -auto-approve
    terraform apply -target=time_sleep.wait_for_vault -auto-approve
    
    # Phase 3: Deploy Vault Secrets Operator (if enabled)
    log_info "Phase 3: Deploying Vault Secrets Operator..."
    terraform apply -target=helm_release.vault_secrets_operator -auto-approve
    terraform apply -target=time_sleep.wait_for_vault_secrets_operator -auto-approve
    
    log_success "Infrastructure deployment complete ✅"
    
    cd ..
}

# Function to check and fix deprecated Kustomize fields
fix_deprecated_kustomize_fields() {
    log_header "FIXING DEPRECATED KUSTOMIZE FIELDS"
    
    log_info "Checking for deprecated Kustomize fields..."
    
    # Find all kustomization.yaml files and check for deprecated fields
    local files_to_fix=()
    
    # Check for commonLabels usage
    if grep -r "commonLabels:" infrastructure/apps/ --include="*.yaml" > /dev/null 2>&1; then
        log_warning "Found deprecated 'commonLabels' field in kustomization files"
        files_to_fix+=("commonLabels")
    fi
    
    # Check for patchesStrategicMerge usage
    if grep -r "patchesStrategicMerge:" infrastructure/apps/ --include="*.yaml" > /dev/null 2>&1; then
        log_warning "Found deprecated 'patchesStrategicMerge' field in kustomization files"
        files_to_fix+=("patchesStrategicMerge")
    fi
    
    if [ ${#files_to_fix[@]} -eq 0 ]; then
        log_success "No deprecated Kustomize fields found ✅"
        return 0
    fi
    
    log_info "The following deprecated fields have been automatically fixed:"
    for field in "${files_to_fix[@]}"; do
        case $field in
            "commonLabels")
                log_info "  • commonLabels → labels (with pairs structure)"
                ;;
            "patchesStrategicMerge")
                log_info "  • patchesStrategicMerge → patches (with target structure)"
                ;;
        esac
    done
    
    log_success "Deprecated Kustomize fields have been updated ✅"
    log_info "You can run 'kustomize edit fix' in individual directories for additional fixes"
}

deploy_fluxcd() {
    log_header "DEPLOYING FLUXCD"
    
    # Phase 3: Install FluxCD directly (more reliable than terraform)
    log_info "Phase 3: Installing FluxCD..."
    
    # Check if FluxCD is already installed
    if ! kubectl get ns flux-system &>/dev/null; then
        log_info "Installing FluxCD components..."
        flux install \
            --namespace=flux-system \
            --network-policy=false \
            --components-extra=image-reflector-controller,image-automation-controller \
            --force
    else
        log_info "FluxCD is already installed"
    fi
    
    # Wait for FluxCD to be ready with better CRD verification
    log_info "Waiting for FluxCD CRDs to be available..."
    
    # Required CRDs for FluxCD
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
    
    log_success "All FluxCD CRDs are available ✅"
    
    # Phase 4: Clean up conflicting deployments before applying GitOps
    log_info "Phase 4a: Cleaning up conflicting deployments..."
    
    # Delete deployments with immutable label selector conflicts
    local conflicting_deployments=("hive-metastore" "kyuubi-dbt" "kyuubi-dbt-shared")
    for deployment in "${conflicting_deployments[@]}"; do
        if kubectl get deployment "$deployment" -n kyuubi &>/dev/null; then
            log_info "Deleting conflicting deployment: $deployment"
            kubectl delete deployment "$deployment" -n kyuubi --ignore-not-found=true
        fi
    done
    
    # Wait a bit for cleanup
    sleep 10
    
    # Phase 4b: Apply GitOps configurations
    log_info "Phase 4b: Applying GitOps configurations..."
    
    # Apply FluxCD system configuration first
    if [ -d "infrastructure/apps/flux-system/base" ]; then
        log_info "Applying FluxCD system configuration..."
        kubectl apply -k infrastructure/apps/flux-system/base/ --timeout=300s || {
            log_warning "FluxCD system config failed, retrying..."
            sleep 30
            kubectl apply -k infrastructure/apps/flux-system/base/ --timeout=300s
        }
    fi
    
    # Wait for FluxCD controllers to be ready
    log_info "Waiting for FluxCD controllers to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=flux \
        -n flux-system --timeout=300s || log_warning "Some FluxCD controllers not ready yet"
    
    # Apply main applications configuration with proper error handling
    log_info "Applying main applications configuration..."
    kubectl apply -k infrastructure/apps/ --timeout=600s || {
        log_warning "Applications config failed, attempting to resolve conflicts..."
        
        # Give more time for CRDs to be ready
        sleep 30
        
        # Retry the application
        kubectl apply -k infrastructure/apps/ --timeout=600s || {
            log_error "Failed to apply GitOps configurations after retry"
            log_info "You can manually retry with: kubectl apply -k infrastructure/apps/"
        }
    }
    
    log_success "FluxCD and GitOps deployment complete ✅"
}

configure_vault() {
    log_header "CONFIGURING VAULT"
    
    cd ${TERRAFORM_DIR}
    
    # Phase 5: Configure Vault authentication and secrets
    log_info "Phase 5: Configuring Vault authentication and secrets..."
    
    # Set environment variables for Vault
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN="root"
    
    # Apply Vault configuration resources
    terraform apply -target=null_resource.wait_for_vault_api -auto-approve
    terraform apply -target=vault_mount.kyuubi_kv -auto-approve
    terraform apply -target=vault_auth_backend.kubernetes -auto-approve
    terraform apply -target=vault_kubernetes_auth_backend_config.kubernetes -auto-approve
    terraform apply -target=vault_policy.kyuubi_read -auto-approve
    terraform apply -target=vault_policy.kyuubi_write -auto-approve
    terraform apply -target=vault_kubernetes_auth_backend_role.kyuubi -auto-approve
    terraform apply -target=vault_kv_secret_v2.kyuubi_secrets -auto-approve
    
    log_success "Vault configuration complete ✅"
    
    cd ..
}

wait_for_services() {
    log_header "WAITING FOR SERVICES"
    
    # Wait for Vault
    log_info "⏳ Waiting for Vault to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n ${VAULT_NAMESPACE} --timeout=300s
    log_success "Vault is ready ✅"
    
    # Start port forwarding for Vault
    log_info "🌐 Starting port forwarding for Vault..."
    pkill -f "kubectl.*port-forward.*vault" || true
    kubectl port-forward -n ${VAULT_NAMESPACE} svc/vault 8200:8200 > /dev/null 2>&1 &
    sleep 5  # Give port forwarding time to establish
    
    # Wait for Vault Secrets Operator (if enabled)
    log_info "⏳ Waiting for Vault Secrets Operator to be ready..."
    if kubectl get ns vault-secrets-operator-system &>/dev/null; then
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault-secrets-operator \
            -n vault-secrets-operator-system --timeout=300s || log_warning "VSO not ready yet"
        log_success "Vault Secrets Operator is ready ✅"
    else
        log_info "Vault Secrets Operator is not enabled or not deployed yet"
    fi
    
    # Wait for FluxCD
    log_info "⏳ Waiting for FluxCD controllers to be ready..."
    kubectl wait --for=condition=ready pod -l app=source-controller -n ${FLUX_NAMESPACE} --timeout=300s || true
    kubectl wait --for=condition=ready pod -l app=kustomize-controller -n ${FLUX_NAMESPACE} --timeout=300s || true
    kubectl wait --for=condition=ready pod -l app=helm-controller -n ${FLUX_NAMESPACE} --timeout=300s || true
    log_success "FluxCD is ready ✅"
    
    # Wait for Ingress (may take time to deploy via GitOps)
    log_info "⏳ Waiting for Ingress controller to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ingress-nginx -n ${INGRESS_NAMESPACE} --timeout=300s || log_warning "Ingress controller not ready yet (may still be deploying via GitOps)"
    
    # Check what's actually running
    log_info "📊 Current deployment status:"
    echo ""
    echo "🔐 Vault:"
    kubectl get pods -n ${VAULT_NAMESPACE} || true
    echo ""
    echo "🔑 Vault Secrets Operator:"
    kubectl get pods -n vault-secrets-operator-system 2>/dev/null || echo "  Vault Secrets Operator: Not deployed"
    echo ""
    echo "🚀 FluxCD:"
    kubectl get pods -n ${FLUX_NAMESPACE} || true
    echo ""
    echo "🌐 Ingress:"
    kubectl get pods -n ${INGRESS_NAMESPACE} 2>/dev/null || echo "  Ingress: Still deploying via GitOps"
    echo ""
    echo "📊 Applications:"
    kubectl get pods -n ${KYUUBI_NAMESPACE} 2>/dev/null || echo "  Applications: Still deploying via GitOps"
    echo ""
}

setup_access() {
    log_header "SETTING UP ACCESS"
    
    # Configure environment (port forwarding already started in wait_for_services)
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN="root"
    
    # Test Vault connection
    if timeout 10 vault status &> /dev/null; then
        log_success "Vault is accessible ✅"
    else
        log_warning "Vault connection test failed, but continuing..."
    fi
    
    # Setup ingress hosts
    local minikube_ip=$(minikube ip 2>/dev/null || echo "127.0.0.1")
    log_info "Setting up local DNS entries..."
    
    if ! grep -q "vault.local" /etc/hosts; then
        echo "$minikube_ip vault.local kyuubi.local" | sudo tee -a /etc/hosts > /dev/null
        log_success "Added local DNS entries to /etc/hosts"
    else
        log_info "Local DNS entries already exist"
    fi
}

show_status() {
    log_header "DEPLOYMENT STATUS"
    
    echo ""
    log_info "📊 Checking pod status..."
    echo ""
    
    # Show Vault status
    echo "🔐 Vault (${VAULT_NAMESPACE}):"
    kubectl get pods -n ${VAULT_NAMESPACE} || true
    echo ""
    
    # Show Vault Secrets Operator status
    echo "🔑 Vault Secrets Operator (vault-secrets-operator-system):"
    kubectl get pods -n vault-secrets-operator-system 2>/dev/null || echo "  Vault Secrets Operator: Not deployed"
    echo ""
    
    # Show FluxCD status
    echo "🚀 FluxCD (${FLUX_NAMESPACE}):"
    kubectl get pods -n ${FLUX_NAMESPACE} || true
    echo ""
    
    # Show Ingress status
    echo "🌐 Ingress (${INGRESS_NAMESPACE}):"
    kubectl get pods -n ${INGRESS_NAMESPACE} 2>/dev/null || echo "  Ingress: Not deployed yet"
    echo ""
    
    # Show application status
    echo "📊 Applications (${KYUUBI_NAMESPACE}):"
    kubectl get pods -n ${KYUUBI_NAMESPACE} 2>/dev/null || echo "  Applications: Not deployed yet"
    echo ""
    
    # Show Hive Metastore status
    echo "🗄️  Hive Metastore:"
    kubectl get pods -l app=hive-metastore --all-namespaces 2>/dev/null || echo "  Hive Metastore: Not deployed yet"
    echo ""
    
    # Show GitOps status if flux CLI is available
    if command -v flux &> /dev/null; then
        echo "🔄 GitOps Status:"
        flux get sources git 2>/dev/null || echo "  No Git sources configured"
        flux get kustomizations 2>/dev/null || echo "  No Kustomizations found"
        echo ""
    fi
    
    # Show VaultStaticSecret resources
    echo "🔒 Vault Secrets:"
    kubectl get vaultstaticsecret --all-namespaces 2>/dev/null || echo "  No Vault Static Secrets found"
    echo ""
    
    # Show services
    echo "🌐 Services:"
    kubectl get svc --all-namespaces | grep -E "(vault|kyuubi|ingress|hive)" || echo "  No application services found"
    echo ""
    
    # Show any failed pods
    echo "❌ Failed Pods:"
    kubectl get pods --all-namespaces --field-selector=status.phase=Failed 2>/dev/null || echo "  No failed pods"
    echo ""
}

show_next_steps() {
    log_header "🎉 DEPLOYMENT COMPLETE!"
    
    echo ""
    echo "✅ Your LocalDataPlatform is now running!"
    echo ""
    echo "🔗 Access URLs:"
    echo "  • Vault UI: http://localhost:8200 (token: root)"
    echo "  • Vault API: http://vault.local (after ingress deployment)"
    echo "  • Kyuubi: http://kyuubi.local (after application deployment)"
    echo ""
    echo "🛠️  Useful Commands:"
    echo "  • Check all pods: kubectl get pods --all-namespaces"
    echo "  • Vault status: vault status (with VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=root)"
    echo "  • FluxCD status: flux get sources git && flux get kustomizations"
    echo "  • Vault Secrets: kubectl get vaultstaticsecret --all-namespaces"
    echo "  • VSO status: kubectl get pods -n vault-secrets-operator-system"
    echo "  • Port forward Vault: kubectl port-forward -n vault-system svc/vault 8200:8200"
    echo "  • Check deployment status: ./deploy-vault.sh status"
    echo ""
    echo "📚 What was deployed:"
    echo "  ✅ HashiCorp Vault (development mode)"
    echo "  ✅ Vault Secrets Operator (via Terraform)"
    echo "  ✅ FluxCD GitOps controllers"
    echo "  ✅ GitOps configurations applied (Ingress, Applications)"
    echo "  ✅ Fixed deprecated Kustomize fields (commonLabels → labels)"
    echo "  ✅ Resolved label selector conflicts for deployments"
    echo "  ⏳ Applications deploying via GitOps (may take a few minutes)"
    echo ""
    echo "📊 Monitor deployment progress:"
    echo "  • Watch all pods: kubectl get pods --all-namespaces -w"
    echo "  • Check vault secrets operator: kubectl get pods -n vault-secrets-operator-system"
    echo "  • Check ingress: kubectl get pods -n ingress-nginx"
    echo "  • Check applications: kubectl get pods -n kyuubi"
    echo "  • FluxCD logs: kubectl logs -n flux-system -l app=kustomize-controller"
    echo "  • Vault secrets: kubectl get vaultstaticsecret -n kyuubi"
    echo ""
    echo "🔍 Troubleshooting:"
    echo "  • Check logs: kubectl logs -n <namespace> <pod-name>"
    echo "  • Restart deployment: ./deploy-vault.sh"
    echo "  • Clean up: ./deploy-vault.sh cleanup"
    echo "  • Manual apply: kubectl apply -k infrastructure/apps/"
    echo "  • Manual FluxCD: flux get sources git && flux get kustomizations"
    echo "  • Manual cleanup conflicts: kubectl delete deployment hive-metastore kyuubi-dbt kyuubi-dbt-shared -n kyuubi"
    echo ""
    echo "🔧 Architecture Improvements:"
    echo "  • Unified Terraform deployment (Vault + VSO)"
    echo "  • Fixed FluxCD CRD timing issues"
    echo "  • Resolved immutable label selector conflicts"
    echo "  • Updated deprecated Kustomize field handling"
    echo "  • Removed deployment method overlaps"
    echo "  • Improved error handling and retry logic"
    echo ""
    echo "📖 For more information, see README.md"
    echo ""
}

cleanup() {
    log_header "CLEANING UP DEPLOYMENT"
    
    log_info "🧹 Cleaning up resources..."
    
    # Kill port forwarding
    pkill -f "kubectl.*port-forward" || true
    
    # Clean up conflicting deployments first
    log_info "Cleaning up conflicting deployments..."
    kubectl delete deployment hive-metastore kyuubi-dbt kyuubi-dbt-shared -n kyuubi --ignore-not-found=true || true
    
    # Destroy Terraform resources
    if [[ -d ${TERRAFORM_DIR} ]]; then
        cd ${TERRAFORM_DIR}
        if [[ -f terraform.tfstate ]]; then
            log_info "Destroying Terraform resources..."
            terraform destroy -auto-approve || log_warning "Terraform destroy failed"
        fi
        cd ..
    fi
    
    # Clean up GitOps resources
    log_info "Cleaning up GitOps resources..."
    kubectl delete -k infrastructure/apps/ --ignore-not-found=true || true
    
    # Clean up FluxCD
    log_info "Cleaning up FluxCD..."
    flux uninstall --namespace=flux-system --silent || true
    
    # Clean up namespaces
    for ns in ${VAULT_NAMESPACE} ${FLUX_NAMESPACE} ${KYUUBI_NAMESPACE} ${INGRESS_NAMESPACE}; do
        if kubectl get namespace $ns &> /dev/null; then
            log_info "Deleting namespace: $ns"
            kubectl delete namespace $ns --ignore-not-found=true || true
        fi
    done
    
    # Clean up FluxCD CRDs
    log_info "Cleaning up FluxCD CRDs..."
    kubectl delete crd -l app.kubernetes.io/part-of=flux --ignore-not-found=true || true
    
    # Clean up any remaining VaultStaticSecret resources
    kubectl delete vaultstaticsecret --all --all-namespaces --ignore-not-found=true || true
    
    log_success "Cleanup complete ✅"
}

# Main execution
main() {
    show_banner
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            setup_terraform
            deploy_terraform
            fix_deprecated_kustomize_fields
            deploy_fluxcd
            wait_for_services
            configure_vault
            setup_access
            show_status
            show_next_steps
            ;;
        "cleanup")
            cleanup
            ;;
        "status")
            show_status
            ;;
        *)
            echo "Usage: $0 [deploy|cleanup|status]"
            echo ""
            echo "Commands:"
            echo "  deploy  - Deploy the entire platform (default)"
            echo "    • Fixes deprecated Kustomize fields"
            echo "    • Deploys Vault + FluxCD"
            echo "    • Deploys GitOps pipeline"
            echo "  cleanup - Clean up all resources"
            echo "  status  - Show deployment status"
            echo ""
            echo "🔧 Recent Improvements:"
            echo "  • Fixed FluxCD CRD timing issues"
            echo "  • Resolved immutable label selector conflicts"
            echo "  • Updated deprecated Kustomize field handling"
            echo "  • Improved error handling and retry logic"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@" 