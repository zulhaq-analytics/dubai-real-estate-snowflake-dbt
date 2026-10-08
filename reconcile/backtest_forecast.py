"""
Backtest the v2 forecast (same ETS model as models/marts/mart_forecasts.py).

For each series: train on everything except the last 12 known months, forecast
those 12 months, and compare with what actually happened.
Prints the average error (MAPE) and how often the actual value fell inside
the 95% likely range.

Run from the repo folder:
    python reconcile/backtest_forecast.py
"""
import sys
import warnings

import duckdb
import numpy as np
import pandas as pd
from statsmodels.tsa.exponential_smoothing.ets import ETSModel

warnings.filterwarnings("ignore")
PATH = sys.argv[1] if len(sys.argv) > 1 else "C:/Portfolio/dld/marts/mart_monthly_series.parquet"
HOLDOUT = 12

monthly = duckdb.sql(f"select * from read_parquet('{PATH}')").df()
monthly["month_start"] = pd.to_datetime(monthly["month_start"])

print(f"{'Series':18s} {'Avg error':>10s} {'Inside range':>13s}   Test months")
for name, frame in monthly.sort_values("month_start").groupby("series"):
    y = frame.set_index("month_start")["value"].astype(float).asfreq("MS").interpolate()
    train, test = y.iloc[:-HOLDOUT], y.iloc[-HOLDOUT:]
    fit = ETSModel(np.log(train), error="add", trend="add", damped_trend=True,
                   seasonal="add", seasonal_periods=12).fit(disp=False)
    pred = fit.get_prediction(start=len(train), end=len(train) + HOLDOUT - 1).summary_frame(alpha=0.05)
    mean = np.exp(pred["mean"].to_numpy())
    lo, hi = np.exp(pred["pi_lower"].to_numpy()), np.exp(pred["pi_upper"].to_numpy())
    actual = test.to_numpy()
    mape = np.mean(np.abs(mean - actual) / actual)
    inside = np.mean((actual >= lo) & (actual <= hi))
    print(f"{name:18s} {mape:>10.1%} {inside:>13.0%}   {test.index[0]:%b %Y} to {test.index[-1]:%b %Y}")
