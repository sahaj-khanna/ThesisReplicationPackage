# Replication Package

This folder is the canonical, thesis-facing replication package for the Frontier Airlines honours thesis project.

## Scope

The package curates only thesis-reported analyses and their required upstream support code. It is non-destructive: original source folders remain in the main repo during migration.

## How To Run

Run the package from the shell entrypoint:

```bash
cd replication_package
./run_replication.sh
```

Environment toggles:

- `RUN_DATA_PIPELINE=0|1`
- `RUN_SUMMARY_BACKGROUND=0|1`
- `RUN_MAIN_RESULTS=0|1`
- `RUN_MECHANISMS=0|1`
- `RUN_HETEROGENEITY=0|1`
- `RUN_ROBUSTNESS=0|1`
- `STATA_BIN=<stata command>`

The default run starts from the existing final dataset and skips raw-data cleaning.

Package-local support files for the thesis figures live under `data/intermediate/` when they are not part of the final merged panel itself.

## Exclusion Rule

The package does not migrate exploratory scripts unless they are needed for a reported thesis output. By default this excludes:

- scripts prefixed with `_`
- scripts containing `quick`
- scripts containing `probe`
- `archive/`
- `_archive/`
- ad hoc exploratory scratch files
