-- 1. Load the 8 tables we need (geolocation is skipped: 1M rows of zip-code coordinates we don't need)
CREATE OR REPLACE TABLE orders         AS SELECT * FROM read_csv_auto('data/raw/olist_orders_dataset.csv');
CREATE OR REPLACE TABLE items          AS SELECT * FROM read_csv_auto('data/raw/olist_order_items_dataset.csv');
CREATE OR REPLACE TABLE payments       AS SELECT * FROM read_csv_auto('data/raw/olist_order_payments_dataset.csv');
CREATE OR REPLACE TABLE reviews        AS SELECT * FROM read_csv_auto('data/raw/olist_order_reviews_dataset.csv');
CREATE OR REPLACE TABLE customers      AS SELECT * FROM read_csv_auto('data/raw/olist_customers_dataset.csv');
CREATE OR REPLACE TABLE sellers        AS SELECT * FROM read_csv_auto('data/raw/olist_sellers_dataset.csv');
CREATE OR REPLACE TABLE products       AS SELECT * FROM read_csv_auto('data/raw/olist_products_dataset.csv');
CREATE OR REPLACE TABLE category_names AS SELECT * FROM read_csv_auto('data/raw/product_category_name_translation.csv');

-- 2. Rows vs unique keys: does each table have one row per ID?
SELECT 'orders' AS table_name, COUNT(*) AS row_count, COUNT(DISTINCT order_id) AS unique_ids FROM orders
UNION ALL SELECT 'customers (per order)', COUNT(*), COUNT(DISTINCT customer_id)        FROM customers
UNION ALL SELECT 'customers (real people)', COUNT(*), COUNT(DISTINCT customer_unique_id) FROM customers
UNION ALL SELECT 'products', COUNT(*), COUNT(DISTINCT product_id)  FROM products
UNION ALL SELECT 'sellers',  COUNT(*), COUNT(DISTINCT seller_id)   FROM sellers
UNION ALL SELECT 'items',    COUNT(*), COUNT(DISTINCT CONCAT(order_id, '-', order_item_id)) FROM items
UNION ALL SELECT 'payments (orders paid)', COUNT(*), COUNT(DISTINCT order_id) FROM payments
UNION ALL SELECT 'reviews',  COUNT(*), COUNT(DISTINCT review_id)   FROM reviews;

-- 3. Order status: how many orders were actually delivered?
SELECT
    order_status,
    COUNT(*)                                            AS orders,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)  AS pct
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- 4. Orders per month: which months are complete enough to report on?
SELECT
    STRFTIME(order_purchase_timestamp, '%Y-%m') AS month,
    COUNT(*)                                    AS orders
FROM orders
GROUP BY 1
ORDER BY 1;

-- 5. Data gaps and quirks
SELECT
    (SELECT COUNT(*) FROM orders WHERE order_status = 'delivered'
                                   AND order_delivered_customer_date IS NULL)                AS delivered_but_no_date,
    (SELECT COUNT(*) FROM products WHERE product_category_name IS NULL)                      AS products_no_category,
    (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS
        (SELECT 1 FROM items i WHERE i.order_id = o.order_id))                               AS orders_no_items,
    (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS
        (SELECT 1 FROM payments p WHERE p.order_id = o.order_id))                            AS orders_no_payment,
    (SELECT COUNT(*) FROM (SELECT order_id FROM reviews GROUP BY order_id HAVING COUNT(*) > 1)) AS orders_multi_reviews,
    (SELECT COUNT(*) FROM payments WHERE payment_value = 0)                                  AS zero_value_payments;
    