********************************************************************************
* 94_frequency_heterogeneity_csdid2.do
*
* Heterogeneity by Frontier post-entry service frequency using csdid2.
*
* Design:
*   - Build treated-route frequency buckets from Frontier observations only
*   - Average weekly departures over g through g+3
*   - Require at least 2 observed quarters in that window
*   - Buckets: <3/week, 3-<5/week, >=5/week
*   - Estimate incumbent-only ATTs with csdid2 for:
*       1) ln_average_fare
*       2) sa_ln_total_departures_routeqoy
*       3) carrier_delay
*       4) arrival_15
*       5) sa_ln_total_passengers_routeqoy
*       6) sa_ln_total_seats_routeqoy
*       7) arrival_delay
*       8) cancellation
*   - Export ATT summaries and support diagnostics only (no plots, no events)
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local source_dta   "${input_dir}/final_dataset.dta"
local analysis_dta "${datawork_dir}/analysis_panel.dta"

local out_root    "${results_het}/frequency_csdid2"
local out_models  "`out_root'/models"
local out_summary "`out_root'/summary"
local out_support "`out_root'/support"

capture mkdir "${results_het}"
capture mkdir "`out_root'"
capture mkdir "`out_models'"
capture mkdir "`out_summary'"
capture mkdir "`out_support'"

tempfile freq_map support_tmp att_tmp

********************************************************************************
* 1) Build route-level Frontier frequency buckets from final_dataset.dta
********************************************************************************
use "`source_dta'", clear

keep route carrier is_f9_entry_route first_treat time_period total_departures_performed
keep if carrier == "F9"
keep if is_f9_entry_route == 1
drop if missing(first_treat)

gen int rel_q = time_period - first_treat
keep if inrange(rel_q, 0, 3)

gen double weekly_dep = total_departures_performed / 13 if !missing(total_departures_performed)

bysort route: egen int n_obs = count(weekly_dep)
bysort route: egen double avg_weekly_dep = mean(weekly_dep)

gen byte freq_bucket = .
replace freq_bucket = 1 if n_obs >= 2 & avg_weekly_dep < 3
replace freq_bucket = 2 if n_obs >= 2 & avg_weekly_dep >= 3 & avg_weekly_dep < 5
replace freq_bucket = 3 if n_obs >= 2 & avg_weekly_dep >= 5

label define freq_bucket_lbl ///
    1 "<3/week" ///
    2 "3-<5/week" ///
    3 ">=5/week", replace
label values freq_bucket freq_bucket_lbl

bysort route: keep if _n == 1
keep route n_obs avg_weekly_dep freq_bucket
sort route
save "`freq_map'", replace

export delimited using "`out_support'/route_frequency_bucket_map.csv", replace
save "`out_support'/route_frequency_bucket_map.dta", replace

tempname psupp
postfile `psupp' ///
    str40 metric str24 subgroup double value ///
    using "`support_tmp'", replace

quietly count
post `psupp' ("treated_routes_all") ("all") (r(N))

quietly count if n_obs < 2
post `psupp' ("treated_routes_dropped_nobs_lt2") ("all") (r(N))

quietly count if n_obs >= 2
post `psupp' ("treated_routes_retained") ("all") (r(N))

forvalues g = 1/3 {
    local glabel : label freq_bucket_lbl `g'
    quietly count if freq_bucket == `g'
    post `psupp' ("treated_routes_bucket_count") ("`glabel'") (r(N))
}

********************************************************************************
* 2) Load incumbent-only analysis sample and merge route-level buckets
********************************************************************************
use "`analysis_dta'", clear

capture assert carrier != "F9"
if _rc != 0 {
    di as error "Frontier observations detected in analysis sample."
    exit 459
}

merge m:1 route using "`freq_map'", nogen keep(master match)

preserve
    keep route first_treat freq_bucket
    bysort route: keep if _n == 1

    quietly count if first_treat > 0
    post `psupp' ("analysis_treated_routes_total") ("all") (r(N))

    quietly count if first_treat > 0 & missing(freq_bucket)
    post `psupp' ("analysis_treated_routes_missing_bucket") ("all") (r(N))

    forvalues g = 1/3 {
        local glabel : label freq_bucket_lbl `g'
        quietly count if first_treat > 0 & freq_bucket == `g'
        post `psupp' ("analysis_treated_routes_bucket_count") ("`glabel'") (r(N))
    }
