# Run Order

## Default Run

1. Summary/background R scripts
2. Main-results Stata scripts
3. Mechanism Stata scripts
4. Heterogeneity Stata scripts
5. Robustness Stata scripts

## Dependency Notes

- `20_main_results/01_prepare_panel.do` is a prerequisite for the main, mechanism, heterogeneity, and most robustness Stata scripts.
- `20_main_results/04_fare_event.do`, `05_departures_event.do`, `06_delay_event.do`, and `07_reliability_appendix.do` are parallel substantive analyses after panel preparation, not a strict dependency chain.
- `30_mechanisms/01_route_passenger_panel_prep.do` is a prerequisite for `02_route_passenger_event_full_sa.do`.
- `50_robustness/03_prepare_preulcc_panel.do` is a prerequisite for `04_preulcc_fares.do` and `05_preulcc_departures.do`.

## Logging

The package currently writes one combined Stata log at `replication_package/output/logs/stata_driver.log`.
The shell wrapper writes a top-level run log at `replication_package/output/logs/run_replication.log`.
