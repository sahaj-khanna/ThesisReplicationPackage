********************************************************************************
* replication_package/code/shared/paths.do
* Central package paths, output roots, and thesis-analysis specs.
********************************************************************************

version 18

if `"$package_root"' == "" {
    global package_root `"`c(pwd)'"'
}

global repo_root = subinstr("$package_root", "/replication_package", "", .)

global code_root   "${package_root}/code"
global shared_code_dir "${code_root}/shared"

global data_root   "${package_root}/data"
global input_dir   "${data_root}/final"
global raw_data_dir "${data_root}/raw"
global intermediate_data_dir "${data_root}/intermediate"

global output_dir   "${package_root}/output"
global logs_dir     "${output_dir}/logs"
global datawork_dir "${output_dir}/shared/data_work"
global results_main "${output_dir}/20_main_results"
global results_het  "${output_dir}/40_heterogeneity"
global results_rob  "${output_dir}/50_robustness"
global results_sum  "${output_dir}/10_summary_background"

capture mkdir "${output_dir}"
capture mkdir "${logs_dir}"
capture mkdir "${datawork_dir}"
capture mkdir "${results_main}"
capture mkdir "${results_het}"
capture mkdir "${results_rob}"
capture mkdir "${results_sum}"

* -------------------------- CORE PANEL VARS ----------------------------------
global ivar panel_id
global tvar time_period
global gvar first_treat
global clustvar route_id

* ------------------------- BASE SAMPLE FILTER --------------------------------
global base_sample "(is_never_f9_route == 1 | is_f9_entry_route == 1)"

* ----------------------------- OUTCOMES --------------------------------------
global outcomes_main "ln_average_fare average_fare fare_ratio_90_10 total_seats total_departures_performed load_factor departure_delay arrival_delay delay_15 arrival_15 cancellation"
global outcomes_no_covars "ln_average_fare average_fare fare_ratio_90_10 total_seats total_departures_performed load_factor departure_delay arrival_delay delay_15 arrival_15 cancellation"
global outcomes_fare_percentiles "fare_p10 fare_p25 fare_p75 fare_p90"
global outcomes_carrier_type "ln_average_fare fare_ratio_90_10 total_departures_performed total_seats load_factor"
global outcomes_robust_key "ln_average_fare total_departures_performed arrival_delay"

* -------------------------- COVARIATE SPECS ----------------------------------
global covars_none ""
global covars_small "average_dist route_hhi ln_geo_mean_pop ln_geo_mean_income origin_leisure_share_emp dest_leisure_share_emp big_city_route hub_route"
global covars_large "average_dist route_hhi route_capacity_passengers ln_geo_mean_pop ln_geo_mean_income origin_leisure_share_emp dest_leisure_share_emp big_city_route any_lcc_route hub_route"

global covar_spec_main "small"
global covar_spec_het  "small"

* -------------------------- CARRIER SUBGROUPS --------------------------------
global legacy_filter `"inlist(carrier, "AA", "DL", "UA", "US", "AS", "CO")"'
global lcc_filter    `"inlist(carrier, "WN", "B6", "FL", "VX")"'
global ulcc_filter   `"inlist(carrier, "NK", "G4")"'

* ------------------------- STANDARDIZED SETTINGS ------------------------------
global seed_std 240422
global wb_reps 999
global wpre_main 6
global wpost_main 8
global wpre_delay 6
global wpost_quality 8
