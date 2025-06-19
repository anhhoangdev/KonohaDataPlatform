{{
  config(
    materialized='table',
    file_format='iceberg',
    location_root=var('warehouse_path') ~ '/marts',
    tags=['marts', 'users', 'orders', 'business_intelligence'],
    on_schema_change='fail',
    description='User order summary providing comprehensive customer analytics and metrics'
  )
}}

-- User order summary mart
-- This demonstrates advanced CTE patterns with joins and window functions

WITH user_metrics AS (
    SELECT 
        u.user_id,
        u.full_name,
        u.email,
        u.department,
        u.career_stage,
        COUNT(o.order_id) as total_orders,
        COALESCE(SUM(CASE WHEN o.status = 'COMPLETED' THEN o.amount END), 0) as total_completed_revenue,
        COALESCE(SUM(o.amount), 0) as total_revenue,
        COALESCE(AVG(CASE WHEN o.status = 'COMPLETED' THEN o.amount END), 0) as avg_order_value,
        MIN(o.order_date) as first_order_date,
        MAX(o.order_date) as last_order_date,
        COUNT(CASE WHEN o.status = 'COMPLETED' THEN 1 END) as completed_orders,
        COUNT(CASE WHEN o.status = 'PENDING' THEN 1 END) as pending_orders,
        COUNT(CASE WHEN o.status = 'CANCELLED' THEN 1 END) as cancelled_orders
    FROM {{ ref('stg_users') }} u
    LEFT JOIN {{ ref('stg_orders') }} o ON u.user_id = o.user_id
    GROUP BY u.user_id, u.full_name, u.email, u.department, u.career_stage
),

user_rankings AS (
    SELECT 
        *,
        -- Add ranking and analytics
        ROW_NUMBER() OVER (ORDER BY total_completed_revenue DESC) as revenue_rank,
        ROW_NUMBER() OVER (ORDER BY total_orders DESC) as order_count_rank,
        ROW_NUMBER() OVER (ORDER BY avg_order_value DESC) as avg_order_rank,
        -- Calculate percentiles
        PERCENT_RANK() OVER (ORDER BY total_completed_revenue) as revenue_percentile,
        -- Add department rankings
        ROW_NUMBER() OVER (PARTITION BY department ORDER BY total_completed_revenue DESC) as dept_revenue_rank,
        current_timestamp() as calculated_at
    FROM user_metrics
),

final AS (
    SELECT 
        user_id,
        full_name,
        email,
        department,
        career_stage,
        total_orders,
        completed_orders,
        pending_orders,
        cancelled_orders,
        total_completed_revenue,
        total_revenue,
        ROUND(avg_order_value, 2) as avg_order_value,
        first_order_date,
        last_order_date,
        revenue_rank,
        order_count_rank,
        avg_order_rank,
        ROUND(revenue_percentile * 100, 1) as revenue_percentile,
        dept_revenue_rank,
        -- Customer lifecycle calculations
        CASE 
            WHEN total_orders = 0 THEN 'No Orders'
            WHEN total_orders = 1 THEN 'New Customer'
            WHEN total_orders <= 5 THEN 'Regular Customer'
            ELSE 'VIP Customer'
        END as customer_tier,
        -- Revenue per order completion rate
        CASE 
            WHEN total_orders > 0 THEN ROUND((completed_orders * 100.0 / total_orders), 1)
            ELSE 0
        END as completion_rate_pct,
        calculated_at
    FROM user_rankings
)

SELECT * FROM final
ORDER BY revenue_rank 