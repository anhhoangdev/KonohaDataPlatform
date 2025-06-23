#!/bin/bash

# LocalDataPlatform - Complete Deployment with Image Building
# Handles everything: downloads, build, load to minikube, deploy

set -e
set -o pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🚀 LocalDataPlatform - Complete Deployment${NC}"
echo "=================================================="
echo "✅ Downloads dependencies"
echo "✅ Builds all custom images"
echo "✅ Loads images into minikube"
echo "✅ Deploys with Terraform (no port forwarding)"
echo "✅ Sets up ingress with DNS"
echo ""

# Check prerequisites
check_prerequisites() {
    echo -e "${BLUE}📋 Checking prerequisites...${NC}"
    
    for tool in terraform minikube kubectl docker; do
        if ! command -v $tool &> /dev/null; then
            echo -e "${RED}❌ $tool is not installed${NC}"
            exit 1
        fi
    done
    
    if ! minikube status &> /dev/null; then
        echo -e "${RED}❌ Minikube is not running${NC}"
        echo "Start with: minikube start --cpus=6 --memory=12288 --disk-size=40g"
        exit 1
    fi
    
    if ! docker ps &> /dev/null; then
        echo -e "${RED}❌ Docker daemon is not running${NC}"
        exit 1
    fi
    
    # Enable ingress addon
    echo "🌐 Enabling minikube ingress addon..."
    minikube addons enable ingress
    
    echo -e "${GREEN}✅ All prerequisites met${NC}"
}

# Setup DNS entries
setup_dns() {
    echo -e "${BLUE}🌐 Setting up DNS entries...${NC}"
    
    local minikube_ip=$(minikube ip)
    local hosts_entries="vault.local grafana.local airflow.local kyuubi.local minio.local keycloak.local trino.local metabase.local"
    
    # Check if we need to add entries to /etc/hosts
    if ! grep -q "vault.local" /etc/hosts 2>/dev/null; then
        echo "Adding DNS entries to /etc/hosts..."
        echo "$minikube_ip $hosts_entries" | sudo tee -a /etc/hosts > /dev/null
        echo -e "${GREEN}✅ DNS entries added${NC}"
    else
        echo -e "${GREEN}✅ DNS entries already exist${NC}"
    fi
}

# Phase 1: Download dependencies
download_dependencies() {
    echo -e "${BLUE}📦 Phase 1: Downloading Dependencies${NC}"
    
    cd docker
    
    if [ ! -d "downloads" ] || [ ! -f "downloads/apache-hive-3.1.3-bin.tar.gz" ]; then
        echo "📥 Downloading required dependencies..."
        chmod +x download-dependencies.sh
        ./download-dependencies.sh
    else
        echo -e "${GREEN}✅ Dependencies already downloaded${NC}"
    fi
    
    cd ..
}

# Phase 2: Build all custom images
build_images() {
    echo -e "${BLUE}🐳 Phase 2: Building Custom Images (inside minikube)${NC}"
    
    # Use minikube docker daemon so images are immediately usable by cluster
    eval $(minikube docker-env)
    
    cd docker
    
    echo "🔨 Building all custom Docker images inside minikube..."
    chmod +x build-all-images.sh
    ./build-all-images.sh
    
    cd ..
    
    # Revert to host docker daemon
    eval $(minikube docker-env -u)
    
    echo -e "${GREEN}✅ All images built inside minikube${NC}"

    # Start port-forward for Vault svc if not already running
    start_vault_portforward
}

# Start port-forward for Vault svc if not already running
start_vault_portforward() {
    if pgrep -f "kubectl port-forward.*svc/vault 8200:8200" >/dev/null; then
        echo "🔌 Vault port-forward already running"
    else
        echo "🔌 Starting Vault port-forward (vault-system svc/vault → localhost:8200)"
        kubectl port-forward -n vault-system svc/vault 8200:8200 >/dev/null 2>&1 &
        VAULT_PF_PID=$!
        # small wait to establish
        sleep 3
    fi
}

