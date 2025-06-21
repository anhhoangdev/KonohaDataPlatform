# DBT inside Kyuubi 🐉

DBT jobs run *inside* Kyuubi pods (two flavours: USER and SERVER share-level). The dbt image `dbt-spark:latest` is bundled into those pods, so no separate deployment is needed.

## Running a model locally against Kyuubi
```bash
export Kyuubi_URL=jdbc:hive2://localhost:10010/default
cd dbt
source env/bin/activate
DBT_KYUUBI_URL=$Kyuubi_URL dbt run
```

## Secrets
DBT profiles are generated at runtime from Vault secrets mounted to `/etc/dbt/credentials.yml` inside the pod. 