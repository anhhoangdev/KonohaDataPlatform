# HashiCorp Vault Integration for Kyuubi LocalDataPlatform

This directory contains Terraform configurations to deploy and configure HashiCorp Vault in your minikube environment for secure secrets management in the Kyuubi LocalDataPlatform.

## Overview

This Terraform setup provides:
- ✅ HashiCorp Vault deployment using Helm
- ✅ Kubernetes authentication integration
- ✅ Vault policies for secure access control
- ✅ Pre-configured secrets for Kyuubi applications
- ✅ Service accounts with proper RBAC
- ✅ Development and production mode support

## Prerequisites

Before running Terraform, ensure you have:

1. **Required tools installed:**
   ```bash
   # Terraform
   terraform --version  # >= 1.0

   # Kubectl
   kubectl version --client

   # Helm
   helm version

   # Vault CLI
   vault version
   ```

2. **Minikube cluster running:**
   ```bash
   # Start minikube first
   ./run.sh minikube
   
   # Or manually
   minikube start --cpus=12 --memory=24576 --disk-size=50g
   ```

3. **kubectl configured for minikube:**
   ```bash
   kubectl cluster-info
   ```

## Quick Start

1. **Initialize and deploy Vault:**
   ```bash
   # Run the deployment script
   ./deploy-vault.sh
   
   # Or step by step
   ./deploy-vault.sh init
   ./deploy-vault.sh plan
   ./deploy-vault.sh apply
   ```

2. **Access Vault UI:**
   ```bash
   # Port forwarding is set up automatically
   open http://localhost:8200/ui
   
   # Dev mode token: root
   # Production mode: check terraform outputs
   ```

3. **Configure environment:**
   ```bash
   export VAULT_ADDR=http://localhost:8200
   export VAULT_TOKEN=root  # dev mode
   
   # Test connection
   vault status
   ```

## Configuration

### terraform.tfvars

Copy and customize the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferences
```

Key configuration options:

```hcl
# Development mode (easier setup, less secure)
vault_dev_mode = true
vault_ui_enabled = true

# Production mode (more secure, requires initialization)
vault_dev_mode = false
vault_storage_size = "10Gi"

# Secrets to create for Kyuubi
create_vault_secrets = true
kyuubi_secrets = {
  database = {
    path = "kyuubi/database"
    data = {
      mariadb_password = "your-secure-password"
      # ... other database config
    }
  }
  # ... other secrets
}
```

## Vault Integration Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kyuubi Pod    │    │  Vault Server    │    │  Kubernetes     │
│                 │    │                  │    │  API Server     │
│ [ServiceAccount]│◄──►│ [Auth Backend]   │◄──►│                 │
│ [Vault Agent]   │    │ [KV Secrets]     │    │ [Token Review]  │
│ [App Container] │    │ [Policies]       │    │                 │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Authentication Flow

1. Kyuubi pod starts with a Kubernetes ServiceAccount
2. ServiceAccount JWT token is used to authenticate with Vault
3. Vault validates the token with Kubernetes API
4. Vault issues a Vault token with appropriate policies
5. Pod uses Vault token to retrieve secrets

### Secrets Structure

```
vault kv/
└── kyuubi/
    ├── database/          # MariaDB credentials
    │   ├── mariadb_user
    │   ├── mariadb_password
    │   └── mariadb_host
    ├── spark/             # Spark configuration
    │   ├── spark_executor_memory
    │   └── spark_executor_cores
    ├── kyuubi-server/     # Kyuubi server settings
    │   ├── kyuubi_user_timeout
    │   └── kyuubi_server_timeout
    └── minio/             # S3/MinIO credentials
        ├── minio_access_key
        └── minio_secret_key
```

## Usage Examples

### Reading Secrets with Vault CLI

```bash
# List all secrets
vault kv list kyuubi/

# Read database secrets
vault kv get kyuubi/database

# Read specific secret field
vault kv get -field=mariadb_password kyuubi/database
```

### Using Secrets in Kubernetes

#### Method 1: Vault Agent Injector (Recommended)

Add annotations to your deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kyuubi-server
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/auth-path: "auth/kubernetes"
        vault.hashicorp.com/role: "kyuubi"
        vault.hashicorp.com/agent-inject-secret-database: "kyuubi/database"
        vault.hashicorp.com/agent-inject-template-database: |
          {{- with secret "kyuubi/database" -}}
          MARIADB_PASSWORD={{ .Data.data.mariadb_password }}
          MARIADB_USER={{ .Data.data.mariadb_user }}
          {{- end }}
    spec:
      serviceAccountName: kyuubi-dbt
      containers:
      - name: kyuubi
        image: kyuubi-server:1.10.0
        env:
        - name: MARIADB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: vault-secret-database
              key: mariadb_password
```

#### Method 2: External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "http://vault.vault-system:8200"
      path: "kyuubi"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "kyuubi"
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: kyuubi-database-secret
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: kyuubi-database
    creationPolicy: Owner
  data:
  - secretKey: mariadb_password
    remoteRef:
      key: database
      property: mariadb_password
