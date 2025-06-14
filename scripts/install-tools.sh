#!/bin/bash

# LocalDataPlatform - Tool Installation Script
# Installs all required tools for the platform

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Detect OS
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if command -v apt-get &> /dev/null; then
        DISTRO="debian"
    elif command -v yum &> /dev/null; then
        DISTRO="rhel"
    else
        log_error "Unsupported Linux distribution"
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
else
    log_error "Unsupported operating system: $OSTYPE"
    exit 1
fi

install_docker() {
    if command -v docker &> /dev/null; then
        log_success "Docker is already installed"
        return
    fi
    
    log_info "Installing Docker..."
    if [[ "$OS" == "linux" && "$DISTRO" == "debian" ]]; then
        sudo apt-get update
        sudo apt-get install -y docker.io
        sudo usermod -aG docker $USER
        log_warning "Please log out and back in for Docker group changes to take effect"
    elif [[ "$OS" == "macos" ]]; then
        log_info "Please install Docker Desktop from https://www.docker.com/products/docker-desktop"
        return
    fi
    log_success "Docker installed"
}

install_minikube() {
    if command -v minikube &> /dev/null; then
        log_success "Minikube is already installed"
        return
    fi
    
    log_info "Installing Minikube..."
    if [[ "$OS" == "linux" ]]; then
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    elif [[ "$OS" == "macos" ]]; then
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-darwin-amd64
        sudo install minikube-darwin-amd64 /usr/local/bin/minikube
        rm minikube-darwin-amd64
    fi
    log_success "Minikube installed"
}

install_kubectl() {
    if command -v kubectl &> /dev/null; then
        log_success "kubectl is already installed"
        return
    fi
    
    log_info "Installing kubectl..."
    if [[ "$OS" == "linux" ]]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    elif [[ "$OS" == "macos" ]]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"
        sudo install -o root -g wheel -m 0755 kubectl /usr/local/bin/kubectl
        rm kubectl
    fi
    log_success "kubectl installed"
}

install_terraform() {
    if command -v terraform &> /dev/null; then
        log_success "Terraform is already installed"
        return
    fi
    
    log_info "Installing Terraform..."
    if [[ "$OS" == "linux" && "$DISTRO" == "debian" ]]; then
        wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
        sudo apt update && sudo apt install -y terraform
    elif [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew tap hashicorp/tap
            brew install hashicorp/tap/terraform
        else
            log_error "Please install Homebrew first or install Terraform manually"
            return
        fi
    fi
    log_success "Terraform installed"
}

install_helm() {
    if command -v helm &> /dev/null; then
        log_success "Helm is already installed"
        return
    fi
    
    log_info "Installing Helm..."
    if [[ "$OS" == "linux" && "$DISTRO" == "debian" ]]; then
        curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
        sudo apt-get update && sudo apt-get install -y helm
    elif [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew install helm
        else
            curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
            chmod 700 get_helm.sh
            ./get_helm.sh
            rm get_helm.sh
        fi
    fi
    log_success "Helm installed"
}

install_vault_cli() {
    if command -v vault &> /dev/null; then
        log_success "Vault CLI is already installed"
        return
    fi
    
    log_info "Installing Vault CLI..."
    if [[ "$OS" == "linux" && "$DISTRO" == "debian" ]]; then
        # Already added HashiCorp repo for Terraform
        sudo apt install -y vault
    elif [[ "$OS" == "macos" ]]; then
        if command -v brew &> /dev/null; then
            brew tap hashicorp/tap
            brew install hashicorp/tap/vault
        else
            log_error "Please install Homebrew first or install Vault CLI manually"
            return
        fi
    fi
    log_success "Vault CLI installed"
}

install_flux_cli() {
    if command -v flux &> /dev/null; then
        log_success "FluxCD CLI is already installed"
        return
    fi
    
    log_info "Installing FluxCD CLI..."
    curl -s https://fluxcd.io/install.sh | sudo bash
    log_success "FluxCD CLI installed"
}

main() {
    echo "🚀 Installing LocalDataPlatform tools..."
    echo ""
    
    install_docker
    install_minikube
    install_kubectl
    install_terraform
    install_helm
    install_vault_cli
    install_flux_cli
    
    echo ""
    log_success "✅ All tools installed successfully!"
    echo ""
    echo "Next steps:"
    echo "1. Start Minikube: minikube start --driver=docker --cpus=4 --memory=8192"
    echo "2. Clone the repository: git clone https://github.com/anhhoangdev/LocalDataPlatform.git"
    echo "3. Run deployment: cd LocalDataPlatform && ./deploy-vault.sh"
    echo ""
    
    if [[ "$OS" == "linux" ]]; then
        log_warning "If you installed Docker, please log out and back in for group changes to take effect"
    fi
}

main "$@" 