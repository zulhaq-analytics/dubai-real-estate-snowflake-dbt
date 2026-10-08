"""
DLD API loader: pulls Dubai Land Department open data into a local DuckDB file.

Usage (from Anaconda Prompt, inside C:\\Portfolio\\dld\\loader):
    python dld_loader.py seed                 load history from the CSV files in C:\\Portfolio\\dld\\raw
    python dld_loader.py daily --since 2026-09-01   one-time catch-up from a given date
    python dld_loader.py full projects        full reload of one dataset
    python dld_loader.py full all             full reload of all five datasets
    python dld_loader.py daily                rolling-window refresh (last 30 days of sales and valuations, 60 of rent)
    python dld_loader.py daily rent_contracts refresh one dataset only
    python dld_loader.py dedupe               remove older copies of records that DLD re-dated
    python dld_loader.py status               row counts and latest dates

A full load that stops halfway (Ctrl+C, laptop sleeps, network drops) resumes
from where it stopped when you run the same command again. Add --restart to
throw away the partial load and start from page 1.

Credentials come from user environment variables (never hard-coded):
    DLD_PROD_CLIENT_ID, DLD_PROD_CLIENT_SECRET, DLD_PROD_APP_ID
"""
import argparse
import logging
import os
import re
import sys
import time
from datetime import date, datetime, timedelta
from pathlib import Path

import duckdb
import pandas as pd
import requests

# ---------------------------------------------------------------- settings
BASE = "https://apis.data.dubai"
TOKEN_URL = f"{BASE}/secure/ssis/dubaiai/gatewaytoken/1.0.0/getAccessToken"
ROOT = Path(r"C:\Portfolio\dld")
DB_PATH = ROOT / "dld.duckdb"
LOG_DIR = ROOT / "logs"
RAW_CSV_DIR = ROOT / "raw"
SEED_SKIP = {"projects"}           # projects already come from the API (newer than the July CSV)

PAGE_SIZE = 1000                   # API maximum
MIN_SECONDS_BETWEEN_CALLS = 1.1    # keeps us under 60 requests per minute
FLUSH_EVERY_PAGES = 25             # write to DuckDB every 25,000 rows
TOKEN_REFRESH_SECONDS = 50 * 60    # token lasts 60 minutes; refresh at 50
MAX_ATTEMPTS = 6

DATASETS = {
    "transactions":   {"path": "dld/dld_transactions-open-api",   "date_col": "instance_date",       "window_days": 30,
                       "key": ["transaction_id"]},
    "valuation":      {"path": "dld/dld_valuation-open-api",      "date_col": "instance_date",       "window_days": 30,
                       "key": ["procedure_year", "procedure_number"]},
    "rent_contracts": {"path": "dld/dld_rent_contracts-open-api", "date_col": "contract_start_date", "window_days": 60,
                       "key": ["contract_id", "line_number"]},
    "projects":       {"path": "dld/dld_projects-open-api",       "date_col": None,                  "window_days": None},
    "units":          {"path": "dld/dld_units-open-api",          "date_col": None,                  "window_days": None},
}
DAILY_DATASETS = ["transactions", "valuation", "rent_contracts"]

log = logging.getLogger("dld")


# ---------------------------------------------------------------- logging
def setup_logging():
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    (ROOT / "marts").mkdir(parents=True, exist_ok=True)   # dbt writes Parquet files here
    fmt = logging.Formatter("%(asctime)s  %(levelname)-7s  %(message)s", "%Y-%m-%d %H:%M:%S")
    log.setLevel(logging.INFO)
    fh = logging.FileHandler(LOG_DIR / f"loader_{date.today():%Y%m%d}.log", encoding="utf-8")
    fh.setFormatter(fmt)
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    log.addHandler(fh)
    log.addHandler(sh)


