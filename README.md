# LocalDataPlatform

A comprehensive data platform built on Kubernetes with HashiCorp Vault for secrets management, FluxCD for GitOps, and support for Kyuubi, Hive Metastore, and other data tools.
## Table of Contents

- [Architecture](#-architecture)
- [Prerequisites](#-prerequisites)
- [Quick Start](#-quick-start-end-to-end-deployment)
- [Project Structure](#-project-structure)
- [Configuration](#-configuration)
- [Management Commands](docs/management-commands.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Security Notes](#-security-notes)
- [Contributing](#-contributing)
- [License](#-license)
- [Support](#-support)


## 🏗️ Architecture

- **Kubernetes**: Minikube for local development
- **HashiCorp Vault**: Centralized secrets management
- **FluxCD**: GitOps continuous deployment
- **NGINX Ingress**: Load balancing and ingress
- **Kyuubi**: Distributed SQL query engine
- **Hive Metastore**: Metadata management
- **Terraform**: Infrastructure as Code

## 📋 Prerequisites

### Required Tools

1. **Docker** (for Minikube)
   ```bash
   # Ubuntu/Debian
   sudo apt-get update && sudo apt-get install -y docker.io
   sudo usermod -aG docker $USER
   # Log out and back in
   ```

2. **Minikube**
   ```bash
   curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
   sudo install minikube-linux-amd64 /usr/local/bin/minikube
   ```

3. **kubectl**
   ```bash
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

4. **Terraform**
   ```bash
   wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
   echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
   sudo apt update && sudo apt install terraform
   ```

5. **FluxCD CLI**
   ```bash
   curl -s https://fluxcd.io/install.sh | sudo bash
   ```

6. **Helm**
   ```bash
   curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
   sudo apt-get update && sudo apt-get install helm
   ```

### System Requirements

- **CPU**: 4+ cores recommended
- **Memory**: 8GB+ RAM
- **Disk**: 20GB+ free space
- **OS**: Linux (Ubuntu 20.04+ recommended)

## 🚀 Quick Start (End-to-End Deployment)

### Step 1: Clone and Setup Repository

```bash
# Clone the repository
git clone https://github.com/anhhoangdev/LocalDataPlatform.git
cd LocalDataPlatform

# Make scripts executable
chmod +x deploy-vault.sh
chmod +x infrastructure/apps/*/run.sh 2>/dev/null || true
```

### Step 2: Start Minikube

```bash
# Start Minikube with sufficient resources
minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=20g

# Enable required addons
minikube addons enable ingress
minikube addons enable metrics-server

# Verify cluster is running
kubectl cluster-info
```

### Step 3: Configure Terraform Variables

```bash
# Copy and customize the Terraform configuration
cd terraform
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your settings
# The key settings are already configured for local development:
# - vault_token = "root"
# - vault_dev_mode = true
# - git_repository_url = "https://github.com/anhhoangdev/LocalDataPlatform"
```

### Step 4: Deploy the Platform

```bash
# Run the automated deployment script
cd ..
./deploy-vault.sh

# This script will:
# 1. Initialize and apply Terraform configuration
# 2. Deploy HashiCorp Vault in development mode
# 3. Install FluxCD for GitOps
# 4. Configure Vault authentication and policies
# 5. Create initial secrets for Kyuubi
```

### Step 5: Verify Deployment

```bash
# Check all pods are running
kubectl get pods --all-namespaces

# Verify Vault is ready
kubectl get pods -n vault-system

# Verify FluxCD is ready
kubectl get pods -n flux-system

# Check Vault status
kubectl port-forward -n vault-system svc/vault 8200:8200 &
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root"
vault status
```

### Step 6: Access Services

#### Vault UI
```bash
# Port forward to access Vault UI
kubectl port-forward -n vault-system svc/vault 8200:8200

# Open browser to: http://localhost:8200
# Login with token: root
```

#### Deploy Applications via GitOps
```bash
# FluxCD will automatically deploy applications from infrastructure/apps/
# Monitor GitOps deployments
flux get sources git
flux get kustomizations

# Check application deployments
kubectl get pods -n kyuubi
kubectl get pods -n hive-metastore
```

## 📁 Project Structure

```
LocalDataPlatform/
├── terraform/                    # Infrastructure as Code
│   ├── main.tf                  # Provider configurations
│   ├── variables.tf             # Variable definitions
│   ├── vault.tf                 # Vault deployment
│   ├── vault-config.tf          # Vault configuration
│   ├── fluxcd.tf               # FluxCD bootstrap
│   ├── outputs.tf              # Output values
│   └── terraform.tfvars        # Configuration values
├── infrastructure/              # GitOps configurations
│   └── apps/                   # Application deployments
│       ├── flux-system/        # FluxCD configuration
│       ├── ingress-nginx/      # Ingress controller
│       ├── hive-metastore/     # Hive Metastore
│       └── kyuubi/            # Kyuubi SQL engine
├── deploy-vault.sh             # Automated deployment script
└── README.md                   # This file
```

## 🔧 Configuration

### Vault Configuration

The platform uses HashiCorp Vault for centralized secrets management:

- **Development Mode**: Enabled by default (`vault_dev_mode = true`)
- **Root Token**: `"root"` (for development only)
- **UI**: Accessible at `http://localhost:8200`
- **Authentication**: Kubernetes auth backend configured
- **Secrets**: Pre-configured for Kyuubi, database, Spark, and MinIO

### FluxCD GitOps

FluxCD monitors this Git repository and automatically deploys changes:

- **Repository**: Configured to monitor your fork
- **Branch**: `main` (configurable)
- **Path**: `infrastructure/apps/`
- **Sync Interval**: 1 minute

### Ingress Configuration

NGINX Ingress Controller provides external access:

- **Vault**: `vault.local` (add to `/etc/hosts`)
- **Kyuubi**: `kyuubi.local` (add to `/etc/hosts`)

```bash
# Add to /etc/hosts for local access
echo "$(minikube ip) vault.local kyuubi.local" | sudo tee -a /etc/hosts
```

For day-to-day administration, see [Management Commands](docs/management-commands.md).
If you run into issues, check the [Troubleshooting guide](docs/troubleshooting.md).


## 🔒 Security Notes

⚠️ **Important**: This configuration is for development only!

For production use:
- Disable Vault development mode
- Use proper authentication and TLS
- Implement proper RBAC
- Use external secret management
- Enable audit logging
- Implement backup strategies

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test the deployment
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For issues and questions:
- Create an issue in this repository
- Check the [Troubleshooting guide](docs/troubleshooting.md)
- Review Kubernetes and Vault documentation 