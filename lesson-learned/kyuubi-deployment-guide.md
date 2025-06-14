# Kyuubi Deployment Guide - Lessons Learned

## Overview
This guide documents the complete setup and troubleshooting process for deploying Apache Kyuubi on Kubernetes with Spark and Iceberg support. The deployment uses a GitOps approach with FluxCD and includes two service levels: USER-level and SERVER-level sharing.

## Architecture

### Infrastructure Components
- **Kyuubi Server**: Query gateway and session management
- **Spark Engine**: Distributed compute engine with Iceberg support
- **Hive Metastore**: Metadata management with MariaDB backend
- **Kubernetes**: Container orchestration on Minikube
- **FluxCD**: GitOps deployment automation

### Service Levels
1. **kyuubi-dbt** (USER-level): Individual user sessions, 30s timeout, 3 replicas
2. **kyuubi-dbt-shared** (SERVER-level): Shared sessions, 15min timeout, 1 replica

## Docker Images

### 1. Kyuubi Server Image (`kyuubi-server:1.10.0`)
```dockerfile
FROM apache/kyuubi:1.10.0

# Add Kyuubi Spark SQL Engine JAR
RUN mkdir -p /opt/kyuubi/externals/engines/spark
COPY kyuubi-spark-sql-engine_2.12-1.10.0.jar /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar

# Set permissions
RUN chown -R kyuubi:kyuubi /opt/kyuubi/externals && \
    chmod -R 755 /opt/kyuubi/externals
```

### 2. Spark Engine Image (`spark-engine-iceberg:1.5.0`)
```dockerfile
FROM apache/spark:3.5.0

# Install Iceberg and AWS dependencies
RUN curl -L https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.5.0/iceberg-spark-runtime-3.5_2.12-1.5.0.jar \
    -o /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.5.0.jar

# Add Kyuubi Spark SQL Engine JAR (CRITICAL!)
RUN curl -L https://repo1.maven.org/maven2/org/apache/kyuubi/kyuubi-spark-sql-engine_2.12/1.10.0/kyuubi-spark-sql-engine_2.12-1.10.0.jar \
    -o /opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar

# Create kyuubi directories and copy JAR
RUN mkdir -p /opt/kyuubi/externals/engines/spark && \
    cp /opt/spark/jars/kyuubi-spark-sql-engine_2.12-1.10.0.jar /opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar

# Set permissions for work directory and kyuubi
RUN mkdir -p /opt/spark/work-dir && \
    chown -R 1000:1000 /opt/kyuubi /opt/spark/work-dir && \
    chmod -R 755 /opt/kyuubi /opt/spark/work-dir

# Set environment
ENV SPARK_USER=spark
```

## Key Configuration

### Kyuubi Server Configuration
```yaml
env:
- name: KYUUBI_FRONTEND_BIND_HOST
  value: "0.0.0.0"  # CRITICAL: Required for external connections
- name: KYUUBI_ENGINE_SHARE_LEVEL
  value: "USER"  # or "SERVER"
- name: KYUUBI_SESSION_ENGINE_IDLE_TIMEOUT
  value: "PT30S"  # USER-level: 30s, SERVER-level: PT15M
- name: SPARK_KUBERNETES_CONTAINER_IMAGE
  value: "spark-engine-iceberg:1.5.0"
- name: SPARK_KUBERNETES_AUTHENTICATE_DRIVER_SERVICEACCOUNTNAME
  value: "kyuubi-sa"
```

### Spark Configuration
```yaml
- name: SPARK_MASTER
  value: "k8s://https://kubernetes.default.svc:443"
- name: SPARK_SUBMIT_DEPLOYMODE
  value: "cluster"
- name: SPARK_DRIVER_MEMORY
  value: "5g"
- name: SPARK_DRIVER_MEMORY_OVERHEAD
  value: "1g"
- name: SPARK_EXECUTOR_MEMORY
  value: "12g"
- name: SPARK_EXECUTOR_CORES
  value: "2"
- name: SPARK_HIVE_METASTORE_URIS
  value: "thrift://hive-metastore:9083"
```

### Dynamic Allocation
```yaml
- name: SPARK_DYNAMICALLOCATION_ENABLED
  value: "true"
- name: SPARK_DYNAMICALLOCATION_MINEXECUTORS
  value: "0"
- name: SPARK_DYNAMICALLOCATION_MAXEXECUTORS
  value: "9"
- name: SPARK_DYNAMICALLOCATION_EXECUTORIDLETIMEOUT
  value: "60s"
- name: SPARK_DYNAMICALLOCATION_CACHEDEXECUTORIDLETIMEOUT
  value: "1800s"
```

## Critical Lessons Learned

### 1. JAR Placement Issue
**Problem**: `NoSuchFileException` and `AccessDeniedException` when starting Spark engines.

**Root Cause**: The Kyuubi Spark SQL Engine JAR must be available in the **Spark driver pod**, not just the Kyuubi server pod.

**Solution**: 
- Add JAR to both `/opt/spark/jars/` and `/opt/kyuubi/externals/engines/spark/` in the Spark image
- Set `kyuubi.session.engine.spark.main.resource=local:///opt/kyuubi/externals/engines/spark/kyuubi-spark-sql-engine.jar`
- Use `local://` URI to indicate the JAR is already available locally

### 2. Frontend Binding Issue
**Problem**: `Connection refused` errors when port-forwarding to Kyuubi services.

**Root Cause**: Kyuubi server binds to localhost by default, preventing external connections.