restore

********************************************************************************
* 3) Recreate route x quarter-of-year seasonal adjustment for departures,
*    passengers, and seats
********************************************************************************
capture drop qoy ///
    ln_total_passengers_q ln_total_seats_q ///
    mean_dep_panelq mean_pax_panelq mean_seats_panelq ///
    sa_ln_total_departures_panelqoy sa_ln_total_passengers_panelqoy sa_ln_total_seats_panelqoy ///
    route_cluster_id

gen byte qoy = mod(${tvar} - 1, 4) + 1

gen double ln_total_passengers_q = .
replace ln_total_passengers_q = log(total_passengers) if total_passengers > 0

gen double ln_total_seats_q = .
replace ln_total_seats_q = log(total_seats) if total_seats > 0

bysort ${ivar} qoy: egen double mean_dep_panelq = mean(ln_total_departures_performed)
bysort ${ivar} qoy: egen double mean_pax_panelq = mean(ln_total_passengers_q)
bysort ${ivar} qoy: egen double mean_seats_panelq = mean(ln_total_seats_q)

gen double sa_ln_total_departures_panelqoy = ln_total_departures_performed - mean_dep_panelq
gen double sa_ln_total_passengers_panelqoy = ln_total_passengers_q - mean_pax_panelq
gen double sa_ln_total_seats_panelqoy = ln_total_seats_q - mean_seats_panelq

drop mean_dep_panelq
drop mean_pax_panelq mean_seats_panelq

gen long route_cluster_id = route_id

preserve
    keep ${ivar} qoy sa_ln_total_departures_panelqoy sa_ln_total_passengers_panelqoy sa_ln_total_seats_panelqoy
    collapse ///
        (mean) mean_sa_ln_dep = sa_ln_total_departures_panelqoy ///
        (mean) mean_sa_ln_pax = sa_ln_total_passengers_panelqoy ///
        (mean) mean_sa_ln_seats = sa_ln_total_seats_panelqoy, ///
        by(${ivar} qoy)
    gen double abs_mean_sa_ln_dep = abs(mean_sa_ln_dep)
    gen double abs_mean_sa_ln_pax = abs(mean_sa_ln_pax)
    gen double abs_mean_sa_ln_seats = abs(mean_sa_ln_seats)
    quietly summarize abs_mean_sa_ln_dep, meanonly
    post `psupp' ("max_abs_mean_sa_ln_dep_panel_qoy") ("all") (r(max))
    quietly summarize abs_mean_sa_ln_pax, meanonly
    post `psupp' ("max_abs_mean_sa_ln_pax_panel_qoy") ("all") (r(max))
    quietly summarize abs_mean_sa_ln_seats, meanonly
    post `psupp' ("max_abs_mean_sa_ln_seats_panel_qoy") ("all") (r(max))
restore

postclose `psupp'

use "`support_tmp'", clear
sort metric subgroup
save "`out_support'/frequency_support_summary.dta", replace
export delimited using "`out_support'/frequency_support_summary.csv", replace

********************************************************************************
* 4) Run csdid2 ATT-only models by bucket and outcome
********************************************************************************
use "`analysis_dta'", clear

capture assert carrier != "F9"
if _rc != 0 {
    di as error "Frontier observations detected in analysis sample."
    exit 459
}

merge m:1 route using "`freq_map'", nogen keep(master match)

capture drop qoy ///
    ln_total_passengers_q ln_total_seats_q ///
    mean_dep_panelq mean_pax_panelq mean_seats_panelq ///
    sa_ln_total_departures_panelqoy sa_ln_total_passengers_panelqoy sa_ln_total_seats_panelqoy ///
    route_cluster_id
gen byte qoy = mod(${tvar} - 1, 4) + 1

gen double ln_total_passengers_q = .
replace ln_total_passengers_q = log(total_passengers) if total_passengers > 0

gen double ln_total_seats_q = .
replace ln_total_seats_q = log(total_seats) if total_seats > 0

bysort ${ivar} qoy: egen double mean_dep_panelq = mean(ln_total_departures_performed)
bysort ${ivar} qoy: egen double mean_pax_panelq = mean(ln_total_passengers_q)
bysort ${ivar} qoy: egen double mean_seats_panelq = mean(ln_total_seats_q)