```

## Terraform Resources

### Main Resources Created

- `kubernetes_namespace.vault` - Vault system namespace
- `helm_release.vault` - Vault server deployment
- `vault_auth_backend.kubernetes` - Kubernetes auth method
- `vault_mount.kyuubi_kv` - KV secrets engine
- `vault_policy.kyuubi_read` - Read-only policy
- `vault_kubernetes_auth_backend_role.kyuubi` - Auth role
- `kubernetes_service_account.kyuubi*` - Service accounts

### Outputs

Key outputs available after deployment:

```bash
# Get all outputs
terraform output

# Get specific output
terraform output vault_ui_url
terraform output vault_root_token
```

## Operations

### Daily Operations

```bash
# Check Vault status
vault status

# List available secrets
vault kv list kyuubi/

# Add new secret
vault kv put kyuubi/new-service password=secret123

# Update existing secret
vault kv patch kyuubi/database new_field=value

# View audit logs
kubectl logs -n vault-system -l app.kubernetes.io/name=vault
```

### Backup and Recovery

```bash
# Backup Vault data (production mode)
kubectl exec -n vault-system vault-0 -- vault operator backup

# In dev mode, secrets are recreated from Terraform
terraform apply -refresh-only
```

### Scaling

```bash
# Update replica count (production mode)
# Edit terraform.tfvars
vault_replicas = 3

# Apply changes
terraform apply
```

## Troubleshooting

### Common Issues

#### 1. Vault Pod Not Starting

```bash
# Check pod status
kubectl get pods -n vault-system

# Check pod logs
kubectl logs -n vault-system -l app.kubernetes.io/name=vault

# Check events
kubectl describe pod -n vault-system vault-0
```

#### 2. Authentication Issues

```bash
# Verify Kubernetes auth is configured
vault auth list

# Test Kubernetes auth
vault write auth/kubernetes/login role=kyuubi jwt=$SA_JWT_TOKEN

# Check service account tokens
kubectl get secret $(kubectl get sa kyuubi -o jsonpath='{.secrets[0].name}') -o yaml
```

#### 3. Secret Access Issues

```bash
# Check policies
vault policy list
vault policy read kyuubi-read

# Check token capabilities
vault token capabilities kyuubi/database
```

#### 4. Port Forwarding Issues

```bash
# Kill existing port forwards
pkill -f "kubectl.*port-forward.*vault"

# Restart port forwarding
kubectl port-forward -n vault-system svc/vault 8200:8200
```

### Recovery Procedures

#### Reset Development Environment

```bash
# Destroy and recreate
./deploy-vault.sh cleanup
./deploy-vault.sh deploy
```

#### Production Environment Recovery

```bash
# Check Vault seal status
vault status

# If sealed, unseal Vault
vault operator unseal

# Verify data integrity
vault kv list kyuubi/
```

## Security Considerations

### Development Mode vs Production Mode

**Development Mode (vault_dev_mode = true):**
- ✅ Easy setup and testing
- ✅ Automatic unsealing
- ❌ Data stored in memory only
- ❌ Root token is "root"
- ❌ Not suitable for production

**Production Mode (vault_dev_mode = false):**
- ✅ Persistent storage
- ✅ Secure initialization
- ✅ Proper seal/unseal process
- ❌ Requires manual initialization
- ❌ More complex setup

### Best Practices

1. **Use least privilege policies**
2. **Rotate secrets regularly**
3. **Monitor audit logs**
4. **Use different namespaces for different environments**
5. **Implement backup strategies for production**

## Integration with Existing Kyuubi Setup

To integrate Vault with your existing Kyuubi deployments:

1. **Update Kustomize configurations** to reference Vault secrets
2. **Add Vault annotations** to deployment templates
3. **Update service accounts** to use Vault-enabled ones
4. **Migrate existing secrets** to Vault

Example migration script:

```bash
#!/bin/bash
# Migrate existing Kubernetes secrets to Vault

# Get existing secret
OLD_PASSWORD=$(kubectl get secret mariadb-secret -o jsonpath='{.data.password}' | base64 -d)

# Store in Vault
vault kv put kyuubi/database mariadb_password="$OLD_PASSWORD"

# Update deployment to use Vault
kubectl patch deployment kyuubi-server -p '{"spec":{"template":{"metadata":{"annotations":{"vault.hashicorp.com/agent-inject":"true"}}}}}'
```

## Next Steps

1. **Deploy Vault**: Run `./deploy-vault.sh`
2. **Test integration**: Use `./deploy-vault.sh test`
3. **Update Kyuubi configs**: Modify your Kustomize files
4. **Implement secret rotation**: Set up automated rotation
5. **Monitor and maintain**: Regular backup and monitoring

For more detailed information, see the [official Vault documentation](https://www.vaultproject.io/docs). 