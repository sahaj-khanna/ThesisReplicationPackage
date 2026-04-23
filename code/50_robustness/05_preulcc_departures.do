* 64_preulcc_seasadj_lndep_smallcov_core.do
* Pre-ULCC event study: seasonally-adjusted ln_total_departures_performed
* Mirrors Script 47b but residualises on route x quarter-of-year means
* before running CSDID (same seasonal adjustment as Script 57).
* Sample  : All incumbent carriers in pre-ULCC panel (no core-carrier restriction)
* Covars  : covars_small
* Method  : DRIPW, cluster(route_id)
* Control : never-treated (never-F9 routes)
* Window  : -6 to +8

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel_secondary_preulcc.dta"
local out_root "${results_rob}/preulcc_seasadj_lndep_smallcov_core"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

* -------------------------------------------------------------------------
* Step 1: Load and residualise
* -------------------------------------------------------------------------
use "`in_dta'", clear

* Quarter of year (1=Q1 ... 4=Q4)
gen byte qoy = mod(${tvar} - 1, 4) + 1

* Route x quarter-of-year demeaning (same as Script 57)
bysort ${ivar} qoy: egen mean_dep_rq = mean(ln_total_departures_performed)
gen double ln_dep_seas_adj = ln_total_departures_performed - mean_dep_rq
drop mean_dep_rq

di as result "=== Residualisation complete ==="
summarize ln_dep_seas_adj, detail

* Sample summary
quietly count if gvar_preulcc > 0 & !missing(gvar_preulcc)
local n_treated = r(N)
quietly count if gvar_preulcc == 0
local n_control = r(N)
di as result "======================================================"
di as result "PRE-ULCC | seas-adj ln_departures | SMALL covars | all incumbents"
di as result "======================================================"
di as result "Treated obs:  `n_treated'"
di as result "Control obs:  `n_control'"
di as result "======================================================"

* -------------------------------------------------------------------------
* Step 2: CSDID2 on seasonally-adjusted outcome
* -------------------------------------------------------------------------
capture drop cluster_id
gen long cluster_id = route_id

local model_stub "preulcc_seasadj_lndep_maincov_never_dripw"

cd "`out_ster'"
capture noisily csdid2 ln_dep_seas_adj ${covars_small}, ///
    ivar(${ivar}) time(${tvar}) gvar(gvar_preulcc) ///
    method(dripw) cluster(cluster_id) short

if _rc != 0 {
    di as error "FAILED (rc=`_rc')"
    exit _rc
}

estimates save "`model_stub'", replace

di as result _newline "=== OVERALL ATT ==="
estat simple, wboot reps(${wb_reps}) rseed(${seed_std})

estat event, window(-${wpre_main} ${wpost_main}) wboot reps(${wb_reps}) rseed(${seed_std})

* -------------------------------------------------------------------------
* Step 3: Extract event study and plot
* -------------------------------------------------------------------------
matrix E = r(table)
local cnames : colfullnames E
local k = colsof(E)

tempfile ev_tmp
tempname pev
postfile `pev' int event_time double coef ll ul using "`ev_tmp'", replace
forvalues j = 1/`k' {
    local cname : word `j' of `cnames'
    local et = .
    if      regexm("`cname'", "^tm([0-9]+)$") local et = -real(regexs(1))
    else if regexm("`cname'", "^tp([0-9]+)$") local et =  real(regexs(1))
    else continue
    post `pev' (`et') (E[1,`j']) (E[5,`j']) (E[6,`j'])
}
postclose `pev'

use "`ev_tmp'", clear
sort event_time

local n = _N + 1
set obs `n'
replace event_time = -1 in `n'
replace coef = 0 in `n'
replace ll = 0 in `n'
replace ul = 0 in `n'
sort event_time

gen double coef_plot = coef * 100
gen double ll_plot   = ll   * 100
gen double ul_plot   = ul   * 100

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

quietly sum ll_plot
local ymin = floor(r(min)/5)*5 - 5
quietly sum ul_plot
local ymax = ceil(r(max)/5)*5  + 5

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
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
di as result "DONE: `model_stub'"
