"""Read-only tools for the Dubai Property Advisor agent.

Every number comes from summary tables that dbt builds daily on the Oracle Cloud
server and publishes to Object Storage. Nothing in this module writes data.
"""
import difflib

import duckdb
import pandas as pd

TABLES = {
    "seg": "mart_agent_area_segment.parquet",
    "area_year": "mart_area_rental_yield.parquet",
    "forecast": "mart_forecasts.parquet",
}
ROOMS = ["Studio", "1 BR", "2 BR", "3 BR", "4 BR", "5+ BR"]
TYPES = ["Apartment", "Villa"]
GOALS = ["rent_out", "live"]
MAX_ROWS = 15
ALIASES = {
    "jvc": "jumeirah village circle",
    "jvt": "jumeirah village triangle",
    "jlt": "jumeirah lakes towers",
    "jbr": "jumeirah beach residence",
    "dip": "dubai investment park",
    "downtown": "downtown dubai",
    "marina": "dubai marina",
    "difc": "difc",
    "silicon oasis": "silicon oasis",
    "sports city": "sports city",
    "motor city": "motor city",
    "arjan": "arjan",
}

_con = None


def load(base_url: str) -> str:
    """Load the summary tables from Object Storage into memory. Returns the data as-of date."""
    global _con
    _con = duckdb.connect()
    _con.sql("INSTALL httpfs; LOAD httpfs;")
    for name, file in TABLES.items():
        _con.sql(f"CREATE OR REPLACE TABLE {name} AS SELECT * FROM read_parquet('{base_url}{file}')")
    return str(_con.sql("SELECT max(as_of_date) FROM seg").fetchone()[0])[:10]


def _clean(v):
    if isinstance(v, (list, dict)):
        return v
    if v is None or pd.isna(v):
        return None
    if hasattr(v, "isoformat"):
        return v.isoformat()[:10]
    if hasattr(v, "item"):
        v = v.item()
    if isinstance(v, float):
        if v.is_integer():
            return int(v)
        return round(v, 2)
    return v


def _rows(sql: str, params=None, limit: int = MAX_ROWS) -> list:
    df = _con.execute(sql, params or []).df().head(limit)
    return [{k: _clean(v) for k, v in rec.items()} for rec in df.to_dict("records")]


def _check(value: str, allowed: list, label: str):
    if value and value not in allowed:
        return {"error": f"Unknown {label} '{value}'. Use one of: {allowed}"}
    return None


def resolve_area(name: str) -> dict:
    """Find Dubai areas matching a name the user typed. Call this FIRST whenever the user mentions
    an area, then use the exact area_display_name it returns in the other tools.
    name: area or community name as the user wrote it, for example 'JVC', 'marina' or 'Business Bay'."""
    names = [r[0] for r in _con.sql(
        "SELECT DISTINCT area_display_name FROM seg WHERE area_display_name IS NOT NULL").fetchall()]
    q = ALIASES.get(name.strip().lower(), name.strip().lower())
    hits = [n for n in names if q in n.lower()]
    if not hits:
        hits = difflib.get_close_matches(name.strip(), names, n=5, cutoff=0.6)
    if not hits:
        return {"matches": [], "note": "No area found. Ask the user to check the name."}
    rows = _rows(f"""
        SELECT area_display_name, sum(sales_12m) AS sales_12m, sum(rents_12m) AS new_leases_12m
        FROM seg WHERE area_display_name IN ({','.join('?' * len(hits))})
        GROUP BY 1 ORDER BY sales_12m DESC""", hits, limit=5)
    return {"matches": rows}


def get_segment(area_display_name: str, property_type: str, room_category: str) -> dict:
    """Get prices, rents, yields and price/rent changes for one area, property type and bedroom count,
    for the last 12 months. Read the 'notes' field: it explains any figure that is not published.
    area_display_name: exact name from resolve_area. property_type: 'Apartment' or 'Villa'.
    room_category: 'Studio', '1 BR', '2 BR', '3 BR', '4 BR' or '5+ BR'."""
    err = _check(property_type, TYPES, "property_type") or _check(room_category, ROOMS, "room_category")
    if err:
        return err
    rows = _rows("""
        SELECT as_of_date, area_display_name, property_type, room_category,
               sales_12m, ready_sales_12m, offplan_sales_12m,
               median_price_aed          AS median_price_all_sales_aed,
               median_ready_price_aed, median_offplan_price_aed, median_size_sqm,
               median_price_per_sqm_aed  AS median_price_per_sqm_all_sales_aed,
               rents_12m, median_annual_rent_aed, median_rent_per_sqm_aed,
               ready_price_per_sqm_change_pct, rent_per_sqm_change_pct,
               gross_yield_ready_pct, net_yield_ready_pct
        FROM seg
        WHERE area_display_name = ? AND property_type = ? AND room_category = ?""",
        [area_display_name, property_type, room_category])
    if not rows:
        return {"error": "No data for that combination. Check the area with resolve_area, or try another bedroom count."}
    s = rows[0]
    notes = []
    if s["gross_yield_ready_pct"] is None:
        notes.append("Gross yield NOT published: it needs at least 30 ready sales and 30 new leases in the "
                     "last 12 months. Do not calculate it from price and rent.")
    if s["net_yield_ready_pct"] is None:
        notes.append("Net yield NOT published: it is only calculated for apartments with a gross yield and "
                     "service-charge data for at least 5 projects in the area.")
    if s["ready_price_per_sqm_change_pct"] is None:
        notes.append("Ready price change NOT published: it needs at least 50 ready sales in both 12-month periods.")
    if s["rent_per_sqm_change_pct"] is None:
        notes.append("Rent change NOT published: it needs at least 50 new leases in both 12-month periods.")
    if (s["ready_sales_12m"] or 0) < 10:
        notes.append("Very few ready sales: treat the median ready price as indicative only.")
    return {"segment": s, "notes": notes}


