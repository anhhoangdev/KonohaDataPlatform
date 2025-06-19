{{
  config(
    materialized='incremental',
    unique_key='metric_date',
    file_format='iceberg',
    location_root=var('warehouse_path') ~ '/marts',
    tags=['marts', 'metrics', 'incremental', 'daily'],
    on_schema_change='fail',
    incremental_strategy='merge',
    description='Daily aggregated order metrics for business reporting and monitoring'
  )
}}

-- Daily order metrics - incremental model for performance
-- Demonstrates incremental processing with model-level configuration

WITH daily_aggregates AS (
    SELECT
        order_date,
        COUNT(*) as total_orders,
        COUNT(CASE WHEN status = 'COMPLETED' THEN 1 END) as completed_orders,
        COUNT(CASE WHEN status = 'PENDING' THEN 1 END) as pending_orders,
        COUNT(CASE WHEN status = 'CANCELLED' THEN 1 END) as cancelled_orders,
        SUM(amount) as total_revenue,
        SUM(CASE WHEN status = 'COMPLETED' THEN amount ELSE 0 END) as completed_revenue,
        AVG(amount) as avg_order_value,
        MIN(amount) as min_order_value,
        MAX(amount) as max_order_value,
        COUNT(DISTINCT user_id) as unique_customers,
        current_timestamp() as calculated_at
    FROM {{ ref('stg_orders') }}
    {% if is_incremental() %}
        -- Only process new/updated data in incremental runs
        WHERE order_date >= (SELECT MAX(metric_date) FROM {{ this }})
    {% endif %}
    GROUP BY order_date
),

metrics_with_calculations AS (
    SELECT
        order_date as metric_date,
        total_orders,
        completed_orders,
        pending_orders,
        cancelled_orders,
        unique_customers,
        ROUND(total_revenue, 2) as total_revenue,
        ROUND(completed_revenue, 2) as completed_revenue,
        ROUND(avg_order_value, 2) as avg_order_value,
        min_order_value,
        max_order_value,
        -- Calculate rates
        ROUND((completed_orders * 100.0 / NULLIF(total_orders, 0)), 2) as completion_rate_pct,
        ROUND((cancelled_orders * 100.0 / NULLIF(total_orders, 0)), 2) as cancellation_rate_pct,
        ROUND((pending_orders * 100.0 / NULLIF(total_orders, 0)), 2) as pending_rate_pct,
        -- Customer metrics
        ROUND(total_revenue / NULLIF(unique_customers, 0), 2) as revenue_per_customer,
        ROUND(total_orders / NULLIF(unique_customers, 0), 2) as orders_per_customer,
        calculated_at
    FROM daily_aggregates
)

SELECT * FROM metrics_with_calculations
ORDER BY metric_date DESC 