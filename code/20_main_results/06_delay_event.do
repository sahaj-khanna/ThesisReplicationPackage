* Carrier-delay event study using the baseline thesis specification.

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

********************************************************************************
* Paths
********************************************************************************

local in_dta   "${datawork_dir}/analysis_panel.dta"

local out_root  "${results_main}/delay_main"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

********************************************************************************
* Load data
********************************************************************************

use "`in_dta'", clear

di as result "Loaded: `in_dta'"
di as result "Obs in full panel: `=_N'"

********************************************************************************
* Sample summary
********************************************************************************

di as result _newline "======================================================"
di as result "FULL SAMPLE — BASELINE-COVARIATE CARRIER DELAY"
di as result "======================================================"

quietly count if first_treat > 0
local n_treated = r(N)
quietly count if first_treat == 0
local n_control = r(N)

quietly levelsof route_id if first_treat > 0, local(rt_treated)
quietly levelsof route_id if first_treat == 0, local(rt_control)
local n_rt_treated : word count `rt_treated'
local n_rt_control : word count `rt_control'

di as result "Treated obs:       `n_treated'    |  Treated routes: `n_rt_treated'"
di as result "Control obs:       `n_control'    |  Control routes: `n_rt_control'"
di as result "======================================================"

********************************************************************************
* CSDID2 — carrier_delay, baseline-covariate spec, never-treated controls
********************************************************************************

capture drop cluster_id
gen long cluster_id = route_id

local model_stub "carrdelay_maincov_never_dripw"

di as result _newline "======================================================"
di as result "Running CSDID: `model_stub'"
di as result "Outcome : carrier_delay (minutes, levels)"
di as result "Sample  : Full panel"
di as result "Controls: never-treated"
di as result "Covars  : baseline thesis covariates"
di as result "======================================================"

cd "`out_ster'"

capture noisily csdid2 carrier_delay ${covars_small}, ///
    ivar(panel_id) time(time_period) gvar(first_treat) ///
    method(dripw) cluster(cluster_id) short

if _rc != 0 {
    di as error "FAILED: `model_stub' (rc = `_rc')"
    exit `_rc'
}

estimates save "`model_stub'", replace
di as result "Estimates saved: `out_ster'/`model_stub'.ster"

********************************************************************************
* Event study extraction  [-6, +8]
********************************************************************************

capture noisily estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
capture noisily estat event, window(-${wpre_delay} ${wpost_quality}) wboot reps(${wb_reps}) rseed(${seed_std})

if _rc != 0 {
    di as error "Event study extraction failed (rc = `_rc')"
    exit `_rc'
}

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

********************************************************************************
* Save event study data & plot
********************************************************************************

use "`ev_tmp'", clear
sort event_time

local n = _N + 1
set obs `n'
replace event_time = -1 in `n'
replace coef = 0 in `n'
replace ll = 0 in `n'
replace ul = 0 in `n'
sort event_time

gen double coef_plot = coef
gen double ll_plot   = ll
gen double ul_plot   = ul

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace
di as result "Event study data saved."

* ---- Plot ----
local xt  "Quarters Relative to Frontier's Entry"
local yt  "Estimated Effect (minutes)"

twoway ///
    (rarea ul_plot ll_plot event_time, color(gs8%40) lwidth(none)) ///
    (connected coef_plot event_time, sort lcolor(gs4) mcolor(gs4) ///
        msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0,    lcolor(gs10) lpattern(shortdash)) ///
    xline(-0.5, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_delay}(2)${wpost_quality}, labsize(medium)) ///
    ylabel(, labsize(medium)) ///
    xtitle("`xt'", size(medlarge)) ///
    ytitle("`yt'", size(medlarge)) ///
    subtitle("Full sample | carrier_delay | baseline covariates | never-treated controls", ///
             size(vsmall) color(gs6)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
graph export "`plots_dir'/es_`model_stub'_v2.pdf", replace
di as result "Plot saved: `plots_dir'/es_`model_stub'.pdf"
di as result "Legacy alias saved: `plots_dir'/es_`model_stub'_v2.pdf"

********************************************************************************
* Done
********************************************************************************

di as result _newline "======================================================"
di as result "DONE: 06_delay_event.do"
di as result "Model : `out_ster'/`model_stub'.ster"
di as result "Event : `out_event'/event_`model_stub'.csv"
di as result "Plot  : `plots_dir'/es_`model_stub'.pdf"
di as result "======================================================"