def find_segments(max_budget_aed: float, goal: str, room_category: str = "", property_type: str = "",
                  limit: int = 10) -> dict:
    """Find area, property type and bedroom combinations whose median READY home price is within budget.
    goal: 'rent_out' ranks by gross rental yield; 'live' ranks by median home size (most space for the money).
    max_budget_aed: maximum price in AED. room_category and property_type are optional filters.
    limit: number of results, at most 15. Only segments with at least 30 ready sales are returned."""
    err = (_check(goal, GOALS, "goal") or _check(room_category, ROOMS, "room_category")
           or _check(property_type, TYPES, "property_type"))
    if err:
        return err
    where, params = ["ready_sales_12m >= 30", "median_ready_price_aed <= ?"], [float(max_budget_aed)]
    if room_category:
        where.append("room_category = ?"); params.append(room_category)
    if property_type:
        where.append("property_type = ?"); params.append(property_type)
    if goal == "rent_out":
        where.append("gross_yield_ready_pct IS NOT NULL")
        order = "gross_yield_ready_pct DESC"
    else:
        order = "median_size_sqm DESC"
    cond = " AND ".join(where)
    total = _con.execute(f"SELECT count(*) FROM seg WHERE {cond}", params).fetchone()[0]
    rows = _rows(f"""
        SELECT area_display_name, property_type, room_category, ready_sales_12m, median_ready_price_aed,
               median_size_sqm, rents_12m, median_annual_rent_aed, gross_yield_ready_pct, net_yield_ready_pct,
               ready_price_per_sqm_change_pct, rent_per_sqm_change_pct
        FROM seg WHERE {cond} ORDER BY {order} LIMIT {max(1, min(int(limit), MAX_ROWS))}""", params)
    return {"total_matches": total, "ranked_by": order.split()[0], "results": rows}


def get_area_trend(area_display_name: str) -> dict:
    """Get yearly sales counts, median prices per sqm, rents per sqm and gross yields for one area,
    for the last 5 calendar years up to the data date (all property types and sizes combined;
    the current year is partial). area_display_name: exact name from resolve_area."""
    rows = _rows("""
        WITH d AS (SELECT year(max(as_of_date)) AS y FROM seg)
        SELECT year, sales_count, round(median_price_per_sqm_aed) AS median_price_per_sqm_aed,
               round(median_ready_price_per_sqm_aed) AS median_ready_price_per_sqm_aed,
               rent_count, round(median_rent_per_sqm_aed) AS median_rent_per_sqm_aed,
               round(gross_rental_yield_ready * 100, 2) AS gross_yield_ready_pct,
               round(net_rental_yield_ready * 100, 2) AS net_yield_ready_pct
        FROM area_year, d
        WHERE area_display_name = ? AND year BETWEEN d.y - 4 AND d.y
        ORDER BY year""", [area_display_name])
    if not rows:
        return {"error": "No yearly data for that area. Check the name with resolve_area."}
    return {"area": area_display_name, "years": rows, "note": "The latest year is partial (to the data date)."}


def get_market_forecast() -> dict:
    """Get the citywide 12-month forecast for each market series (price per sqm, rent per sqm,
    sales per month), with the last actual value and the forecast 6 and 12 months ahead,
    including lower and upper bounds."""
    out = []
    for (s,) in _con.sql("SELECT DISTINCT series FROM forecast ORDER BY 1").fetchall():
        last = _rows("""SELECT month_start, round(actual_value) AS actual_value FROM forecast
                        WHERE series = ? AND NOT is_forecast AND actual_value IS NOT NULL
                        ORDER BY month_start DESC LIMIT 1""", [s])
        fc = _rows("""SELECT month_start, round(forecast_value) AS forecast_value,
                             round(lower_bound) AS lower_bound, round(upper_bound) AS upper_bound
                      FROM forecast WHERE series = ? AND is_forecast ORDER BY month_start""", [s], limit=24)
        out.append({
            "series": s,
            "last_actual": last[0] if last else None,
            "forecast_6m": fc[5] if len(fc) > 5 else None,
            "forecast_12m": fc[11] if len(fc) > 11 else (fc[-1] if fc else None),
        })
    return {"series": out, "note": "Model forecast (exponential smoothing). Bounds show the model's uncertainty range."}


TOOLS = [resolve_area, find_segments, get_segment, get_area_trend, get_market_forecast]