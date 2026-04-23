# Data Sources

The package uses the following dataset families:

- DB1B fare data
- T-100 operations data
- OTP on-time-performance data
- CBSA / regional auxiliary data

## Default Run

The default run treats these files as input artifacts:

- `replication_package/data/final/final_dataset.dta`
- `replication_package/data/final/final_dataset.fst`
- `replication_package/data/final/final_dataset_unfiltered.fst`

These are linked to the existing project build for now so the curated package can start from the final merged panel without rerunning the heaviest upstream pipeline stages.

The summary-background Frontier operations figure also uses package-local support files:

- `replication_package/data/intermediate/frontier_operations/Domestic Available Seat Miles .htm`
- `replication_package/data/intermediate/frontier_operations/System Total Expense per Available Seat Mile (CASM ex fuel and Transport Related).htm`

## Rebuild Mode

Rebuilding from raw data requires user-supplied raw files. Those are not bundled in this package by default. Place them under `replication_package/data/raw/` or adjust the pipeline scripts after migration if you want a fully self-contained raw-data rebuild.