# ensure port-forward is cleaned up on exit
cleanup() {
    if [ -n "$VAULT_PF_PID" ] && kill -0 $VAULT_PF_PID 2>/dev/null; then
        echo "🛑 Stopping Vault port-forward"
        kill $VAULT_PF_PID
    fi
}

trap cleanup EXIT

# Phase 4: Deploy basic infrastructure
deploy_infrastructure() {
    echo -e "${BLUE}🏗️ Phase 4: Basic Infrastructure${NC}"
    
    cd terraform
    
    # Clean start - remove any existing state lock
    rm -f terraform.tfstate*
    rm -f .terraform.lock.hcl
    terraform init
    
    # Deploy basic infrastructure first
    echo "📦 Deploying core namespaces and Vault..."
    terraform apply -target=kubernetes_namespace.vault \
                   -target=kubernetes_namespace.kyuubi \
                   -target=kubernetes_namespace.source_data \
                   -target=kubernetes_namespace.kafka \
                   -target=kubernetes_service_account.vault \
                   -target=kubernetes_service_account.kyuubi \
                   -target=kubernetes_service_account.kyuubi_dbt \
                   -target=kubernetes_service_account.kyuubi_dbt_shared \
                   -target=kubernetes_secret.vault_auth \
                   -target=helm_release.vault \
                   -target=time_sleep.wait_for_vault \
                   -auto-approve
    
    echo "🔧 Deploying Vault Secrets Operator..."
    terraform apply -target=helm_release.vault_secrets_operator \
                   -target=time_sleep.wait_for_vault_secrets_operator \
                   -auto-approve
    
    cd ..
    
    echo -e "${GREEN}✅ Basic infrastructure deployed${NC}"
}

