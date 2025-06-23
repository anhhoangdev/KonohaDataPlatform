# LocalDataPlatform - Docker Images Guide

## 🐳 Why Build & Load Images to Minikube?

### **The Problem**
When you deploy Kubernetes manifests that reference custom Docker images, minikube cannot find them because:

1. **Separate Docker Daemon**: Minikube runs its own Docker daemon isolated from your host system
2. **Image Not Available**: Custom images built on your host aren't accessible inside minikube
3. **ImagePullBackOff**: Pods fail with `ImagePullBackOff` or `ErrImagePull` errors
4. **No Registry**: Local images aren't pushed to a container registry minikube can access

### **The Solution**
We need to **build images** and **load them into minikube's Docker registry**.

## 🔧 Custom Images in LocalDataPlatform

### **What We Build:**
```bash
# Data Platform Images
hive-metastore:3.1.3           # Apache Hive Metastore with Iceberg support
kyuubi-server:1.10.0           # Kyuubi SQL Gateway server
spark-engine-iceberg:3.5.0-1.4.2  # Spark with Iceberg + AWS libraries

# Processing Images  
dbt-spark:latest               # DBT with Spark adapter
local-kafka-connect-full:latest # Kafka Connect with CDC connectors
postgres-cdc:15                # PostgreSQL with CDC configuration
```

### **Why Custom Images?**
- **Iceberg Integration**: Pre-configured with Apache Iceberg libraries
- **AWS Support**: S3/MinIO connectivity for data lake storage  
- **CDC Capabilities**: Change Data Capture for real-time data streaming
- **Optimized Configuration**: Tuned for the data platform workloads

## 🚀 Complete Deployment Process

### **Option 1: One Command (Recommended)**
```bash
./deploy-complete.sh
```

**What it does:**
1. ✅ Downloads all dependencies (~2GB)
2. ✅ Builds 6 custom Docker images 
3. ✅ Loads images into minikube registry
4. ✅ Deploys infrastructure with Terraform
5. ✅ Configures Vault and secrets
6. ✅ Deploys all applications
7. ✅ Sets up ingress (no port forwarding)

### **Option 2: Step by Step**
```bash
# Step 1: Build and load images only
./deploy-complete.sh images

# Step 2: Deploy infrastructure
./deploy-no-portforward.sh

# Step 3: Check status
./deploy-complete.sh status
```

## 🔍 Image Loading Technical Details

### **How Images Are Loaded:**
```bash
# Switch to minikube Docker environment
eval $(minikube docker-env)

# Build images (they go directly to minikube)
docker build -t hive-metastore:3.1.3 .

# Or load existing images
docker save hive-metastore:3.1.3 | docker load

# Reset to host Docker environment  
eval $(minikube docker-env -u)
```

### **Verification:**
```bash
# Check images in minikube
eval $(minikube docker-env)
docker images | grep -E "(hive|kyuubi|spark|dbt)"

# Check pod status
kubectl get pods --all-namespaces
```

## ⚠️ Common Issues & Solutions

### **Issue 1: ImagePullBackOff**
```bash
Error: Failed to pull image "kyuubi-server:1.10.0": rpc error: code = NotFound
```

**Solution:** Run image loading:
```bash
./deploy-complete.sh images
```

### **Issue 2: Build Failures**
```bash
Error: Dependencies not found
```

**Solution:** Download dependencies first:
```bash
cd docker && ./download-dependencies.sh
```

### **Issue 3: Docker Environment Mix-up**
**Problem:** Images built but not visible in minikube

**Solution:** Use the complete script:
```bash
./deploy-complete.sh
```

## 🎯 Best Practices

### **Fresh Deployment:**
1. **Always use the complete script** for fresh minikube clusters
2. **Don't skip image building** - it prevents deployment failures
3. **Check prerequisites** - Docker, minikube, terraform, kubectl

### **Development Workflow:**
```bash
# Rebuild specific image
cd docker && docker build -t kyuubi-server:1.10.0 kyuubi-server/

# Load to minikube
eval $(minikube docker-env)
docker build -t kyuubi-server:1.10.0 kyuubi-server/
eval $(minikube docker-env -u)

# Restart deployment
kubectl rollout restart deployment/kyuubi-server -n kyuubi
```

### **Image Updates:**
```bash
# Update and reload all images
./deploy-complete.sh images

# Restart affected deployments
kubectl rollout restart deployment --all -n kyuubi
kubectl rollout restart deployment --all -n airflow
```

## 📊 Image Sizes

| Image | Size | Purpose |
|-------|------|---------|
| hive-metastore:3.1.3 | ~800MB | Metadata management |
| kyuubi-server:1.10.0 | ~1.2GB | SQL gateway |
| spark-engine-iceberg:3.5.0-1.4.2 | ~1.5GB | Spark processing |
| dbt-spark:latest | ~500MB | Data transformation |
| local-kafka-connect-full:latest | ~1GB | Streaming & CDC |
| postgres-cdc:15 | ~400MB | Database with CDC |

**Total:** ~5.4GB of custom images

## 🚀 Quick Start

For a fresh minikube cluster:

```bash
# 1. Start minikube with enough resources
minikube start --cpus=6 --memory=12288 --disk-size=40g

# 2. Run complete deployment (handles everything)
./deploy-complete.sh

# 3. Access services
# - Vault: http://vault.local
# - Airflow: http://airflow.local  
# - Grafana: http://grafana.local
# - Keycloak: http://keycloak.local
```

## 🔄 Alternative: Using Docker Registry

If you prefer using a registry instead of direct loading:

```bash
# Tag for registry
docker tag kyuubi-server:1.10.0 localhost:5000/kyuubi-server:1.10.0

# Push to local registry
docker push localhost:5000/kyuubi-server:1.10.0

# Update Kubernetes manifests to use registry URL
# image: localhost:5000/kyuubi-server:1.10.0
```

The `deploy-complete.sh` script handles the direct loading approach which is simpler for local development. 