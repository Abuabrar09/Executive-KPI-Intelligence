"""
01_kpi_charts.py
Builds 6 executive charts from the star schema in kpi.duckdb
(run sql/02_build_model.sql first).
"""
import duckdb
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mtick
from pathlib import Path

COMMISSION = 0.10   # assumption: Olist earns 10% of product price
PAY_FEE = 0.025     # assumption: card processing costs 2.5% of order value

Path("images").mkdir(exist_ok=True)
con = duckdb.connect("kpi.duckdb", read_only=True)

def q(sql):
    return con.sql(sql).df()

BLUE, ORANGE, RED, GREY, LIGHT = "#2a78d6", "#eb6834", "#d03b3b", "#52514e", "#b7b5ad"
plt.rcParams.update({
    "figure.facecolor": "#fcfcfb", "axes.facecolor": "#fcfcfb",
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": "#ebeae6", "axes.axisbelow": True,
    "axes.titlelocation": "left", "axes.titleweight": "bold", "axes.titlesize": 13,
    "xtick.color": GREY, "ytick.color": GREY,
    "text.parse_math": False,   # print "R$" as plain text
})
pct = mtick.PercentFormatter(decimals=0)

def save(fig, name):
    fig.tight_layout()
    fig.savefig(f"images/{name}", dpi=150)
    plt.close(fig)
    print("Saved images/" + name)

# ---------- Chart 1: growth vs service ----------
m = q("""
    SELECT order_month,
           SUM(gmv) FILTER (WHERE is_cancelled = 0) / 1e6 AS gmv_m,
           100.0 * AVG(on_time)                          AS on_time_pct
    FROM fact_orders WHERE in_scope = 1
    GROUP BY order_month ORDER BY order_month""")
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 6.5), sharex=True,
                               gridspec_kw={"height_ratios": [2, 1]})
ax1.bar(m["order_month"], m["gmv_m"], width=20, color=BLUE)
ax1.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"R${x:,.1f}M"))
ax1.grid(axis="x", visible=False)
ax1.set_ylabel("Monthly GMV", color=GREY)
ax1.set_title("Revenue doubled, then flattened in 2018 while on-time delivery slipped")
ax2.plot(m["order_month"], m["on_time_pct"], color=ORANGE, marker="o", linewidth=2)
ax2.yaxis.set_major_formatter(pct)
ax2.set_ylabel("On-time delivery", color=GREY)
save(fig, "01_growth_and_service.png")

# ---------- Chart 2: late delivery vs reviews ----------
d = q("""
    SELECT CASE on_time WHEN 1 THEN 'On time' ELSE 'Late' END            AS delivery,
           AVG(review_score)                                             AS review,
           100.0 * AVG(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)    AS bad_pct
    FROM fact_orders
    WHERE in_scope = 1 AND is_delivered = 1 AND on_time IS NOT NULL
    GROUP BY 1 ORDER BY 1 DESC""")
ratio = d["bad_pct"].max() / d["bad_pct"].min()
fig, ax = plt.subplots(figsize=(8, 4.2))
bars = ax.bar(d["delivery"], d["bad_pct"], color=[BLUE, RED], width=0.5)
for b, p, r in zip(bars, d["bad_pct"], d["review"]):
    ax.text(b.get_x() + b.get_width() / 2, p + 1, f"{p:.0f}% bad reviews\navg {r:.2f} stars",
            ha="center", va="bottom", fontsize=10, color=GREY)
ax.yaxis.set_major_formatter(pct)
ax.set_ylim(0, d["bad_pct"].max() * 1.35)
ax.grid(axis="x", visible=False)
ax.set_title(f"A late delivery makes a 1-2 star review {ratio:.1f}x more likely")
save(fig, "02_late_delivery_reviews.png")

# ---------- Chart 3: order size vs contribution ----------
b = q(f"""
    SELECT CASE WHEN product_value < 50  THEN 'Under R$50'
                WHEN product_value < 100 THEN 'R$50-100'
                WHEN product_value < 200 THEN 'R$100-200'
                ELSE 'R$200+' END                                AS band,
           MIN(product_value)                                    AS sort_key,
           COUNT(*)                                              AS orders,
           SUM(product_value * {COMMISSION} - gmv * {PAY_FEE})   AS contribution
    FROM fact_orders
    WHERE in_scope = 1 AND is_cancelled = 0 AND items > 0
    GROUP BY 1 ORDER BY sort_key""")
b["orders_pct"] = 100 * b["orders"] / b["orders"].sum()
b["contrib_pct"] = 100 * b["contribution"] / b["contribution"].sum()
x = np.arange(len(b))
fig, ax = plt.subplots(figsize=(9, 4.5))
ax.bar(x - 0.2, b["orders_pct"], 0.4, color=LIGHT, label="Share of orders")
ax.bar(x + 0.2, b["contrib_pct"], 0.4, color=BLUE, label="Share of contribution")
for i in x:
    ax.text(i - 0.2, b["orders_pct"][i] + 1, f"{b['orders_pct'][i]:.0f}%", ha="center", fontsize=9, color=GREY)
    ax.text(i + 0.2, b["contrib_pct"][i] + 1, f"{b['contrib_pct'][i]:.0f}%", ha="center", fontsize=9, color=GREY)
