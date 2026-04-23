* Seasonally-adjusted load-factor event study using the baseline thesis specification.
* Step 1: Residualise load_factor on carrier-route x quarter-of-year FEs
* Step 2: Run csdid2 event study (asymptotic SEs, no bootstrap)
version 18
set more off
do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${output_dir}/30_mechanisms/lf_sa_smallcov"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

use "`in_dta'", clear

* Quarter of year (1=Q1, 2=Q2, 3=Q3, 4=Q4)
gen byte qoy = mod(${tvar} - 1, 4) + 1

* --- Step 1: Residualise on carrier-route x quarter-of-year FEs ---
di as result "=== Residualising load_factor on carrier-route x quarter-of-year means ==="
bysort ${ivar} qoy: egen mean_lf_rq = mean(load_factor)
gen double lf_seas_adj = load_factor - mean_lf_rq
di as result "Residualisation complete."
summarize lf_seas_adj, detail

* --- Step 2: csdid2 event study ---
local model_stub "lf_full_sa_maincov_never_dripw"

di as result _newline "=== csdid2 on seasonally-adjusted load_factor ==="

* csdid2 requires cluster variable to differ from ivar
gen long cluster_id = ${ivar}

cd "`out_ster'"
csdid2 lf_seas_adj ${covars_small}, ///
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

* --- Extract event-time estimates ---
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

* Add t=-1 reference period (normalisation point)
local n = _N + 1
set obs `n'
replace event_time = -1 in `n'
replace coef = 0      in `n'
replace ll   = 0      in `n'
replace ul   = 0      in `n'
sort event_time

gen double coef_plot = coef
gen double ll_plot   = ll
gen double ul_plot   = ul

save "`out_event'/event_`model_stub'.dta", replace
export delimited using "`out_event'/event_`model_stub'.csv", replace

quietly sum ll_plot
local ymin = floor(r(min)*100)/100 - 0.005
quietly sum ul_plot
local ymax = ceil(r(max)*100)/100  + 0.005

twoway ///
    (rarea ul_plot ll_plot event_time, color(gs8%40) lwidth(none)) ///
    (connected coef_plot event_time, sort lcolor(gs4) mcolor(gs4) ///
        msymbol(O) msize(small) lwidth(medthick)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_main}(2)${wpost_main}, labsize(medium)) ///
    ylabel(`ymin'(0.01)`ymax', labsize(medium)) ///
    yscale(range(`ymin' `ymax')) ///
    xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
    ytitle("Estimated Treatment Effect (pp, SA)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
di as result "DONE: `model_stub'"
di as result "Plot: `plots_dir'/es_`model_stub'.pdf"
