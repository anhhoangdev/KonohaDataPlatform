# Kyuubi Troubleshooting Checklist

## Quick Diagnostic Commands

### 1. Check Overall Health
```bash
# Check all pods in kyuubi namespace
kubectl get pods -n kyuubi -o wide

# Check services
kubectl get svc -n kyuubi

# Check recent events
kubectl get events -n kyuubi --sort-by='.lastTimestamp'
```

### 2. Check Specific Pod Issues
```bash
# Describe problematic pod
kubectl describe pod <pod-name> -n kyuubi

# Check logs
kubectl logs <pod-name> -n kyuubi --tail=100

# Check previous container logs (if restarted)
kubectl logs <pod-name> -n kyuubi --previous
```

## Common Issues & Solutions

### ❌ Connection Refused (Port Forward)
**Symptoms**: `Connection refused` when connecting via JDBC
**Check**: 
```bash
# Verify frontend binding
kubectl logs <kyuubi-pod> -n kyuubi | grep -i "frontend\|bind"
```
**Solution**: Add `KYUUBI_FRONTEND_BIND_HOST=0.0.0.0` to deployment

### ❌ Spark Engine Fails to Start
**Symptoms**: `NoSuchFileException` or `AccessDeniedException` in Spark driver logs
**Check**:
```bash
# Check Spark driver pod logs
kubectl logs <spark-driver-pod> -n kyuubi

# Verify JAR exists in Spark image
kubectl exec <spark-driver-pod> -n kyuubi -- ls -la /opt/spark/jars/ | grep kyuubi
```
**Solution**: Ensure Kyuubi engine JAR is in Spark image at `/opt/spark/jars/`

### ❌ Permission Denied in Work Directory
**Symptoms**: `AccessDeniedException` writing to `/opt/spark/work-dir/`
**Check**:
```bash
# Check work directory permissions
kubectl exec <spark-driver-pod> -n kyuubi -- ls -la /opt/spark/work-dir/
```
**Solution**: Set proper ownership in Dockerfile: `chown -R 1000:1000 /opt/spark/work-dir`

### ❌ Pods Stuck in Pending
**Symptoms**: Kyuubi or Spark pods stuck in `Pending` state
**Check**:
```bash
# Check resource availability
kubectl describe node minikube

# Check pod resource requests
kubectl describe pod <pending-pod> -n kyuubi
```
**Solution**: Increase Minikube resources or reduce pod resource requests

### ❌ RBAC Permission Errors
**Symptoms**: `Forbidden` errors when creating Spark pods
**Check**:
```bash
# Verify service account
kubectl get sa kyuubi-sa -n kyuubi

# Check cluster role binding
kubectl describe clusterrolebinding kyuubi-spark-binding
```
**Solution**: Ensure proper RBAC configuration with pod creation permissions

### ❌ Image Pull Errors
**Symptoms**: `ImagePullBackOff` or `ErrImagePull`
**Check**:
```bash
# Check image pull policy
kubectl describe pod <pod-name> -n kyuubi | grep -A5 "Image:"

# Verify images exist in Minikube
eval $(minikube docker-env) && docker images | grep kyuubi
```
**Solution**: Set `imagePullPolicy: Never` for local Minikube images

## Health Check Script

Create this script to quickly verify Kyuubi health:

```bash
#!/bin/bash
# kyuubi-health-check.sh

echo "=== Kyuubi Health Check ==="

echo "1. Checking pods..."
kubectl get pods -n kyuubi

echo -e "\n2. Checking services..."
kubectl get svc -n kyuubi

echo -e "\n3. Checking recent events..."
kubectl get events -n kyuubi --sort-by='.lastTimestamp' | tail -10

echo -e "\n4. Testing connectivity..."
timeout 5 bash -c "</dev/tcp/localhost/10009" && echo "✅ Port 10009 accessible" || echo "❌ Port 10009 not accessible"
timeout 5 bash -c "</dev/tcp/localhost/10010" && echo "✅ Port 10010 accessible" || echo "❌ Port 10010 not accessible"

echo -e "\n5. Checking Spark applications..."
kubectl get pods -n kyuubi | grep spark | wc -l | xargs echo "Active Spark pods:"
```

## Log Analysis Patterns

### Look for these patterns in logs:

#### Kyuubi Server Logs
```bash
# Successful startup
kubectl logs <kyuubi-pod> -n kyuubi | grep -i "started\|ready\|listening"

# Connection issues
kubectl logs <kyuubi-pod> -n kyuubi | grep -i "connection\|bind\|address"

# Engine creation
kubectl logs <kyuubi-pod> -n kyuubi | grep -i "engine\|spark"
```

#### Spark Driver Logs
```bash
# JAR loading issues
kubectl logs <spark-driver-pod> -n kyuubi | grep -i "jar\|class\|resource"

# Permission issues
kubectl logs <spark-driver-pod> -n kyuubi | grep -i "permission\|access\|denied"

# Kubernetes integration
kubectl logs <spark-driver-pod> -n kyuubi | grep -i "kubernetes\|k8s"
```

## Performance Monitoring

### Resource Usage
```bash
# Check resource usage
kubectl top pods -n kyuubi

# Check node resources
kubectl top node minikube

# Check persistent volumes
kubectl get pv,pvc -n kyuubi
```

### Connection Testing
```bash
# Test JDBC connection with beeline
beeline -u "jdbc:hive2://localhost:10009/default" -e "SELECT 1;"

# Test with timeout
timeout 10 beeline -u "jdbc:hive2://localhost:10009/default" -e "SHOW DATABASES;"
```

## Emergency Recovery

### Restart All Kyuubi Services
```bash
# Restart deployments
kubectl rollout restart deployment/kyuubi-dbt -n kyuubi
kubectl rollout restart deployment/kyuubi-dbt-shared -n kyuubi

# Wait for rollout
kubectl rollout status deployment/kyuubi-dbt -n kyuubi
kubectl rollout status deployment/kyuubi-dbt-shared -n kyuubi
```

### Clean Up Stuck Spark Pods
```bash
# Force delete stuck Spark pods
kubectl get pods -n kyuubi | grep spark | awk '{print $1}' | xargs kubectl delete pod --force --grace-period=0 -n kyuubi

# Clean up completed pods
kubectl delete pods -n kyuubi --field-selector=status.phase=Succeeded
```

### Reset Minikube (Last Resort)
```bash
# Stop and delete cluster
minikube stop
minikube delete

# Restart with proper resources
minikube start --cpus=12 --memory=24576 --disk-size=50g

# Rebuild images
eval $(minikube docker-env)
# ... rebuild your images ...

# Redeploy
kubectl apply -k infrastructure/apps/kyuubi/overlays/minikube/
```

## Monitoring Commands

### Continuous Monitoring
```bash
# Watch pod status
watch kubectl get pods -n kyuubi

# Follow logs
kubectl logs -f <pod-name> -n kyuubi

# Monitor events
kubectl get events -n kyuubi -w
```

### Resource Monitoring
```bash
# Monitor resource usage
watch kubectl top pods -n kyuubi

# Check cluster resources
kubectl describe node minikube | grep -A5 "Allocated resources"
``` 