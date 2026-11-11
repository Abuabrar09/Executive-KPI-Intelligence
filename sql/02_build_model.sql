-- 1. Payments: one row per order (some orders are paid in several parts)
CREATE OR REPLACE TABLE order_payments AS
SELECT
    order_id,
    SUM(payment_value)                    AS payment_total,
    MAX(payment_installments)             AS installments,
    ARG_MAX(payment_type, payment_value)  AS main_payment_type,
    COUNT(*)                              AS payment_parts
FROM payments
GROUP BY order_id;

-- 2. Reviews: one row per order (keep the latest review)
CREATE OR REPLACE TABLE order_reviews AS
SELECT order_id, review_score
FROM (
    SELECT order_id, review_score,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_answer_timestamp DESC) AS rn
    FROM reviews
)
WHERE rn = 1;

-- 3. Items: one row per order
CREATE OR REPLACE TABLE order_items_sum AS
SELECT
    order_id,
    COUNT(*)                  AS items,
    COUNT(DISTINCT seller_id) AS sellers,
    SUM(price)                AS product_value,
    SUM(freight_value)        AS freight_value
FROM items
GROUP BY order_id;

-- 4. Unified fact table: one row per order with sales, finance and operations
CREATE OR REPLACE TABLE fact_orders AS
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    CAST(o.order_purchase_timestamp AS DATE)                   AS order_date,
    CAST(DATE_TRUNC('month', o.order_purchase_timestamp) AS DATE) AS order_month,
    COALESCE(i.items, 0)                                       AS items,
    COALESCE(i.product_value, 0)                               AS product_value,
    COALESCE(i.freight_value, 0)                               AS freight_value,
    COALESCE(i.product_value, 0) + COALESCE(i.freight_value, 0) AS gmv,
    p.payment_total,
    p.installments,
    p.main_payment_type,
    r.review_score,
    DATE_DIFF('day', o.order_purchase_timestamp, o.order_delivered_customer_date) AS delivery_days,
    CASE WHEN o.order_delivered_customer_date IS NULL THEN NULL
         WHEN CAST(o.order_delivered_customer_date AS DATE) <= CAST(o.order_estimated_delivery_date AS DATE) THEN 1
         ELSE 0 END                                            AS on_time,
    CASE WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
         THEN 1 ELSE 0 END                                     AS is_delivered,
    CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN 1 ELSE 0 END AS is_cancelled,
    CASE WHEN ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id
                                 ORDER BY o.order_purchase_timestamp) = 1
         THEN 1 ELSE 0 END                                     AS is_first_order,
    CASE WHEN o.order_purchase_timestamp >= TIMESTAMP '2017-01-01'
          AND o.order_purchase_timestamp <  TIMESTAMP '2018-09-01'
         THEN 1 ELSE 0 END                                     AS in_scope
FROM orders o
JOIN customers c             ON o.customer_id = c.customer_id
LEFT JOIN order_items_sum i  ON o.order_id = i.order_id
LEFT JOIN order_payments p   ON o.order_id = p.order_id
LEFT JOIN order_reviews r    ON o.order_id = r.order_id;

-- 5. Item-level fact: for category and seller drill-downs
CREATE OR REPLACE TABLE fact_items AS
SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    i.price,
    i.freight_value,
    f.order_date,
    f.order_month,
    f.order_status,
    f.customer_state,
    f.is_delivered,
    f.on_time,
    f.review_score,
    f.in_scope
FROM items i
JOIN fact_orders f          ON i.order_id = f.order_id
LEFT JOIN products p        ON i.product_id = p.product_id
LEFT JOIN category_names t  ON p.product_category_name = t.product_category_name;

-- 6. Seller dimension
CREATE OR REPLACE TABLE dim_sellers AS
SELECT seller_id, seller_city, seller_state FROM sellers;

-- 7. Reconciliation: does the model add up?
SELECT
    (SELECT COUNT(*) FROM fact_orders)                         AS orders,
    (SELECT COUNT(*) FROM fact_items)                          AS items,
    (SELECT SUM(in_scope) FROM fact_orders)                    AS orders_in_scope,
    (SELECT ROUND(SUM(gmv), 0) FROM fact_orders)               AS gmv_order_level,
    (SELECT ROUND(SUM(price) + SUM(freight_value), 0) FROM fact_items) AS gmv_item_level,
    (SELECT ROUND(SUM(payment_total), 0) FROM fact_orders)     AS payments_total;

-- 8. Export for Python and Power BI
COPY fact_orders TO 'data/processed/fact_orders.csv' (HEADER);
COPY fact_items  TO 'data/processed/fact_items.csv'  (HEADER);
COPY dim_sellers TO 'data/processed/dim_sellers.csv' (HEADER);
