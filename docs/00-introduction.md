# Konoha Data Platform – Overview 🏯✨

Welcome to **Konoha Data Platform**, an all-in-one, cloud-native analytics stack that spins up on any vanilla Kubernetes cluster in *under 15 minutes*.

Built on battle-tested open-source projects—Apache Iceberg, Kyuubi, Airflow, Trino, HashiCorp Vault, FluxCD and more—the platform delivers a fully-featured **Lakehouse**, real-time **Streaming**, workflow **Orchestration** and end-to-end **Observability** right on your laptop.

> "Spark-powered compute is our Nine-Tails chakra, Airflow is the Hokage mission board, and Vault seals your secrets. Believe it!"

---

## What Problems Does It Solve?

| Challenge | Traditional Pain | Konoha Solution |
|-----------|-----------------|-----------------|
| Local dev env for big-data | Hours of manual setup; heavyweight VMs | One-liner deploy script on Minikube |
| Secure secret management  | `.env` files scattered everywhere | HashiCorp Vault + Vault-Secrets-Operator |
| Lakehouse table format    | Hive / Parquet chaos | Iceberg with ACID guarantees |
| Interactive & batch SQL   | `spark-submit` boilerplate | Kyuubi JDBC server + DBT integration |
| Reproducible infra        | Click-ops, snowflake clusters | Terraform + FluxCD GitOps |

---

## Core Tenets

1. **Laptop-first experience** – everything, including secrets and object store, runs inside Minikube.
2. **GitOps as the source of truth** – any change to infrastructure or apps flows through Git.
3. **Boring technology choices** – prefer mature OSS projects with vibrant communities.
4. **Extensibility** – add your own UDFs, connectors or dashboards without forking the stack.

---

## Next Steps

* **Deploy now:** head to [01-quick-start](01-quick-start.md).
* **Understand the architecture:** read [architecture/overview](architecture/overview.md).
* **Deep-dive per service:** see [components/](components/).
* **Operate & troubleshoot:** visit [ops/](ops/).

Happy ninja-coding! 🥷 