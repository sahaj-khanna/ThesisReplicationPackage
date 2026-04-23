# Method Inventory

This file describes the current standardized state of the curated replication package.
It is no longer a pre-standardization inventory. Most thesis-facing scripts have
already been harmonized onto a common design, with a short list of explicit exceptions.

## Package Standard

- Estimator: `csdid2`
- Base period: varying base period via `short`
- Comparison group: never-treated routes by default
- Inference: `estat simple, wboot reps(999) rseed(${seed_std})` and, where relevant,
  `estat event, wboot reps(999) rseed(${seed_std})`
- Event window: `-6/+8` for dynamic event studies
- Main covariate set:
  - `average_dist`
  - `route_hhi`
  - `ln_geo_mean_pop`
  - `ln_geo_mean_income`
  - `origin_leisure_share_emp`
  - `dest_leisure_share_emp`
  - `big_city_route`
  - `hub_route`

## Explicit Exceptions

- `20_main_results/02_main_atts.do`
  - keeps the documented robustness variants:
    - extended covariates (`covars_large`)
    - no-covariate regression baseline
- `30_mechanisms/02_route_passenger_event_full_sa.do`
  - runs on a route-quarter panel rather than the carrier-route-quarter panel
- `50_robustness/02_concurrent_carriers.do`
  - runs on a route-quarter panel because the outcome is the number of carriers on a route
- `50_robustness/04_preulcc_fares.do`
  - keeps the large-covariate pre-ULCC robustness specification
- `50_robustness/09_incumbent_passengers_seats_pretreat_sa.do`
  - uses pre-treatment seasonal adjustment by design as the robustness counterpart

## Seasonal-Adjustment Rules

- No seasonal adjustment:
  - fares
  - delays
  - cancellation / late-share reliability outcomes
  - scheduled time
- Full-sample route x quarter-of-year:
  - route-passenger mechanism
- Full-sample carrier-route x quarter-of-year:
  - departures event study
  - load factor
  - incumbent passengers / seats / departures mechanism block
  - exit-robustness quantity outcomes
  - pre-ULCC departures robustness
- Pre-treatment-only carrier-route x quarter-of-year:
  - incumbent passengers / seats / departures robustness block

## Script-Level Inventory

| Script | Category | Estimator | Controls | Inference | Event window | Seasonal adjustment | Panel unit | Covariates | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `20_main_results/02_main_atts.do` | Main | `csdid2` | never-treated | `estat simple, wboot reps(999)` | ATT only | none | carrier-route-quarter | `small`, `large`, and no-covariate variants | main ATT table |
| `20_main_results/04_fare_event.do` | Main | `csdid2` | never-treated | `estat event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `small` | fresh estimation, not replot-only |
| `20_main_results/05_departures_event.do` | Main | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | full-sample carrier-route x quarter-of-year | carrier-route-quarter | `small` | departures event study |
| `20_main_results/06_delay_event.do` | Main | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `small` | carrier-delay event study |
| `20_main_results/07a_share_flights_late.do` | Main appendix | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `small` | reliability appendix |
| `20_main_results/07b_cancellation_rate.do` | Main appendix | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `small` | reliability appendix |
| `30_mechanisms/02_route_passenger_event_full_sa.do` | Mechanism | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | full-sample route x quarter-of-year | route-quarter | route-level baseline set | route-passenger exception |
| `30_mechanisms/03_load_factor_event.do` | Mechanism | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | full-sample carrier-route x quarter-of-year | carrier-route-quarter | `small` | load-factor event study |
| `30_mechanisms/04_incumbent_passengers_seats_full_sa.do` | Mechanism | `csdid2` | never-treated | `estat simple, wboot reps(999)` | ATT only | full-sample carrier-route x quarter-of-year | carrier-route-quarter | `small` | departures / passengers / seats mechanism block |
| `40_heterogeneity/01_fare_percentiles.do` | Heterogeneity | `csdid2` | never-treated | `estat simple, wboot reps(999)` | ATT only | none | carrier-route-quarter | `small` | percentile ATT comparisons |
| `40_heterogeneity/02_carrier_type.do` | Heterogeneity | `csdid2` | never-treated | `estat simple, wboot reps(999)` | ATT only | full-sample carrier-route x quarter-of-year for quantity outcomes | carrier-route-quarter | `small` | legacy vs LCC subgroups |
| `40_heterogeneity/03_frontier_service_frequency.do` | Heterogeneity | `csdid2` | never-treated | `estat simple, wboot reps(999)` | ATT only | full-sample carrier-route x quarter-of-year for quantity outcomes | carrier-route-quarter | `small` | Frontier-frequency buckets |
| `50_robustness/01_scheduled_time.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `small` | scheduled-time padding check |
| `50_robustness/02_concurrent_carriers.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | route-quarter | route-level baseline set | number-of-carriers exception |
| `50_robustness/04_preulcc_fares.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `large` | pre-ULCC fare robustness |
| `50_robustness/05_preulcc_departures.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | full-sample carrier-route x quarter-of-year | carrier-route-quarter | `small` | pre-ULCC departures robustness |
| `50_robustness/06_basic_economy_southwest.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | none | carrier-route-quarter | `small` | Southwest-only fare robustness |
| `50_robustness/07_never_exited.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | full-sample carrier-route x quarter-of-year for quantity outcomes | carrier-route-quarter | `small` | never-exited routes |
| `50_robustness/08_continuous_service.do` | Robustness | `csdid2` | never-treated | `estat simple/event, wboot reps(999)` | `-6/+8` | full-sample carrier-route x quarter-of-year for quantity outcomes | carrier-route-quarter | `small` | continuous-service routes |
| `50_robustness/09_incumbent_passengers_seats_pretreat_sa.do` | Robustness | `csdid2` | never-treated | `estat simple, wboot reps(999)` | ATT only | pre-treatment-only carrier-route x quarter-of-year | carrier-route-quarter | `small` | incumbent quantity robustness |

## Remaining Non-Method Cleanup

- Some script headers still carry legacy filenames from the source repo.
- The combined driver log is the authoritative Stata log; scripts do not each open their own log file.
- Direct single-script execution still assumes `$package_root` is available. The package entrypoint remains `run_replication.sh`.