# ---------------------------------------------------------------- API client
class DLDClient:
    """Handles login, token refresh, rate limiting and retries."""

    def __init__(self):
        for var in ("DLD_PROD_CLIENT_ID", "DLD_PROD_CLIENT_SECRET", "DLD_PROD_APP_ID"):
            if not os.environ.get(var):
                raise SystemExit(f"Missing environment variable {var}")
        self.session = requests.Session()
        self.token = None
        self.token_time = 0.0
        self.last_call = 0.0
        self.calls = 0

    def _login(self):
        r = self.session.post(
            TOKEN_URL,
            headers={"Content-Type": "application/json",
                     "x-DDA-SecurityApplicationIdentifier": os.environ["DLD_PROD_APP_ID"]},
            json={"grant_type": "client_credentials",
                  "client_id": os.environ["DLD_PROD_CLIENT_ID"],
                  "client_secret": os.environ["DLD_PROD_CLIENT_SECRET"]},
            timeout=30,
        )
        r.raise_for_status()
        self.token = r.json()["access_token"]
        self.token_time = time.time()
        log.info("Got a new access token")

    def _headers(self):
        if self.token is None or time.time() - self.token_time > TOKEN_REFRESH_SECONDS:
            self._login()
        return {"Authorization": f"Bearer {self.token}"}

    def _throttle(self):
        wait = MIN_SECONDS_BETWEEN_CALLS - (time.time() - self.last_call)
        if wait > 0:
            time.sleep(wait)
        self.last_call = time.time()

    def get_page(self, path, page, filter_=None, order_by=None):
        params = {"page": page, "pageSize": PAGE_SIZE}
        if filter_:
            params["filter"] = filter_
        if order_by:
            params["order_by"] = order_by
            params["order_dir"] = "desc"

        for attempt in range(1, MAX_ATTEMPTS + 1):
            self._throttle()
            backoff = min(5 * 2 ** attempt, 300)
            try:
                r = self.session.get(f"{BASE}/open/{path}", headers=self._headers(),
                                     params=params, timeout=120)
                self.calls += 1
            except requests.RequestException as e:
                log.warning(f"{path} page {page}: network error ({e.__class__.__name__}), "
                            f"retry {attempt}/{MAX_ATTEMPTS} in {backoff}s")
                time.sleep(backoff)
                continue

            if r.status_code == 200:
                try:
                    return r.json().get("results", [])
                except ValueError:
                    log.warning(f"{path} page {page}: response was not JSON, retry in {backoff}s")
                    time.sleep(backoff)
                    continue
            if r.status_code == 401:
                log.info("Token rejected, logging in again")
                self.token = None
                continue
            if r.status_code in (408, 425, 429) or r.status_code >= 500:   # temporary DLD-side problems
                log.warning(f"{path} page {page}: HTTP {r.status_code}, "
                            f"retry {attempt}/{MAX_ATTEMPTS} in {backoff}s")
                time.sleep(backoff)
                continue
            raise RuntimeError(f"{path} page {page}: HTTP {r.status_code} {r.text[:200]}")

        raise RuntimeError(f"{path} page {page}: gave up after {MAX_ATTEMPTS} attempts")


# ---------------------------------------------------------------- DuckDB helpers
def connect():
    con = duckdb.connect(str(DB_PATH))
    con.execute("create schema if not exists raw")
    con.execute("""create table if not exists raw._load_state (
                       dataset varchar primary key, next_page integer, run_ts timestamp)""")
    return con


def table_exists(con, table):
    return con.execute("""select count(*) from information_schema.tables
                          where table_schema = 'raw' and table_name = ?""", [table]).fetchone()[0] > 0


def to_frame(rows, run_ts, source):
    # Raw layer keeps every API field as text; dbt staging models cast the types.
    df = pd.DataFrame(rows).astype("string")
    df["_source_file"] = pd.Series(source, index=df.index, dtype="string")
    df["_loaded_at"] = pd.Timestamp(run_ts)
    return df