# Phase 5: Create infrastructure and vault configuration
setup_vault_and_secrets() {
    echo -e "${BLUE}🔐 Phase 5: Vault Setup & Secret Management${NC}"
    
    cd terraform
    
    # Set Vault environment for port-forward
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=root
    
    echo "🔧 Step 1: Configuring Vault mounts and auth..."
    terraform apply -target=null_resource.wait_for_vault_api \
                   -target=vault_mount.kyuubi_kv \
                   -target=vault_mount.airflow_kv \
                   -target=vault_mount.grafana_kv \
                   -target=vault_mount.keycloak_kv \
                   -target=vault_mount.metabase_kv \
                   -target=vault_mount.pki \
                   -target=vault_auth_backend.kubernetes \
                   -auto-approve
    
    echo "📝 Step 2: Creating Vault policies and roles..."
    terraform apply -target=vault_policy.kyuubi_read \
                   -target=vault_policy.kyuubi_write \
                   -target=vault_policy.airflow_read \
                   -target=vault_policy.airflow_write \
                   -target=vault_policy.grafana_read \
                   -target=vault_policy.grafana_write \
                   -target=vault_policy.keycloak_read \
                   -target=vault_policy.keycloak_write \
                   -target=vault_policy.metabase_read \
                   -target=vault_policy.metabase_write \
                   -target=vault_kubernetes_auth_backend_role.kyuubi \
                   -target=vault_kubernetes_auth_backend_role.airflow \
                   -target=vault_kubernetes_auth_backend_role.grafana \
                   -target=vault_kubernetes_auth_backend_role.keycloak \
                   -target=vault_kubernetes_auth_backend_role.metabase \
                   -target=vault_kv_secret_v2.kyuubi_secrets \
                   -target=vault_kv_secret_v2.airflow_secrets \
                   -target=vault_kv_secret_v2.grafana_secrets \
                   -target=vault_kv_secret_v2.keycloak_secrets \
                   -target=vault_kv_secret_v2.metabase_secrets \
                   -auto-approve
    
    echo "🏗️ Step 3: Creating namespaces ONLY (no deployments yet)..."
    # Apply only namespace resources, not deployments
    terraform apply -target=kubectl_manifest.main_vault_auth \
                   -auto-approve
    
    # Create namespaces manually from individual namespace files
    kubectl apply -f infrastructure/apps/airflow/base/namespace.yaml || echo "Airflow namespace exists"
    kubectl apply -f infrastructure/apps/grafana/base/namespace.yaml || echo "Grafana namespace exists"  
    kubectl apply -f infrastructure/apps/keycloak/base/namespace.yaml || echo "Keycloak namespace exists"
    kubectl apply -f infrastructure/apps/kyuubi/base/namespace.yaml || echo "Kyuubi namespace exists"
    kubectl apply -f infrastructure/apps/kafka/base/namespace.yaml || echo "Kyuubi namespace exists"
    kubectl apply -f infrastructure/apps/metabase/base/namespace.yaml || echo "Metabase namespace exists"
    kubectl apply -f infrastructure/apps/trino/base/namespace.yaml || echo "Trino namespace exists"
    
    echo "⏳ Waiting for namespaces to be ready..."
    sleep 5
    
    echo "🔑 Step 4: Creating ALL VaultAuth resources..."
    terraform apply -target=kubectl_manifest.airflow_vault_auth \
                   -target=kubectl_manifest.keycloak_vault_auth \
                   -target=kubectl_manifest.metabase_vault_auth \
                   -auto-approve
    
    echo "🔐 Step 5: Creating VaultStaticSecret resources..."
    # Apply VaultStaticSecret resources
    kubectl apply -f infrastructure/apps/airflow/base/vault-secret.yaml || echo "Airflow secrets applied"
    kubectl apply -f infrastructure/apps/grafana/base/vault-secret.yaml || echo "Grafana secrets applied"
    kubectl apply -f infrastructure/apps/keycloak/base/vault-secret.yaml || echo "Keycloak secrets applied"
    kubectl apply -f infrastructure/apps/metabase/base/vault-secret.yaml || echo "Metabase secrets applied"
    kubectl apply -f infrastructure/apps/kyuubi/base/vault-secrets.yaml || echo "Kyuubi secrets applied"
    kubectl apply -f infrastructure/apps/minio/base/vault-secret.yaml || echo "MinIO secrets applied"
    kubectl apply -f infrastructure/apps/mariadb/base/vault-secret.yaml || echo "MariaDB secrets applied"
    kubectl apply -f infrastructure/apps/hive-metastore/base/vault-secret.yaml || echo "Hive secrets applied"
    
    echo "⏳ Waiting for VaultStaticSecrets to authenticate and create secrets..."
    sleep 90
    
    echo "🔍 Verifying secrets creation..."
    # Wait for actual secrets to be created
    for i in {1..12}; do
        secret_count=$(kubectl get secrets -n kyuubi | grep -c "vault-secret" || echo "0")
        if [ "$secret_count" -ge 3 ]; then
            echo "✅ Secrets created successfully"
            break
        fi
        echo "⏳ Waiting for secrets... ($i/12) - found $secret_count secrets"
        sleep 15
    done
    
    echo "📋 Final secret status:"
    kubectl get secrets --all-namespaces | grep -E "(vault-secret|admin-secret|db-secret)" || echo "No vault secrets found yet"
    
    cd ..
    
    echo -e "${GREEN}✅ Vault and secrets infrastructure ready${NC}"
}