gen double sa_ln_total_departures_panelqoy = ln_total_departures_performed - mean_dep_panelq
gen double sa_ln_total_passengers_panelqoy = ln_total_passengers_q - mean_pax_panelq
gen double sa_ln_total_seats_panelqoy = ln_total_seats_q - mean_seats_panelq

drop mean_dep_panelq
drop mean_pax_panelq mean_seats_panelq
gen long route_cluster_id = route_id

tempname patt
postfile `patt' ///
    str8 subgroup str24 subgroup_label ///
    str32 outcome str120 model_id ///
    str20 covar_spec str200 covariates ///
    byte model_ok int rc ///
    double att se z p ll ul ///
    double N N_clust ///
    double treated_routes_bucket treated_obs_bucket ///
    using "`att_tmp'", replace

forvalues g = 1/3 {
    local glabel : label freq_bucket_lbl `g'
    local gname = cond(`g' == 1, "lt3", cond(`g' == 2, "3to5", "5plus"))

    foreach y in ln_average_fare sa_ln_total_departures_panelqoy carrier_delay arrival_15 cancellation sa_ln_total_passengers_panelqoy sa_ln_total_seats_panelqoy arrival_delay {
        local covars "${covars_small}"
        local covar_spec "main"

        local model_id "freq_`gname'_`y'_dripw"

        di as result _n "Running `model_id'"
        di as text "  Bucket: `glabel'"
        di as text "  Outcome: `y'"
        di as text "  Covariates: `covars'"

        capture noisily csdid2 `y' `covars' if (is_never_f9_route == 1 | freq_bucket == `g'), ///
            ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
            method(dripw) cluster(route_cluster_id) short

        local rc = _rc
        local model_ok = (`rc' == 0)
        local att = .
        local se = .
        local z = .
        local p = .
        local ll = .
        local ul = .
        local N = .
        local N_clust = .
        local treated_routes_bucket = .
        local treated_obs_bucket = .

        tempvar est_input cluster_tag
        egen byte `est_input' = rownonmiss(`y' `covars')
        replace `est_input' = (`est_input' == (1 + wordcount("`covars'"))) ///
            & (is_never_f9_route == 1 | freq_bucket == `g') ///
            & !missing(${ivar}, ${tvar}, ${gvar}, route_cluster_id)
        quietly count if `est_input'
        local N = r(N)
        egen byte `cluster_tag' = tag(route_cluster_id) if `est_input'
        quietly count if `cluster_tag'
        local N_clust = r(N)

        tempvar treated_route_tag
        egen byte `treated_route_tag' = tag(route) if first_treat > 0 & freq_bucket == `g'
        quietly count if `treated_route_tag'
        local treated_routes_bucket = r(N)

        quietly count if `est_input' & first_treat > 0 & freq_bucket == `g'
        local treated_obs_bucket = r(N)

        drop `treated_route_tag'
        drop `est_input' `cluster_tag'

        if `model_ok' {
            estimates save "`out_models'/`model_id'", replace

            capture noisily estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
            local rc_simple = _rc

            if `rc_simple' == 0 {
                matrix A = r(table)
                local att = A[1,1]
                local se  = A[2,1]
                local z   = A[3,1]
                local p   = A[4,1]
                if `p' >= . local p = 2 * normal(-abs(`z'))
                local ll  = A[5,1]
                local ul  = A[6,1]
            }
            else {
                di as error "estat simple failed for `model_id' (rc=`rc_simple')"
                local model_ok = 0
                local rc = `rc_simple'
            }
        }
        else {
            di as error "csdid2 failed for `model_id' (rc=`rc')"
        }

        post `patt' ///
            ("`gname'") ("`glabel'") ///
            ("`y'") ("`model_id'") ///
            ("`covar_spec'") ("`covars'") ///
            (`model_ok') (`rc') ///
            (`att') (`se') (`z') (`p') (`ll') (`ul') ///
            (`N') (`N_clust') ///
            (`treated_routes_bucket') (`treated_obs_bucket')
    }
}

postclose `patt'

use "`att_tmp'", clear
sort subgroup outcome
save "`out_summary'/att_frequency_heterogeneity.dta", replace
export delimited using "`out_summary'/att_frequency_heterogeneity.csv", replace

di as result _n "Frequency heterogeneity ATT module complete."
di as result "Models:  `out_models'"
di as result "ATT CSV: `out_summary'/att_frequency_heterogeneity.csv"
di as result "Support: `out_support'/frequency_support_summary.csv"
