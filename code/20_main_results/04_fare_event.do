* Fare event-study using standardized csdid2 settings
version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta    "${datawork_dir}/analysis_panel.dta"
local out_root  "${results_main}/fare_main"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "${results_main}/figures"
local model_stub "ln_average_fare_baseline_dripw"
local wb_opts "wboot reps(${wb_reps}) rseed(${seed_std})"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

use "`in_dta'", clear
gen long cluster_id = ${clustvar}

cd "`out_ster'"
csdid2 ln_average_fare ${covars_small}, ///
    ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
    method(dripw) cluster(cluster_id) short

if _rc != 0 exit `_rc'

estimates save "`model_stub'", replace
estat event, window(-${wpre_main} ${wpost_main}) `wb_opts'

matrix E = r(table)
local cnames : colfullnames E
local k = colsof(E)

tempfile ev1
tempname ph1
postfile `ph1' int event_time double coef ll ul using "`ev1'", replace
forvalues j = 1/`k' {
    local cname : word `j' of `cnames'
    local et = .
    if regexm("`cname'", "^Tm([0-9]+)$") local et = -real(regexs(1))
    else if regexm("`cname'", "^Tp([0-9]+)$") local et = real(regexs(1))
    else continue
    post `ph1' (`et') (E[1,`j']) (E[5,`j']) (E[6,`j'])
}
postclose `ph1'

use "`ev1'", clear
sort event_time
local n = _N + 1
set obs `n'
replace event_time = -1 in `n'
replace coef = 0 in `n'
replace ll = 0 in `n'
replace ul = 0 in `n'
sort event_time
gen double coef_pct = (exp(coef) - 1) * 100
gen double ll_pct   = (exp(ll) - 1) * 100
gen double ul_pct   = (exp(ul) - 1) * 100

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

twoway ///
    (rarea ul_pct ll_pct event_time, color(gs8%40) lwidth(none)) ///
    (connected coef_pct event_time, sort lcolor(gs4) mcolor(gs4) msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-6(2)8, labsize(medium)) ///
    ylabel(, labsize(medium)) ///
    xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
    ytitle("Estimated Treatment Effect (%)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_ln_average_fare.pdf", replace
