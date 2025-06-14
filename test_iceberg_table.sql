-- Test script to create Iceberg table and verify integration
-- This will test: Kyuubi -> Spark -> Hive Metastore -> MinIO (S3) storage

-- First, test basic Iceberg functionality without S3A
-- Create a simple database without S3A location
CREATE DATABASE IF NOT EXISTS test_db_local;

-- Use the test database
USE test_db_local;

-- Create a basic Iceberg table (stored locally first)
CREATE TABLE IF NOT EXISTS user_activity_local (
    user_id BIGINT,
    username STRING,
    activity_type STRING,
    timestamp TIMESTAMP,
    metadata MAP<STRING, STRING>
) USING ICEBERG
TBLPROPERTIES (
    'format-version' = '2',
    'write.target-file-size-bytes' = '134217728'
);

-- Insert some test data
INSERT INTO user_activity_local VALUES
(1, 'alice', 'login', TIMESTAMP '2025-06-15 10:00:00', MAP('ip', '192.168.1.1', 'device', 'laptop')),
(2, 'bob', 'view_page', TIMESTAMP '2025-06-15 10:05:00', MAP('page', '/dashboard', 'referrer', 'direct'));

-- Query the data to verify basic Iceberg works
SELECT 
    user_id,
    username,
    activity_type,
    timestamp,
    metadata['ip'] as ip_address,
    metadata['device'] as device_type
FROM user_activity_local
ORDER BY timestamp;

-- Show table properties to verify Iceberg format
DESCRIBE EXTENDED user_activity_local;

-- Now test with S3A storage (this requires the S3A libraries)
-- Create a database with S3A location
CREATE DATABASE IF NOT EXISTS test_db
LOCATION 's3a://test-bucket/test_db.db';

-- Use the S3A database
USE test_db;

-- Create an Iceberg table with S3A storage
CREATE TABLE IF NOT EXISTS user_activity (
    user_id BIGINT,
    username STRING,
    activity_type STRING,
    timestamp TIMESTAMP,
    metadata MAP<STRING, STRING>
) USING ICEBERG
LOCATION 's3a://test-bucket/user_activity'
TBLPROPERTIES (
    'format-version' = '2',
    'write.target-file-size-bytes' = '134217728'
);

-- Insert test data to S3A table
INSERT INTO user_activity VALUES
(1, 'alice', 'login', TIMESTAMP '2025-06-15 10:00:00', MAP('ip', '192.168.1.1', 'device', 'laptop')),
(2, 'bob', 'view_page', TIMESTAMP '2025-06-15 10:05:00', MAP('page', '/dashboard', 'referrer', 'direct')),
(3, 'charlie', 'purchase', TIMESTAMP '2025-06-15 10:10:00', MAP('amount', '99.99', 'currency', 'USD')),
(4, 'diana', 'logout', TIMESTAMP '2025-06-15 10:15:00', MAP('session_duration', '900', 'pages_viewed', '5'));

-- Query the S3A data
SELECT 
    user_id,
    username,
    activity_type,
    timestamp,
    metadata['ip'] as ip_address,
    metadata['device'] as device_type
FROM user_activity
ORDER BY timestamp;

-- Show table location to verify S3 storage
SHOW CREATE TABLE user_activity;

-- Show all databases to verify creation
SHOW DATABASES;

-- Show all tables in both databases
SHOW TABLES IN test_db_local;
SHOW TABLES IN test_db;

-- Create a partitioned Iceberg table for more advanced testing
CREATE TABLE IF NOT EXISTS sales_data (
    sale_id BIGINT,
    product_name STRING,
    category STRING,
    price DECIMAL(10,2),
    quantity INT,
    sale_date DATE,
    customer_id BIGINT
) USING ICEBERG
PARTITIONED BY (category, sale_date)
LOCATION 's3a://test-bucket/sales_data'
TBLPROPERTIES (
    'format-version' = '2',
    'write.target-file-size-bytes' = '134217728'
);

-- Insert partitioned data
INSERT INTO sales_data VALUES
(1001, 'Laptop Pro', 'electronics', 1299.99, 1, DATE '2025-06-15', 101),
(1002, 'Coffee Mug', 'home', 15.99, 2, DATE '2025-06-15', 102),
(1003, 'Running Shoes', 'sports', 89.99, 1, DATE '2025-06-15', 103),
(1004, 'Smartphone', 'electronics', 699.99, 1, DATE '2025-06-14', 104),
(1005, 'Yoga Mat', 'sports', 29.99, 1, DATE '2025-06-14', 105);

-- Query partitioned data
SELECT 
    category,
    sale_date,
    COUNT(*) as num_sales,
    SUM(price * quantity) as total_revenue
FROM sales_data
GROUP BY category, sale_date
ORDER BY sale_date DESC, category;

-- Show partitions
SHOW PARTITIONS sales_data;

-- Test time travel capabilities (Iceberg feature)
-- This will show the table state after the first insert
SELECT COUNT(*) as record_count FROM user_activity; 