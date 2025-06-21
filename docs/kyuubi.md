# Apache Kyuubi – Chakra Forge Engine 🐉

> **TL;DR** – Kyuubi provides multi-tenant, REST/JDBC SQL access to our Spark clusters while hiding all Spark boilerplate.  Think of it as "HiveServer2 on steroids" with native Iceberg compatibility and Kubernetes-first deployment.

---

## 1. Deployment Topology

| Pod | Share-Level | Image | Exposed Ports |
|------|------------|-------|---------------|
| `kyuubi-dbt` | **USER** (one Spark application *per user*) | `kyuubi-server:1.10.0` | 10010 (binary) / 10099 (REST) |
| `kyuubi-dbt-shared` | **SERVER** (single Spark application shared by all) | `kyuubi-server:1.10.0` | 10009 (binary) / 10098 (REST) |

Two flavours lets you choose between full isolation (USER) and rapid start-up (SERVER).

Both pods mount the same ConfigMaps & Vault-sourced secrets; only the `engine.share.level` differs.

---

## 2. Image Contents
* **Base**: Apache Kyuubi 1.10.0 binary distribution.
* **Extras**  
  `kyuubi-spark-sql-engine.jar` (built-in)  
  Iceberg runtime 1.4.2  
  AWS / S3 SDK 1.12.x  
  Prometheus JMX exporter (port 4040 on driver pods)

---

## 3. Secrets & Credentials
All secrets are injected by **Vault-Secrets-Operator** into three files:

| Path inside pod | Purpose |
|-----------------|---------|
| `/etc/kyuubi/database.env` | MariaDB creds for Hive Metastore |
| `/etc/kyuubi/minio.env`    | MinIO S3 access & secret keys |
| `/etc/kyuubi/spark.env`    | Spark resource defaults |

`kyuubi.conf` reads them via `${ENV_VAR}` interpolation.

---

## 4. Key Configuration Snippets
```properties
# Iceberg – default catalog
spark.sql.catalog.spark_catalog=org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.spark_catalog.type=hive
spark.sql.catalog.spark_catalog.uri=thrift://hive-metastore:9083
spark.sql.catalog.spark_catalog.warehouse=s3a://warehouse/

# Adaptive execution & dynamic allocation
spark.sql.adaptive.enabled=true
spark.dynamicAllocation.enabled=true
spark.dynamicAllocation.maxExecutors=9
```
Full configs live in `infrastructure/apps/kyuubi/*.yaml` under `kyuubiConf` & `sparkConf`.

---

## 5. Connecting
### Beeline / JDBC
```bash
beeline -u "jdbc:hive2://localhost:10009/default;principal=hive/_HOST@EXAMPLE.COM"
```
Local port-forward:
```bash
kubectl -n kyuubi port-forward svc/kyuubi-dbt-shared 10009:10009
```

### Trino Catalog (external)
```ini
connector.name=iceberg
warehouse=s3a://warehouse
hive.metastore.uri=thrift://hive-metastore:9083
```

---

## 6. Resource Tuning
| Parameter | Default | Comment |
|-----------|---------|---------|
| `spark.executor.memory` | 2 GiB | USER pod can be overriden via Vault secret (`spark_executor_memory`) |
| `spark.sql.shuffle.partitions` | 200 | Set to `cores × 4` for large joins |
| `spark.kubernetes.executor.request.cores` | 1.8 | Keep request < limit (2) |

Update the `kyuubi/spark` secret → `terraform apply` → Flux redeploys pods.

---

## 7. Monitoring
* **Prometheus scrape** annotations on driver pods.  
* **Grafana dashboard**: `grafana/dashboards/kyuubi-spark.json` (import manually).
* **Logs**: `kubectl logs <kyuubi-pod> -c kyuubi`.

---

## 8. Troubleshooting Checklist
| Symptom | Likely Cause | Quick Fix |
|---------|-------------|-----------|
| `ENGINE_TIMEOUT` on `OPEN_SESSION` | Spark image pull / driver slow | Check driver pod events; ensure `spark-engine-iceberg` image loaded into Minikube |
| `Table not found` immediately after creation | HMS cache lag | Run `INVALIDATE METADATA` in Trino or retry after 2 s |
| `S3AEndpointContext` errors | Wrong MinIO creds | Verify `minio.env` secret values |

---

## 9. Useful Commands
```bash
# List active sessions
kubectl exec -n kyuubi deploy/kyuubi-dbt -- bin/kyuubi-ctl list

# Terminate a session
kubectl exec -n kyuubi deploy/kyuubi-dbt -- bin/kyuubi-ctl kill <session-id>

# Spark UI port-forward (driver pod)
kubectl -n kyuubi port-forward pod/<driver-pod> 4040:4040
```

---
*For deeper internals see the official [Kyuubi docs](https://kyuubi.apache.org/docs/latest/). This page focuses on the opinionated setup used in Konoha Data Platform.* 