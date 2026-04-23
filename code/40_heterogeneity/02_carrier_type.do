********************************************************************************
* 95_carrier_heterogeneity_csdid2.do
*
* Carrier-type heterogeneity using csdid2 with seeded wild-bootstrap inference.
*
* Groups:
*   1) Legacy carriers
*   2) LCCs
*
* Outcomes:
*   1) ln_average_fare
*   2) sa_ln_total_departures_routeqoy
*   3) sa_ln_total_passengers_routeqoy
*   4) sa_ln_total_seats_routeqoy
*   5) carrier_delay
*   6) arrival_15
*   7) cancellation
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta "${datawork_dir}/analysis_panel.dta"

local out_root    "${results_het}/carrier_csdid2"
local out_models  "`out_root'/models"
local out_summary "`out_root'/summary"
local out_support "`out_root'/support"

capture mkdir "${results_het}"
capture mkdir "`out_root'"
capture mkdir "`out_models'"
capture mkdir "`out_summary'"
capture mkdir "`out_support'"

tempfile att_tmp support_tmp

********************************************************************************
* 1) Load analysis sample and verify subgroup variables
********************************************************************************
use "`in_dta'", clear

capture assert carrier != "F9"
if _rc != 0 {
    di as error "Frontier observations detected in analysis sample."
    exit 459
}

capture confirm variable is_legacy
if _rc != 0 {
    di as error "is_legacy missing from analysis_panel.dta"
    exit 459
}

capture confirm variable is_lcc
if _rc != 0 {
    di as error "is_lcc missing from analysis_panel.dta"
    exit 459
}

********************************************************************************
* 2) Construct seasonally adjusted quantity outcomes
********************************************************************************
capture drop ///
    qoy ///
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

drop mean_dep_panelq mean_pax_panelq mean_seats_panelq

gen long route_cluster_id = route_id

********************************************************************************
* 3) Support and seasonal-adjustment diagnostics
********************************************************************************
tempname psupp
postfile `psupp' ///
    str40 metric str16 subgroup double value ///
    using "`support_tmp'", replace

forvalues s = 1/2 {
    local subgroup = cond(`s' == 1, "legacy", "lcc")
    local cond = cond(`s' == 1, "is_legacy == 1", "is_lcc == 1")

    preserve
        keep if `cond'

        quietly count
        post `psupp' ("subgroup_obs") ("`subgroup'") (r(N))

        egen byte panel_tag = tag(${ivar})
        quietly count if panel_tag
        post `psupp' ("subgroup_panels") ("`subgroup'") (r(N))
        drop panel_tag

        egen byte route_tag = tag(route)
        quietly count if route_tag
        post `psupp' ("subgroup_routes") ("`subgroup'") (r(N))
        quietly count if route_tag & first_treat > 0
        post `psupp' ("treated_routes") ("`subgroup'") (r(N))
        quietly count if route_tag & is_never_f9_route == 1
        post `psupp' ("never_treated_routes") ("`subgroup'") (r(N))
        drop route_tag
    restore
}

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
save "`out_support'/carrier_support_summary.dta", replace
export delimited using "`out_support'/carrier_support_summary.csv", replace

********************************************************************************
* 4) Estimate subgroup-specific csdid2 models and extract ATT summaries
********************************************************************************
use "`in_dta'", clear

capture assert carrier != "F9"
if _rc != 0 {
    di as error "Frontier observations detected in analysis sample."
    exit 459
}

capture drop ///
    qoy ///
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

drop mean_dep_panelq mean_pax_panelq mean_seats_panelq
gen long route_cluster_id = route_id

tempname patt
postfile `patt' ///
    str8 subgroup str16 subgroup_label ///
    str32 outcome str120 model_id ///
    str20 covar_spec str200 covariates ///
    byte model_ok int rc ///
    double att se z p ll ul ///
    double N N_clust treated_routes ///
    using "`att_tmp'", replace

foreach subgroup in legacy lcc {
    local subgroup_label = cond("`subgroup'" == "legacy", "Legacy", "LCC")
    local cond = cond("`subgroup'" == "legacy", "is_legacy == 1", "is_lcc == 1")

    foreach y in ln_average_fare sa_ln_total_departures_panelqoy sa_ln_total_passengers_panelqoy sa_ln_total_seats_panelqoy carrier_delay arrival_15 cancellation {
        local covars "${covars_small}"
        local covar_spec "main"

        local model_id "carrier_`subgroup'_`y'_dripw"

        di as result _n "Running `model_id'"
        di as text "  Subgroup: `subgroup_label'"
        di as text "  Outcome: `y'"
        di as text "  Covariates: `covars'"

        capture noisily csdid2 `y' `covars' if `cond', ///
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
        local treated_routes = .

        tempvar est_input cluster_tag treated_route_tag
        egen byte `est_input' = rownonmiss(`y' `covars')
        replace `est_input' = (`est_input' == (1 + wordcount("`covars'"))) ///
            & `cond' & !missing(${ivar}, ${tvar}, ${gvar}, route_cluster_id)
        quietly count if `est_input'
        local N = r(N)
        egen byte `cluster_tag' = tag(route_cluster_id) if `est_input'
        quietly count if `cluster_tag'
        local N_clust = r(N)

        egen byte `treated_route_tag' = tag(route) if `cond' & first_treat > 0
        quietly count if `treated_route_tag'
        local treated_routes = r(N)

        drop `treated_route_tag' `est_input' `cluster_tag'

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
            ("`subgroup'") ("`subgroup_label'") ///
            ("`y'") ("`model_id'") ///
            ("`covar_spec'") ("`covars'") ///
            (`model_ok') (`rc') ///
            (`att') (`se') (`z') (`p') (`ll') (`ul') ///
            (`N') (`N_clust') (`treated_routes')
    }
}

postclose `patt'

use "`att_tmp'", clear
sort subgroup outcome
save "`out_summary'/att_carrier_heterogeneity.dta", replace
export delimited using "`out_summary'/att_carrier_heterogeneity.csv", replace

di as result _n "Carrier heterogeneity ATT module complete."
di as result "Models:  `out_models'"
di as result "ATT CSV: `out_summary'/att_carrier_heterogeneity.csv"
di as result "Support: `out_support'/carrier_support_summary.csv"
