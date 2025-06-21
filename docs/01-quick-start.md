# 🚀 Quick Start – End-to-End Deployment

Spin up the entire Konoha Data Platform on **Minikube** with six simple steps.

> Estimated time: **15 minutes** on a laptop with 4 CPUs & 8 GiB RAM.

---

## 1. Clone & Prepare Repository
```bash
# Clone
git clone https://github.com/anhhoangdev/LocalDataPlatform.git
cd LocalDataPlatform

# Make helper scripts executable
chmod +x deploy.sh
chmod +x infrastructure/apps/*/run.sh 2>/dev/null || true
```

## 2. Start Minikube
```bash
minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=20g

# Enable essential addons
minikube addons enable ingress
minikube addons enable metrics-server
kubectl cluster-info
```

## 3. Configure Terraform Variables
```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# (Optional) tweak values in terraform.tfvars
```

## 4. Run the One-Liner Deploy Script
```bash
cd ..
./deploy.sh
```
This script will:
1. **Terraform** – provision Vault & FluxCD
2. **Configure Vault** – dev mode, root token `root`
3. **Bootstrap FluxCD** – GitOps pipeline
4. **Create Secrets** – for Kyuubi, MinIO, MariaDB

## 5. Verify Everything Is Up
```bash
kubectl get pods --all-namespaces
kubectl get pods -n vault-system
kubectl get pods -n flux-system
```

## 6. Access Core Services
| Service | URL / Command |
|---------|---------------|
| Vault UI | `kubectl port-forward -n vault-system svc/vault 8200:8200` → http://localhost:8200 |
| Kyuubi JDBC | `kubectl port-forward -n kyuubi svc/kyuubi-dbt-shared 10009:10009` |
| MinIO Console | `kubectl port-forward -n minio svc/minio 9001:9001` → http://localhost:9001 |

Add entries to `/etc/hosts` for pretty URLs:
```bash
echo "$(minikube ip) vault.local kyuubi.local" | sudo tee -a /etc/hosts
```

---

Need help? See [ops/troubleshooting](ops/troubleshooting.md) or ping the Discord channel. 