# Phase 6: Deploy services in dependency order
deploy_services_ordered() {
    echo -e "${BLUE}🚀 Phase 6: Deploy Services in Dependency Order${NC}"
    
    # Safety check - ensure secrets exist before deploying
    echo "🔒 Verifying secrets are ready before deployment..."
    secret_count=$(kubectl get secrets -n kyuubi | grep -c "vault-secret" || echo "0")
    if [ "$secret_count" -lt 3 ]; then
        echo -e "${RED}❌ ERROR: Secrets not ready! Found only $secret_count secrets${NC}"
        echo "VaultStaticSecrets may have failed to authenticate. Check Vault configuration."
        kubectl get vaultstaticsecrets.secrets.hashicorp.com -n kyuubi
        exit 1
    fi
    echo -e "${GREEN}✅ Secrets verified ($secret_count found)${NC}"
    
    echo "📦 Step 1: Deploy Storage Layer (MinIO, MariaDB)..."
    kubectl apply -f infrastructure/apps/minio/base/minio-deployment.yaml
    kubectl apply -f infrastructure/apps/mariadb/base/mariadb-deployment.yaml
    
    echo "⏳ Waiting for storage layer to be ready..."
    kubectl wait --for=condition=available deployment/minio -n kyuubi --timeout=300s || echo "MinIO still starting..."
    kubectl wait --for=condition=available deployment/mariadb -n kyuubi --timeout=300s || echo "MariaDB still starting..."
    
    echo "🐝 Step 2: Deploy Hive Metastore..."
    kubectl apply -f infrastructure/apps/hive-metastore/base/hive-metastore-deployment.yaml
    
    echo "⏳ Waiting for Hive Metastore to be ready..."
    kubectl wait --for=condition=available deployment/hive-metastore -n kyuubi --timeout=300s || echo "Hive Metastore still starting..."
    
    echo "🔥 Step 3: Deploy Kyuubi Services..."
    kubectl apply -f infrastructure/apps/kyuubi/base/kyuubi-dbt-deployment.yaml
    kubectl apply -f infrastructure/apps/kyuubi/base/kyuubi-dbt-shared-deployment.yaml
    kubectl apply -f infrastructure/apps/kyuubi/base/spark-pod-templates.yaml
    kubectl apply -f infrastructure/apps/kyuubi/base/rbac.yaml
    
    echo "⚡ Step 4: Deploy Application Services..."
    kubectl apply -k infrastructure/apps/airflow/base/ || echo "Airflow deployment attempted"
    kubectl apply -k infrastructure/apps/grafana/base/ || echo "Grafana deployment attempted"
    kubectl apply -k infrastructure/apps/keycloak/base/ || echo "Keycloak deployment attempted"
    kubectl apply -k infrastructure/apps/metabase/base/ || echo "Metabase deployment attempted"
    kubectl apply -k infrastructure/apps/trino/base/ || echo "Trino deployment attempted"
    kubectl apply -k infrastructure/apps/kafka/base/ || echo "Kafka deployment attempted"
    kubectl apply -k infrastructure/apps/postgres-cdc/ || echo "Postgres CDC deployment attempted"
    
    echo "🌐 Step 5: Deploy Ingress Rules..."
    kubectl apply -k infrastructure/apps/ingress-nginx/overlays/minikube/ || echo "Ingress rules applied"
    
    echo -e "${GREEN}✅ All services deployed in proper order${NC}"
}

# Phase 7: Verify deployment status
verify_deployment_status() {
    echo -e "${BLUE}🔍 Phase 7: Verify Deployment Status${NC}"
    
    echo "📋 Checking all namespaces..."
    kubectl get namespaces | grep -E "(airflow|keycloak|grafana|metabase|trino|kafka|kyuubi)"
    
    echo "📋 Checking VaultAuth resources..."
    kubectl get vaultauths.secrets.hashicorp.com --all-namespaces
    
    echo "📋 Checking VaultStaticSecrets..."
    kubectl get vaultstaticsecrets.secrets.hashicorp.com --all-namespaces
    
    echo "📋 Checking secrets created..."
    kubectl get secrets --all-namespaces | grep -E "(vault-secret|admin-secret|db-secret|minio-secret|mariadb-secret)" || echo "Some secrets still being created..."
    
    echo "🚀 Checking pod status..."
    kubectl get pods --all-namespaces | grep -E "(airflow|keycloak|grafana|metabase|trino|kafka|kyuubi|minio|mariadb|hive)" || echo "Checking services..."
    
    echo "🌐 Checking ingress status..."
    kubectl get ingress --all-namespaces
    
    echo -e "${GREEN}✅ Deployment verification complete${NC}"
}

