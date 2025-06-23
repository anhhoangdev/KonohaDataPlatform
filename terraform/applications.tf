# Application overlay paths - organized by dependency layers
locals {
  # Phase 1: Infrastructure and Storage Layer
  infrastructure_apps = {
    ingress        = "${path.module}/../infrastructure/apps/ingress-nginx/overlays/minikube"
    postgres_cdc   = "${path.module}/../infrastructure/apps/postgres-cdc"
  }
  
  # Phase 2: Database and Storage Services (foundation layer)
  foundation_apps = {
    mariadb        = "${path.module}/../infrastructure/apps/mariadb/base"
    minio          = "${path.module}/../infrastructure/apps/minio/base"
  }
  
  # Phase 3: Data Platform Services (depend on databases/storage)
  platform_apps = {
    kafka          = "${path.module}/../infrastructure/apps/kafka/base"
    hive_metastore = "${path.module}/../infrastructure/apps/hive-metastore/base"
  }
  
  # Phase 4: Compute and Analytics Services (depend on data platform)
  analytics_apps = {
    kyuubi         = "${path.module}/../infrastructure/apps/kyuubi"
    trino          = "${path.module}/../infrastructure/apps/trino/base"
  }
  
  # Phase 5: Application and Visualization Services
  application_apps = {
    airflow        = "${path.module}/../infrastructure/apps/airflow/base"
    metabase       = "${path.module}/../infrastructure/apps/metabase/base"
    grafana        = "${path.module}/../infrastructure/apps/grafana/base"
    keycloak       = "${path.module}/../infrastructure/apps/keycloak/base"
  }
}

# Apply the main vault-auth.yaml (outside overlays) for kyuubi namespace
resource "kubectl_manifest" "main_vault_auth" {
  yaml_body = file("${path.module}/../infrastructure/apps/vault-auth.yaml")
  
  depends_on = [
    helm_release.vault_secrets_operator,
    kubernetes_service_account.kyuubi
  ]
}

# PHASE 1: Infrastructure Services
data "kustomization_build" "infrastructure_apps" {
  for_each = local.infrastructure_apps
  path     = each.value
}

locals {
  infrastructure_manifest_map = merge([
    for name, build in data.kustomization_build.infrastructure_apps : {
      for idx, m in build.manifests : "${name}-${idx}" => m
    }
  ]...)
}

resource "kubectl_manifest" "infrastructure_apps" {
  for_each  = local.infrastructure_manifest_map
  yaml_body = each.value
  
  depends_on = [
    kubectl_manifest.main_vault_auth
  ]
}

# PHASE 2: Foundation Services (MariaDB, MinIO)
data "kustomization_build" "foundation_apps" {
  for_each = local.foundation_apps
  path     = each.value
}

locals {
  foundation_manifest_map = merge([
    for name, build in data.kustomization_build.foundation_apps : {
      for idx, m in build.manifests : "${name}-${idx}" => m
    }
  ]...)
}

resource "kubectl_manifest" "foundation_apps" {
  for_each  = local.foundation_manifest_map
  yaml_body = each.value
  
  depends_on = [
    kubectl_manifest.infrastructure_apps
  ]
}

# Wait for foundation services to be ready (MariaDB & MinIO)
resource "null_resource" "wait_for_foundation" {
  depends_on = [kubectl_manifest.foundation_apps]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      kubectl rollout status deployment/mariadb -n kyuubi --timeout=300s
      kubectl rollout status deployment/minio   -n kyuubi --timeout=300s
    EOT
    interpreter = ["bash", "-c"]
  }
}

# Wait for Vault Secrets Operator CRDs to be fully served
resource "null_resource" "wait_for_vso_crds" {
  provisioner "local-exec" {
    command = <<EOT
      set -e
      echo "Waiting for Vault Secrets Operator CRDs to be established..."
      kubectl wait crd/vaultauths.secrets.hashicorp.com --for=condition=Established --timeout=120s
      kubectl wait crd/vaultstaticsecrets.secrets.hashicorp.com --for=condition=Established --timeout=120s
    EOT
    interpreter=["bash","-c"]
  }
  depends_on=[helm_release.vault_secrets_operator]
}

# PHASE 3: Data Platform Services (Kafka, Hive Metastore)
data "kustomization_build" "platform_apps" {
  for_each = local.platform_apps
  path     = each.value
}

locals {
  platform_manifest_map = merge([
    for name, build in data.kustomization_build.platform_apps : {
      for idx, m in build.manifests : "${name}-${idx}" => m
    }
  ]...)
}

resource "kubectl_manifest" "platform_apps" {
  for_each  = local.platform_manifest_map
  yaml_body = each.value
  
  depends_on = [
    null_resource.wait_for_foundation
  ]
}

# Create kafka vault-auth after kafka namespace is created
resource "kubectl_manifest" "kafka_vault_auth" {
  yaml_body = file("${path.module}/../infrastructure/apps/kafka/base/vault-auth.yaml")
  
  depends_on = [
    null_resource.wait_for_vso_crds,
    kubectl_manifest.platform_apps  # This creates kafka namespace
  ]
}

