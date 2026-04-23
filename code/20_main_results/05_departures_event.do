* Seasonally-adjusted departures event study using the baseline thesis specification.
version 18
set more off
do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${results_main}/departures_main"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

use "`in_dta'", clear

* Quarter of year (1=Q1, 2=Q2, 3=Q3, 4=Q4)
capture drop qoy
gen byte qoy = mod(${tvar} - 1, 4) + 1

* --- Step 1: Residualise on route x quarter-of-year FEs ---
* For each route x qoy cell, subtract the route's own seasonal mean.
* This removes each route's idiosyncratic seasonal departure pattern.
di as result "=== Residualising ln_departures on route x quarter-of-year means ==="
bysort ${ivar} qoy: egen mean_dep_rq = mean(ln_total_departures_performed)
gen double ln_dep_seas_adj = ln_total_departures_performed - mean_dep_rq

di as result "Residualisation complete."
summarize ln_dep_seas_adj, detail

capture drop cluster_id
gen long cluster_id = ${clustvar}

* --- Step 2: CSDID2 event study on seasonally-adjusted outcome ---
local model_stub "seasadj_lndep_maincov_never_dripw"

di as result _newline "=== CSDID on seasonally-adjusted ln_departures ==="

cd "`out_ster'"
csdid2 ln_dep_seas_adj ${covars_small}, ///
    ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
    method(dripw) cluster(cluster_id) short

if _rc != 0 {
    di as error "FAILED (rc=`_rc')"
    exit `_rc'
}

estimates save "`model_stub'", replace

di as result _newline "=== OVERALL ATT ==="
estat simple, wboot reps(${wb_reps}) rseed(${seed_std})

estat event, window(-${wpre_main} ${wpost_main}) wboot reps(${wb_reps}) rseed(${seed_std})

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

gen double coef_plot = coef
gen double ll_plot   = ll
gen double ul_plot   = ul

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

quietly sum ll_plot
local ymin = floor(r(min)*10)/10 - 0.05
quietly sum ul_plot
local ymax = ceil(r(max)*10)/10 + 0.05

twoway ///
    (rarea ul_plot ll_plot event_time, color(gs8%40) lwidth(none)) ///
    (connected coef_plot event_time, sort lcolor(gs4) mcolor(gs4) ///
        msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_main}(2)${wpost_main}, labsize(medium)) ///
    ylabel(`ymin'(0.1)`ymax', labsize(medium)) ///
    yscale(range(`ymin' `ymax')) ///
    xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
    ytitle("Estimated Treatment Effect (%)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
di as result "DONE: `model_stub'"
