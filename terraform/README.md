# Kyuubi LocalDataPlatform - Terraform Infrastructure

This directory contains the Terraform Infrastructure as Code (IaC) configuration for deploying the Kyuubi LocalDataPlatform with HashiCorp Vault for secrets management and FluxCD for GitOps.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Minikube Cluster                        │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Vault System  │  │   Flux System   │  │     Kyuubi      │  │
│  │                 │  │                 │  │                 │  │
│  │ • Vault Server  │  │ • Source Ctrl   │  │ • Kyuubi DBT    │  │
│  │ • Vault UI      │  │ • Kustomize     │  │ • Kyuubi Shared │  │
│  │ • Secrets Mgmt  │  │ • Git Sync      │  │ • Spark Engines │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                                                                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Infrastructure│  │    Monitoring   │  │     Storage     │  │
│  │                 │  │   (Optional)    │  │                 │  │
│  │ • MariaDB       │  │ • Prometheus    │  │ • Hive Metastore│  │
│  │ • Hive Metastore│  │ • Grafana       │  │ • MinIO (S3)    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Features

### 🔐 HashiCorp Vault Integration
- **Secrets Management**: All sensitive data stored securely in Vault
- **Kubernetes Auth**: Service accounts authenticate with Vault automatically
- **Dynamic Secrets**: Database credentials and API keys managed dynamically
- **Policy-Based Access**: Fine-grained access control with Vault policies

### 🚀 FluxCD GitOps
- **Git-Driven Deployments**: Infrastructure changes via Git commits
- **Automatic Reconciliation**: Continuous sync between Git and cluster state
- **Health Checks**: Automated deployment validation
- **Rollback Capability**: Easy rollback to previous configurations

### 🏗️ Infrastructure as Code
- **Terraform Managed**: Complete infrastructure defined in code
- **Version Controlled**: All changes tracked in Git
- **Reproducible**: Identical environments every time
- **Modular Design**: Reusable components and configurations

## Prerequisites

### Required Tools
```bash
# Install required tools
brew install minikube kubectl docker terraform flux vault

# Or on Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y minikube kubectl docker.io terraform

# Install FluxCD CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Install Vault CLI
curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo apt-key add -
sudo apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
sudo apt-get update && sudo apt-get install vault
```

### Environment Variables
```bash
# Required: GitHub Personal Access Token
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

# Required: GitHub Username/Organization
export GITHUB_OWNER="your-github-username"

# Optional: Repository name (defaults to LocalDataPlatform)
export GITHUB_REPOSITORY="LocalDataPlatform"
```

## Quick Start

### 1. Full Deployment
```bash
# Set environment variables
export GITHUB_TOKEN="your_github_token"
export GITHUB_OWNER="your_username"

# Run complete setup
./terraform-run.sh
```

### 2. Step-by-Step Deployment
```bash
# 1. Setup Minikube
./terraform-run.sh minikube

# 2. Build Docker images
./terraform-run.sh build

# 3. Deploy infrastructure with Terraform
./terraform-run.sh terraform

# 4. Setup port forwarding
./terraform-run.sh port-forward

# 5. Check status
./terraform-run.sh status
```

## Configuration

### Terraform Variables

Create or modify `terraform.tfvars`:

```hcl
# GitHub Configuration
github_token = "ghp_xxxxxxxxxxxxxxxxxxxx"
github_owner = "your-username"
github_repository = "LocalDataPlatform"

# Minikube Resources
minikube_cpus = 12
minikube_memory = 24576
minikube_disk_size = "50g"

# Vault Configuration
enable_vault_ui = true
vault_dev_mode = true

# Kyuubi Configuration
kyuubi_user_timeout = "PT30S"
kyuubi_server_timeout = "PT15M"

# Spark Configuration
spark_executor_memory = "12g"
spark_executor_cores = 2
spark_max_executors = 9

# Optional Features
enable_monitoring = false
```

### Vault Secrets Structure

Secrets are automatically created in Vault under the `kyuubi/` path:

```
kyuubi/
├── data/
│   ├── database          # MariaDB credentials
│   ├── spark            # Spark configuration
│   ├── kyuubi-server    # Kyuubi server config
│   ├── aws              # S3/MinIO credentials
│   └── monitoring       # Grafana/Prometheus (if enabled)
```

## Terraform Resources

### Core Infrastructure
- **Kubernetes Namespaces**: vault-system, flux-system, kyuubi
- **HashiCorp Vault**: Secrets management with Kubernetes auth
- **FluxCD**: GitOps controller with Git repository sync
- **RBAC**: Service accounts and cluster roles

### Vault Configuration
- **KV Secrets Engine**: Stores all application secrets
- **Kubernetes Auth**: Automatic pod authentication
- **Policies**: Fine-grained access control
- **Secret Injection**: Automatic secret mounting

### FluxCD Configuration
- **Git Repository**: Source of truth for configurations
- **Kustomizations**: Application deployment definitions
- **Health Checks**: Deployment validation
- **Notifications**: Optional Slack/Discord alerts

## Usage

### Accessing Services

#### Vault UI
```bash
# Port forward Vault UI
kubectl port-forward -n vault-system svc/vault 8200:8200

# Access at: http://localhost:8200/ui
# Token: Check terraform output or use 'root' in dev mode
```

