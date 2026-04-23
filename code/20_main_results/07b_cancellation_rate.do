* Cancellation appendix event study
version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${results_main}/reliability_cancellation"
local out_ster "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

use "`in_dta'", clear

capture drop cluster_id
gen long cluster_id = route_id

local model_stub "cancellation_maincov_never_dripw"

cd "`out_ster'"
capture noisily csdid2 cancellation ${covars_small}, ///
    ivar(panel_id) time(time_period) gvar(first_treat) ///
    method(dripw) cluster(cluster_id) short

if _rc != 0 exit `_rc'

estimates save "`model_stub'", replace
estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
estat event, window(-${wpre_delay} ${wpost_quality}) wboot reps(${wb_reps}) rseed(${seed_std})

matrix E = r(table)
local cnames : colfullnames E
local k = colsof(E)
tempfile ev_tmp
tempname pev
postfile `pev' int event_time double coef ll ul using "`ev_tmp'", replace
forvalues j = 1/`k' {
    local cname : word `j' of `cnames'
    local et = .
    if regexm("`cname'", "^tm([0-9]+)$") local et = -real(regexs(1))
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
gen double ll_plot = ll
gen double ul_plot = ul
save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

twoway ///
    (rarea ul_plot ll_plot event_time, color(gs8%40) lwidth(none)) ///
    (connected coef_plot event_time, sort lcolor(gs4) mcolor(gs4) msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_delay}(2)${wpost_quality}, labsize(medium)) ///
    ylabel(, labsize(medium)) ///
    xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
    ytitle("Estimated Effect (percentage points)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
