"""
02_export_for_powerbi.py
Exports the star schema (Jan 2017 - Aug 2018 only) to one Excel file.
Each sheet is formatted as an Excel table so Power BI can import it.
"""
import duckdb
import pandas as pd
from pathlib import Path
from openpyxl.utils import get_column_letter
from openpyxl.worksheet.table import Table, TableStyleInfo

con = duckdb.connect("kpi.duckdb", read_only=True)

# Brazil's 5 official regions, for the Region > State drill-down
REGIONS = {
    "AC": "North", "AP": "North", "AM": "North", "PA": "North", "RO": "North", "RR": "North", "TO": "North",
    "AL": "Northeast", "BA": "Northeast", "CE": "Northeast", "MA": "Northeast", "PB": "Northeast",
    "PE": "Northeast", "PI": "Northeast", "RN": "Northeast", "SE": "Northeast",
    "DF": "Center-West", "GO": "Center-West", "MT": "Center-West", "MS": "Center-West",
    "ES": "Southeast", "MG": "Southeast", "RJ": "Southeast", "SP": "Southeast",
    "PR": "South", "RS": "South", "SC": "South",
}

orders = con.sql("""
    SELECT order_id, customer_unique_id, customer_state, order_status, order_date,
           items, product_value, freight_value, gmv, payment_total, installments,
           main_payment_type, review_score, delivery_days, on_time,
           is_delivered, is_cancelled, is_first_order
    FROM fact_orders WHERE in_scope = 1""").df()

items = con.sql("""
    SELECT order_id, order_item_id, product_id, seller_id, category, price, freight_value,
           order_date, customer_state, order_status, is_delivered, on_time, review_score
    FROM fact_items WHERE in_scope = 1""").df()
items["category"] = items["category"].str.replace("_", " ")

sellers = con.sql("SELECT seller_id, seller_city, seller_state FROM dim_sellers").df()
sellers["seller_region"] = sellers["seller_state"].map(REGIONS).fillna("Other")

states = pd.DataFrame(sorted(REGIONS.items()), columns=["state", "region"])

dates = pd.DataFrame({"Date": pd.date_range("2017-01-01", "2018-08-31")})
dates["Year"] = dates["Date"].dt.year
dates["Quarter"] = "Q" + dates["Date"].dt.quarter.astype(str)
dates["MonthNum"] = dates["Date"].dt.month
dates["Month"] = dates["Date"].dt.strftime("%b")
dates["YearMonth"] = dates["Date"].dt.strftime("%Y-%m")

# Plain dates (no time part) and empty cells instead of NaN
for df in (orders, items, dates):
    col = "Date" if "Date" in df else "order_date"
    df[col] = pd.to_datetime(df[col]).dt.date
for c in ["review_score", "delivery_days", "on_time", "payment_total", "installments"]:
    orders[c] = orders[c].astype("float")
for c in ["review_score", "on_time"]:
    items[c] = items[c].astype("float")

out = Path("powerbi/executive_kpi_model.xlsx")
out.parent.mkdir(exist_ok=True)
sheets = {"fact_orders": orders, "fact_items": items, "dim_date": dates,
          "dim_state": states, "dim_sellers": sellers}

with pd.ExcelWriter(out, engine="openpyxl") as writer:
    for name, df in sheets.items():
        df.to_excel(writer, sheet_name=name, index=False)
        ws = writer.sheets[name]
        table = Table(displayName=name, ref=f"A1:{get_column_letter(df.shape[1])}{len(df) + 1}")
        table.tableStyleInfo = TableStyleInfo(name="TableStyleMedium2", showRowStripes=True)
        ws.add_table(table)
        print(f"{name:<12} {len(df):>8,} rows  {df.shape[1]:>3} columns")

print(f"\nSaved {out} ({out.stat().st_size / 1e6:.1f} MB)")
