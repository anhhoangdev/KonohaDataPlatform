output "vault_address" {
  description = "Vault server address"
  value       = "http://localhost:8200"
}

output "vault_ui_port_forward" {
  description = "Command to port-forward Vault UI"
  value       = "kubectl port-forward -n ${local.vault_namespace} svc/vault 8200:8200"
}

output "kyuubi_server_endpoints" {
  description = "Kyuubi server JDBC endpoints"
  value = {
    server_level = "jdbc:hive2://localhost:10009/default"
    user_level   = "jdbc:hive2://localhost:10010/default"
  }
}

output "kyuubi_port_forward_commands" {
  description = "Commands to port-forward Kyuubi services"
  value = {
    server_level = "kubectl port-forward -n ${local.namespace} svc/kyuubi-dbt-shared 10009:10009"
    user_level   = "kubectl port-forward -n ${local.namespace} svc/kyuubi-dbt 10010:10009"
  }
}

output "flux_status_commands" {
  description = "Commands to check FluxCD status"
  value = {
    kustomizations = "kubectl get kustomizations -n ${local.flux_namespace}"
    git_repository = "kubectl get gitrepository -n ${local.flux_namespace}"
    sources        = "kubectl get sources -A"
  }
}

output "vault_secrets_path" {
  description = "Vault secrets paths"
  value = {
    database   = "${vault_mount.kyuubi.path}/data/database"
    spark      = "${vault_mount.kyuubi.path}/data/spark"
    kyuubi     = "${vault_mount.kyuubi.path}/data/kyuubi-server"
    aws        = "${vault_mount.kyuubi.path}/data/aws"
    monitoring = var.enable_monitoring ? "${vault_mount.kyuubi.path}/data/monitoring" : "disabled"
  }
}

output "kubernetes_namespaces" {
  description = "Created Kubernetes namespaces"
  value = {
    vault      = local.vault_namespace
    flux       = local.flux_namespace
    kyuubi     = local.namespace
    monitoring = var.enable_monitoring ? "monitoring" : "disabled"
  }
}

output "monitoring_endpoints" {
  description = "Monitoring endpoints (if enabled)"
  value = var.enable_monitoring ? {
    grafana_port_forward    = "kubectl port-forward -n monitoring svc/grafana 3000:80"
    prometheus_port_forward = "kubectl port-forward -n monitoring svc/prometheus-server 9090:80"
  } : {}
}

output "useful_commands" {
  description = "Useful commands for managing the platform"
  value = {
    # Vault commands
    vault_login = "export VAULT_ADDR=http://localhost:8200 && vault auth -method=userpass username=admin"
    vault_ui    = "open http://localhost:8200/ui"
    
    # Kubernetes commands
    get_all_pods     = "kubectl get pods --all-namespaces"
    kyuubi_pods      = "kubectl get pods -n ${local.namespace}"
    kyuubi_logs      = "kubectl logs -f deployment/kyuubi-dbt -n ${local.namespace}"
    spark_pods       = "kubectl get pods -n ${local.namespace} | grep spark"
    
    # FluxCD commands
    flux_reconcile   = "flux reconcile kustomization kyuubi -n ${local.flux_namespace}"
    flux_logs        = "flux logs -n ${local.flux_namespace}"
    flux_get_sources = "flux get sources all -A"
    
    # Troubleshooting
    describe_kyuubi_pod = "kubectl describe pod <pod-name> -n ${local.namespace}"
    check_vault_status  = "kubectl exec -n ${local.vault_namespace} vault-0 -- vault status"
  }
}

output "terraform_workspace_info" {
  description = "Terraform workspace information"
  value = {
    workspace = terraform.workspace
    version   = "Terraform ${terraform.version}"
    providers = {
      kubernetes = "~> 2.23"
      helm       = "~> 2.11"
      vault      = "~> 3.20"
      flux       = "~> 1.0"
      github     = "~> 5.0"
    }
  }
}

output "next_steps" {
  description = "Next steps after deployment"
  value = [
    "1. Wait for all pods to be ready: kubectl get pods --all-namespaces",
    "2. Port-forward Vault UI: kubectl port-forward -n ${local.vault_namespace} svc/vault 8200:8200",
    "3. Access Vault UI at: http://localhost:8200/ui",
    "4. Port-forward Kyuubi services using the commands above",
    "5. Connect DataGrip to jdbc:hive2://localhost:10009/default (SERVER-level)",
    "6. Connect DataGrip to jdbc:hive2://localhost:10010/default (USER-level)",
    "7. Check FluxCD status: flux get kustomizations -A",
    "8. Monitor logs: kubectl logs -f deployment/kyuubi-dbt -n ${local.namespace}"
  ]
} 