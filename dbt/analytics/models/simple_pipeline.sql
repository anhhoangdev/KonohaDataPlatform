{{
  config(
    materialized='table',
    file_format='iceberg',
    location_root=var('warehouse_path'),
    tags=['pipeline', 'demo', 'complete_example'],
    on_schema_change='fail',
    description='Complete CTE pipeline demonstrating advanced data transformations with dummy data'
  )
}}

-- Complete CTE pipeline demonstrating advanced data transformations
-- This shows the full power of CTEs with dummy data, joins, window functions, and analytics

WITH raw_users AS (
    -- Dummy users data
    SELECT 1 as user_id, 'Alice Johnson' as full_name, 'alice@example.com' as email, 25 as age, 'Engineering' as department
    UNION ALL
    SELECT 2, 'Bob Smith', 'bob@example.com', 30, 'Marketing'
    UNION ALL  
    SELECT 3, 'Charlie Brown', 'charlie@example.com', 35, 'Sales'
    UNION ALL
    SELECT 4, 'Diana Prince', 'diana@example.com', 28, 'Engineering'
    UNION ALL
    SELECT 5, 'Eve Wilson', 'eve@example.com', 32, 'Marketing'
),

raw_orders AS (
    -- Dummy orders data
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

user_metrics AS (
    -- Advanced aggregations and analytics
    SELECT 
        u.user_id,
        u.full_name,
        u.email,
        u.department,
        u.age,
        CASE 
            WHEN u.age < 30 THEN 'Young Professional'
            WHEN u.age >= 30 AND u.age < 40 THEN 'Mid-Career'
            ELSE 'Senior Professional'
        END as career_stage,
        COUNT(o.order_id) as total_orders,
        COALESCE(SUM(CASE WHEN UPPER(o.status) = 'COMPLETED' THEN o.amount END), 0) as total_completed_revenue,
        COALESCE(SUM(o.amount), 0) as total_revenue,
        COALESCE(AVG(CASE WHEN UPPER(o.status) = 'COMPLETED' THEN o.amount END), 0) as avg_order_value,
        MIN(CAST(o.order_date AS DATE)) as first_order_date,
        MAX(CAST(o.order_date AS DATE)) as last_order_date,
        COUNT(CASE WHEN UPPER(o.status) = 'COMPLETED' THEN 1 END) as completed_orders,
        COUNT(CASE WHEN UPPER(o.status) = 'PENDING' THEN 1 END) as pending_orders,
        COUNT(CASE WHEN UPPER(o.status) = 'CANCELLED' THEN 1 END) as cancelled_orders
    FROM raw_users u
    LEFT JOIN raw_orders o ON u.user_id = o.user_id
    GROUP BY u.user_id, u.full_name, u.email, u.department, u.age
),

final_analytics AS (
    -- Window functions and advanced analytics
    SELECT 
        *,
        -- Rankings
        ROW_NUMBER() OVER (ORDER BY total_completed_revenue DESC) as revenue_rank,
        ROW_NUMBER() OVER (ORDER BY total_orders DESC) as order_count_rank,
        ROW_NUMBER() OVER (PARTITION BY department ORDER BY total_completed_revenue DESC) as dept_revenue_rank,
        
        -- Percentiles
        ROUND(PERCENT_RANK() OVER (ORDER BY total_completed_revenue) * 100, 1) as revenue_percentile,
        
        -- Customer segmentation
        CASE 
            WHEN total_orders = 0 THEN 'No Orders'
            WHEN total_orders = 1 THEN 'New Customer'
            WHEN total_orders <= 3 THEN 'Regular Customer'
            ELSE 'VIP Customer'
        END as customer_tier,
        
        -- Completion rate
        CASE 
            WHEN total_orders > 0 THEN ROUND((completed_orders * 100.0 / total_orders), 1)
            ELSE 0
        END as completion_rate_pct,
        
        current_timestamp() as calculated_at
    FROM user_metrics
)

SELECT * FROM final_analytics
ORDER BY revenue_rank 