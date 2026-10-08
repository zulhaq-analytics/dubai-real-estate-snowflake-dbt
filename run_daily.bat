@echo off
rem Daily refresh of the Dubai property pipeline (v2).
rem 1. Load new DLD records from the API into DuckDB
rem 2. Reload the projects list (4 API calls)
rem 3. Rebuild and test all dbt models; report tables are exported to Parquet
rem Everything is logged to C:\Portfolio\dld\logs\daily_run.log

set LOG=C:\Portfolio\dld\logs\daily_run.log
if not exist C:\Portfolio\dld\logs mkdir C:\Portfolio\dld\logs

echo. >> "%LOG%"
echo ===== Daily run started %date% %time% ===== >> "%LOG%"

rem Use the Anaconda Python that has duckdb, pandas and statsmodels
call "%USERPROFILE%\anaconda3\Scripts\activate.bat" >> "%LOG%" 2>&1

cd /d "%~dp0loader"
python dld_loader.py daily >> "%LOG%" 2>&1
python dld_loader.py full projects >> "%LOG%" 2>&1

cd /d "%~dp0"
"%APPDATA%\Python\Python313\Scripts\dbt.exe" build --no-use-colors >> "%LOG%" 2>&1

echo ===== Daily run finished %date% %time% ===== >> "%LOG%"
