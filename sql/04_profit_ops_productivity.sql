-- ASSUMPTIONS (state these in the README): commission 10 pct of product price, payment fees 2.5 pct of order value

-- 1. Profitability by category (top 15 by revenue)
WITH cat AS (
    SELECT category,
           COUNT(*)           AS items,
           SUM(price)         AS revenue,
           SUM(freight_value) AS freight,
           AVG(review_score)  AS review
    FROM fact_items
    WHERE in_scope = 1 AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY category
)
SELECT
    category,
    items,
    ROUND(revenue, 0)                                       AS product_revenue,
    ROUND(revenue * 0.10, 0)                                AS commission,
    ROUND((revenue + freight) * 0.025, 0)                   AS payment_fees,
    ROUND(revenue * 0.10 - (revenue + freight) * 0.025, 0)  AS contribution,
    ROUND(100.0 * (revenue * 0.10 - (revenue + freight) * 0.025) / (revenue * 0.10), 1) AS contribution_margin_pct,
    ROUND(100.0 * freight / revenue, 1)                     AS freight_pct,
    ROUND(review, 2)                                        AS avg_review
FROM cat
ORDER BY product_revenue DESC
LIMIT 15;

-- 2. Order size: are small orders worth it?
SELECT
    CASE WHEN product_value < 50  THEN '1. under R$50'
         WHEN product_value < 100 THEN '2. R$50-100'
         WHEN product_value < 200 THEN '3. R$100-200'
         ELSE '4. R$200+' END                                      AS order_band,
    COUNT(*)                                                       AS orders,
    ROUND(100.0 * SUM(freight_value) / SUM(product_value), 1)      AS freight_pct,
    ROUND(AVG(product_value * 0.10 - gmv * 0.025), 2)              AS contribution_per_order,
    ROUND(AVG(review_score), 2)                                    AS avg_review
FROM fact_orders
WHERE in_scope = 1 AND is_cancelled = 0 AND items > 0
GROUP BY 1
ORDER BY 1;

-- 3. Delivery: does being late hurt customer satisfaction?
SELECT
    CASE on_time WHEN 1 THEN 'On time' ELSE 'Late' END               AS delivery,
    COUNT(*)                                                         AS orders,
    ROUND(AVG(delivery_days), 1)                                     AS avg_days,
    ROUND(AVG(review_score), 2)                                      AS avg_review,
    ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END), 1) AS bad_review_pct
FROM fact_orders
WHERE in_scope = 1 AND is_delivered = 1 AND on_time IS NOT NULL
GROUP BY 1;

-- 4. Regional operations: top 10 customer states
SELECT
    customer_state,
    COUNT(*)                                                   AS orders,
    ROUND(SUM(gmv), 0)                                         AS gmv_brl,
    ROUND(AVG(delivery_days), 1)                               AS avg_days,
    ROUND(100.0 * AVG(on_time), 1)                             AS on_time_pct,
    ROUND(100.0 * SUM(freight_value) / SUM(product_value), 1)  AS freight_pct,
    ROUND(AVG(review_score), 2)                                AS avg_review
FROM fact_orders
WHERE in_scope = 1 AND is_delivered = 1
GROUP BY customer_state
ORDER BY orders DESC
LIMIT 10;

-- 5. Seller productivity: revenue concentration by seller decile
WITH s AS (
    SELECT seller_id,
           SUM(price)               AS revenue,
           COUNT(DISTINCT order_id) AS orders,
           AVG(review_score)        AS review
    FROM fact_items
    WHERE in_scope = 1 AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY seller_id
),
ranked AS (
    SELECT *, NTILE(10) OVER (ORDER BY revenue DESC) AS decile FROM s
)
SELECT
    decile,
    COUNT(*)                                                  AS sellers,
    ROUND(SUM(revenue), 0)                                    AS revenue,
    ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1) AS pct_of_revenue,
    ROUND(AVG(orders), 1)                                     AS avg_orders,
    ROUND(AVG(review), 2)                                     AS avg_review
FROM ranked
GROUP BY decile
ORDER BY decile;

-- 6. Seller productivity over time
SELECT
    order_month,
    COUNT(DISTINCT seller_id)                       AS active_sellers,
    ROUND(SUM(price) / COUNT(DISTINCT seller_id), 0) AS revenue_per_seller
FROM fact_items
WHERE in_scope = 1 AND order_status NOT IN ('canceled', 'unavailable')
GROUP BY order_month
ORDER BY order_month;