# Wait for platform services to be ready (Kafka & Hive)
resource "null_resource" "wait_for_platform" {
  depends_on = [kubectl_manifest.platform_apps, kubectl_manifest.kafka_vault_auth]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      kubectl rollout status statefulset/kafka        -n kafka      --timeout=600s || true
      kubectl rollout status deployment/hive-metastore -n kyuubi    --timeout=400s
    EOT
    interpreter = ["bash", "-c"]
  }
}

# PHASE 4: Analytics Services (Kyuubi, Trino)
data "kustomization_build" "analytics_apps" {
  for_each = local.analytics_apps
  path     = each.value
}

locals {
  analytics_manifest_map = merge([
    for name, build in data.kustomization_build.analytics_apps : {
      for idx, m in build.manifests : "${name}-${idx}" => m
    }
  ]...)
}

resource "kubectl_manifest" "analytics_apps" {
  for_each  = local.analytics_manifest_map
  yaml_body = each.value
  
  depends_on = [
    null_resource.wait_for_platform
  ]
}

# Create trino vault-auth after trino namespace is created
resource "kubectl_manifest" "trino_vault_auth" {
  yaml_body = file("${path.module}/../infrastructure/apps/trino/base/vault-auth.yaml")
  
  depends_on = [
    null_resource.wait_for_vso_crds,
    kubectl_manifest.analytics_apps  # This creates trino namespace
  ]
}

# Wait for analytics services to be ready (Kyuubi & Trino)
resource "null_resource" "wait_for_analytics" {
  depends_on = [kubectl_manifest.analytics_apps, kubectl_manifest.trino_vault_auth]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      kubectl rollout status deployment/kyuubi-dbt          -n kyuubi --timeout=400s
      kubectl rollout status deployment/kyuubi-dbt-shared   -n kyuubi --timeout=400s
      kubectl rollout status deployment/trino               -n trino  --timeout=400s || true
    EOT
    interpreter = ["bash", "-c"]
  }
}

# PHASE 5a: Create Application Namespaces ONLY (no deployments yet)
data "kustomization_build" "application_namespaces" {
  for_each = local.application_apps
  path     = each.value
}

locals {
  # Filter to only namespace resources from application manifests
  application_namespace_manifests = merge([
    for name, build in data.kustomization_build.application_namespaces : {
      for idx, m in build.manifests : "${name}-ns-${idx}" => m
      if contains(split("/", try(m.kind, "")), "Namespace")
    }
  ]...)
}

resource "kubectl_manifest" "application_namespaces" {
  for_each  = local.application_namespace_manifests
  yaml_body = each.value
  
  depends_on = [
    null_resource.wait_for_analytics
  ]
}

# PHASE 5b: Create vault-auth resources immediately after namespaces exist
resource "kubectl_manifest" "airflow_vault_auth" {
  yaml_body = file("${path.module}/../infrastructure/apps/airflow/base/vault-auth.yaml")
  
  depends_on = [
    null_resource.wait_for_vso_crds,
    kubectl_manifest.application_namespaces  # Wait for namespaces to be created
  ]
}

resource "kubectl_manifest" "keycloak_vault_auth" {
  yaml_body = file("${path.module}/../infrastructure/apps/keycloak/base/vault-auth.yaml")
  
  depends_on = [
    null_resource.wait_for_vso_crds,
    kubectl_manifest.application_namespaces  # Wait for namespaces to be created
  ]
}

resource "kubectl_manifest" "metabase_vault_auth" {
  yaml_body = file("${path.module}/../infrastructure/apps/metabase/base/vault-auth.yaml")
  
  depends_on = [
    null_resource.wait_for_vso_crds,
    kubectl_manifest.application_namespaces  # Wait for namespaces to be created
  ]
}

# Wait for vault secrets to be ready
resource "null_resource" "wait_for_vault_secrets" {
  depends_on = [
    kubectl_manifest.airflow_vault_auth,
    kubectl_manifest.keycloak_vault_auth,
    kubectl_manifest.metabase_vault_auth
  ]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      echo "Waiting for vault secrets to be created..."
      
      # Wait for metabase secret specifically
      for i in $(seq 1 60); do
        if kubectl get secret metabase-secrets -n metabase >/dev/null 2>&1; then
          echo "metabase-secrets created successfully"
          break
        fi
        if [ $i -eq 60 ]; then
          echo "Timeout waiting for metabase-secrets"
          exit 1
        fi
        echo "Waiting for metabase-secrets... ($i/60)"
        sleep 5
      done
    EOT
    interpreter = ["bash", "-c"]
  }
}

# PHASE 5c: Application Services (now deployments with secrets available)
locals {
  # Filter out namespace resources, only keep non-namespace manifests
  application_manifest_map = merge([
    for name, build in data.kustomization_build.application_namespaces : {
      for idx, m in build.manifests : "${name}-${idx}" => m
      if !contains(split("/", try(m.kind, "")), "Namespace")
    }
  ]...)
}

resource "kubectl_manifest" "application_apps" {
  for_each  = local.application_manifest_map
  yaml_body = each.value
  
  depends_on = [
    null_resource.wait_for_vault_secrets  # Ensure secrets exist before deploying apps
  ]
} 