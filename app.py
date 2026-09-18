"""
Olist Marketing Analytics - Streamlit app
Pages: Descriptive, Diagnostic, Predictive
Data comes from Snowflake. The prediction model is loaded from low_review_model.pkl
"""

from pathlib import Path

import streamlit as st
import joblib
import numpy as np
import pandas as pd
import plotly.express as px
import snowflake.connector
import streamlit as st
from scipy import stats
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

st.set_page_config(page_title="Olist Marketing Analytics", layout="wide")

APP_DIR = Path(__file__).resolve().parent
CUTOFF = "2018-09-01" 



USERNAME = "binal_06"       
PASSWORD = "olist_2018"     

if "logged_in" not in st.session_state:
    st.session_state.logged_in = False

if not st.session_state.logged_in:
    st.title("Project Dashboard Login")
    st.subheader("Please log in to review the model")

    username_input = st.text_input("Username")
    password_input = st.text_input("Password", type="password")

    if st.button("Log in"):
        if username_input == USERNAME and password_input == PASSWORD:
            st.session_state.logged_in = True
            st.rerun()
        else:
            st.error("Incorrect username or password.")

    st.stop() 
@st.cache_resource
def get_connection():
    s = st.secrets["snowflake"]
    return snowflake.connector.connect(
        user=s["user"],
        password=s["password"],
        account=s["account"],
        warehouse=s["warehouse"],
        database=s["database"],
        schema=s["schema"],
    )


def run_query(sql):
    conn = get_connection()
    if conn.is_closed():  # reconnect if the cached connection expired
        get_connection.clear()
        conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql)
    df = cur.fetch_pandas_all()
    cur.close()
    df.columns = [c.lower() for c in df.columns]
    return df


# One row per order. Same logic as the base table in the marketing notebook:
# first item -> category, first payment -> payment type, max review score per order
BASE_SQL = f"""
WITH items_agg AS (
    SELECT order_id, SUM(price) AS total_price, SUM(freight_value) AS total_freight,
           COUNT(order_item_id) AS n_items
    FROM ORDER_ITEMS GROUP BY order_id
),
first_item AS (
    SELECT order_id, product_id FROM (
        SELECT order_id, product_id,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY order_item_id) AS rn
        FROM ORDER_ITEMS
    ) WHERE rn = 1
),
pay_agg AS (
    SELECT order_id, SUM(payment_value) AS total_payment, MAX(payment_installments) AS max_installments
    FROM PAYMENTS GROUP BY order_id
),
pay_type AS (
    SELECT order_id, payment_type FROM (
        SELECT order_id, payment_type,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY payment_sequential) AS rn
        FROM PAYMENTS
    ) WHERE rn = 1
),
rev_agg AS (
    SELECT order_id, MAX(review_score) AS review_score FROM REVIEWS GROUP BY order_id
)
SELECT o.order_id, o.customer_id, c.customer_unique_id, c.customer_city, c.customer_state,
       o.order_status, o.order_purchase_timestamp, o.order_delivered_customer_date,
       o.order_estimated_delivery_date, ia.total_price, ia.total_freight, ia.n_items,
       CASE WHEN fi.product_id IS NULL THEN NULL
            ELSE COALESCE(ct.product_category_name_english, 'Uncategorized') END AS product_category_name_english,
       pa.total_payment, pa.max_installments, pt.payment_type, ra.review_score
FROM ORDERS o
LEFT JOIN CUSTOMERS c ON o.customer_id = c.customer_id
LEFT JOIN items_agg ia ON o.order_id = ia.order_id
LEFT JOIN first_item fi ON o.order_id = fi.order_id
LEFT JOIN PRODUCTS p ON fi.product_id = p.product_id
LEFT JOIN CATEGORY_TRANSLATION ct ON p.product_category_name = ct.product_category_name
LEFT JOIN pay_agg pa ON o.order_id = pa.order_id
LEFT JOIN pay_type pt ON o.order_id = pt.order_id
LEFT JOIN rev_agg ra ON o.order_id = ra.order_id
WHERE o.order_purchase_timestamp < '{CUTOFF}'
"""

