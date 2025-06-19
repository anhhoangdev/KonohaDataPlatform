#!/bin/bash
set -e

echo "💬 Substituting environment variables in config files..."
envsubst < ${HIVE_CONF_DIR}/hive-site.xml.template > ${HIVE_CONF_DIR}/hive-site.xml
envsubst < ${HADOOP_CONF_DIR}/core-site.xml.template > ${HADOOP_CONF_DIR}/core-site.xml

echo "💬 Waiting for MariaDB to be ready..."
sleep 15

echo "💬 Checking if Hive schema is already there…"

TABLE_EXISTS=$(mysql -h "${MYSQL_HOST}" -P "${MYSQL_PORT}" -u"${MYSQL_USER}" -p"${MYSQL_PASSWORD}" \
               -D"${MYSQL_DATABASE}" -N -s -e "SHOW TABLES LIKE 'CTLGS';" 2>/dev/null || echo "")

if [ -z "$TABLE_EXISTS" ]; then
  echo "📦 Schema not found – running schematool -initSchema"
  /opt/hive/bin/schematool -dbType mysql -initSchema --verbose
else
  echo "✅ Schema already present – skipping schematool"
fi

# ---------- start metastore in foreground -------------------------
echo "🚀 Starting Hive Metastore Thrift server…"
exec hive --service metastore 