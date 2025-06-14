FROM apache/hive:3.1.3

ENV HIVE_HOME=/opt/hive \
    SERVICE_NAME=hive-metastore \
    HIVE_METASTORE_PORT=9083 \
    MYSQL_USER=hive \
    MYSQL_PASSWORD=hivepassword \
    MYSQL_DATABASE=metastore

USER root

# 📥 Install curl and default-mysql-client (important!)
RUN apt-get update && apt-get install -y curl default-mysql-client

# 📥 Download JDBC driver
RUN curl -L -A "Mozilla/5.0" https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.0.33/mysql-connector-j-8.0.33.jar -o /opt/hive/lib/mysql-connector-j-8.0.33.jar

# 📄 Copy configs and entrypoint
COPY configs/hive-site.xml ${HIVE_HOME}/conf/hive-site.xml
COPY entrypoint.sh /opt/entrypoint.sh

RUN chmod +x /opt/entrypoint.sh

EXPOSE 9083

ENTRYPOINT ["/opt/entrypoint.sh"] 