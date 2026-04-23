# Environment

## Stata

- Curated Stata scripts currently declare `version 18`.
- Required user-installed packages include at least:
  - `csdid`
  - `csdid2`

See `code/shared/dependencies.do` for the package-side dependency check.

## R

The package currently relies on the R packages already used in the source project, including common data and plotting libraries such as:

- `tidyverse`
- `dplyr`
- `fst`
- `readr`
- `data.table`
- `zoo`
- `showtext`

This pass documents dependencies but does not yet pin them with `renv`.

## Runtime Notes

- The default run starts from the prebuilt final dataset and skips raw-data cleaning.
- Full raw-data rebuilding is substantially heavier and is intentionally off by default.
