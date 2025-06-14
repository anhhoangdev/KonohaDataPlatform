# Vault Secrets Operator Integration

This document explains how the Vault Secrets Operator is integrated into the LocalDataPlatform setup to provide seamless secret management between HashiCorp Vault and Kubernetes.

## Overview

The Vault Secrets Operator enables Kubernetes workloads to consume Vault secrets natively through Custom Resource Definitions (CRDs). It bridges the gap between Vault's secret management capabilities and Kubernetes' native secret handling.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kubernetes    │    │ Vault Secrets    │    │   HashiCorp     │
│   Workloads     │    │   Operator       │    │     Vault       │
│                 │    │                  │    │                 │
│ [Pod]           │◄──►│ [Controller]     │◄──►│ [KV Secrets]    │
│ [Secret Mount]  │    │ [CRDs]           │    │ [Auth Methods]  │
│ [Env Variables] │    │ [Watchers]       │    │ [Policies]      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## Installation

The Vault Secrets Operator is automatically installed when you run:

```bash
./run.sh full          # Full setup including VSO
./run.sh deploy         # Deploy apps (includes VSO)
./run.sh vault-operator # Install only VSO
```

### Installation Method

The Vault Secrets Operator is installed using the official HashiCorp Helm chart. This provides:

- Automatic CRD management
- Proper versioning and upgrades
- Official HashiCorp support
- Easy configuration through Helm values

### Prerequisites

- **Helm 3.7+** - Required for installing the Vault Secrets Operator
- **Kubernetes 1.23+** - Minimum Kubernetes version
- **kubectl** - Kubernetes command-line tool
- **minikube** - For local development clusters

### Manual Installation

If you need to install it manually using Helm:

```bash
# Add HashiCorp Helm repository
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

# Install Vault Secrets Operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    --version 0.8.1 \
    --namespace vault-secrets-operator-system \
    --create-namespace \
    --wait
```

## Custom Resource Definitions (CRDs)

The operator provides the following CRDs:

### 1. VaultAuth
Defines how to authenticate with Vault:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: kyuubi
spec:
  method: kubernetes        # Authentication method
  mount: kubernetes         # Mount path in Vault
  kubernetes:
    role: kyuubi           # Vault role
    serviceAccount: kyuubi # K8s service account
    audiences:
      - vault
```

### 2. VaultStaticSecret
Syncs static secrets from Vault KV store:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: database-credentials
  namespace: kyuubi
spec:
  type: kv-v2              # Vault secret engine type
  mount: kyuubi            # Vault mount path
  path: kyuubi/database    # Secret path in Vault
  destination:
    name: db-secret        # Target K8s secret name
    create: true           # Create if doesn't exist
  refreshAfter: 30s        # Refresh interval
  vaultAuthRef: vault-auth # Reference to VaultAuth
```

### 3. VaultDynamicSecret
For dynamic secrets (database credentials, etc.):

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: database-creds
  namespace: kyuubi
spec:
  mount: database
  path: database/creds/readonly
  destination:
    name: dynamic-db-creds
    create: true
  vaultAuthRef: vault-auth
```

### 4. VaultConnection
Defines connection details to Vault server:

```yaml
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: kyuubi
spec:
  address: http://vault.vault-system.svc.cluster.local:8200
  skipTLSVerify: true
  timeoutSeconds: 10
```

## Current Integration

### Existing Resources

The LocalDataPlatform currently uses these Vault Secrets Operator resources:

1. **Hive Metastore** (`infrastructure/apps/hive-metastore/base/vault-secret.yaml`):
   - `hive-metastore-credentials` - Database credentials
   - `hive-metastore-minio-credentials` - MinIO/S3 credentials
   - `vault-auth` - Authentication configuration

2. **Kyuubi** (`infrastructure/apps/kyuubi/base/vault-secrets.yaml`):
   - `kyuubi-database-secret` - Database connection
   - `kyuubi-minio-secret` - Object storage credentials
   - `kyuubi-spark-secret` - Spark configuration

3. **MariaDB** (`infrastructure/apps/mariadb/base/vault-secret.yaml`):
   - `mariadb-credentials` - Database user credentials

4. **MinIO** (`infrastructure/apps/minio/base/vault-secret.yaml`):
   - `minio-credentials` - Access credentials

### Authentication Flow

1. **Kubernetes ServiceAccount** → Pod gets ServiceAccount JWT token
2. **Vault Secrets Operator** → Uses JWT to authenticate with Vault
3. **Vault** → Validates token with Kubernetes API
4. **Vault** → Issues Vault token with appropriate policies
5. **Operator** → Uses Vault token to retrieve secrets
6. **Kubernetes** → Operator creates/updates Kubernetes secrets
7. **Application** → Mounts secrets as files or environment variables

## Troubleshooting

### Common Issues

#### 1. CRDs Not Found
```bash
# Error: no matches for kind "VaultAuth"
# Solution: Install the operator
./run.sh vault-operator
```

#### 2. Authentication Failures
```bash
# Check operator logs
kubectl logs -n vault-secrets-operator-system deployment/vault-secrets-operator-controller-manager

