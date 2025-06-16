# 🔍 Troubleshooting

### Common Issues

1. **Minikube not starting**
   ```bash
   minikube delete
   minikube start --driver=docker --cpus=4 --memory=8192
   ```

2. **Vault token errors**
   ```bash
   # Ensure token is set
   export TF_VAR_vault_token="root"
   # Or check terraform.tfvars has vault_token = "root"
   ```

3. **FluxCD not syncing**
   ```bash
   # Check FluxCD status
   flux check
   flux get sources git
   
   # Force reconciliation
   flux reconcile source git flux-system
   ```

4. **Pods not starting**
   ```bash
   # Check pod logs
   kubectl logs -n <namespace> <pod-name>
   
   # Check events
   kubectl get events -n <namespace> --sort-by='.lastTimestamp'
   ```

### Useful Commands

```bash
# Get all resources
kubectl get all --all-namespaces

# Port forward services
kubectl port-forward -n vault-system svc/vault 8200:8200
kubectl port-forward -n kyuubi svc/kyuubi 10009:10009

# Check resource usage
kubectl top nodes
kubectl top pods --all-namespaces

# Clean up
./deploy-vault.sh cleanup
minikube delete
```
