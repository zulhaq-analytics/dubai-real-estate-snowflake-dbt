# Dubai Real Estate Analytics - Snowflake · dbt · Power BI

> **Status: in progress.** The data platform and dbt project are complete and running daily in production; the Power BI report is being finished. A full write-up with screenshots is coming in October 2026.

I wanted to answer the questions people actually ask about Dubai property: where prices are heading, what homes really earn after costs, which developers deliver on time, and what a tenant can afford. To find out, I'm building an end-to-end analytics project on the Dubai Land Department's open data.

## What's built so far

- **Data:** 15 Dubai Land Department open datasets, about 15.4 million rows (sales, rent contracts, units, buildings, land, projects, developers, valuations, service charges and lookups).
- **Snowflake:** separate raw and analytics databases, dedicated warehouses for loading, transforming and reporting, role-based access, key-pair authenticated service users, and a resource monitor capping spend.
- **dbt:** staging, intermediate and mart layers (15 staging views, 3 intermediate models, 10 mart tables), 100+ data tests, reusable cast and parsing macros, a type-2 snapshot of project status, and a scheduled daily production build.
- **Power BI:** a multi-page report connected to Snowflake, covering the market, where to buy, prices, rental yields, where to rent, developers and area profiles.

## Repository layout

| Folder | Contents |
|---|---|
| `models/staging/dld/` | One cleaned view per raw dataset, with source definitions and tests |
| `models/intermediate/` | Enrichment: bedrooms, validity flags, price and rent per sq m, unit hierarchy |
| `models/marts/` | Facts, dimensions and the area rental-yield mart used by Power BI |
| `macros/` | Safe casting, bedroom parsing and name-cleaning helpers |
| `snapshots/` | Type-2 history of project status and completion |

## Data source

Source data © Dubai Land Department, published as open data via Dubai Pulse and the Dubai Data portal. This is an independent analysis, not affiliated with or endorsed by the Dubai Land Department or the Government of Dubai.
