********************************************************************************
* replication_package/code/shared/run_replication.do
* Stata-only driver invoked by run_replication.sh.
********************************************************************************

version 18
clear all
set more off
set matsize 10000

local envroot : env REPLICATION_PACKAGE_ROOT
if `"`envroot'"' == "" {
    global package_root `"`c(pwd)'"'
}
else {
    global package_root `"`envroot'"'
    cd "${package_root}"
}

do "${package_root}/code/shared/paths.do"
do "${package_root}/code/shared/dependencies.do"

local run_main_results : env RUN_MAIN_RESULTS
local run_mechanisms : env RUN_MECHANISMS
local run_heterogeneity : env RUN_HETEROGENEITY
local run_robustness : env RUN_ROBUSTNESS

if `"`run_main_results'"' == "" local run_main_results "1"
if `"`run_mechanisms'"' == "" local run_mechanisms "1"
if `"`run_heterogeneity'"' == "" local run_heterogeneity "1"
if `"`run_robustness'"' == "" local run_robustness "1"

capture log close _all
log using "${logs_dir}/stata_driver.log", text replace

if "`run_main_results'" == "1" {
    do "${package_root}/code/20_main_results/01_prepare_panel.do"
    do "${package_root}/code/20_main_results/02_main_atts.do"
    do "${package_root}/code/20_main_results/03_extract_main_results.do"
    do "${package_root}/code/20_main_results/04_fare_event.do"
    do "${package_root}/code/20_main_results/05_departures_event.do"
    do "${package_root}/code/20_main_results/06_delay_event.do"
    do "${package_root}/code/20_main_results/07_reliability_appendix.do"
}

if "`run_mechanisms'" == "1" {
    do "${package_root}/code/30_mechanisms/01_route_passenger_panel_prep.do"
    do "${package_root}/code/30_mechanisms/02_route_passenger_event_full_sa.do"
    do "${package_root}/code/30_mechanisms/03_load_factor_event.do"
    do "${package_root}/code/30_mechanisms/04_incumbent_passengers_seats_full_sa.do"
}

if "`run_heterogeneity'" == "1" {
    do "${package_root}/code/40_heterogeneity/01_fare_percentiles.do"
    do "${package_root}/code/40_heterogeneity/02_carrier_type.do"
    do "${package_root}/code/40_heterogeneity/03_frontier_service_frequency.do"
}

if "`run_robustness'" == "1" {
    do "${package_root}/code/50_robustness/01_scheduled_time.do"
    do "${package_root}/code/50_robustness/02_concurrent_carriers.do"
    do "${package_root}/code/50_robustness/03_prepare_preulcc_panel.do"
    do "${package_root}/code/50_robustness/04_preulcc_fares.do"
    do "${package_root}/code/50_robustness/05_preulcc_departures.do"
    do "${package_root}/code/50_robustness/06_basic_economy_southwest.do"
    do "${package_root}/code/50_robustness/07_never_exited.do"
    do "${package_root}/code/50_robustness/08_continuous_service.do"
    do "${package_root}/code/50_robustness/09_incumbent_passengers_seats_pretreat_sa.do"
}

log close
