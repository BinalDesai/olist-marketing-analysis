
# Olist Marketing Analytics

An end-to-end marketing analytics project on the Olist Brazilian E-Commerce dataset. It covers a SQL data audit, Python EDA and customer analytics, a low-review risk model, Power BI dashboards and a Streamlit app.

**Live app:** https://olist-marketing-analysis-advwt8s7acuzbkhi4rk86p.streamlit.app/

---

## 1. Objective

Olist is a marketplace with strong operations (97% of orders delivered, 4.09 average review) but very few repeat customers (3.11%). This project helps a marketing team answer three questions:

1. **Where does revenue come from**, and how is the business trending?
2. **Why do customers leave unhappy or never come back?**
3. **Which orders are likely to get a bad review**, so service can step in early?

The goal is to move from data to clear, actionable recommendations, not just charts.

---

## 2. Dataset

[Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle): 7 CSV files (customers, orders, order items, payments, reviews, products, category translation), about 99K orders and 547K records, Sep 2016 to Oct 2018.

**Analysis window:** orders placed before 1 Sep 2018. The last 20 orders (Sep and Oct 2018) are dropped because that period is incomplete. This leaves **99,421 orders**.

---

## 3. Tech stack

| Layer | Tool |
|---|---|
| Data warehouse | SQL (Snowflake) |
| Analysis and modelling | Python (Jupyter / Databricks): pandas, scipy, scikit-learn |
| Dashboards | Power BI (4 pages) |
| Web app | Streamlit + Plotly |
| Code hosting | GitHub |

---

## 4. Project workflow

1. **Load and audit (SQL):** load the 7 tables into a Snowflake star schema and run data-quality checks.
2. **Clean and model (SQL):** flag issues, fix missing category translations, build enriched views and KPI/KRI views.
3. **Explore and analyse (Python):** descriptive, seasonality, diagnostic and customer analytics.
4. **Predict (Python):** train and compare models to flag orders likely to get a 1-2 star review.
5. **Deliver:** Power BI dashboards for stakeholders and a Streamlit app with the analyses and the model.

---

## 5. Data audit (SQL)

Checks included key uniqueness, foreign keys, nulls, value ranges, category domains, timestamp chronology and amount reconciliation. Issues were flagged, not deleted. Main points:

- 2,945 orders were never delivered (no delivery date). They are excluded from delivery KPIs.
- 756 orders have no items (mostly unavailable or canceled), so they have no revenue.
- Some orders have several payment records or several reviews. The first payment and the highest review score are used.
- 2 product categories had no English translation and were mapped.

---

## 6. Metric definitions

| Metric | Definition |
|---|---|
| Revenue | Item price + freight per order, all order statuses |
| AOV | Revenue divided by orders that contain at least one item |
| Repeat rate | Customers with 2+ orders divided by unique customers (`customer_unique_id`) |
| On-time / late rate | Delivered orders only; late means delivered after the estimated date |
| Delivery delay | Delivered date minus estimated date, in days (negative = early) |
| 1-2 star rate | Reviews of 1-2 stars divided by orders that have a review |
| Category | Category of the first item in the order |

---

## 7. Analyses and findings

### 7.1 Headline KPIs

| KPI | Value |
|---|---|
| Revenue | R$15.84M |
| Orders | 99,421 |
| Unique customers | 96,090 |
| Average order value | R$160.58 |
| Repeat customer rate | 3.11% |
| On-time delivery | 91.89% |
| Late delivery | 8.11% |
| Average review score | 4.09 |
| 1-2 star reviews | 14.62% |
| Orders delivered / canceled | 97.04% / 0.61% |

### 7.2 Descriptive analysis

- **Order status:** 97% of orders are delivered. 609 orders are "unavailable" and 1,106 are stuck in "shipped" with no delivery date.
- **Trend:** orders grew from about 800 (Jan 2017) to a peak of 7,544 (Nov 2017), then stayed between roughly 5.7K and 7.5K a month.
- **Geography:** Sao Paulo gives 37.4% of revenue. SP, RJ and MG together give 62.5%.
- **Categories:** no single category dominates. The top 3 (health_beauty, watches_gifts, bed_bath_table) give 25.1% of revenue across 72 categories.
- **Reviews:** polarised. 57.9% give 5 stars, but 11.5% give 1 star.
- **Delivery:** most orders arrive before the estimate, yet 8.11% arrive late. Late rates are highest in AL (23.9%), MA (19.7%) and PI (16.0%).
- **Payments:** credit card is 77.0% of orders (about 3.5 installments on average), boleto 19.9%, voucher 1.6%, debit card 1.5%.

### 7.3 Trends and seasonality

- Nov 2017 (Black Friday) ran **26.8% above** its 3-month trend. Jan 2018 was +10.9%.
- Monday is the busiest day. Saturday is about 33% lower.
- Buying peaks between 10am and 4pm and again around 8-9pm.

### 7.4 Diagnostic analysis

