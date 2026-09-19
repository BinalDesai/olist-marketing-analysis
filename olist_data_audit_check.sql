-- OLIST MARKETING ANALYTICS - SNOWFLAKE SQL PIPELINE
-- What this script does from start to finish:

-- 1. Set up the Snowflake environment
--    (database, schema, warehouse, file format, and stage)

-- 2. Create the raw tables and load the CSV files from the stage

-- 3. Check the data quality
--    (duplicate IDs, missing values, incorrect relationships,
--     and calculations that don't match across tables)

-- 4. Fix the data issues found during the quality checks

-- 5. Create the main analytical views
--    (VW_ORDERS_ENRICHED, VW_PRODUCTS_ENRICHED, etc.)
--    These views are used as the main source of data for
--    KPIs, analysis, diagnostic queries, and the Streamlit app

-- 6. Create KPI and KRI views and perform descriptive
--    and diagnostic analysis

-- 7. Perform deeper marketing analysis
--    (RFM, CLV, customer retention, Pareto analysis, and seasonality)



-- SECTION 1: INFRASTRUCTURE SETUP
CREATE DATABASE olist_db;
CREATE SCHEMA marketing;
CREATE WAREHOUSE olist_wh WAREHOUSE_SIZE='XSMALL';
USE DATABASE olist_db; 
USE SCHEMA marketing; 
USE WAREHOUSE olist_wh;

CREATE OR REPLACE FILE FORMAT OLIST_CSV_FORMAT
TYPE = CSV
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
MULTI_LINE = TRUE;

 CREATE STAGE OLIST_STAGE;
TRUNCATE TABLE ORDER_ITEMS;
TRUNCATE TABLE ORDERS;
TRUNCATE TABLE REVIEWS;
TRUNCATE TABLE PRODUCTS;
TRUNCATE TABLE CUSTOMERS;
TRUNCATE TABLE PAYMENTS;

COPY INTO ORDER_ITEMS FROM @OLIST_STAGE/olist_order_items_dataset.csv FILE_FORMAT=(FORMAT_NAME=OLIST_CSV_FORMAT) FORCE=TRUE;
COPY INTO ORDERS FROM @OLIST_STAGE/olist_orders_dataset.csv FILE_FORMAT=(FORMAT_NAME=OLIST_CSV_FORMAT) FORCE=TRUE;
COPY INTO REVIEWS FROM @OLIST_STAGE/olist_order_reviews_dataset.csv FILE_FORMAT=(FORMAT_NAME=OLIST_CSV_FORMAT) FORCE=TRUE;
COPY INTO PRODUCTS FROM @OLIST_STAGE/olist_products_dataset.csv FILE_FORMAT=(FORMAT_NAME=OLIST_CSV_FORMAT) FORCE=TRUE;
COPY INTO CUSTOMERS FROM @OLIST_STAGE/olist_customers_dataset.csv FILE_FORMAT=(FORMAT_NAME=OLIST_CSV_FORMAT) FORCE=TRUE;
COPY INTO PAYMENTS FROM @OLIST_STAGE/olist_order_payments_dataset.csv FILE_FORMAT=(FORMAT_NAME=OLIST_CSV_FORMAT) FORCE=TRUE;

LIST @OLIST_STAGE;

-- SECTION 2: SCHEMA - TABLE DEFINITIONS

CREATE OR REPLACE TABLE CUSTOMERS (
    customer_id VARCHAR PRIMARY KEY,
    customer_unique_id VARCHAR(32),
    customer_zip_code_prefix VARCHAR(10),
    customer_city VARCHAR(100),
    customer_state VARCHAR(2)
);

CREATE OR REPLACE TABLE ORDERS (
    order_id VARCHAR PRIMARY KEY,
    customer_id VARCHAR REFERENCES CUSTOMERS(customer_id),
    order_status VARCHAR(20),
    order_purchase_timestamp TIMESTAMP_NTZ,
    order_approved_at TIMESTAMP_NTZ,
    order_delivered_carrier_date TIMESTAMP_NTZ,
    order_delivered_customer_date TIMESTAMP_NTZ,
    order_estimated_delivery_date TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE ORDER_ITEMS (
    order_id VARCHAR REFERENCES ORDERS(order_id),
    order_item_id NUMBER(3,0),
    product_id VARCHAR,
    seller_id VARCHAR,
    shipping_limit_date TIMESTAMP_NTZ,
    price NUMBER(10,2),
    freight_value NUMBER(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

CREATE OR REPLACE TABLE PAYMENTS (
    order_id VARCHAR REFERENCES ORDERS(order_id),
    payment_sequential NUMBER(3,0),
    payment_type VARCHAR(20),
    payment_installments NUMBER(3,0),
    payment_value NUMBER(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

CREATE OR REPLACE TABLE REVIEWS (
    review_id VARCHAR,
    order_id VARCHAR REFERENCES ORDERS(order_id),
    review_score NUMBER(1,0),
    review_comment_title VARCHAR(200),
    review_comment_message VARCHAR(5000),
    review_creation_date TIMESTAMP_NTZ,
    review_answer_timestamp TIMESTAMP_NTZ,
    PRIMARY KEY (review_id, order_id)   
);

CREATE OR REPLACE TABLE PRODUCTS (
    product_id VARCHAR PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght NUMBER(5,0),
    product_description_lenght NUMBER(6,0),
    product_photos_qty NUMBER(3,0),
    product_weight_g NUMBER(8,0),
    product_length_cm NUMBER(5,0),
    product_height_cm NUMBER(5,0),
    product_width_cm NUMBER(5,0)
);

CREATE OR REPLACE TABLE CATEGORY_TRANSLATION (
    product_category_name VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
);

ALTER TABLE CUSTOMERS
ALTER COLUMN CUSTOMER_UNIQUE_ID SET DATA TYPE VARCHAR(50);

-- SECTION 3: DATA QUALITY AUDIT

-- Row count check 
SELECT 'CUSTOMERS' AS tbl, COUNT(*) AS row_count FROM CUSTOMERS
UNION ALL SELECT 'ORDERS', COUNT(*) FROM ORDERS
UNION ALL SELECT 'ORDER_ITEMS', COUNT(*) FROM ORDER_ITEMS
UNION ALL SELECT 'PAYMENTS', COUNT(*) FROM PAYMENTS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM REVIEWS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'CATEGORY_TRANSLATION', COUNT(*) FROM CATEGORY_TRANSLATION;

--1. Primary Key Uniqueness
-- CUSTOMERS
SELECT customer_id, COUNT(*) AS cnt
FROM CUSTOMERS
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- ORDERS
SELECT order_id, COUNT(*) AS cnt
FROM ORDERS
GROUP BY order_id
HAVING COUNT(*) > 1;

-- PRODUCTS
SELECT product_id, COUNT(*) AS cnt
FROM PRODUCTS
GROUP BY product_id
HAVING COUNT(*) > 1;

-- CATEGORY_TRANSLATION
SELECT product_category_name, COUNT(*) AS cnt
FROM CATEGORY_TRANSLATION
GROUP BY product_category_name
HAVING COUNT(*) > 1;

-- ORDER_ITEMS (composite key)
SELECT order_id, order_item_id, COUNT(*) AS cnt
FROM ORDER_ITEMS
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;


-- PAYMENTS (composite key)
SELECT order_id, payment_sequential, COUNT(*) AS cnt
FROM PAYMENTS
GROUP BY order_id, payment_sequential
HAVING COUNT(*) > 1;

-- REVIEWS (single-column key — FLAGS THE ISSUE)
SELECT review_id, COUNT(*) AS cnt
FROM REVIEWS
GROUP BY review_id
HAVING COUNT(*) > 1;
--Result: 789 duplicate groups / 1,603 rows involved


-- REVIEWS (composite key — CONFIRMS THE FIX)
SELECT review_id, order_id, COUNT(*) AS cnt
FROM REVIEWS
GROUP BY review_id, order_id
HAVING COUNT(*) > 1;

--2. Referential Integrity
-- orders.customer_id must exist in customers
SELECT COUNT(*) AS orphan_count
FROM ORDERS o
LEFT JOIN CUSTOMERS c ON o.customer_id = c.customer_id
WHERE c.customer_id IS NULL;

-- order_items.order_id must exist in orders
SELECT COUNT(*) AS orphan_count
FROM ORDER_ITEMS oi
LEFT JOIN ORDERS o ON oi.order_id = o.order_id
WHERE o.order_id IS NULL;

-- order_items.product_id must exist in products
SELECT COUNT(*) AS orphan_count
FROM ORDER_ITEMS oi
LEFT JOIN PRODUCTS p ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;


-- payments.order_id must exist in orders
SELECT COUNT(*) AS orphan_count
FROM PAYMENTS pay
LEFT JOIN ORDERS o ON pay.order_id = o.order_id
WHERE o.order_id IS NULL;

-- reviews.order_id must exist in orders
SELECT COUNT(*) AS orphan_count
FROM REVIEWS r
LEFT JOIN ORDERS o ON r.order_id = o.order_id
WHERE o.order_id IS NULL;

-- products.product_category_name must exist in category_translation
SELECT DISTINCT p.product_category_name, COUNT(*) AS product_count
FROM PRODUCTS p
LEFT JOIN CATEGORY_TRANSLATION ct
  ON p.product_category_name = ct.product_category_name
WHERE ct.product_category_name IS NULL
  AND p.product_category_name IS NOT NULL
GROUP BY p.product_category_name;

-- Result: 2 orphan category names found
--   'pc_gamer'- 3 products
--   'portateis_cozinha_e_preparadores_de_alimentos' - 10 products

-- how many products have NULL category at all
SELECT COUNT(*) AS null_category_products
FROM PRODUCTS
WHERE product_category_name IS NULL;
-- Result: 610

--3. Null / Completeness Audit
-- Generic pattern per table — run for every column you care about
SELECT
  COUNT(*) AS total_rows,
  COUNT(*) - COUNT(order_approved_at) AS null_order_approved_at,
  COUNT(*) - COUNT(order_delivered_carrier_date) AS null_delivered_carrier_date,
  COUNT(*) - COUNT(order_delivered_customer_date) AS null_delivered_customer_date
FROM ORDERS;
-- Result: total=99,441 | null_approved_at=160 | null_carrier_date=1,783 | null_customer_date=2,965 

SELECT
  COUNT(*) AS total_rows,
  COUNT(*) - COUNT(review_comment_title) AS null_comment_title,
  COUNT(*) - COUNT(review_comment_message) AS null_comment_message,
  COUNT(*) - COUNT(review_score) AS null_review_score
FROM REVIEWS;
-- Result: total=99,224 | null_title=87,656 | null_message=58,247 | null_score=0 

SELECT
  COUNT(*) AS total_rows,
  COUNT(*) - COUNT(product_category_name) AS null_category,
  COUNT(*) - COUNT(product_weight_g) AS null_weight,
  COUNT(*) - COUNT(product_photos_qty) AS null_photos_qty
FROM PRODUCTS;
-- Result: total=32,951 | null_category=610 | null_weight=2 | null_photos_qty=610 

-- Confirm zero nulls in transaction-critical columns
SELECT
  COUNT(*) - COUNT(price) AS null_price,
  COUNT(*) - COUNT(freight_value) AS null_freight
FROM ORDER_ITEMS;
-- Result: 0, 0 

SELECT
  COUNT(*) - COUNT(payment_type)   AS null_payment_type,
  COUNT(*) - COUNT(payment_value)  AS null_payment_value
FROM PAYMENTS;
-- Result: 0, 0 (clean)

--4. Cross-Table Arithmetic 

-- Simple row-count sanity check per table
SELECT 'CUSTOMERS' AS tbl, COUNT(*) AS row_count FROM CUSTOMERS
UNION ALL SELECT 'ORDERS', COUNT(*) FROM ORDERS
UNION ALL SELECT 'ORDER_ITEMS', COUNT(*) FROM ORDER_ITEMS
UNION ALL SELECT 'PAYMENTS', COUNT(*) FROM PAYMENTS
UNION ALL SELECT 'REVIEWS', COUNT(*) FROM REVIEWS
UNION ALL SELECT 'PRODUCTS', COUNT(*) FROM PRODUCTS
UNION ALL SELECT 'CATEGORY_TRANSLATION', COUNT(*) FROM CATEGORY_TRANSLATION;

-- Value range checks
SELECT COUNT(*) FROM REVIEWS WHERE review_score NOT BETWEEN 1 AND 5;                  -- 0
SELECT COUNT(*) FROM ORDER_ITEMS WHERE price <= 0;                                     -- 0
SELECT COUNT(*) FROM ORDER_ITEMS WHERE freight_value < 0;                              -- 0
SELECT COUNT(*) FROM PAYMENTS WHERE payment_value < 0;                                 -- 0
SELECT COUNT(*) FROM PAYMENTS WHERE payment_value = 0;                                 -- 9
SELECT COUNT(*) FROM PAYMENTS WHERE payment_installments <= 0;                         -- 2
SELECT COUNT(*) FROM PRODUCTS WHERE product_weight_g = 0;                              -- 4

-- Categorical domain check
SELECT DISTINCT order_status FROM ORDERS;
-- delivered, invoiced, shipped, processing, unavailable, canceled, created, approved

SELECT DISTINCT payment_type FROM PAYMENTS;
-- credit_card, boleto, voucher, debit_card, not_defined

-- Chronological consistency
SELECT COUNT(*) FROM ORDERS WHERE order_approved_at < order_purchase_timestamp;             -- 0
SELECT COUNT(*) FROM ORDERS WHERE order_delivered_carrier_date < order_approved_at;         -- 1,359
SELECT COUNT(*) FROM ORDERS WHERE order_delivered_customer_date < order_delivered_carrier_date; -- 23
SELECT COUNT(*) FROM ORDERS WHERE order_delivered_customer_date < order_purchase_timestamp; -- 0

-- Date range validity
SELECT MIN(order_purchase_timestamp), MAX(order_purchase_timestamp) FROM ORDERS;
-- 2016-09-04  to  2018-10-17

-- Amount reconciliation
WITH items_agg AS (
  SELECT order_id, SUM(price) + SUM(freight_value) AS items_total
  FROM ORDER_ITEMS GROUP BY order_id
),
pay_agg AS (
  SELECT order_id, SUM(payment_value) AS payments_total
  FROM PAYMENTS GROUP BY order_id
)
SELECT COUNT(*) AS mismatched_orders
FROM items_agg i JOIN pay_agg p ON i.order_id = p.order_id
WHERE ABS(i.items_total - p.payments_total) > 0.10;

-- 259 mismatched orders out of 98,665 compared

-- Same customer_unique_id appearing under more than one state across their orders
SELECT COUNT(*) FROM (
  SELECT customer_unique_id, COUNT(DISTINCT customer_state) AS state_count
  FROM CUSTOMERS
  GROUP BY customer_unique_id
  HAVING COUNT(DISTINCT customer_state) > 1
);
-- Result: 39 customers

-- SECTION 4: DATA CLEANING & FIXES

--Fix the 2 missing category translations
insert into category_translation (product_category_name,product_category_name_english)
values ('pc_gamer', 'gaming_computers'),
  ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_appliances');

--Add data-quality flags instead of deleting/altering raw rows
create or replace view vw_orders_quality_flagged as
select o.*,
    case 
        when order_delivered_carrier_date < order_approved_at then 1 
        when order_delivered_customer_date < order_delivered_carrier_date then 1
        else 0
    end as is_timestamp_anomaly
from orders o;

-- SECTION 5: CORE ANALYTICAL VIEWS
--Build the enriched order-level and product-level view

create or replace view vw_orders_enriched as
select
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    datediff('day',o.order_estimated_delivery_date,o.order_delivered_customer_date) as delivery_delay_days,
    CASE 
        WHEN o.order_delivered_customer_date IS NULL THEN NULL
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 
        ELSE 0 
    END AS is_late,
    items.total_price,
    items.total_freight,
    items.total_price + items.total_freight as order_revenue,
    r.review_score,
    case when r.review_score <= 2 then 1 else 0 end as is_low_review,
    p.payment_types,
    p.total_payment_value,
    q.is_timestamp_anomaly
from orders o
left join customers c on o.customer_id=c.customer_id
left join (
    select order_id,sum(price) as total_price,sum(freight_value) as total_freight
    from order_items group by order_id 
) items on o.order_id = items.order_id
left join (
    select order_id,max(review_score) as review_score
    from reviews group by order_id
) r on o.order_id = r.order_id
left join (
    select order_id, listagg(distinct payment_type, ', ') as payment_types, sum(payment_value) as total_payment_value
    from PAYMENTS group by order_id
) p on o.order_id = p.order_id
left join VW_ORDERS_QUALITY_FLAGGED q ON o.order_id = q.order_id;


create or replace view VW_PRODUCTS_ENRICHED as
select
    p.product_id,
    p.product_category_name,
    COALESCE(ct.product_category_name_english, 'uncategorized') AS product_category_name_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
from PRODUCTS p
left join CATEGORY_TRANSLATION ct ON p.product_category_name = ct.product_category_name;

CREATE OR REPLACE VIEW VW_ORDER_PRIMARY_PAYMENT AS
SELECT order_id, payment_type AS primary_payment_type
FROM (
    SELECT order_id, payment_type, payment_value,
           ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_value DESC) AS rn
    FROM PAYMENTS
) 
WHERE rn = 1;
CREATE OR REPLACE VIEW VW_REVIEW_MONTHLY AS
SELECT
    r.order_id,
    r.review_creation_date,
    TO_CHAR(r.review_creation_date, 'MON ''YY') AS month_year,
    oe.review_score
FROM REVIEWS r
JOIN VW_ORDERS_ENRICHED oe
    ON r.order_id = oe.order_id;
SELECT CURRENT_USER();

SELECT COUNT(*) FROM OLIST_DB.MARKETING.VW_ORDER_PRIMARY_PAYMENT;

--Re-validate the fix worked
-- Should now be 0 (was 13)

select count(*) from products p
left join category_translation ct on p.product_category_name=ct.product_category_name
where ct.product_category_name is null and p.product_category_name is not null;

-- Sanity check the enriched view row count matches ORDERS
select count(*) from vw_orders_enriched;

--SECTION 6: DESCRIPTIVE, DIAGNOSTIC & KPI/KRI VIEWS

-- Built on VW_ORDERS_ENRICHED / VW_PRODUCTS_ENRICHED



-- SECTION A: FORMAL KPI / KRI VIEWS
--- KPI: Repeat Customer Rate

create or replace view VW_KPI_REPEAT_RATE as
select 
    count(*) AS total_customers,
    sum(case when order_count > 1 then 1 else 0 end) as repeat_customers,
    round(sum(case when order_count > 1 then 1 else 0 end) * 100.0 / COUNT(*), 2) as repeat_rate_pct
from (
    select customer_unique_id, count(distinct order_id) as order_count
    from VW_ORDERS_ENRICHED
    group by customer_unique_id
);

-- KPI: On-Time Delivery Rate
create or replace view VW_KPI_ON_TIME_DELIVERY as
select
    round(sum(case when is_late = 0 then 1 else 0 end) * 100.0 /
          sum(case when order_delivered_customer_date is not null then 1 else 0 end), 2) as on_time_rate_pct
from VW_ORDERS_ENRICHED;

select top 5 * from vw_orders_enriched;


-- KRI: % low-score Reviews (1-2 stars)
create or replace view VW_KRI_LOW_REVIEW_RATE as
select
    round(sum(is_low_review) * 100.0 / count(review_score), 2) as low_review_rate_pct
from VW_ORDERS_ENRICHED
where review_score is not null;
 
-- KPI: Average Order Value
create or replace view VW_KPI_AOV as
select round(sum(order_revenue) / count(distinct order_id), 2) as avg_order_value
from VW_ORDERS_ENRICHED;

 --SECTION B: DESCRIPTIVE ANALYSIS 
 -- B1.Sales & Revenue Performance
select 
    order_status,
    count(distinct order_id) as orders,
    sum(order_revenue) as revenue,
    round(avg(order_revenue), 2) as aov
from VW_ORDERS_ENRICHED
group by order_status
order by revenue desc;
 
-- B2. Customer Segmentation & Geography
select
    customer_state,
    count(distinct customer_unique_id) as unique_customers,
    count(distinct order_id) as orders,
    sum(order_revenue) as revenue
from VW_ORDERS_ENRICHED
group by customer_state
order by revenue desc;
 
-- B3. Temporal Patterns — order volume by month
select
    date_trunc('month', order_purchase_timestamp) as order_month,
    count(distinct order_id) as orders,
    sum(order_revenue) as revenue
from VW_ORDERS_ENRICHED
group by order_month
order by order_month;
 
-- B3b. Temporal Patterns — order volume by day of week
select
    dayname(order_purchase_timestamp) as day_of_week,
    count(distinct order_id) as orders
from VW_ORDERS_ENRICHED
group by day_of_week
order by orders desc;
 
-- B4. Product & Category Performance
select
    pe.product_category_name_english,
    count(distinct oi.order_id) as orders,
    sum(oi.price) as revenue,
    round(avg(oi.price), 2) as avg_item_price
from ORDER_ITEMS oi
join VW_PRODUCTS_ENRICHED pe on oi.product_id = pe.product_id
group by pe.product_category_name_english
order by revenue desc
limit 10;

SELECT 
    pe.product_category_name_english,
    SUM(oi.price) AS revenue,
    COUNT(DISTINCT oi.order_id) AS orders
FROM ORDER_ITEMS oi
JOIN VW_PRODUCTS_ENRICHED pe ON oi.product_id = pe.product_id
JOIN ORDERS o ON oi.order_id = o.order_id
WHERE o.order_purchase_timestamp < '2018-09-01'
GROUP BY pe.product_category_name_english
ORDER BY revenue DESC
LIMIT 15;

-- B5. Customer Satisfaction Patterns — score distribution
select
    review_score,
    count(*) AS review_count,
    round(count(*) * 100.0 / sum(count(*)) over(), 2) as pct_of_total
from VW_ORDERS_ENRICHED
where review_score IS NOT NULL
group by review_score
order by review_score;
 
-- B6. Delivery Experience
select
    round(avg(delivery_delay_days), 2) as avg_delivery_delay_days,
    ROUND(SUM(is_late) * 100.0 / COUNT(*), 2) as late_delivery_pct
from VW_ORDERS_ENRICHED
where order_delivered_customer_date is not NULL;
 
-- B7. Payment Behavior
select
    payment_type,
    count(distinct order_id) as orders,
    round(avg(payment_installments), 2) as avg_installments,
    round(avg(payment_value), 2) AS avg_payment_value
from PAYMENTS
group by payment_type
order by orders desc;
 

-- SECTION C: DIAGNOSTIC ANALYSIS 
-- C1. Does late delivery drive down review scores?
select
    case when is_late = 1 then 'Late' else 'On-Time' end as delivery_bucket,
    round(avg(review_score), 2) as avg_review_score,
    count(*) as orders
from VW_ORDERS_ENRICHED
where review_score is not NULL and order_delivered_customer_date is not NULL
group by delivery_bucket;
 
-- C2. Why do some categories get low scores despite high volume?
select
    pe.product_category_name_english,
    count(distinct oe.order_id) as orders,
    round(avg(oe.review_score), 2) as avg_review_score,
    round(avg(oe.delivery_delay_days), 2) as avg_delay,
    round(avg(oi.freight_value / nullif(oi.price, 0)) * 100, 2) as avg_freight_ratio_pct
from VW_ORDERS_ENRICHED oe
join ORDER_ITEMS oi on oe.order_id = oi.order_id
join VW_PRODUCTS_ENRICHED pe on oi.product_id = pe.product_id
group by pe.product_category_name_english
having count(distinct oe.order_id) > 100
order by orders desc;
 
-- C3. Which states show low satisfaction not explained by delay?
SELECT
    customer_state,
    round(avg(delivery_delay_days), 2) as avg_delay,
    ROUND(avg(review_score), 2) as avg_review_score
from VW_ORDERS_ENRICHED
where review_score is not NULL and order_delivered_customer_date is not NULL
group by customer_state
order by avg_review_score asc;
 
-- C4. Why do customers never place a second order?
-- (first-order attributes compared: one-time vs. repeat customers)
with first_orders as (
    select customer_unique_id, order_id, review_score, delivery_delay_days,
           ROW_NUMBER() over (partition by customer_unique_id order by order_purchase_timestamp) as rn
    from VW_ORDERS_ENRICHED
),
customer_order_counts as (
    select customer_unique_id, count(distinct order_id) as order_count
    from VW_ORDERS_ENRICHED group by customer_unique_id
)
select
    case when c.order_count > 1 then 'Repeat' else 'One-Time' end as customer_type,
    round(avg(f.review_score), 2) as avg_first_order_review,
    round(avg(f.delivery_delay_days), 2) as avg_first_order_delay
from first_orders f
join customer_order_counts c on f.customer_unique_id = c.customer_unique_id
where f.rn = 1
group by customer_type;
 
-- C5. Does installment count affect order value or cancellation risk?
select
    p.payment_installments,
    round(avg(oi.price + oi.freight_value), 2) as avg_order_value,
    round(sum(case when o.order_status = 'canceled' then 1 else 0 end) * 100.0 / COUNT(*), 2) as cancellation_rate_pct
from PAYMENTS p
join ORDERS o on p.order_id = o.order_id
join ORDER_ITEMS oi on o.order_id = oi.order_id
group by p.payment_installments
order by p.payment_installments;
 
-- C6. Do high-freight-ratio categories suppress order volume?
select
    pe.product_category_name_english,
    count(distinct oi.order_id) as orders,
    round(avg(oi.freight_value / nullif(oi.price, 0)) * 100, 2) AS avg_freight_ratio_pct
from ORDER_ITEMS oi
join VW_PRODUCTS_ENRICHED pe on oi.product_id = pe.product_id
group by pe.product_category_name_english
order by avg_freight_ratio_pct desc;

-- the descriptive/diagnostic sections with standard marketing
-- analytics techniques (RFM, CLV, cohort retention, concentration,
-- seasonality).
-- D1. RFM SEGMENTATION (Recency, Frequency, Monetary)

create or replace view VW_RFM_SEGMENTATION as
with rfm_base as (
    select
        customer_unique_id,
        datediff('day', max(order_purchase_timestamp), (select max(order_purchase_timestamp) from VW_ORDERS_ENRICHED)) as recency_days,
        count(distinct order_id) as frequency,
        round(avg(order_revenue), 2) as avg_monetary
    from VW_ORDERS_ENRICHED
    group by customer_unique_id
),
rfm_scored as (
    select *,
        NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,   -- lower recency_days = more recent = higher score
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY avg_monetary ASC) AS m_score
    FROM rfm_base
)
SELECT *,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
        WHEN r_score >= 4 AND f_score < 4 THEN 'New/Promising'
        WHEN r_score < 3 AND f_score >= 4 THEN 'At-Risk Loyal'
        WHEN r_score < 3 AND f_score < 3 THEN 'Lost/Churned'
        ELSE 'Regular'
    END AS rfm_segment
FROM rfm_scored;
 
-- Segment size summary
SELECT rfm_segment, COUNT(*) AS customers, ROUND(AVG(avg_monetary),2) AS avg_order_value
FROM VW_RFM_SEGMENTATION
GROUP BY rfm_segment
ORDER BY customers DESC;
 
-- D2. CUSTOMER LIFETIME VALUE (simple estimate)
-- CLV = avg order value x order frequency (no cost/margin data available,
-- so this is a revenue-based CLV proxy, not true profit-based CLV).

CREATE OR REPLACE VIEW VW_CUSTOMER_CLV AS
SELECT
    customer_unique_id,
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(order_revenue) AS lifetime_revenue,
    ROUND(AVG(order_revenue), 2) AS avg_order_value
FROM VW_ORDERS_ENRICHED
GROUP BY customer_unique_id;
 
-- Distribution check — how concentrated is revenue among top customers?
SELECT
    NTILE(10) OVER (ORDER BY lifetime_revenue DESC) AS decile,
    lifetime_revenue
FROM VW_CUSTOMER_CLV
QUALIFY decile = 1
ORDER BY lifetime_revenue DESC
LIMIT 20;

-- D3. COHORT RETENTION ANALYSIS
-- Groups customers by their first-purchase month, tracks whether
-- they ordered again in subsequent months. 

CREATE OR REPLACE VIEW VW_COHORT_RETENTION AS
WITH first_order AS (
    SELECT customer_unique_id, MIN(DATE_TRUNC('month', order_purchase_timestamp)) AS cohort_month
    FROM VW_ORDERS_ENRICHED
    GROUP BY customer_unique_id
),
orders_with_cohort AS (
    SELECT
        o.customer_unique_id,
        f.cohort_month,
        DATE_TRUNC('month', o.order_purchase_timestamp) AS order_month,
        DATEDIFF('month', f.cohort_month, DATE_TRUNC('month', o.order_purchase_timestamp)) AS month_number
    FROM VW_ORDERS_ENRICHED o
    JOIN first_order f ON o.customer_unique_id = f.customer_unique_id
)
SELECT
    cohort_month,
    month_number,
    COUNT(DISTINCT customer_unique_id) AS active_customers
FROM orders_with_cohort
GROUP BY cohort_month, month_number
ORDER BY cohort_month, month_number;
 
-- Retention rate table (% of cohort still active in month N)
SELECT
    cohort_month,
    month_number,
    active_customers,
    ROUND(active_customers * 100.0 / FIRST_VALUE(active_customers) OVER (
        PARTITION BY cohort_month ORDER BY month_number
    ), 2) AS retention_pct
FROM VW_COHORT_RETENTION
ORDER BY cohort_month, month_number;
 

-- D4. REVENUE CONCENTRATION / PARETO ANALYSIS
-- Real finding: SP alone = 38.3% of revenue; top 7 states = ~81.5%

WITH state_revenue AS (
    SELECT customer_state, SUM(order_revenue) AS revenue
    FROM VW_ORDERS_ENRICHED
    GROUP BY customer_state
)
SELECT
    customer_state,
    revenue,
    ROUND(SUM(revenue) OVER (ORDER BY revenue DESC) * 100.0 /
          SUM(revenue) OVER (), 2) AS cumulative_pct
FROM state_revenue
ORDER BY revenue DESC;
 
-- Same concentration check at the customer level (do a small % of
-- customers drive a disproportionate share of revenue?)
WITH customer_revenue AS (
    SELECT customer_unique_id, SUM(order_revenue) AS revenue
    FROM VW_ORDERS_ENRICHED
    GROUP BY customer_unique_id
)
SELECT
    ROUND(SUM(revenue) OVER (ORDER BY revenue DESC) * 100.0 /
          SUM(revenue) OVER (), 2) AS cumulative_pct,
    ROW_NUMBER() OVER (ORDER BY revenue DESC) * 100.0 / COUNT(*) OVER () AS cumulative_customer_pct
FROM customer_revenue
QUALIFY cumulative_customer_pct <= 20  -- top 20% of customers
ORDER BY cumulative_pct DESC
LIMIT 1;
 

-- D5. SEASONALITY / HOLIDAY SPIKE DETECTION
-- Real finding: November 2017 shows a Black Friday spike

select
    date_trunc('month', order_purchase_timestamp) as order_month,
    count(distinct order_id) as orders,
    sum(order_revenue) as revenue,
    round(avg(count(distinct order_id)) over (
        order by date_trunc('month', order_purchase_timestamp)
        rows between 2 preceding and 2 following
    ), 0) as rolling_5mo_avg_orders
from VW_ORDERS_ENRICHED
where order_purchase_timestamp < '2018-09-01'  -- exclude incomplete final months
group by order_month
order by order_month;





 
