# Apache Iceberg – Data Lake Layer ❄️

All tables written by Spark (Kyuubi) or Kafka Connect land in Iceberg format stored on MinIO (`s3a://warehouse`).

## Key conventions
* **Namespace = database**  (e.g., `sales.orders`)
* **Table location** automatically `/warehouse/sales.db/orders/` via Hive Metastore.
* Time-travel queries in Trino:
```sql
SELECT * FROM sales.orders FOR TIMESTAMP AS OF NOW() - INTERVAL '1' DAY;
``` 