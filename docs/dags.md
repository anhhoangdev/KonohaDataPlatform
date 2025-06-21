# DAGs in Konoha Data Platform

Directed Acyclic Graphs (DAGs) are the mission scrolls scheduled by the Hokage Mission Board (Airflow). Place your custom DAG python files in the `dag/` folder of the repo; the `sync-dags.sh` helper mounts or syncs them into the `airflow-dag-pvc` persistent volume so scheduler & workers see them instantly.

## Quick Tips
- Use `@task` / TaskFlow API for readability.
- Keep external configs in Vault-backed Kubernetes Secrets and reference via env vars.
- Enable retries + alerts via Grafana/Prometheus integration (`airflow/exporter`). 