# Terraform Infrastructure Guide - Kyuubi LocalDataPlatform

## Overview

This guide documents the evolution from manual deployment scripts to a complete Infrastructure as Code (IaC) solution using Terraform, HashiCorp Vault, and FluxCD for the Kyuubi LocalDataPlatform.

## Architecture Evolution

### Before: Manual Script Approach
```
Manual Script (run.sh)
├── Minikube setup
├── Docker image building
├── kubectl apply commands
├── Manual port forwarding
└── Manual configuration management
```

**Problems:**
- Manual configuration management
- Secrets stored in plain text
- No version control for infrastructure
- Difficult to reproduce environments
- No automated rollbacks
- Manual dependency management

### After: Infrastructure as Code
```
Terraform + Vault + FluxCD
├── Terraform (Infrastructure)
│   ├── Minikube cluster management
│   ├── Vault deployment & configuration
│   ├── FluxCD installation & setup
│   └── RBAC and networking
├── Vault (Secrets Management)
│   ├── Encrypted secret storage
│   ├── Kubernetes authentication
│   ├── Policy-based access control
│   └── Dynamic secret generation
└── FluxCD (GitOps)
    ├── Git-driven deployments
    ├── Automatic reconciliation
    ├── Health monitoring
    └── Rollback capabilities
```

**Benefits:**
- ✅ Infrastructure as Code (version controlled)
- ✅ Secure secrets management with Vault
- ✅ GitOps workflow with FluxCD
- ✅ Automated deployments and rollbacks
- ✅ Reproducible environments
- ✅ Policy-based access control
- ✅ Continuous reconciliation

## Key Components

### 1. Terraform Infrastructure

#### Core Resources
```hcl
# Kubernetes namespaces
resource "kubernetes_namespace" "vault" { ... }
resource "kubernetes_namespace" "flux_system" { ... }

# Vault deployment via Helm
resource "helm_release" "vault" { ... }

# FluxCD bootstrap
resource "flux_bootstrap_git" "this" { ... }

# Vault secrets configuration
resource "vault_mount" "kyuubi" { ... }
resource "vault_kv_secret_v2" "database" { ... }
```

#### Benefits
- **Declarative**: Infrastructure defined in code
- **Version Controlled**: All changes tracked in Git
- **Reproducible**: Identical environments every time
- **Dependency Management**: Automatic resource ordering
- **State Management**: Tracks actual vs desired state

### 2. HashiCorp Vault Integration

#### Secrets Structure
```
vault/kyuubi/
├── database/          # MariaDB credentials
├── spark/            # Spark configuration
├── kyuubi-server/    # Kyuubi server settings
├── aws/              # S3/MinIO credentials
└── monitoring/       # Grafana/Prometheus (optional)
```

#### Authentication Flow
```
1. Kyuubi Pod starts with ServiceAccount
2. ServiceAccount authenticates with Vault
3. Vault validates against Kubernetes API
4. Vault issues token with kyuubi-policy
5. Pod retrieves secrets using token
6. Secrets injected as environment variables
```

#### Benefits
- **Security**: Encrypted storage with access policies
- **Dynamic Secrets**: Automatic credential rotation
- **Audit Trail**: Complete access logging
- **Integration**: Native Kubernetes authentication
- **Centralized**: Single source of truth for secrets

### 3. FluxCD GitOps

#### Workflow
```
1. Developer commits infrastructure changes to Git
2. FluxCD detects changes in repository
3. FluxCD applies changes to Kubernetes cluster
4. Health checks validate deployment success
5. Automatic rollback if deployment fails
```

#### Kustomizations
```yaml
# Infrastructure components
infrastructure:
  path: ./infrastructure/apps
  healthChecks: [mariadb, hive-metastore]

# Kyuubi applications  
kyuubi:
  path: ./infrastructure/apps/kyuubi/overlays/minikube
  healthChecks: [kyuubi-dbt, kyuubi-dbt-shared]
  dependsOn: [infrastructure]

# Vault secrets sync
vault-secrets:
  path: ./infrastructure/vault-secrets
  interval: 10m
```

#### Benefits
- **Git-Driven**: Infrastructure changes via Git commits
- **Automatic Sync**: Continuous reconciliation
- **Health Monitoring**: Deployment validation
- **Rollback**: Easy revert to previous state
- **Audit**: Complete change history in Git

## Deployment Comparison

### Manual Script Deployment
```bash
# Old approach
./run.sh full

# Steps:
1. Manual Minikube setup
2. Docker image building
3. kubectl apply commands
4. Manual secret creation
5. Manual port forwarding
6. Manual health checks
```

### Terraform Infrastructure Deployment
```bash
# New approach
export GITHUB_TOKEN="ghp_xxx"
export GITHUB_OWNER="username"
./terraform-run.sh full

# Steps:
1. Terraform provisions infrastructure
2. Vault automatically configured
3. FluxCD syncs from Git
4. Secrets injected automatically
5. Health checks automated
6. Port forwarding scripted
```

## Configuration Management

### Before: Manual Configuration
```yaml
# Hardcoded in YAML files
env:
- name: MARIADB_PASSWORD
  value: "hardcoded-password"
- name: SPARK_EXECUTOR_MEMORY
  value: "12g"
```

### After: Vault-Managed Configuration
```yaml
# Vault secret injection
env:
- name: MARIADB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: vault-secret-database
      key: mariadb_password
```

```hcl
# Terraform-managed secrets
resource "vault_kv_secret_v2" "database" {
  mount = vault_mount.kyuubi.path
  name  = "database"
  data_json = jsonencode({
    mariadb_password = var.database_password
  })
}
```

## Security Improvements

### Authentication & Authorization

#### Before: No Authentication
```yaml
# No authentication mechanism
kyuubi.authentication=NONE
```