# Check VaultAuth status
kubectl describe vaultauth vault-auth -n kyuubi
```

#### 3. Secret Sync Issues
```bash
# Check VaultStaticSecret status
kubectl describe vaultstaticsecret <secret-name> -n kyuubi

# Check if target secret exists
kubectl get secret <target-secret-name> -n kyuubi
```

#### 4. Connection Issues
```bash
# Test Vault connectivity
kubectl run vault-test --rm -it --image=vault:latest -- vault status -address=http://vault.vault-system.svc.cluster.local:8200
```

### Debug Commands

```bash
# Check operator status
kubectl get pods -n vault-secrets-operator-system

# List all CRDs
kubectl get crd | grep vault

# Check all vault resources
kubectl get vaultauth,vaultstaticsecret -A

# View operator logs
kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator

# Check events
kubectl get events -n kyuubi --sort-by='.lastTimestamp'
```

## Configuration

### Operator Configuration

The operator is installed with default settings. For custom configuration:

```yaml
# Custom configuration (not applied by default)
apiVersion: v1
kind: ConfigMap
metadata:
  name: vault-secrets-operator-config
  namespace: vault-secrets-operator-system
data:
  vault-address: "http://vault.vault-system.svc.cluster.local:8200"
  default-auth-method: "kubernetes"
  default-mount-path: "kubernetes"
```

### Environment Variables

The operator supports various environment variables for configuration:

- `VAULT_ADDR` - Vault server address
- `VAULT_NAMESPACE` - Vault namespace (Enterprise)
- `VAULT_CACERT` - CA certificate path
- `VAULT_CLIENT_TIMEOUT` - Client timeout

## Security Considerations

### Least Privilege

Each application has its own Vault role with minimal required permissions:

```hcl
# Example Vault policy
path "kyuubi/data/database" {
  capabilities = ["read"]
}

path "kyuubi/data/minio" {
  capabilities = ["read"]
}
```

### ServiceAccount Binding

Each ServiceAccount is bound to specific Vault roles:

```yaml
# Terraform configuration
resource "vault_kubernetes_auth_backend_role" "kyuubi" {
  role_name                        = "kyuubi"
  bound_service_account_names      = ["kyuubi", "kyuubi-dbt", "kyuubi-dbt-shared"]
  bound_service_account_namespaces = ["kyuubi"]
  token_policies                   = ["kyuubi-read"]
}
```

### Secret Rotation

Secrets are automatically refreshed based on `refreshAfter` settings:

- Database credentials: 30 seconds
- MinIO credentials: 30 seconds
- Application configs: 30 seconds

## Monitoring

### Metrics

The operator exposes Prometheus metrics:

```bash
# Port forward to metrics endpoint
kubectl port-forward -n vault-secrets-operator-system svc/vault-secrets-operator-controller-manager-metrics-service 8080:8443

# Access metrics
curl -k https://localhost:8080/metrics
```

### Health Checks

```bash
# Check operator health
kubectl get pods -n vault-secrets-operator-system
kubectl describe deployment vault-secrets-operator-controller-manager -n vault-secrets-operator-system
```

## Integration with Other Components

### Terraform Integration

The Terraform configuration creates the necessary Vault roles and policies:

- `vault_kubernetes_auth_backend_role.kyuubi` - Main application role
- `vault_kubernetes_auth_backend_role.vault_secrets_operator` - Operator role
- `vault_policy.kyuubi_read` - Read-only policy for secrets

### FluxCD Integration

The operator works seamlessly with FluxCD for GitOps workflows:

```yaml
# VaultStaticSecret is reconciled by FluxCD
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: app-secret
  namespace: kyuubi
spec:
  # FluxCD applies this resource
  # Operator syncs the secret from Vault
  # Application consumes the Kubernetes secret
```

## Best Practices

1. **Use Specific Vault Roles**: Create dedicated roles for each application
2. **Implement Secret Rotation**: Use appropriate `refreshAfter` values
3. **Monitor Secret Sync**: Set up alerts for sync failures
4. **Use Least Privilege**: Grant minimal required permissions
5. **Secure Communications**: Use TLS in production environments
6. **Regular Updates**: Keep the operator updated to latest versions

## Version Compatibility

- **Vault Secrets Operator**: v0.8.1
- **HashiCorp Vault**: v1.15.4+
- **Kubernetes**: v1.24+
- **Terraform Vault Provider**: v3.0+

## Resources

- [Vault Secrets Operator Documentation](https://developer.hashicorp.com/vault/docs/platform/k8s/vso)
- [CRD Reference](https://developer.hashicorp.com/vault/docs/platform/k8s/vso/api-reference)
- [GitHub Repository](https://github.com/hashicorp/vault-secrets-operator)
- [Release Notes](https://github.com/hashicorp/vault-secrets-operator/releases) 