ax.set_xticks(x, b["band"])
ax.yaxis.set_major_formatter(pct)
ax.set_ylim(0, max(b["orders_pct"].max(), b["contrib_pct"].max()) * 1.2)
ax.grid(axis="x", visible=False)
ax.legend(frameon=False)
ax.set_title(f"Orders under R$50 are {b['orders_pct'][0]:.0f}% of volume "
             f"but only {b['contrib_pct'][0]:.0f}% of contribution")
save(fig, "03_order_size_contribution.png")

# ---------- Chart 4: seller concentration ----------
s = q("""
    SELECT SUM(price) AS revenue FROM fact_items
    WHERE in_scope = 1 AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY seller_id ORDER BY revenue DESC""")
cum = (s["revenue"].cumsum() / s["revenue"].sum() * 100).values
share_sellers = np.arange(1, len(s) + 1) / len(s) * 100
top10 = cum[int(len(s) * 0.10) - 1]
fig, ax = plt.subplots(figsize=(8, 4.8))
ax.plot(share_sellers, cum, color=BLUE, linewidth=2.4)
ax.plot([0, 100], [0, 100], color=LIGHT, linestyle="--", linewidth=1)
ax.scatter([10], [top10], color=ORANGE, zorder=3, s=50)
ax.annotate(f"Top 10% of sellers = {top10:.0f}% of revenue", (10, top10),
            xytext=(18, top10 - 12), fontsize=10, color=GREY)
ax.xaxis.set_major_formatter(pct)
ax.yaxis.set_major_formatter(pct)
ax.set_xlabel("Sellers, ranked by revenue", color=GREY)
ax.set_ylabel("Cumulative share of revenue", color=GREY)
ax.set_title(f"Revenue is concentrated: {len(s):,} sellers, a few hundred carry the business")
save(fig, "04_seller_concentration.png")

# ---------- Chart 5: seller growth vs productivity ----------
p = q("""
    SELECT order_month,
           COUNT(DISTINCT seller_id)                     AS sellers,
           SUM(price) / COUNT(DISTINCT seller_id)        AS rev_per_seller
    FROM fact_items
    WHERE in_scope = 1 AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 1 ORDER BY 1""")
growth = p["sellers"].iloc[-1] / p["sellers"].iloc[0]
drop = (p["rev_per_seller"].iloc[-1] / p["rev_per_seller"].max() - 1) * 100
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(11, 6), sharex=True)
ax1.bar(p["order_month"], p["sellers"], width=20, color=LIGHT)
ax1.set_ylabel("Active sellers", color=GREY)
ax1.grid(axis="x", visible=False)
ax1.set_title(f"Active sellers grew {growth:.1f}x, but revenue per seller is {drop:.0f}% below its peak")
ax2.plot(p["order_month"], p["rev_per_seller"], color=ORANGE, marker="o", linewidth=2)
ax2.yaxis.set_major_formatter(mtick.FuncFormatter(lambda x, _: f"R${x:,.0f}"))
ax2.set_ylabel("Revenue per seller", color=GREY)
save(fig, "05_seller_productivity.png")

# ---------- Chart 6: delivery time vs review by state ----------
st = q("""
    SELECT customer_state, COUNT(*) AS orders,
           AVG(delivery_days) AS days, AVG(review_score) AS review
    FROM fact_orders
    WHERE in_scope = 1 AND is_delivered = 1
    GROUP BY 1""")
corr = np.corrcoef(st["days"], st["review"])[0, 1]
fig, ax = plt.subplots(figsize=(10, 5.5))
ax.scatter(st["days"], st["review"], s=st["orders"] / st["orders"].max() * 1500 + 20,
           color=BLUE, alpha=0.5, edgecolor="white")
for r in st.itertuples():
    if r.orders > 1500 or r.days > 20:
        ax.annotate(r.customer_state, (r.days, r.review), ha="center", va="center", fontsize=8)
ax.set_xlabel("Average delivery days", color=GREY)
ax.set_ylabel("Average review score", color=GREY)
ax.set_title(f"Slower states rate lower (correlation {corr:.2f}); bubble size = orders")
save(fig, "06_state_delivery_reviews.png")

print(f"\nLate orders: bad reviews {ratio:.1f}x more likely | Top 10% sellers: {top10:.1f}% of revenue")
print(f"Sellers grew {growth:.1f}x | revenue per seller {drop:.0f}% vs peak | state days-vs-review corr {corr:.2f}")
