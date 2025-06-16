# 🛠️ Management Commands

### Vault Operations

```bash
# Access Vault CLI
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root"

# List secrets
vault kv list kyuubi/

# Read a secret
vault kv get kyuubi/database

# Create/update a secret
vault kv put kyuubi/custom key1=value1 key2=value2
```

### FluxCD Operations

```bash
# Check GitOps status
flux get sources git
flux get kustomizations

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization apps

# Suspend/resume GitOps
flux suspend kustomization apps
flux resume kustomization apps
```

### Application Management

```bash
# Deploy Kyuubi
cd infrastructure/apps/kyuubi
./run.sh

# Deploy Hive Metastore
cd infrastructure/apps/hive-metastore
./run.sh

# Check application status
kubectl get pods -n kyuubi
kubectl get pods -n hive-metastore
```
