#!/bin/bash
# Daily refresh of the Dubai property pipeline on the Oracle Cloud server (Linux twin of run_daily.bat).
# 1. Load new DLD records from the API into DuckDB
# 2. Reload the projects list
# 3. Rebuild and test all dbt models; report tables are exported to Parquet
# 4. Upload the Parquet files to Object Storage (bucket dld-marts) for Power BI - only if dbt succeeded
source "$HOME/.dld_env"
source "$HOME/venv/bin/activate"
REPO="$(cd "$(dirname "$0")" && pwd)"
LOG="$DLD_ROOT/logs/daily_run.log"
mkdir -p "$DLD_ROOT/logs" "$DLD_ROOT/marts"

# keep the log under 5 MB (older lines go to daily_run.log.1)
if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG")" -gt 5242880 ]; then mv "$LOG" "$LOG.1"; fi

STATUS="ALL OK"
{
  echo
  echo "===== Daily run started $(date -u '+%Y-%m-%d %H:%M:%S') UTC ====="
  cd "$REPO/loader"
  python dld_loader.py daily          || STATUS="FAILED at loader daily"
  python dld_loader.py full projects  || STATUS="FAILED at loader projects"
  cd "$REPO"
  if dbt build --no-use-colors --vars "{parquet_export_path: '$DLD_ROOT/marts'}"; then
    ok=0; fail=0
    for f in "$DLD_ROOT"/marts/*.parquet; do
      n=$(basename "$f")
      if curl -sS -f --retry 3 -T "$f" "${DLD_MARTS_PAR}${n}" >/dev/null; then ok=$((ok+1)); else fail=$((fail+1)); echo "Upload FAILED: $n"; fi
    done
    echo "Upload to Object Storage: $ok uploaded, $fail failed"
    [ "$fail" -eq 0 ] || STATUS="FAILED at upload ($fail files)"
  else
    STATUS="FAILED at dbt build (nothing uploaded)"
  fi
  echo "===== Daily run finished $(date -u '+%Y-%m-%d %H:%M:%S') UTC | RESULT: $STATUS ====="
} >> "$LOG" 2>&1
