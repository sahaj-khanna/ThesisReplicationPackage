********************************************************************************
* 01_prepare_panel.do
* Loads final dataset, applies base restrictions, builds panel IDs, saves input
* used by all analysis modules.
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"

use "${input_dir}/final_dataset.dta", clear

* Base sample restrictions
drop if carrier == "F9"
keep if ${base_sample}

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

* Carrier type indicators for subgroup analysis
capture drop is_legacy 
capture drop is_lcc 
capture drop is_ulcc
gen byte is_legacy = ${legacy_filter}
gen byte is_lcc    = ${lcc_filter}
gen byte is_ulcc   = ${ulcc_filter}

* Time-varying route-level carrier-type presence (incumbents only): 1 if any carrier type
* operates on this route in this quarter.
capture drop any_lcc_route any_legacy_route any_ulcc_route
bysort route ${tvar}: egen byte any_lcc_route    = max(is_lcc)
bysort route ${tvar}: egen byte any_legacy_route = max(is_legacy)
bysort route ${tvar}: egen byte any_ulcc_route   = max(is_ulcc)

* Market size covariates: log geometric means of passenger volumes and personal income
capture drop ln_geo_mean_pop ln_geo_mean_income
gen double ln_geo_mean_pop    = 0.5 * (log(origin_cainc_pop) + log(dest_cainc_pop))
gen double ln_geo_mean_income = 0.5 * (log(origin_cainc_per_capita_income) + log(dest_cainc_per_capita_income))

* Leisure employment share controls (origin and destination separately)
* These variables are created in final_dataset_cleaned.R Section 7 and must exist in the .dta
capture confirm variable origin_leisure_share_emp dest_leisure_share_emp
if _rc != 0 {
    di as error "origin_leisure_share_emp or dest_leisure_share_emp not found in dataset."
    di as error "Re-run final_dataset_cleaned.R before running this script."
    exit 1
}
label var origin_leisure_share_emp "Leisure employment share — origin CBSA"
label var dest_leisure_share_emp   "Leisure employment share — destination CBSA"

* Big city route dummy
* A CBSA is "big city" if it ranks in the top 30 by CAINC population in that quarter.
* Route is "big city" if BOTH origin and destination endpoints are big city.
* Population is not affected by Frontier's entry, so time-varying ranking is appropriate.

capture drop origin_big_city dest_big_city big_city_route

* Step 1: Rank origin CBSAs by population within each time period
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

* Step 2: Rank destination CBSAs by population within each time period
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

* Step 3: Route-level big city indicator
gen byte big_city_route = (origin_big_city == 1 & dest_big_city == 1)
replace big_city_route = . if missing(origin_big_city) | missing(dest_big_city)

label var origin_big_city "Origin CBSA in top 30 by CAINC population (time-varying)"
label var dest_big_city   "Destination CBSA in top 30 by CAINC population (time-varying)"
label var big_city_route  "Both endpoints in top-30 CBSA by population"

* Log departures (for scale-robust heterogeneity comparisons)
capture drop ln_total_departures_performed
gen double ln_total_departures_performed = .
replace ln_total_departures_performed = log(total_departures_performed) if total_departures_performed > 0

* Additional logged departure/capacity outcomes for robustness grids
capture drop ln_total_departures_scheduled ln_total_seats
gen double ln_total_departures_scheduled = .
replace ln_total_departures_scheduled = log(total_departures_scheduled) if total_departures_scheduled > 0
gen double ln_total_seats = .
replace ln_total_seats = log(total_seats) if total_seats > 0

* Note: SA outcomes (sa_total_departures_performed, sa_load_factor, sa_ln_total_departures_performed)
* were removed. CSDID's DRIPW estimator already absorbs common time effects internally via
* the time fixed effects in the propensity score and outcome regressions, making a separate
* residualization on global quarter dummies redundant.


* Route-level carrier-structure variables for competition heterogeneity
* n_carriers_rt: distinct incumbent carriers on route-quarter
capture drop __tag_carrier n_carriers_rt
bysort route ${tvar} carrier: gen byte __tag_carrier = (_n == 1)
bysort route ${tvar}: egen int n_carriers_rt = total(__tag_carrier)
drop __tag_carrier

* n_carriers_pre_treat: carrier count one quarter before treatment (treated routes only)
* comp_grp_treated: 1=mono, 2=duop, 3=olig (>=3) for treated routes; missing for never-treated
capture drop route_first_treat is_tminus1 n_carriers_pre_treat comp_grp_treated
bysort route: egen int route_first_treat = max(${gvar})
gen byte is_tminus1 = (route_first_treat > 0 & ${tvar} == route_first_treat - 1)
bysort route: egen int n_carriers_pre_treat = max(cond(is_tminus1 == 1, n_carriers_rt, .))
gen byte comp_grp_treated = .
replace comp_grp_treated = 1 if route_first_treat > 0 & n_carriers_pre_treat == 1
replace comp_grp_treated = 2 if route_first_treat > 0 & n_carriers_pre_treat == 2
replace comp_grp_treated = 3 if route_first_treat > 0 & n_carriers_pre_treat >= 3 & n_carriers_pre_treat < .
drop is_tminus1

* Fixed competition-structure controls used in heterogeneity CSDID runs:
* treated routes use t = g-1 count; never-treated routes use first observed count.
capture drop first_route_obs n_carriers_first_obs n_carriers_match_base
bysort route (${tvar}): gen byte first_route_obs = (_n == 1)
bysort route: egen int n_carriers_first_obs = max(cond(first_route_obs == 1, n_carriers_rt, .))
gen int n_carriers_match_base = n_carriers_pre_treat
replace n_carriers_match_base = n_carriers_first_obs if route_first_treat == 0
drop first_route_obs

capture drop ncar_match_duop ncar_match_olig
gen byte ncar_match_duop = (n_carriers_match_base == 2) if n_carriers_match_base < .
gen byte ncar_match_olig = (n_carriers_match_base >= 3) if n_carriers_match_base < .

label define comp_grp_treated_lbl 1 "Monopoly (1)" 2 "Duopoly (2)" 3 "Oligopoly (3+)"
label values comp_grp_treated comp_grp_treated_lbl

* Save reusable analysis dataset
save "${datawork_dir}/analysis_panel.dta", replace

di as text "Prepared panel saved to ${datawork_dir}/analysis_panel.dta"
di as text "Observations: " _N
tab first_treat if first_treat > 0
di as text "Carrier count one quarter pre-treatment (treated routes):"
capture tab n_carriers_pre_treat if route_first_treat > 0, missing
di as text "Treated competition groups (route level):"
capture tab comp_grp_treated if route_first_treat > 0, missing

	
