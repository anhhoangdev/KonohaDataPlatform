# 🚀 Quick Start – End-to-End Deployment

Spin up the entire Konoha Data Platform on **Minikube** with just **three** commands.

> Estimated time: **15 minutes** on a laptop with 4 CPUs & 8 GiB RAM.

---

## 1. Spin-up the Cluster
```bash
./start-minikube.sh start          # creates/starts Minikube with addons
```

## 2. Build Images & Deploy Core Infra
```bash
./deploy-complete.sh              # builds images, loads them, deploys Vault (+ port-forward)
```
When it finishes you'll have:
• All custom Docker images already inside the cluster
• Namespaces created, Vault dev mode running and port-forwarded to http://localhost:8200 (token `root`)

## 3. Let Terraform Do the Magic
```bash
cd terraform
terraform init
terraform apply -auto-approve      # ☕ wait ~10 min – full stack appears
```

Vault, MinIO, Hive Metastore, Iceberg, Kyuubi, Airflow, Trino, Grafana, etc. are up and wired together.

<details>
<summary>Need the old step-by-step flow with the helper script? (click)</summary>

The original six-step guide (clone repo, `./deploy.sh`, etc.) is still available <a href="https://github.com/anhhoangdev/LocalDataPlatform/blob/main/docs/legacy/quick-start-v1.md">here</a> for power-users who prefer granular control.

</details>

---

Need help? See [ops/troubleshooting](ops/troubleshooting.md) or open an issue. 