# one row per order item (used for the freight ratio analysis)
ITEMS_SQL = f"""
SELECT oi.order_id, oi.price, oi.freight_value,
       COALESCE(ct.product_category_name_english, 'Uncategorized') AS category
FROM ORDER_ITEMS oi
JOIN ORDERS o ON oi.order_id = o.order_id
LEFT JOIN PRODUCTS p ON oi.product_id = p.product_id
LEFT JOIN CATEGORY_TRANSLATION ct ON p.product_category_name = ct.product_category_name
WHERE o.order_purchase_timestamp < '{CUTOFF}'
"""


@st.cache_data(ttl=3600, show_spinner="Loading data from Snowflake...")
def load_base():
    df = run_query(BASE_SQL)

    for col in ["order_purchase_timestamp", "order_delivered_customer_date", "order_estimated_delivery_date"]:
        df[col] = pd.to_datetime(df[col])
    for col in ["total_price", "total_freight", "n_items", "total_payment", "max_installments", "review_score"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df["order_revenue"] = df["total_price"] + df["total_freight"]

    # delivery columns only make sense for orders that were delivered
    df["is_delivered"] = df["order_delivered_customer_date"].notna()
    df["delivery_delay_days"] = (df["order_delivered_customer_date"] - df["order_estimated_delivery_date"]).dt.days
    late = (df["order_delivered_customer_date"] > df["order_estimated_delivery_date"]).astype(float)
    df["is_late"] = np.where(df["is_delivered"], late, np.nan)

    # low review = 1 or 2 stars, only for orders that have a review
    df["is_low_review"] = np.where(df["review_score"].notna(), (df["review_score"] <= 2).astype(float), np.nan)

    ts = df["order_purchase_timestamp"]
    df["order_month"] = ts.dt.to_period("M").dt.to_timestamp()
    df["order_month_num"] = ts.dt.month
    df["order_dow_num"] = ts.dt.dayofweek
    df["order_dow"] = ts.dt.day_name()
    return df


@st.cache_data(ttl=3600, show_spinner="Loading item data from Snowflake...")
def load_items():
    df = run_query(ITEMS_SQL)
    df["price"] = pd.to_numeric(df["price"], errors="coerce")
    df["freight_value"] = pd.to_numeric(df["freight_value"], errors="coerce")
    return df


# ------------------------------------------------------------
# Page 1: Descriptive analysis
# ------------------------------------------------------------
def descriptive_page(df):
    st.title("Descriptive Analysis")
    st.caption(
        f"{len(df):,} orders from {df['order_purchase_timestamp'].min():%b %Y} "
        f"to {df['order_purchase_timestamp'].max():%b %Y}. All amounts are in R$."
    )

    # ---- KPI calculations ----
    orders_per_customer = df.groupby("customer_unique_id")["order_id"].count()
    delivered = df[df["is_delivered"]]
    reviewed = df[df["review_score"].notna()]
    total_revenue = df["order_revenue"].sum()

    repeat_rate = (orders_per_customer > 1).mean() * 100
    on_time_rate = (delivered["is_late"] == 0).mean() * 100
    late_rate = delivered["is_late"].mean() * 100
    low_review_rate = reviewed["is_low_review"].mean() * 100
    aov = total_revenue / df["order_revenue"].notna().sum()  # orders that have items
    avg_delay = delivered["delivery_delay_days"].mean()
    avg_review = reviewed["review_score"].mean()
    delivered_pct = (df["order_status"] == "delivered").mean() * 100
    cancel_pct = (df["order_status"] == "canceled").mean() * 100

    st.subheader("KPIs")
    row1 = st.columns(4)
    row1[0].metric("Repeat Customer Rate", f"{repeat_rate:.2f}%")
    row1[1].metric("On-Time Delivery Rate", f"{on_time_rate:.2f}%")
    row1[2].metric("% 1-2 Star Reviews", f"{low_review_rate:.2f}%")
    row1[3].metric("Average Order Value", f"R${aov:,.2f}")

    row2 = st.columns(4)
    row2[0].metric("Total Revenue", f"R${total_revenue / 1e6:.2f}M")
    row2[1].metric("Total Orders", f"{len(df):,}")
    row2[2].metric("Unique Customers", f"{len(orders_per_customer):,}")
    row2[3].metric("Average Review Score", f"{avg_review:.2f}")

    row3 = st.columns(4)
    row3[0].metric("Avg Delivery Delay (days)", f"{avg_delay:.2f}")
    row3[1].metric("Late Delivery Rate", f"{late_rate:.2f}%")
    row3[2].metric("Orders Delivered", f"{delivered_pct:.2f}%")
    row3[3].metric("Cancellation Rate", f"{cancel_pct:.2f}%")

    with st.expander("How the KPIs are calculated"):
        st.write(
            "- Repeat rate: customers with 2 or more orders / all unique customers.\n"
            "- On-time and late rate: based on delivered orders only.\n"
            "- % 1-2 star reviews: based on orders that have a review.\n"
            "- Average order value: total revenue (price + freight) / orders that have items.\n"
            "- Avg delivery delay: delivered date minus estimated date (negative means early).\n"
            f"- Orders from {CUTOFF} onwards are excluded because that period is incomplete."
        )

    st.divider()
    tabs = st.tabs(["Sales", "Time", "Geography", "Products", "Reviews", "Delivery", "Payments"])

    # ---- sales by order status ----
    with tabs[0]:
        st.subheader("Sales and Revenue by Order Status")
        status = (df.groupby("order_status")
                  .agg(orders=("order_id", "count"), revenue=("order_revenue", "sum"),
                       avg_order_value=("order_revenue", "mean"))
                  .sort_values("revenue", ascending=False).round(2))
        st.dataframe(status)
        st.plotly_chart(px.bar(status.reset_index(), x="order_status", y="revenue", title="Revenue by order status"))
        share = status.loc["delivered", "orders"] / status["orders"].sum() * 100
        st.write(f"Insight: {share:.1f}% of orders reached delivered status.")

    # ---- time patterns ----
    with tabs[1]:
        st.subheader("Orders and Revenue by Month")
        monthly = (df.groupby("order_month")
                   .agg(orders=("order_id", "count"), revenue=("order_revenue", "sum")).reset_index())
        st.plotly_chart(px.line(monthly, x="order_month", y="orders", markers=True, title="Orders by month"))
        st.plotly_chart(px.line(monthly, x="order_month", y="revenue", markers=True, title="Revenue by month"))
        peak = monthly.loc[monthly["orders"].idxmax()]
        st.write(f"Insight: the busiest month is {peak['order_month']:%B %Y} with {int(peak['orders']):,} orders.")

        st.subheader("Orders by Day of Week")
        days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        dow = df.groupby("order_dow")["order_id"].count().reindex(days).reset_index()
        dow.columns = ["day", "orders"]
        st.plotly_chart(px.bar(dow, x="day", y="orders"))

    # ---- geography ----
    with tabs[2]:
        st.subheader("Revenue by State")
        geo = (df.groupby("customer_state")
               .agg(customers=("customer_unique_id", "nunique"), orders=("order_id", "count"),
                    revenue=("order_revenue", "sum"), avg_order_value=("order_revenue", "mean"))
               .sort_values("revenue", ascending=False).round(2))
        st.plotly_chart(px.bar(geo.head(10).reset_index(), x="customer_state", y="revenue", title="Top 10 states by revenue"))
        st.dataframe(geo)
        st.write(f"Insight: {geo.index[0]} alone gives {geo['revenue'].iloc[0] / geo['revenue'].sum() * 100:.1f}% of total revenue.")

    # ---- products ----
    with tabs[3]:
        st.subheader("Top 10 Categories by Revenue")
        cats = (df.groupby("product_category_name_english")
                .agg(orders=("order_id", "count"), revenue=("order_revenue", "sum"))
                .sort_values("revenue", ascending=False).round(2))
        top = cats.head(10).reset_index()
        st.plotly_chart(px.bar(top, x="revenue", y="product_category_name_english", orientation="h")
                        .update_layout(yaxis=dict(autorange="reversed")))
        st.dataframe(cats.head(10))
        st.caption("Each order's revenue is counted under the category of its first item.")

    # ---- reviews ----
    with tabs[4]:
        st.subheader("Review Score Distribution")
        dist = (df["review_score"].value_counts(normalize=True).sort_index() * 100).round(2).reset_index()
        dist.columns = ["review_score", "percent"]
        st.plotly_chart(px.bar(dist, x="review_score", y="percent", title="% of reviews by score"))
        st.write(f"Insight: average score is {avg_review:.2f} but {low_review_rate:.1f}% of reviews are 1 or 2 stars.")

    # ---- delivery ----
    with tabs[5]:
        st.subheader("Delivery Delay")
        delays = delivered["delivery_delay_days"].dropna()
        shown = delays[(delays >= -60) & (delays <= 40)]
        fig = px.histogram(shown, nbins=60, title="Delivery delay in days (negative = early)")
        fig.add_vline(x=0, line_dash="dash", line_color="red")
        st.plotly_chart(fig)
        st.caption(f"{len(delays) - len(shown):,} extreme values outside -60 to 40 days are not shown.")
        st.write(f"Insight: orders arrive {abs(avg_delay):.1f} days earlier than estimated on average, "
                 f"but {late_rate:.1f}% of delivered orders are late.")

    # ---- payments ----
    with tabs[6]:
        st.subheader("Payment Type")
        mix = df["payment_type"].value_counts(normalize=True).mul(100).round(2).reset_index()
        mix.columns = ["payment_type", "percent"]
        st.plotly_chart(px.pie(mix, names="payment_type", values="percent", title="Payment type mix"))
        pay = (df.groupby("payment_type")
               .agg(orders=("order_id", "count"), avg_installments=("max_installments", "mean"),
                    avg_payment=("total_payment", "mean")).round(2))
        st.dataframe(pay)
        st.caption("Payment type is the type of the first payment on the order.")


# ------------------------------------------------------------
# Page 2: Diagnostic analysis
# ------------------------------------------------------------
@st.cache_data(ttl=3600, show_spinner=False)
def run_kmeans():
    df = load_base()
    snapshot = df["order_purchase_timestamp"].max()
    rfm = (df.groupby("customer_unique_id")
           .agg(last_order=("order_purchase_timestamp", "max"), frequency=("order_id", "count"),
                monetary=("order_revenue", "mean")).dropna())
    rfm["recency_days"] = (snapshot - rfm["last_order"]).dt.days
    rfm = rfm[["recency_days", "frequency", "monetary"]]

    scaled = StandardScaler().fit_transform(rfm)
    rfm["cluster"] = KMeans(n_clusters=4, random_state=42, n_init=10).fit_predict(scaled)
    summary = rfm.groupby("cluster").agg(customers=("recency_days", "count"), avg_recency=("recency_days", "mean"),
                                         avg_frequency=("frequency", "mean"), avg_monetary=("monetary", "mean"))

    # cluster numbers are random, so give each cluster a name from its values
    names = {}
    high_value = summary["avg_monetary"].idxmax()
    names[high_value] = "High value buyers"
    rest = summary.drop(index=high_value)
    repeat = rest["avg_frequency"].idxmax()
    names[repeat] = "Repeat buyers"
    rest = rest.drop(index=repeat)
    if len(rest) == 2:
        names[rest["avg_recency"].idxmax()] = "Dormant one-time buyers"
        names[rest["avg_recency"].idxmin()] = "Recent one-time buyers"
    else:
        for c in rest.index:
            names[c] = f"Cluster {c}"
    rfm["segment"] = rfm["cluster"].map(names)
    summary.insert(0, "segment", summary.index.map(names))
    return summary.sort_values("customers", ascending=False).round(2), rfm.sample(min(5000, len(rfm)), random_state=42)


def diagnostic_page(df):
    st.title("Diagnostic Analysis")
    options = [
        "1. Late delivery vs review score",
        "2. Category volume vs satisfaction",
        "3. State satisfaction",
        "4. One-time vs repeat customers",
        "5. Installments vs order value and cancellation",
        "6. Freight ratio by category"
       
    ]
    choice = st.selectbox("Choose an analysis", options)
    st.divider()

    # ---- 1. late delivery vs review ----
    if choice == options[0]:
        st.subheader("Does late delivery hurt review scores?")
        d = df[df["is_delivered"] & df["review_score"].notna()].copy()
        d["delivery_status"] = np.where(d["is_late"] == 1, "Late", "On-Time")
        res = (d.groupby("delivery_status")
               .agg(avg_score=("review_score", "mean"), orders=("review_score", "count"),
                    low_review_pct=("is_low_review", "mean")).reindex(["On-Time", "Late"]))
        res["low_review_pct"] = res["low_review_pct"] * 100

        late_scores = d.loc[d["is_late"] == 1, "review_score"]
        ontime_scores = d.loc[d["is_late"] == 0, "review_score"]
        t_stat, p_value = stats.ttest_ind(late_scores, ontime_scores, equal_var=False)

        st.dataframe(res.round(2))
        fig = px.bar(res.reset_index(), x="delivery_status", y="avg_score", color="delivery_status",
                     color_discrete_map={"On-Time": "green", "Late": "red"}, title="Average review score")
        st.plotly_chart(fig)
        gap = res.loc["On-Time", "avg_score"] - res.loc["Late", "avg_score"]
        p_text = "< 0.001" if p_value < 0.001 else f"{p_value:.3f}"
        st.write(f"Insight: on-time orders score {res.loc['On-Time', 'avg_score']:.2f} and late orders score "
                 f"{res.loc['Late', 'avg_score']:.2f}, a gap of {gap:.2f}. Welch t-test p-value: {p_text}.")

    # ---- 2. category quality ----
    elif choice == options[1]:
        st.subheader("Top 15 categories by volume: order count vs average review score")
        r = df.dropna(subset=["review_score", "product_category_name_english"])
        c2 = (r.groupby("product_category_name_english")
              .agg(orders=("order_id", "count"), avg_score=("review_score", "mean"))
              .sort_values("orders", ascending=False).head(15).round(3))
        st.plotly_chart(px.scatter(c2.reset_index(), x="orders", y="avg_score", text="product_category_name_english"))
        st.dataframe(c2)
        worst = c2["avg_score"].idxmin()
        st.write(f"Insight: {worst} has the lowest average score ({c2.loc[worst, 'avg_score']:.2f}) "
                 f"among these top categories, with {int(c2.loc[worst, 'orders']):,} orders.")

    # ---- 3. state satisfaction ----
    elif choice == options[2]:
        st.subheader("Which states have low satisfaction? (states with more than 200 orders)")
        s = (df.dropna(subset=["review_score", "delivery_delay_days"]).groupby("customer_state")
             .agg(avg_delay=("delivery_delay_days", "mean"), avg_score=("review_score", "mean"),
                  orders=("order_id", "count")))
        s = s[s["orders"] > 200].sort_values("avg_score").round(3)
        st.plotly_chart(px.bar(s.head(10).reset_index(), x="avg_score", y="customer_state", orientation="h",
                               title="10 lowest states by average review score")
                        .update_layout(yaxis=dict(autorange="reversed")))
        st.plotly_chart(px.scatter(s.reset_index(), x="avg_delay", y="avg_score", text="customer_state", size="orders",
                                   title="Average delay vs average score"))
        st.dataframe(s)
        st.write(f"Insight: {s.index[0]} has the lowest score ({s['avg_score'].iloc[0]:.2f}). "
                 "Delay does not fully explain the differences between states.")

    # ---- 4. one-time vs repeat ----
    elif choice == options[3]:
        st.subheader("Why do customers not place a second order?")
        counts = df.groupby("customer_unique_id")["order_id"].count().rename("order_count")
        first = (df.sort_values("order_purchase_timestamp").drop_duplicates("customer_unique_id")
                 .merge(counts, left_on="customer_unique_id", right_index=True))
        first["customer_type"] = np.where(first["order_count"] > 1, "Repeat", "One-Time")
        res = (first.groupby("customer_type")
               .agg(customers=("customer_unique_id", "count"), avg_first_review=("review_score", "mean"),
                    avg_first_delay=("delivery_delay_days", "mean")).round(3))
        st.dataframe(res)
        left, right = st.columns(2)
        left.plotly_chart(px.bar(res.reset_index(), x="customer_type", y="avg_first_review", title="First order review score"))
        right.plotly_chart(px.bar(res.reset_index(), x="customer_type", y="avg_first_delay", title="First order delay (days)"))
        st.write("Insight: repeat customers had a similar (slightly better) first order experience, so a bad first "
                 "order is not the main reason customers leave.")

    # ---- 5. installments ----
    elif choice == options[4]:
        st.subheader("Do installments change order value or cancellation?")
        res = (df.dropna(subset=["max_installments"]).groupby("max_installments")
               .agg(avg_order_value=("order_revenue", "mean"),
                    cancel_rate=("order_status", lambda x: (x == "canceled").mean() * 100),
                    orders=("order_id", "count")))
        res = res[res["orders"] > 50].round(2)
        left, right = st.columns(2)
        left.plotly_chart(px.bar(res.reset_index(), x="max_installments", y="avg_order_value", title="Average order value"))
        right.plotly_chart(px.line(res.reset_index(), x="max_installments", y="cancel_rate", markers=True,
                                   title="Cancellation rate (%)"))
        st.dataframe(res)
        st.write("Insight: order value goes up with more installments, while the cancellation rate stays low.")

    # ---- 6. freight ratio ----
    elif choice == options[5]:
        st.subheader("Freight as a share of item price, by category")
        items = load_items().copy()
        items["freight_ratio"] = items["freight_value"] / items["price"].replace(0, np.nan)
        res = (items.groupby("category")
               .agg(orders=("order_id", "nunique"), avg_freight_ratio=("freight_ratio", "mean")))
        res["avg_freight_pct"] = (res["avg_freight_ratio"] * 100).round(2)
        top = res.sort_values("avg_freight_pct", ascending=False).head(10)
        st.plotly_chart(px.bar(top.reset_index(), x="avg_freight_pct", y="category", orientation="h",
                               title="10 categories with the highest freight ratio (%)")
                        .update_layout(yaxis=dict(autorange="reversed")))
        st.dataframe(top[["orders", "avg_freight_pct"]])
        valid = res.dropna()
        rho, _ = stats.spearmanr(valid["avg_freight_pct"], valid["orders"])
        st.write(f"Insight: correlation between freight ratio and order count across categories is {rho:.2f}. "
                 "Categories with very high freight cost are good candidates for a free shipping offer.")

   


# ------------------------------------------------------------
# Page 3: Predictive analysis
# ------------------------------------------------------------
# results copied from the predictive modeling notebook (test set)
MODEL_RESULTS = pd.DataFrame(
    {
        "Model": ["Logistic Regression (baseline)", "Logistic Regression (balanced)",
                  "Random Forest (baseline)", "Random Forest (tuned, used in app)"],
        "Accuracy": [0.877, 0.726, 0.89, 0.848],
        "Precision": [0.62, 0.251, 0.70, 0.416],
        "Recall": [0.08, 0.584, 0.25, 0.500],
        "F1": [0.14, 0.351, 0.37, 0.454],
        "ROC-AUC": [None, 0.714, 0.735, 0.738],
    }
)

# get_dummies(drop_first=True) removed one category and one payment type from the feature list,
# so they are added back here (all their dummy columns stay 0)
KNOWN_CATEGORIES = ["auto", "bed_bath_table", "computers_accessories", "furniture_decor", "health_beauty",
                    "housewares", "sports_leisure", "telephony", "toys", "watches_gifts", "other"]
KNOWN_PAYMENTS = ["boleto", "credit_card", "debit_card", "not_defined", "voucher"]
MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


@st.cache_resource
def load_model():
    model_file = APP_DIR / "low_review_model.pkl"
    feature_file = APP_DIR / "model_features.pkl"
    if not (model_file.exists() and feature_file.exists()):
        return None, None
    return joblib.load(model_file), list(joblib.load(feature_file))


def get_options(feature_names, prefix, known):
    present = sorted(c[len(prefix):] for c in feature_names if c.startswith(prefix))
    missing = [k for k in known if k not in present and k < present[0]]
    return sorted(present + (missing if len(missing) == 1 else []))


def predictive_page(df):
    st.title("Predictive Analysis: Low Review Risk")
    st.write("This page predicts the probability that an order gets a 1-2 star review.")

    model, feature_names = load_model()
    if model is None:
        st.error("low_review_model.pkl and model_features.pkl were not found in the app folder.")
        return

    st.subheader("Enter order details")
    categories = get_options(feature_names, "category_grouped_", KNOWN_CATEGORIES)
    payments = get_options(feature_names, "payment_type_", KNOWN_PAYMENTS)

    col1, col2 = st.columns(2)
    with col1:
        total_price = st.number_input("Order total price (R$)", min_value=1.0, value=120.0)
        total_freight = st.number_input("Freight value (R$)", min_value=0.0, value=20.0)
        n_items = st.number_input("Number of items", min_value=1, value=1, step=1)
        installments = st.number_input("Payment installments", min_value=1, value=1, step=1)
    with col2:
        delay = st.slider("Delivery delay in days (negative = early)", -60, 60, -10)
        month = st.selectbox("Order month", list(range(1, 13)), index=5, format_func=lambda m: MONTHS[m - 1])
        dow = st.selectbox("Order day of week", list(range(7)), index=2, format_func=lambda d: DAYS[d])
        category = st.selectbox("Product category", categories)
        payment_type = st.selectbox("Payment type", payments)
    st.caption("Delivery delay is only known after delivery. For orders in transit use the expected delay.")

    if st.button("Predict"):
        # one row with all model columns set to 0, then fill in the inputs
        row = pd.DataFrame(np.zeros((1, len(feature_names))), columns=feature_names)
        row.loc[0, "total_price"] = total_price
        row.loc[0, "total_freight"] = total_freight
        row.loc[0, "n_items"] = n_items
        row.loc[0, "max_installments"] = installments
        row.loc[0, "delivery_delay_days"] = delay
        row.loc[0, "order_month_num"] = month
        row.loc[0, "order_dow_num"] = dow
        row.loc[0, "price_per_item"] = total_price / n_items
        row.loc[0, "freight_ratio"] = total_freight / total_price
        for col in [f"category_grouped_{category}", f"payment_type_{payment_type}"]:
            if col in row.columns:
                row.loc[0, col] = 1

        probability = model.predict_proba(row)[0, 1]
        st.metric("Probability of a 1-2 star review", f"{probability * 100:.1f}%")
        if probability >= 0.5:
            st.error("At risk: this order is likely to get a low review.")
        else:
            st.success("Low risk: this order is likely to get a review of 3 stars or more.")

    st.divider()
    st.subheader("Model results (test set)")
    st.dataframe(MODEL_RESULTS.set_index("Model"))
    st.write("Only about 14.5% of orders get a low review, so accuracy alone is not a good measure. "
             "Recall on the low review class was used to choose the final model (tuned Random Forest).")

    if hasattr(model, "feature_importances_"):
        imp = pd.Series(model.feature_importances_, index=feature_names).sort_values(ascending=False).head(10)
        imp = imp.rename_axis("feature").reset_index(name="importance")
        st.plotly_chart(px.bar(imp, x="importance", y="feature", orientation="h", title="Top 10 feature importances")
                        .update_layout(yaxis=dict(autorange="reversed")))


# ------------------------------------------------------------
# Navigation
# ------------------------------------------------------------
st.sidebar.title("Olist Marketing Analytics")
page = st.sidebar.radio("Go to", ["Descriptive", "Diagnostic", "Predictive"])
if st.sidebar.button("Refresh data"):
    st.cache_data.clear()
    st.rerun()

try:
    data = load_base()
except Exception as e:
    st.error("Could not load data from Snowflake. Check .streamlit/secrets.toml and the table names.")
    st.exception(e)
    st.stop()

if page == "Descriptive":
    descriptive_page(data)
elif page == "Diagnostic":
    diagnostic_page(data)
else:
    predictive_page(data)