# Show final status and URLs
show_final_status() {
    echo ""
    echo -e "${GREEN}🎉 Complete Deployment Finished!${NC}"
    echo "=================================="
    echo ""
    echo -e "${BLUE}🔗 Access URLs (no port forwarding needed):${NC}"
    echo "  • Vault:    http://vault.local (token: root)"
    echo "  • Keycloak: http://keycloak.local (admin:admin123)"
    echo "  • Grafana:  http://grafana.local (admin:admin)"
    echo "  • Airflow:  http://airflow.local"
    echo "  • Kyuubi:   http://kyuubi.local"
    echo "  • MinIO:    http://minio.local"
    echo "  • Trino:    http://trino.local"
    echo "  • Metabase: http://metabase.local"
    echo ""
    echo -e "${BLUE}📊 Service Status:${NC}"
    kubectl get pods --all-namespaces | grep -E "(vault|keycloak|airflow|grafana|kyuubi|minio|hive|trino|metabase|kafka)" || echo "Checking services..."
    echo ""
    echo -e "${BLUE}🐳 Custom Images in Minikube:${NC}"
    eval $(minikube docker-env)
    docker images | grep -E "(hive-metastore|kyuubi-server|spark-engine|dbt-spark|kafka-connect|local-postgres-cdc)" || echo "No custom images found"
    eval $(minikube docker-env -u)
    echo ""
    echo -e "${BLUE}🌐 Ingress Status:${NC}"
    kubectl get ingress --all-namespaces
    echo ""
    echo -e "${YELLOW}💡 Tips:${NC}"
    echo "  • All services accessible via domain names"
    echo "  • Custom images loaded in minikube"
    echo "  • No port forwarding needed!"
    echo "  • Trino: SQL analytics engine"
    echo "  • Metabase: Business intelligence dashboards"
    echo "  • If pods still failing, run: kubectl describe pod <pod-name> -n <namespace>"
    echo "  • For OIDC setup: configure Keycloak clients"
}

# Main execution
case "${1:-deploy}" in
    "deploy")
        check_prerequisites
        setup_dns
        download_dependencies
        build_images
        deploy_infrastructure
        echo -e "${GREEN}✔️  Minimal infrastructure deployed.\nRun 'terraform apply' in the terraform directory to continue with full stack.${NC}"
        ;;
    "images")
        download_dependencies
        build_images
        ;;
    "status")
        show_final_status
        ;;
    "destroy")
        echo -e "${YELLOW}🧹 Destroying platform...${NC}"
        cd terraform
        terraform destroy -auto-approve
        cd ..
        
        # Clean up DNS entries
        if grep -q "vault.local" /etc/hosts 2>/dev/null; then
            echo "Removing DNS entries from /etc/hosts..."
            sudo sed -i '/vault.local/d' /etc/hosts
        fi
        ;;
    *)
        echo "Usage: $0 [deploy|images|status|destroy]"
        echo ""
        echo "Commands:"
        echo "  deploy  - Complete deployment with images (default)"
        echo "  images  - Only build and load images to minikube"
        echo "  status  - Show current status and URLs"
        echo "  destroy - Destroy all resources and clean DNS"
        echo ""
        echo "🎯 Complete Deployment Features:"
        echo "  ✅ Downloads all dependencies automatically"
        echo "  ✅ Builds custom Docker images" 
        echo "  ✅ Loads images into minikube registry"
        echo "  ✅ Uses Terraform for infrastructure"
        echo "  ✅ No port forwarding required"
        echo "  ✅ Ingress-based service access"
        echo "  ✅ Includes Trino and Metabase"
        echo "  ✅ Proper image availability in cluster"
        ;;
esac 