def add_new_columns(con, table, df):
    """Add any API columns the table doesn't have yet (run outside a transaction)."""
    if not table_exists(con, table):
        return
    existing = {r[0] for r in con.execute(
        """select column_name from information_schema.columns
           where table_schema = 'raw' and table_name = ?""", [table]).fetchall()}
    for col in df.columns:
        if col not in existing:
            log.info(f"{table}: new column from API: {col}")
            con.execute(f'alter table raw."{table}" add column "{col}" varchar')


def insert(con, table, df):
    """Append a batch; creates the table on first use."""
    con.register("batch_df", df)
    if not table_exists(con, table):
        con.execute(f'create table raw."{table}" as select * from batch_df')
    else:
        con.execute(f'insert into raw."{table}" by name select * from batch_df')
    con.unregister("batch_df")


def dedupe(con, name):
    """Keep only the newest copy of each record (by the dataset's key).
    A record can appear twice when DLD changes its date: the old copy sits outside
    the reload window and the new copy comes in from the API. The newest load wins."""
    key = DATASETS[name].get("key")
    if not key or not table_exists(con, name):
        return 0
    cols = ", ".join(f'"{c}"' for c in key)
    removed = con.execute(f"""
        select count(*) from (
            select row_number() over (partition by {cols} order by _loaded_at desc, (_source_file like 'api:%') desc) as rn
            from raw."{name}" where {" and ".join(f'"{c}" is not null' for c in key)}
        ) where rn > 1""").fetchone()[0]
    if removed:
        con.execute(f"""
            delete from raw."{name}" where rowid in (
                select rowid from (
                    select rowid, row_number() over (partition by {cols} order by _loaded_at desc, (_source_file like 'api:%') desc) as rn
                    from raw."{name}" where {" and ".join(f'"{c}" is not null' for c in key)}
                ) where rn > 1)""")
        log.info(f"{name}: removed {removed:,} older duplicate copies (key: {', '.join(key)})")
    return removed


def count(con, table):
    return con.execute(f'select count(*) from raw."{table}"').fetchone()[0]


# ---------------------------------------------------------------- loads
def full_load(con, client, name, restart=False):
    """Page through the whole dataset into a loading table, then swap it in."""
    cfg = DATASETS[name]
    stg = f"{name}__loading"
    state = con.execute("select next_page, run_ts from raw._load_state where dataset = ?",
                        [name]).fetchone()

    if state and not restart:
        page, run_ts = state
        log.info(f"{name}: resuming full load at page {page:,}")
    else:
        con.execute(f'drop table if exists raw."{stg}"')
        con.execute("delete from raw._load_state where dataset = ?", [name])
        page, run_ts = 1, datetime.now().replace(microsecond=0)
        con.execute("insert into raw._load_state values (?, ?, ?)", [name, page, run_ts])
        log.info(f"{name}: starting full load")

    t0 = time.time()
    buffer = []
    while True:
        rows = client.get_page(cfg["path"], page)
        buffer.extend(rows)
        page += 1
        last_page = len(rows) < PAGE_SIZE

        if buffer and (last_page or len(buffer) >= FLUSH_EVERY_PAGES * PAGE_SIZE):
            df = to_frame(buffer, run_ts, f"api:{cfg['path']}")
            add_new_columns(con, stg, df)
            con.begin()
            insert(con, stg, df)
            con.execute("update raw._load_state set next_page = ? where dataset = ?", [page, name])
            con.commit()
            buffer = []
            mins = (time.time() - t0) / 60
            log.info(f"{name}: {count(con, stg):,} rows loaded (page {page - 1:,}, {mins:.1f} min)")
        if last_page:
            break

    if not table_exists(con, stg):
        raise RuntimeError(f"{name}: API returned no rows; existing table left unchanged")

    con.begin()
    con.execute(f'create or replace table raw."{name}" as select distinct * from raw."{stg}"')
    con.execute(f'drop table raw."{stg}"')
    con.execute("delete from raw._load_state where dataset = ?", [name])
    con.commit()
    dedupe(con, name)
    log.info(f"{name}: full load done, {count(con, name):,} rows "
             f"in {(time.time() - t0) / 60:.1f} min")


