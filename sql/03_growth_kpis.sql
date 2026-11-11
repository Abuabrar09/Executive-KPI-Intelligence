-- 1. Executive scorecard: Jan-Aug 2018 vs Jan-Aug 2017 (same months, fair comparison)
SELECT
    CASE WHEN order_date < DATE '2018-01-01' THEN 'Jan-Aug 2017' ELSE 'Jan-Aug 2018' END AS period,
    COUNT(*)                                                         AS orders,
    ROUND(SUM(gmv) FILTER (WHERE is_cancelled = 0), 0)               AS gmv_brl,
    ROUND(AVG(gmv) FILTER (WHERE is_cancelled = 0 AND items > 0), 2) AS avg_order_value,
    COUNT(DISTINCT customer_unique_id)                               AS customers,
    SUM(is_first_order)                                              AS new_customers,
    ROUND(100.0 * AVG(on_time), 1)                                   AS on_time_pct,
    ROUND(AVG(review_score), 2)                                      AS avg_review,
    ROUND(100.0 * AVG(is_cancelled), 2)                              AS cancel_pct
FROM fact_orders
WHERE in_scope = 1 AND MONTH(order_date) <= 8
GROUP BY 1
ORDER BY 1;

-- 2. Monthly trend with month-on-month and year-on-year growth
WITH m AS (
    SELECT order_month,
           COUNT(*)                                  AS orders,
           SUM(gmv) FILTER (WHERE is_cancelled = 0)  AS gmv,
           SUM(is_first_order)                       AS new_customers
    FROM fact_orders
    WHERE in_scope = 1
    GROUP BY order_month
)
SELECT
    order_month,
    orders,
    ROUND(gmv, 0)                                                         AS gmv_brl,
    ROUND(100.0 * (gmv / LAG(gmv) OVER (ORDER BY order_month) - 1), 1)    AS mom_pct,
    ROUND(100.0 * (gmv / LAG(gmv, 12) OVER (ORDER BY order_month) - 1), 1) AS yoy_pct,
    new_customers
FROM m
ORDER BY order_month;

-- 3. Customer loyalty: how many customers come back?
WITH c AS (
    SELECT customer_unique_id, COUNT(*) AS orders, SUM(gmv) AS gmv
    FROM fact_orders
    WHERE in_scope = 1 AND is_cancelled = 0
    GROUP BY customer_unique_id
)
SELECT
    COUNT(*)                                                                 AS customers,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)                              AS repeat_customers,
    ROUND(100.0 * AVG(CASE WHEN orders > 1 THEN 1 ELSE 0 END), 1)            AS repeat_pct,
    ROUND(100.0 * SUM(CASE WHEN orders > 1 THEN gmv ELSE 0 END) / SUM(gmv), 1) AS repeat_gmv_pct
FROM c;
