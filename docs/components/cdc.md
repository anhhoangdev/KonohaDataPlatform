# Change Data Capture (CDC) – Sharingan Layer 👁️

We capture source DB changes via **Debezium Postgres connector**, stream them through Kafka, and write them to Iceberg using the Iceberg Sink.

## Connector lifecycle
1. Source DB (`postgres-cdc` pod) produces logical replication.
2. Debezium captures WAL → Kafka Topic `public-orders`.
3. Iceberg sink writes into `s3a://warehouse/cdc.db/public_orders/` partitioned by `__source_ts`.

### Deploy / update a connector
Upload JSON to Kafka Connect REST:
```bash
curl -X PUT localhost:8083/connectors/orders-cdc/config \
     -H 'Content-Type: application/json' \
     -d @orders-connector.json
```

### Tips
* Use `key.converter=org.apache.kafka.connect.storage.StringConverter` for simple PK streams.
* Set `transforms=unwrap` to flatten envelope before Iceberg sink. 