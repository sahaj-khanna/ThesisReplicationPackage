* 98a_southwest_only_fare_csdid2.do
* Basic economy robustness: Southwest Airlines never introduced basic economy.
* Restricts sample to Southwest (WN) only and re-estimates the main fare spec.
* If the fare ATT is similar to the full-sample estimate (-7.2%), basic economy
* rollout by other carriers is not driving the main result.
*
* Uses the standardized csdid2 + wild-bootstrap package settings.
version 18
set more off
do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${results_rob}/basic_economy/southwest_only"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"
local out_summary "`out_root'/summary"

capture mkdir "${results_rob}/basic_economy"
capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"
capture mkdir "`out_summary'"

* ==========================================================================
*  LOAD DATA & RESTRICT TO SOUTHWEST
* ==========================================================================

use "`in_dta'", clear

* Keep only Southwest Airlines observations
keep if carrier == "WN"

di as result "=== Sample after restricting to Southwest (WN) ==="
di as result "Observations: " _N

* Diagnostics: how many treated/control routes have Southwest service?
quietly count if is_f9_entry_route == 1
local n_treated_obs = r(N)
preserve
    keep if is_f9_entry_route == 1
    bysort route_id: keep if _n == 1
    quietly count
    local n_treated_routes = r(N)
restore
preserve
    keep if is_f9_entry_route == 0
    bysort route_id: keep if _n == 1
    quietly count
    local n_control_routes = r(N)
restore

di as result "Treated route-quarters: `n_treated_obs'"
di as result "Unique treated routes with WN presence: `n_treated_routes'"
di as result "Unique control routes with WN presence: `n_control_routes'"

* Re-set panel structure after subsetting
xtset ${ivar} ${tvar}

* csdid2 requires cluster variable name to differ from ivar
gen long cluster_id = route_id

* ==========================================================================
*  ESTIMATION: LOG AVERAGE FARE
* ==========================================================================

local model_stub "wn_only_lnfare_maincov_never_dripw"

di as result _newline "=== CSDID2: Southwest-only, log average fare ==="

cd "`out_ster'"
csdid2 ln_average_fare ${covars_small}, ///
    ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
    method(dripw) cluster(cluster_id) short

if _rc != 0 {
    di as error "ESTIMATION FAILED (rc=`_rc')"
    exit `_rc'
}

estimates save "`model_stub'", replace

* --- Overall ATT ---
di as result _newline "=== OVERALL ATT: Southwest-only fare effect ==="
estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
matrix A = r(table)

* --- Event study ---
estat event, window(-${wpre_main} ${wpost_main}) wboot reps(${wb_reps}) rseed(${seed_std})

matrix E = r(table)
local cnames : colfullnames E
local k = colsof(E)

tempfile ev_tmp
tempname pev
postfile `pev' int event_time double coef se ll ul using "`ev_tmp'", replace
forvalues j = 1/`k' {
    local cname : word `j' of `cnames'
    local et = .
    if      regexm("`cname'", "^tm([0-9]+)$") local et = -real(regexs(1))
    else if regexm("`cname'", "^tp([0-9]+)$") local et =  real(regexs(1))
    else continue
    post `pev' (`et') (E[1,`j']) (E[2,`j']) (E[5,`j']) (E[6,`j'])
}
postclose `pev'

preserve
use "`ev_tmp'", clear
sort event_time

* Add t=-1 reference period
local n = _N + 1
set obs `n'
replace event_time = -1 in `n'
replace coef = 0      in `n'
replace se   = 0      in `n'
replace ll   = 0      in `n'
replace ul   = 0      in `n'
sort event_time

* Multiply by 100 for percentage interpretation
gen double coef_plot = coef * 100
gen double ll_plot   = ll * 100
gen double ul_plot   = ul * 100

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

* --- Plot ---
quietly sum ll_plot
local ymin = floor(r(min)/5)*5 - 5
quietly sum ul_plot
local ymax = ceil(r(max)/5)*5 + 5

twoway ///
    (rarea ul_plot ll_plot event_time, color(gs8%40) lwidth(none)) ///
    (connected coef_plot event_time, sort lcolor(gs4) mcolor(gs4) ///
        msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_main}(2)${wpost_main}, labsize(medium)) ///
    ylabel(`ymin'(5)`ymax', labsize(medium)) ///
    yscale(range(`ymin' `ymax')) ///
    xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
    ytitle("Estimated Treatment Effect (%)", size(medlarge)) ///
    title("Southwest Airlines Only", size(medium)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
di as result "Saved: `plots_dir'/es_`model_stub'.pdf"

preserve
    clear
    set obs 1
    gen str40 model_stub = "`model_stub'"
    gen str40 sample = "Southwest only"
    gen double att = A[1,1]
    gen double se = A[2,1]
    gen double pvalue = A[4,1]
    gen double ll = A[5,1]
    gen double ul = A[6,1]
    export delimited using "`out_summary'/`model_stub'.csv", replace
restore

restore

* ==========================================================================
*  SUMMARY
* ==========================================================================

di as result _newline(2)
di as result "================================================================"
di as result "  SOUTHWEST-ONLY FARE ROBUSTNESS COMPLETE"
di as result "================================================================"
di as result "  Purpose: Basic economy robustness — WN never introduced BE"
di as result "  Compare ATT to main result: -7.24%"
di as result "  Results in: `out_root'"
di as result "================================================================"