- **Late delivery vs reviews:** on-time orders average 4.30 stars, late orders 2.57 (Welch t-test, p < 0.001). 54% of late orders get 1-2 stars vs 9% of on-time orders. Late orders are 8% of reviewed deliveries but 34% of all 1-2 star reviews.
- **Peak months:** the monthly late rate hit 14.3% (Nov 2017), 16.0% (Feb 2018) and 21.4% (Mar 2018), matching dips in review scores (correlation -0.78).
- **States:** the lowest scores are in MA (3.83), AL (3.86), SE (3.91) and PA (3.91). PA scores 0.21 stars below what its delivery delay predicts.
- **One-time vs repeat customers:** their first orders look almost the same (4.08 vs 4.15 stars). A bad first order is not the main reason customers do not return.
- **Installments:** average order value rises with installments (R$121 at 1x, R$211 at 6x, R$416 at 10x), and cancellation stays below 1%.

### 7.5 Customer analytics

- **RFM:** revenue share simply tracks customer share. Only 135 customers (0.1%) are "Champions". The biggest pool to convert is New/Promising (38,200 customers).
- **Customer lifetime value:** average R$164.88, median R$107.28. The top 10% of customers give 38.5% of revenue and the top 20% give 53.8%. Repeat customers average R$308 vs R$160 for one-time buyers (about 1.9x).
- **Cohort retention:** only about 0.51% of customers order again in month 1, falling to about 0.23% by month 6.
- **K-Means (4 clusters on recency, frequency, order value):** a small high-value group of 2,684 customers averages R$1,115 per order (about 8x a typical order). The rest are recent one-timers (51,767), dormant one-timers (37,996) and repeat buyers (2,973).
- **Voucher use:** voucher users repeat at 9.0% vs 3.0% for others. This is an association, not proof of cause, so a controlled test is needed.

### 7.6 Product and category analysis

- watches_gifts is high-value (about R$201 per item). bed_bath_table has the most orders (9,311) but the lowest review of the top 10 categories (3.99).
- Category review scores differ by only about 0.2 stars, far less than the 1.7-star gap between late and on-time delivery.
- Freight is heavy in some high-volume categories: electronics (68% of item price, 2,550 orders) and telephony (51%, 4,199 orders). Across all categories the link between freight ratio and volume is weak (Spearman -0.08).

### 7.7 Other analyses

- **Pareto:** 7 of 27 states generate 80.9% of revenue.
- **Correlation with review score:** delivery delay is the strongest (-0.27). Items per order (-0.12) and freight (-0.09) are weak. Order value and installments are near zero.

---

## 8. Predictive model: low-review risk

**Goal:** flag orders likely to receive a 1-2 star review.

- **Target:** review score of 1-2 (about 14.5% of orders, so classes are imbalanced).
- **Features:** total price, freight, item count, installments, delivery delay, order month, day of week, price per item, freight ratio, product category (top 10 + other) and payment type.
- **Split:** 80/20 stratified, `random_state=42`.
- **Trials:** logistic regression baseline, balanced logistic regression, random forest, and a random forest tuned with GridSearchCV (scored on recall, 3-fold).

| Model | Accuracy | Precision | Recall | F1 | ROC-AUC |
|---|---|---|---|---|---|
| Logistic Regression baseline | 0.877 | 0.620 | 0.080 | 0.140 | - |
| Logistic Regression (balanced) | 0.726 | 0.251 | 0.584 | 0.351 | 0.714 |
| Random Forest baseline | 0.890 | 0.700 | 0.250 | 0.370 | 0.735 |
| **Random Forest (tuned, final)** | 0.848 | 0.416 | 0.500 | 0.454 | 0.738 |

- **Final model:** random forest, 400 trees, max depth 10, min samples per leaf 5.
- **Why this model:** best balance of precision, F1 and ROC-AUC. Logistic regression has higher recall but many more false alarms.
- **Accuracy trap:** the first baseline reaches 87.7% accuracy but only 8% recall.
- **Top driver:** delivery delay (60% of feature importance), then item count (10.5%) and freight (7.7%).

**Limitations:** delivery delay is only known after delivery, so scoring in-flight orders needs a projected delay. The split is random, not time-based.

---

## 9. Recommendations

1. **Fix the delivery promise:** realistic estimates, proactive delay alerts, more carrier capacity in peak months, and a carrier review in MA, AL, SE and PA.
2. **Build a 30-day retention journey** after the first order, since month-1 repeat is only about 0.5%.
3. **Win back high-value one-timers** (2,684 customers) with a personalised offer.
4. **Send a second-purchase offer** to New/Promising customers within 90 days.
5. **Focus regional spend** on the top 7 states.
6. **Plan for November:** campaign, stock and carrier capacity 4-6 weeks ahead.
7. **A/B test vouchers** on first-time buyers before scaling.
8. **Test free-shipping thresholds** in electronics and telephony, and investigate quality in bed_bath_table.
9. **Pilot the risk model** on in-flight orders with service outreach and a control group.

---

## 10. Limitations and next steps

**Limitations**
- No cost or ad-spend data, so category ROI and profit-based lifetime value cannot be measured.
- Observational data: voucher and retention results are associations, not proof of cause.
- No refund data: revenue includes all order statuses.
- One marketplace over about 2 years: seasonality rests on a single Black Friday.

**Next steps**
- Repeat-purchase (churn) model.
- Late-delivery prediction from pre-delivery features.
- Seller and carrier analysis, and review-text mining (comments are in Portuguese).
- Controlled experiments for retention offers and vouchers.