def window_load(con, client, name, since=None):
    """Reload the last N days: delete them locally, then insert fresh rows from the API."""
    cfg = DATASETS[name]
    if not table_exists(con, name):
        log.warning(f"{name}: no table yet, run 'full {name}' first. Skipped.")
        return

    col = cfg["date_col"]
    if since:
        start = since
    else:
        # Normal window: the last N days. If the last API load is older than today
        # (laptop off, leave), stretch the window back so the gap is covered too.
        window = timedelta(days=cfg["window_days"])
        last_api = con.execute(f"""select max(_loaded_at)::date from raw."{name}"
                                   where _source_file like 'api:%'""").fetchone()[0]
        start_date = date.today() - window
        if last_api and last_api - window < start_date:
            start_date = last_api - window
            log.info(f"{name}: last API load was {last_api}, so reloading from {start_date}")
        start = start_date.isoformat()
    flt = f"{col}>='{start}'"
    t0 = time.time()

    rows, page = [], 1
    while True:
        batch = client.get_page(cfg["path"], page, filter_=flt, order_by=col)
        rows.extend(batch)
        page += 1
        if len(batch) < PAGE_SIZE:
            break
        if (page - 1) % 25 == 0:
            log.info(f"{name}: {len(rows):,} rows fetched so far (page {page - 1}, "
                     f"{(time.time() - t0) / 60:.1f} min)")

    if not rows:
        log.warning(f"{name}: API returned no rows since {start}; nothing changed")
        return

    df = to_frame(rows, datetime.now().replace(microsecond=0), f"api:{cfg['path']}")
    df = df.drop_duplicates(subset=cfg["key"], keep="last") if cfg.get("key") else df.drop_duplicates()
    add_new_columns(con, name, df)
    con.begin()
    removed = con.execute(f'select count(*) from raw."{name}" where "{col}" >= ?', [start]).fetchone()[0]
    con.execute(f'delete from raw."{name}" where "{col}" >= ?', [start])
    insert(con, name, df)
    con.commit()
    dedupe(con, name)
    log.info(f"{name}: window since {start}: replaced {removed:,} rows with {len(df):,} "
             f"({page - 1} pages, {(time.time() - t0) / 60:.1f} min). Total {count(con, name):,}")


def seed_from_csv(con):
    """Load every DLD CSV dataset in RAW_CSV_DIR into raw.<name>. No API calls."""
    groups = {}
    for f in sorted(RAW_CSV_DIR.rglob("*.csv")):
        m = re.match(r"(.+?)_\d{4}-\d{2}-\d{2}_", f.name)
        if m:
            groups.setdefault(m.group(1), []).append(str(f))
    if not groups:
        raise SystemExit(f"No CSV files found under {RAW_CSV_DIR}")

    # clear any partial API loads left from earlier runs
    for (t,) in con.execute("""select table_name from information_schema.tables
                               where table_schema = 'raw' and table_name like '%\\_\\_loading' escape '\\'""").fetchall():
        con.execute(f'drop table raw."{t}"')
        log.info(f"Removed partial load table {t}")
    con.execute("delete from raw._load_state")

    run_ts = datetime.now().replace(microsecond=0)
    for name, files in sorted(groups.items()):
        if name in SEED_SKIP:
            log.info(f"{name}: skipped (loaded from the API instead)")
            continue
        t0 = time.time()
        file_list = "[" + ", ".join("'" + f.replace("'", "''") + "'" for f in files) + "]"
        src = (f"read_csv({file_list}, header = true, all_varchar = true, union_by_name = true, filename = true, "
               f"delim = ',', quote = '\"', escape = '\"')")
        cols = [r[0] for r in con.execute(f"describe select * from {src}").fetchall() if r[0] != "filename"]
        select_list = ", ".join(f'nullif("{c}", \'\') as "{c}"' for c in cols)
        con.execute(f'create or replace table raw."{name}" as '
                    f"select {select_list}, parse_filename(filename) as _source_file, "
                    f"timestamp '{run_ts}' as _loaded_at from {src}")
        log.info(f"{name}: {count(con, name):,} rows from {len(files)} file(s) "
                 f"in {(time.time() - t0) / 60:.1f} min")