#### Kyuubi Services
```bash
# SERVER-level (shared, 15min timeout)
kubectl port-forward -n kyuubi svc/kyuubi-dbt-shared 10009:10009

# USER-level (individual, 30s timeout)
kubectl port-forward -n kyuubi svc/kyuubi-dbt 10010:10009
```

#### DataGrip Connections
- **SERVER-level**: `jdbc:hive2://localhost:10009/default`
- **USER-level**: `jdbc:hive2://localhost:10010/default`

### Managing Secrets

#### View Secrets
```bash
# Set Vault address
export VAULT_ADDR=http://localhost:8200

# List all secrets
vault kv list kyuubi

# Read specific secret
vault kv get kyuubi/database
vault kv get kyuubi/spark
```

#### Update Secrets
```bash
# Update database password
vault kv put kyuubi/database mariadb_password="new-password"

# Update Spark configuration
vault kv put kyuubi/spark spark_executor_memory="16g"
```

### FluxCD Operations

#### Check Status
```bash
# Check all FluxCD resources
flux get all -A

# Check specific kustomization
flux get kustomizations -n flux-system

# Check Git repository sync
flux get sources git -A
```

#### Force Reconciliation
```bash
# Force sync from Git
flux reconcile kustomization kyuubi -n flux-system

# Force sync Git repository
flux reconcile source git kyuubi-platform -n flux-system
```

#### View Logs
```bash
# FluxCD controller logs
flux logs -n flux-system

# Specific controller logs
kubectl logs -n flux-system deployment/source-controller
kubectl logs -n flux-system deployment/kustomize-controller
```

## Troubleshooting

### Common Issues

#### 1. Vault Not Accessible
```bash
# Check Vault pod status
kubectl get pods -n vault-system

# Check Vault logs
kubectl logs -n vault-system deployment/vault

# Port forward Vault
kubectl port-forward -n vault-system svc/vault 8200:8200
```

#### 2. FluxCD Sync Issues
```bash
# Check Git repository status
flux get sources git -A

# Check kustomization status
flux get kustomizations -A

# Force reconciliation
flux reconcile kustomization infrastructure -n flux-system
```

#### 3. Kyuubi Connection Issues
```bash
# Check Kyuubi pods
kubectl get pods -n kyuubi

# Check Kyuubi logs
kubectl logs -n kyuubi deployment/kyuubi-dbt

# Verify secrets are mounted
kubectl exec -n kyuubi deployment/kyuubi-dbt -- env | grep VAULT
```

#### 4. Terraform State Issues
```bash
# Refresh Terraform state
terraform refresh

# Import existing resources
terraform import kubernetes_namespace.kyuubi kyuubi

# Force unlock (if locked)
terraform force-unlock <lock-id>
```

### Debug Commands

```bash
# Check all resources
kubectl get all -A

# Check Terraform state
terraform show

# Check Vault status
vault status

# Check FluxCD health
flux check

# Check resource events
kubectl get events --sort-by='.lastTimestamp' -A
```

## Monitoring and Observability

### Enable Monitoring (Optional)
```hcl
# In terraform.tfvars
enable_monitoring = true
```

This deploys:
- **Prometheus**: Metrics collection
- **Grafana**: Visualization dashboards
- **AlertManager**: Alert routing

### Access Monitoring
```bash
# Grafana (admin/kyuubi-grafana-password)
kubectl port-forward -n monitoring svc/grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-server 9090:80
```

## Security Considerations

### Vault Security
- **Dev Mode**: Only for development (vault_dev_mode = true)
- **Production**: Use proper storage backend and TLS
- **Secrets Rotation**: Implement regular secret rotation
- **Access Policies**: Use least-privilege access

### Kubernetes Security
- **RBAC**: Minimal required permissions
- **Network Policies**: Restrict pod-to-pod communication
- **Pod Security**: Use security contexts and policies
- **Image Security**: Scan images for vulnerabilities

### Git Security
- **Token Permissions**: Minimal required GitHub token permissions
- **Branch Protection**: Protect main branch with reviews
- **Signed Commits**: Use GPG signing for commits
- **Audit Logs**: Monitor Git repository access

## Backup and Recovery

### Vault Backup
```bash
# Backup Vault data (dev mode)
kubectl exec -n vault-system vault-0 -- vault operator raft snapshot save backup.snap

# Restore Vault data
kubectl exec -n vault-system vault-0 -- vault operator raft snapshot restore backup.snap
```

### Terraform State Backup
```bash
# Backup Terraform state
cp terraform.tfstate terraform.tfstate.backup

# Use remote state (recommended)
terraform {
  backend "s3" {
    bucket = "terraform-state-bucket"
    key    = "kyuubi/terraform.tfstate"
    region = "us-east-1"
  }
}
```

## Cleanup

### Destroy Infrastructure
```bash
# Complete cleanup
./terraform-run.sh cleanup

# Or manual cleanup
cd terraform
terraform destroy -auto-approve
minikube delete
```

### Partial Cleanup
```bash
# Remove specific resources
terraform destroy -target=helm_release.vault
terraform destroy -target=kubernetes_namespace.kyuubi
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes to Terraform configurations
4. Test with `terraform plan`
5. Submit a pull request

## Support

For issues and questions:
1. Check the troubleshooting section
2. Review Terraform and Kubernetes logs
3. Check FluxCD and Vault documentation
4. Open an issue in the repository 