********************************************************************************
* 91_route_pax_panel_prep.do
*
* Builds a route-quarter panel for the total-passenger analysis.
* Unlike the main carrier-route panel, Frontier is NOT dropped here because
* route_capacity_passengers (the outcome) should include all carriers' ridership.
* The panel collapses the carrier-route data to one row per route-quarter.
*
* Output: ${datawork_dir}/route_pax_panel.dta
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"

use "${input_dir}/final_dataset.dta", clear

* ---------------------------------------------------------------------------
* 1. Apply base sample filter at route level
*    Keep routes that are treated (F9 entered ≥2014 Q1) or never treated.
*    This mirrors the base_sample global but we keep all carriers (incl. F9).
* ---------------------------------------------------------------------------
keep if ${base_sample}

* ---------------------------------------------------------------------------
* 2. Derive route-level controls that are not in final_dataset.dta
*    (Mirrors 02_prepare_panel.do exactly)
* ---------------------------------------------------------------------------

* Log geometric mean population and income
capture drop ln_geo_mean_pop ln_geo_mean_income
gen double ln_geo_mean_pop    = 0.5 * (log(origin_cainc_pop) + log(dest_cainc_pop))
gen double ln_geo_mean_income = 0.5 * (log(origin_cainc_per_capita_income) + log(dest_cainc_per_capita_income))

* Big city route: both endpoints in top-30 CBSA by population (time-varying)
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

* ---------------------------------------------------------------------------
* 3. Collapse to route-quarter level
*    route_capacity_passengers is already a route-level aggregate (same for all
*    carriers in a route-quarter), so (max) and (first) are equivalent here.
* ---------------------------------------------------------------------------
collapse ///
    (max)   route_capacity_passengers                                       ///
    (max)   first_treat                                                     ///
    (first) average_dist                                                    ///
    (first) route_hhi                                                       ///
    (first) ln_geo_mean_pop ln_geo_mean_income                              ///
    (first) origin_leisure_share_emp dest_leisure_share_emp                 ///
    (first) big_city_route hub_route                                        ///
    , by(route time_period)

* ---------------------------------------------------------------------------
* 4. Create numeric panel ID and log outcome
* ---------------------------------------------------------------------------
encode route, gen(route_id)

gen double ln_route_pax = .
replace ln_route_pax = log(route_capacity_passengers) if route_capacity_passengers > 0

label var ln_route_pax           "Log total route passengers (all carriers, T-100)"
label var route_capacity_passengers "Total route passengers — all carriers (T-100)"

* ---------------------------------------------------------------------------
* 5. Set panel structure and save
* ---------------------------------------------------------------------------
xtset route_id time_period

di as result "Route-pax panel: " _N " obs"
di as result "Routes total:    " `=scalar(e(N_g)) + 0' "  (xtset may not populate — use:"
quietly levelsof route_id, local(all_routes)
di as result "  " `: word count `all_routes'' " unique routes"
quietly count if first_treat > 0
di as result "  Treated route-quarters: " r(N)
quietly count if first_treat == 0
di as result "  Control route-quarters: " r(N)
sum ln_route_pax, detail

save "${datawork_dir}/route_pax_panel.dta", replace
di as result "Saved: ${datawork_dir}/route_pax_panel.dta"
