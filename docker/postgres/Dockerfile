FROM postgres:15

COPY postgres/configs/init.sql /docker-entrypoint-initdb.d/

# Set PostgreSQL configuration for CDC via command line
CMD ["postgres", "-c", "wal_level=logical", "-c", "max_wal_senders=4", "-c", "max_replication_slots=4", "-c", "shared_preload_libraries=pg_stat_statements"]
