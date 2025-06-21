# Use an official OpenJDK runtime as a parent image
FROM eclipse-temurin:8-jre-focal

# Set environment variables for Hive
ENV HIVE_HOME /opt/hive
ENV HIVE_VERSION 3.1.3
ENV HADOOP_HOME /opt/hadoop
ENV HADOOP_VERSION 3.3.4
ENV PATH $HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:$PATH
ENV HIVE_CONF_DIR $HIVE_HOME/conf
ENV HADOOP_CONF_DIR $HADOOP_HOME/etc/hadoop

# Create directories and user
RUN mkdir -p $HIVE_HOME && \
    mkdir -p $HADOOP_HOME && \
    groupadd -r hive && \
    useradd -r -g hive -d $HIVE_HOME -s /sbin/nologin hive

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends tini gettext-base curl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Copy pre-downloaded files from the build context
COPY --chown=hive:hive downloads/apache-hive-${HIVE_VERSION}-bin.tar.gz /tmp/
COPY --chown=hive:hive downloads/hadoop-${HADOOP_VERSION}.tar.gz /tmp/

# Extract Hive and Hadoop
RUN tar -xzvf /tmp/apache-hive-${HIVE_VERSION}-bin.tar.gz -C /opt && \
    mv /opt/apache-hive-${HIVE_VERSION}-bin/* $HIVE_HOME && \
    tar -xzvf /tmp/hadoop-${HADOOP_VERSION}.tar.gz -C /opt && \
    mv /opt/hadoop-${HADOOP_VERSION}/* $HADOOP_HOME && \
    rm /tmp/*.tar.gz

# 📥 Download MySQL JDBC driver
RUN curl -L -A "Mozilla/5.0" https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.0.33/mysql-connector-j-8.0.33.jar -o $HIVE_HOME/lib/mysql-connector-j-8.0.33.jar

# Copy required JARs from downloads folder
COPY --chown=hive:hive downloads/postgresql-42.2.24.jar $HIVE_HOME/lib/
COPY --chown=hive:hive downloads/aws-java-sdk-bundle-1.11.901.jar $HIVE_HOME/lib/
COPY --chown=hive:hive downloads/hadoop-aws-3.3.4.jar $HIVE_HOME/lib/
COPY --chown=hive:hive downloads/iceberg-hive-metastore-1.4.2.jar $HIVE_HOME/lib/

# Copy configuration and entrypoint
COPY --chown=hive:hive hive-metastore/configs/hive-site.xml $HIVE_CONF_DIR/hive-site.xml.template
COPY --chown=hive:hive hive-metastore/configs/core-site.xml $HADOOP_CONF_DIR/core-site.xml.template
COPY --chown=hive:hive hive-metastore/entrypoint.sh /
RUN chmod +x /entrypoint.sh

# Set ownership
RUN chown -R hive:hive $HIVE_HOME && \
    chown -R hive:hive $HADOOP_HOME

# Set user
USER hive

# Expose Metastore port
EXPOSE 9083

# Set entrypoint
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
CMD ["run-metastore"]