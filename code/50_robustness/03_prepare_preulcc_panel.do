********************************************************************************
* 62_prepare_secondary_preulcc_panel.do
* Build secondary analysis panel for pre-ULCC Frontier entries (2011q2-2013q4)
* using never-F9 routes as controls.
*
* Output:
*   ${datawork_dir}/analysis_panel_secondary_preulcc.dta
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"

use "${input_dir}/final_dataset.dta", clear

* -----------------------------------------------------------------------------
* Define route-level pre-ULCC treatment before incumbent/base restrictions.
* A treated route has first Frontier entry in [2011q2, 2013q4].
* -----------------------------------------------------------------------------
capture drop route_first_treat
bysort route: egen int route_first_treat = max(first_treat)

preserve
    keep route time_period year quarter route_first_treat
    keep if route_first_treat > 0 & time_period == route_first_treat
    bysort route: keep if _n == 1

    gen int entry_yq = yq(year, quarter)
    format entry_yq %tq
    gen byte treated_preulcc_route = inrange(entry_yq, yq(2011, 2), yq(2013, 4))

    keep route route_first_treat year quarter entry_yq treated_preulcc_route
    rename year entry_year
    rename quarter entry_quarter

    tempfile preulcc_map
    save `preulcc_map'
restore

merge m:1 route using `preulcc_map', nogen keep(master match)
replace treated_preulcc_route = 0 if missing(treated_preulcc_route)

* -----------------------------------------------------------------------------
* Secondary sample: incumbent observations on pre-ULCC treated routes +
* never-F9 controls only.
* -----------------------------------------------------------------------------
drop if carrier == "F9"
keep if treated_preulcc_route == 1 | is_never_f9_route == 1

* Secondary treatment timing for CSDID
capture drop gvar_preulcc
gen int gvar_preulcc = 0
replace gvar_preulcc = route_first_treat if treated_preulcc_route == 1

count if treated_preulcc_route == 1 & (gvar_preulcc <= 0 | missing(gvar_preulcc))
if r(N) > 0 {
    di as error "Invalid gvar_preulcc for treated_preulcc_route observations."
    exit 459
}

label var treated_preulcc_route "Route first F9 entry in 2012q1-2013q4"
label var gvar_preulcc "Treatment cohort (pre-ULCC window); 0=never-F9 control"

* Ensure panel IDs exist and are stable
capture confirm variable panel_id
if _rc != 0 {
    encode carrier_route, gen(panel_id)
}

capture confirm variable route_id
if _rc != 0 {
    encode route, gen(route_id)
}

xtset ${ivar} ${tvar}

* Carrier type indicators
capture drop is_legacy
capture drop is_lcc
capture drop is_ulcc
gen byte is_legacy = ${legacy_filter}
gen byte is_lcc    = ${lcc_filter}
gen byte is_ulcc   = ${ulcc_filter}

* Time-varying route-level LCC presence
capture drop any_lcc_route
bysort route ${tvar}: egen byte any_lcc_route = max(is_lcc)

* Market size covariates
capture drop ln_geo_mean_pop ln_geo_mean_income
gen double ln_geo_mean_pop    = 0.5 * (log(origin_cainc_pop) + log(dest_cainc_pop))
gen double ln_geo_mean_income = 0.5 * (log(origin_cainc_per_capita_income) + log(dest_cainc_per_capita_income))

* Leisure employment share controls
capture confirm variable origin_leisure_share_emp dest_leisure_share_emp
if _rc != 0 {
    di as error "origin_leisure_share_emp or dest_leisure_share_emp not found in dataset."
    di as error "Re-run final_dataset_cleaned.R before running this script."
    exit 1
}
label var origin_leisure_share_emp "Leisure employment share - origin CBSA"
label var dest_leisure_share_emp   "Leisure employment share - destination CBSA"

* Big city route dummy (time-varying top-30 endpoint populations)
capture drop origin_big_city dest_big_city big_city_route

preserve
    keep origin time_period origin_cainc_pop
    duplicates drop
    gsort time_period -origin_cainc_pop origin
    by time_period: gen int __orig_rank = _n
    gen byte origin_big_city = (__orig_rank <= 30) if !missing(origin_cainc_pop)
    keep origin time_period origin_big_city
    tempfile orig_bc
    save `orig_bc'
restore
merge m:1 origin time_period using `orig_bc', nogen keep(master match)

preserve
    keep dest time_period dest_cainc_pop
    duplicates drop
    gsort time_period -dest_cainc_pop dest
    by time_period: gen int __dest_rank = _n
    gen byte dest_big_city = (__dest_rank <= 30) if !missing(dest_cainc_pop)
    keep dest time_period dest_big_city
    tempfile dest_bc
    save `dest_bc'
restore
merge m:1 dest time_period using `dest_bc', nogen keep(master match)

gen byte big_city_route = (origin_big_city == 1 & dest_big_city == 1)
replace big_city_route = . if missing(origin_big_city) | missing(dest_big_city)

label var origin_big_city "Origin CBSA in top 30 by CAINC population"
label var dest_big_city   "Destination CBSA in top 30 by CAINC population"
label var big_city_route  "Both endpoints in top-30 CBSA by population"

* Log departures outcome
capture drop ln_total_departures_performed
gen double ln_total_departures_performed = .
replace ln_total_departures_performed = log(total_departures_performed) if total_departures_performed > 0

* Save secondary reusable analysis dataset
save "${datawork_dir}/analysis_panel_secondary_preulcc.dta", replace

* Diagnostics
preserve
    keep route treated_preulcc_route is_never_f9_route entry_year entry_quarter route_first_treat
    bysort route: keep if _n == 1

    quietly count if treated_preulcc_route == 1
    local n_treated = r(N)
    quietly count if is_never_f9_route == 1
    local n_control = r(N)

    di as text "Secondary panel saved to ${datawork_dir}/analysis_panel_secondary_preulcc.dta"
    di as text "Route counts: treated_preulcc=" `n_treated' " | never_f9_controls=" `n_control'

    di as text "Pre-ULCC treated route entry-year/quarter distribution:"
    capture noisily tab entry_year entry_quarter if treated_preulcc_route == 1
restore

quietly count
di as text "Observation count: " r(N)
