{{
  config(
    materialized='table',
    file_format='iceberg',
    location_root=var('warehouse_path') ~ '/staging',
    tags=['staging', 'orders'],
    on_schema_change='fail'
  )
}}

-- Staging table for orders with dummy data
-- This demonstrates more complex CTE transformations

WITH raw_orders AS (
    SELECT 1 as order_id, 1 as user_id, 100.50 as amount, '2024-01-15' as order_date, 'completed' as status
    UNION ALL
    SELECT 2, 2, 250.75, '2024-01-16', 'completed'
    UNION ALL
    SELECT 3, 1, 75.25, '2024-01-17', 'pending'
    UNION ALL
    SELECT 4, 3, 400.00, '2024-01-18', 'completed'
    UNION ALL
    SELECT 5, 4, 150.30, '2024-01-19', 'completed'
    UNION ALL
    SELECT 6, 2, 320.80, '2024-01-20', 'cancelled'
    UNION ALL
    SELECT 7, 5, 89.99, '2024-01-21', 'completed'
    UNION ALL
    SELECT 8, 1, 199.95, '2024-01-22', 'completed'
),

transformed_orders AS (
    SELECT 
        order_id,
        user_id,
        amount,
        CAST(order_date AS DATE) as order_date,
        UPPER(TRIM(status)) as status,
        current_timestamp() as created_at,
        -- Add derived fields
        CASE 
            WHEN amount < 100 THEN 'Small'
            WHEN amount >= 100 AND amount < 300 THEN 'Medium'
            ELSE 'Large'
        END as order_size,
        -- Extract date components
        YEAR(CAST(order_date AS DATE)) as order_year,
        MONTH(CAST(order_date AS DATE)) as order_month,
        DAYOFWEEK(CAST(order_date AS DATE)) as order_day_of_week
    FROM raw_orders
)

SELECT * FROM transformed_orders 