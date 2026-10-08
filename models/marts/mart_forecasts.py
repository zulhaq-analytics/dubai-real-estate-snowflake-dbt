"""
12-month forecasts for the three monthly market series (DuckDB target).

Replaces the Snowflake ML forecast from v1. For each series it fits an
exponential smoothing (ETS) model with a damped trend and yearly seasonality
on the log of the values, then forecasts 12 months ahead with a 95% likely range.
Output shape matches v1: actual rows plus forecast rows, one per series per month.
"""
import numpy as np
import pandas as pd

HORIZON = 12
ALPHA = 0.05   # 95% likely range


def forecast_one(name, frame):
    from statsmodels.tsa.exponential_smoothing.ets import ETSModel

    y = (frame.set_index("month_start")["value"]
              .astype(float)
              .asfreq("MS")
              .interpolate())          # fills any missing month
    fit = ETSModel(np.log(y), error="add", trend="add", damped_trend=True,
                   seasonal="add", seasonal_periods=12).fit(disp=False)
    pred = fit.get_prediction(start=len(y), end=len(y) + HORIZON - 1).summary_frame(alpha=ALPHA)
    months = pd.date_range(y.index[-1] + pd.offsets.MonthBegin(1), periods=HORIZON, freq="MS")
    return pd.DataFrame({
        "series": name,
        "month_start": months,
        "actual_value": np.nan,
        "forecast_value": np.exp(pred["mean"].to_numpy()),
        "lower_bound": np.exp(pred["pi_lower"].to_numpy()),
        "upper_bound": np.exp(pred["pi_upper"].to_numpy()),
        "is_forecast": True,
    })


def model(dbt, session):
    dbt.config(materialized="table")

    monthly = dbt.ref("mart_monthly_series").df()
    monthly["month_start"] = pd.to_datetime(monthly["month_start"])
    monthly = monthly.sort_values(["series", "month_start"])

    actuals = pd.DataFrame({
        "series": monthly["series"],
        "month_start": monthly["month_start"],
        "actual_value": monthly["value"].astype(float),
        "forecast_value": np.nan,
        "lower_bound": np.nan,
        "upper_bound": np.nan,
        "is_forecast": False,
    })
    forecasts = [forecast_one(name, frame) for name, frame in monthly.groupby("series")]

    out = pd.concat([actuals] + forecasts, ignore_index=True)
    out["month_start"] = out["month_start"].dt.date
    return out