#### After: Vault-Based Authentication
```yaml
# Kubernetes service account authentication
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kyuubi-sa
  annotations:
    vault.hashicorp.com/auth-path: "auth/kubernetes"
    vault.hashicorp.com/role: "kyuubi-role"
```

### Secret Management

#### Before: Plain Text Secrets
```yaml
# Secrets in plain text
data:
  password: "my-password"
  api-key: "secret-key"
```

#### After: Encrypted Vault Storage
```bash
# Encrypted storage with access policies
vault kv put kyuubi/database password="encrypted-password"
vault policy write kyuubi-policy - <<EOF
path "kyuubi/data/*" {
  capabilities = ["read"]
}
EOF
```

## Operational Benefits

### 1. Disaster Recovery
```bash
# Before: Manual recreation
1. Manually rebuild Minikube
2. Manually apply configurations
3. Manually recreate secrets
4. Manual validation

# After: Automated recovery
1. Run: ./terraform-run.sh full
2. Everything recreated automatically
3. Secrets restored from Vault
4. Health checks automated
```

### 2. Environment Consistency
```bash
# Before: Environment drift
- Different configurations per environment
- Manual configuration updates
- Inconsistent secret management

# After: Consistent environments
- Infrastructure as Code ensures consistency
- Vault provides centralized secret management
- FluxCD ensures desired state compliance
```

### 3. Change Management
```bash
# Before: Manual changes
1. SSH into cluster
2. kubectl edit resources
3. Manual documentation
4. No rollback mechanism

# After: Git-driven changes
1. Create pull request
2. Review infrastructure changes
3. Merge triggers deployment
4. Automatic rollback on failure
```

## Monitoring and Observability

### Infrastructure Monitoring
```bash
# Terraform state monitoring
terraform show
terraform plan

# Vault health monitoring
vault status
vault audit list

# FluxCD monitoring
flux get all -A
flux logs -n flux-system
```

### Application Monitoring (Optional)
```yaml
# Prometheus + Grafana deployment
enable_monitoring = true

# Automatic dashboards for:
- Kyuubi server metrics
- Spark application metrics
- Vault operational metrics
- FluxCD deployment metrics
```

## Best Practices Implemented

### 1. Infrastructure as Code
- **Version Control**: All infrastructure in Git
- **Code Review**: Pull request workflow
- **Testing**: Terraform plan before apply
- **Documentation**: Self-documenting code

### 2. Security
- **Least Privilege**: Minimal RBAC permissions
- **Secret Rotation**: Vault-managed credentials
- **Audit Logging**: Complete access trails
- **Policy Enforcement**: Vault access policies

### 3. GitOps
- **Single Source of Truth**: Git repository
- **Declarative**: Desired state in YAML
- **Automated**: Continuous reconciliation
- **Observable**: Health checks and monitoring

### 4. Operational Excellence
- **Automation**: Minimal manual intervention
- **Reproducibility**: Identical environments
- **Scalability**: Easy resource scaling
- **Maintainability**: Clear separation of concerns

## Migration Path

### Phase 1: Terraform Foundation
```bash
1. Create Terraform configurations
2. Deploy Vault and FluxCD
3. Migrate secrets to Vault
4. Test infrastructure deployment
```

### Phase 2: GitOps Integration
```bash
1. Move Kubernetes manifests to Git
2. Configure FluxCD kustomizations
3. Test Git-driven deployments
4. Implement health checks
```

### Phase 3: Full Automation
```bash
1. Automate image building
2. Implement CI/CD pipelines
3. Add monitoring and alerting
4. Document operational procedures
```

## Troubleshooting Guide

### Common Issues

#### 1. Terraform State Conflicts
```bash
# Problem: Multiple users modifying state
# Solution: Use remote state backend
terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "kyuubi/terraform.tfstate"
  }
}
```

#### 2. Vault Authentication Failures
```bash
# Problem: Service account can't authenticate
# Check: Kubernetes auth configuration
vault auth list
vault read auth/kubernetes/config

# Fix: Reconfigure Kubernetes auth
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"
```

#### 3. FluxCD Sync Issues
```bash
# Problem: Git repository not syncing
# Check: Repository status
flux get sources git -A

# Fix: Force reconciliation
flux reconcile source git kyuubi-platform
```

## Future Enhancements

### 1. Multi-Environment Support
```hcl
# Environment-specific configurations
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

locals {
  config = {
    dev = {
      replicas = 1
      resources = "small"
    }
    prod = {
      replicas = 3
      resources = "large"
    }
  }
}
```

### 2. Advanced Vault Features
```bash
# Dynamic database credentials
vault write database/config/mariadb \
  plugin_name=mysql-database-plugin \
  connection_url="{{username}}:{{password}}@tcp(mariadb:3306)/" \
  allowed_roles="kyuubi-role"

# Certificate management
vault write pki/config/urls \
  issuing_certificates="http://vault:8200/v1/pki/ca" \
  crl_distribution_points="http://vault:8200/v1/pki/crl"
```

### 3. Advanced GitOps
```yaml
# Progressive delivery with Flagger
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: kyuubi-dbt
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: kyuubi-dbt
  analysis:
    interval: 1m
    threshold: 5
    maxWeight: 50
```

## Conclusion

The migration from manual scripts to Infrastructure as Code with Terraform, Vault, and FluxCD provides:

1. **Reliability**: Consistent, reproducible deployments
2. **Security**: Encrypted secrets with access control
3. **Maintainability**: Version-controlled infrastructure
4. **Scalability**: Easy environment replication
5. **Observability**: Complete audit trails and monitoring

This approach transforms the Kyuubi LocalDataPlatform from a development prototype into a production-ready, enterprise-grade data platform. 