* Scheduled-time robustness check
version 18
clear all
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${results_rob}/scheduled_time"
local out_ster "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

use "`in_dta'", clear
xtset panel_id time_period

capture drop cluster_id
gen long cluster_id = route_id

local model_stub "scheduled_time_maincov_never_dripw"
cd "`out_ster'"
csdid2 scheduled_time ${covars_small}, ///
    ivar(panel_id) time(time_period) gvar(first_treat) ///
    method(dripw) cluster(cluster_id) short
estimates save "`model_stub'", replace

estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
estat event, window(-${wpre_main} ${wpost_main}) wboot reps(${wb_reps}) rseed(${seed_std})
matrix E = r(table)
local cnames : colfullnames E
local k = colsof(E)
tempfile ev
tempname ph
postfile `ph' int event_time double coef ll ul using "`ev'", replace
forvalues j = 1/`k' {
    local cname : word `j' of `cnames'
    local et = .
    if regexm("`cname'", "^tm([0-9]+)$") local et = -real(regexs(1))
    else if regexm("`cname'", "^tp([0-9]+)$") local et = real(regexs(1))
    else continue
    post `ph' (`et') (E[1,`j']) (E[5,`j']) (E[6,`j'])
}
postclose `ph'

use "`ev'", clear
sort event_time

local n = _N + 1
set obs `n'
replace event_time = -1 in `n'
replace coef = 0 in `n'
replace ll = 0 in `n'
replace ul = 0 in `n'
sort event_time

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

twoway ///
    (rarea ul ll event_time, color(gs8%40) lwidth(none)) ///
    (connected coef event_time, sort lcolor(gs4) mcolor(gs4) msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_main}(2)${wpost_main}, labsize(medium)) ///
    ylabel(, labsize(medium)) ///
    xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
    ytitle("Estimated Treatment Effect (Minutes)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
