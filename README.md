

Readme · MD
Olist Marketing Analytics
End-to-end marketing analytics on the Olist Brazilian E-Commerce dataset: SQL data audit and KPI views, Python EDA and customer analytics, a low-review risk model, Power BI dashboards and a Streamlit app.

Live app: https://olist-marketing-analysis-advwt8s7acuzbkhi4rk86p.streamlit.app/

Business problem
Olist is a marketplace with strong operations but very few repeat customers. This project answers three questions for the marketing team:

Where does revenue come from, and how is the business trending?
Why do customers leave unhappy or never come back?
Which orders are likely to get a bad review, so service can step in early?
Dataset
Olist Brazilian E-Commerce (Kaggle): 7 CSV files, about 99K orders and 547K records in total, Sep 2016 to Oct 2018.

Analysis window: orders placed before 1 Sep 2018. The last 20 orders (Sep and Oct 2018) are dropped because that period is incomplete. This leaves 99,421 orders.

Tech stack
Layer	Tool
Data warehouse	SQL (Snowflake)
Analysis and modelling	Python (Jupyter / Databricks): pandas, scipy, scikit-learn
Dashboards	Power BI (4 pages)
Web app	Streamlit + Plotly
Repository structure
Adjust the paths below to match your repo.

.
├── sql/
│   └── olist_data_audit_check.sql        # schema, data-quality audit, cleaning, KPI/KRI views, analysis queries
├── notebooks/
│   ├── Olist_Marketing_Analysis.ipynb    # EDA, diagnostic and customer analytics
│   └── Olist_predictive_modeling.ipynb   # low-review risk model
├── app/
│   ├── app.py                            # Streamlit app
│   ├── requirements.txt
│   ├── low_review_model.pkl              # trained model
│   └── model_features.pkl                # feature list used by the model
├── presentation/
│   └── olist_analysis_final_deliverable.pptx
└── README.md
What is in the analysis
Data audit (SQL): key uniqueness, foreign keys, nulls, ranges, chronology and amount reconciliation. Issues are flagged, not deleted.
Descriptive: KPIs, order status, monthly trend, geography, categories, reviews, delivery, payments.
Seasonality: holiday spike detection, day of week and hour of day.
Diagnostic: late delivery vs reviews, state satisfaction, one-time vs repeat customers, installments, freight ratio.
Customer analytics: RFM segments, customer lifetime value, cohort retention, K-Means clusters, voucher vs repeat purchase.
Other: revenue concentration (Pareto) and correlation with review score.
Predictive: model that flags orders likely to get a 1-2 star review.
Key findings
Metric	Value
Revenue (price + freight)	R$15.84M
Orders / unique customers	99,421 / 96,090
Average order value	R$160.58
Repeat customer rate	3.11%
On-time delivery	91.89%
1-2 star reviews	14.62%
Average review score	4.09
Revenue is concentrated: Sao Paulo gives 37.4% of revenue, and 7 of 27 states give 80.9%.
Retention is the biggest gap: only about 0.5% of customers order again in the month after their first order.
Repeat customers are worth about 1.9x more (R$308 vs R$160 lifetime revenue).
Delivery drives satisfaction: late orders average 2.57 stars vs 4.30 for on-time orders, and 54% of late orders get 1-2 stars vs 9%.
Peak months strain logistics: the late rate reached 14.3% (Nov 2017), 16.0% (Feb 2018) and 21.4% (Mar 2018), matching dips in review scores.
Voucher users repeat at 9.0% vs 3.0%. This is an association, not proof of cause.
Predictive model
Target: review score of 1-2 stars (base rate about 14.5% of orders).
Split: 80/20 stratified, random_state=42.
Models tried: logistic regression baseline, balanced logistic regression, random forest, tuned random forest (GridSearchCV, scored on recall, 3-fold).
Final model: random forest, 400 trees, max depth 10, min samples per leaf 5.
Model	Precision	Recall	F1	ROC-AUC
Logistic Regression (balanced)	0.251	0.584	0.351	0.714
Random Forest (tuned, final)	0.416	0.500	0.454	0.738
Delivery delay is the strongest driver (60% of feature importance).

Limitations: delivery delay is only known after delivery, so scoring in-flight orders needs a projected delay. The split is random, not time-based.

Metric definitions
Revenue: item price + freight per order, all order statuses.
AOV: revenue divided by orders that contain at least one item.
Repeat rate: customers with 2+ orders divided by unique customers (customer_unique_id).
On-time / late rate: delivered orders only; late means delivered after the estimated date.
1-2 star rate: reviews of 1-2 stars divided by orders with a review.
Category: category of the first item in the order.
Run the Streamlit app locally
Install dependencies:
   pip install -r requirements.txt
Use the same scikit-learn version the model was trained with (for example scikit-learn==1.6.1).

Create .streamlit/secrets.toml with your Snowflake details:
toml
   [snowflake]
   user = "..."
   password = "..."
   account = "..."
   warehouse = "..."
   database = "..."
   schema = "..."
Do not commit this file.

Make sure the 7 Olist tables exist in Snowflake (created by the SQL script) and that low_review_model.pkl and model_features.pkl are in the same folder as app.py.
Start the app:
   streamlit run app.py
The app has three pages: Descriptive (12 KPIs and 7 tabs), Diagnostic (14 analyses in a dropdown) and Predictive (enter order details, get the risk of a 1-2 star review).

How to reproduce
Download the dataset from Kaggle and load the 7 CSVs into Snowflake using olist_data_audit_check.sql (Sections 1-2).
Run the audit, cleaning and views (Sections 3-5, A-D) in the same script.
Run Olist_Marketing_Analysis.ipynb, then Olist_predictive_modeling.ipynb. The second notebook saves the model files.
Start the Streamlit app.
Author
Binal Desai