**Solution**: Set `KYUUBI_FRONTEND_BIND_HOST=0.0.0.0` in all Kyuubi deployments.

### 3. Permission Issues
**Problem**: `AccessDeniedException` when writing to `/opt/spark/work-dir/`.

**Solution**: 
- Set proper ownership: `chown -R 1000:1000 /opt/spark/work-dir`
- Set proper permissions: `chmod -R 755 /opt/spark/work-dir`
- Set `SPARK_USER=spark` environment variable

### 4. Pod Naming Conflicts
**Problem**: Hardcoded pod names causing conflicts in multi-user scenarios.

**Solution**: Remove `spark.kubernetes.driver.pod.name` to allow automatic generation.

## Deployment Structure

```
infrastructure/apps/kyuubi/
├── base/
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── rbac.yaml
│   ├── kyuubi-dbt-deployment.yaml      # USER-level service
│   ├── kyuubi-dbt-shared-deployment.yaml  # SERVER-level service
│   └── configmap.yaml
└── overlays/
    └── minikube/
        ├── kustomization.yaml
        └── patches/
```

## RBAC Configuration
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kyuubi-sa
  namespace: kyuubi
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: kyuubi-spark-role
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "persistentvolumeclaims"]
  verbs: ["create", "get", "list", "watch", "delete", "update", "patch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
```

## Connection Details

### JDBC URLs
- **USER-level**: `jdbc:hive2://localhost:10010/default`
- **SERVER-level**: `jdbc:hive2://localhost:10009/default`

### Port Forwarding
```bash
# SERVER-level (shared, 15min timeout)
kubectl port-forward -n kyuubi svc/kyuubi-dbt-shared 10009:10009

# USER-level (individual, 30s timeout)  
kubectl port-forward -n kyuubi svc/kyuubi-dbt 10010:10009
```

## Timeout Behavior

### USER-level (`kyuubi-dbt`)
- **Session timeout**: 30 seconds
- **Use case**: Individual development, quick queries
- **Behavior**: Spark driver + executors terminate 30s after last activity

### SERVER-level (`kyuubi-dbt-shared`)
- **Session timeout**: 15 minutes
- **Use case**: Shared workloads, production queries
- **Behavior**: Spark engines stay alive for 15 minutes of inactivity

### Executor-level Timeouts
- **Idle executors**: Removed after 60 seconds
- **Cached executors**: Kept for 30 minutes (1800s)

## Troubleshooting Commands

### Check Pod Status
```bash
kubectl get pods -n kyuubi -o wide
kubectl describe pod <pod-name> -n kyuubi
kubectl logs <pod-name> -n kyuubi
```

### Check Spark Applications
```bash
kubectl get pods -n kyuubi | grep spark
kubectl logs <spark-driver-pod> -n kyuubi
```

### Test Connectivity
```bash
# Test JDBC connection
beeline -u "jdbc:hive2://localhost:10009/default" -e "SHOW TABLES;"

# Test with DataGrip
# Host: localhost
# Port: 10009 (shared) or 10010 (user-level)
# Database: default
# Authentication: No auth
```

## Performance Tuning

### Resource Allocation
- **Driver**: 5GB memory + 1GB overhead
- **Executors**: 12GB memory, 2 cores each
- **Dynamic scaling**: 0-9 executors based on workload

### Minikube Configuration
```bash
minikube start --cpus=12 --memory=24576 --disk-size=50g
```

## Build and Deploy Process

### 1. Build Images
```bash
# Set Minikube Docker environment
eval $(minikube docker-env)

# Build Kyuubi server image
docker build -t kyuubi-server:1.10.0 -f docker/kyuubi-server/Dockerfile .

# Build Spark engine image
docker build -t spark-engine-iceberg:1.5.0 -f docker/spark-engine-iceberg/Dockerfile .
```

### 2. Deploy with FluxCD
```bash
# Apply FluxCD source and kustomization
kubectl apply -f infrastructure/flux-system/sources/
kubectl apply -f infrastructure/flux-system/kyuubi-kustomization.yaml

# Or apply directly
kubectl apply -k infrastructure/apps/kyuubi/overlays/minikube/
```

## Success Indicators

### Healthy Deployment
- All Kyuubi pods in `Running` state
- Successful JDBC connections with <50ms ping
- Spark driver/executor pods launch on query execution
- Pods terminate according to timeout settings

### Working Features
- ✅ Dynamic executor allocation
- ✅ Hive Metastore integration
- ✅ Iceberg table support
- ✅ Multi-user isolation (USER-level)
- ✅ Shared resources (SERVER-level)
- ✅ Automatic cleanup on idle timeout

## Common Pitfalls

1. **Missing JAR in Spark image**: Always include Kyuubi engine JAR in Spark container
2. **Frontend binding**: Always set `KYUUBI_FRONTEND_BIND_HOST=0.0.0.0`
3. **Permission issues**: Ensure proper ownership and permissions for work directories
4. **Resource limits**: Ensure sufficient CPU/memory for Minikube cluster
5. **Image pull policy**: Use `Never` for local Minikube images
6. **Service account**: Ensure RBAC permissions for Spark pod creation

## Future Improvements

- [ ] Add persistent storage for Spark event logs
- [ ] Implement proper authentication (LDAP/Kerberos)
- [ ] Add monitoring with Prometheus/Grafana
- [ ] Configure S3-compatible storage for Iceberg tables
- [ ] Add resource quotas and limits
- [ ] Implement backup/restore procedures 