def status(con):
    print(f"\nDatabase: {DB_PATH}\n")
    print(f"{'dataset':16s} {'rows':>12s}  {'latest date':22s} {'loaded at'}")
    for name, cfg in DATASETS.items():
        if not table_exists(con, name):
            print(f"{name:16s} {'(not loaded)':>12s}")
            continue
        col = cfg["date_col"]
        latest = (con.execute(f'select max("{col}") from raw."{name}" where "{col}" <= ?',
                              [date.today().isoformat() + " 23:59:59"]).fetchone()[0]
                  if col else "-")
        loaded = con.execute(f'select max(_loaded_at) from raw."{name}"').fetchone()[0]
        print(f"{name:16s} {count(con, name):>12,}  {str(latest):22s} {loaded}")
    pending = con.execute("select dataset, next_page from raw._load_state").fetchall()
    for ds, pg in pending:
        print(f"\nUnfinished full load: {ds} (resumes at page {pg:,})")
    print()


# ---------------------------------------------------------------- main
def main():
    p = argparse.ArgumentParser(description="DLD API -> DuckDB loader")
    p.add_argument("mode", choices=["seed", "full", "daily", "dedupe", "status"])
    p.add_argument("dataset", nargs="?", default=None,
                   help="for 'full': one of " + ", ".join(DATASETS) + " or 'all'; for 'daily': optional, one dataset")
    p.add_argument("--restart", action="store_true", help="discard a partial full load")
    p.add_argument("--since", help="for 'daily': reload from this date (YYYY-MM-DD) instead of the usual window")
    args = p.parse_args()

    setup_logging()
    con = connect()

    if args.mode == "status":
        status(con)
        return
    if args.mode == "seed":
        seed_from_csv(con)
        status(con)
        return
    if args.mode == "dedupe":
        for name in DATASETS:
            if not dedupe(con, name) and DATASETS[name].get("key"):
                log.info(f"{name}: no duplicates")
        return
    if args.since:
        try:
            date.fromisoformat(args.since)
        except ValueError:
            raise SystemExit("--since must look like 2026-09-01")

    client = DLDClient()
    started = time.time()
    failed = []

    if args.mode == "full":
        if args.dataset not in list(DATASETS) + ["all"]:
            raise SystemExit("For 'full', name a dataset: " + ", ".join(DATASETS) + " or all")
        targets = list(DATASETS) if args.dataset == "all" else [args.dataset]
    elif args.dataset:
        if args.dataset not in DAILY_DATASETS:
            raise SystemExit("For 'daily', name one of: " + ", ".join(DAILY_DATASETS))
        targets = [args.dataset]
    else:
        targets = DAILY_DATASETS

    for name in targets:
        try:
            if args.mode == "full":
                full_load(con, client, name, restart=args.restart)
            else:
                window_load(con, client, name, since=args.since)
        except KeyboardInterrupt:
            log.warning(f"{name}: stopped by you. Run the same command again to resume.")
            sys.exit(130)
        except Exception as e:
            try:
                con.rollback()
            except Exception:
                pass
            log.error(f"{name}: FAILED: {e}")
            failed.append(name)

    log.info(f"Run finished in {(time.time() - started) / 60:.1f} min, "
             f"{client.calls:,} API calls. Failed: {', '.join(failed) or 'none'}")
    con.close()
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
