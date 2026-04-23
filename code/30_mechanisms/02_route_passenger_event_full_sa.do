********************************************************************************
* CSDID2 event study — total route passengers (all carriers including Frontier)
* Outcome : ln_route_pax_sa  (log route passengers, seasonally adjusted)
* SA method: route × quarter-of-year demeaning (mirrors 57_seasadj_lndep_main_event.do)
* Panel   : route-quarter  (ivar = route_id, not carrier-route panel_id)
* Covars  : covars_small minus route_capacity_passengers (which is the outcome)
* Method  : DRIPW, wild-bootstrap, varying base period, never-treated controls
* Window  : -6 to +8 quarters
*
* Run 91_route_pax_panel_prep.do first to create route_pax_panel.dta.
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta    "${datawork_dir}/route_pax_panel.dta"
local out_root  "${output_dir}/30_mechanisms/route_pax_full_sa"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"

use "`in_dta'", clear

* ---------------------------------------------------------------------------
* Step 1: Seasonal adjustment — route × quarter-of-year demeaning
*   Mirrors 57_seasadj_lndep_main_event.do exactly, but ivar is route_id
*   and the outcome is ln_route_pax instead of ln_total_departures_performed.
*   Removes each route's idiosyncratic seasonal passenger pattern so that
*   staggered entry timing does not conflate seasonal peaks with treatment effects.
* ---------------------------------------------------------------------------
capture drop qoy
gen byte qoy = mod(${tvar} - 1, 4) + 1   // 1=Q1, 2=Q2, 3=Q3, 4=Q4

di as result "=== Residualising ln_route_pax on route x quarter-of-year means ==="
bysort route_id qoy: egen mean_pax_rq = mean(ln_route_pax)
gen double ln_route_pax_sa = ln_route_pax - mean_pax_rq

di as result "Residualisation complete."
summarize ln_route_pax_sa, detail

* ---------------------------------------------------------------------------
* Step 2: Sample diagnostics
* ---------------------------------------------------------------------------
* CSDID cannot have ivar and cluster() share the same variable name.
* Create a copy of route_id for clustering (mathematically identical).
gen long route_cluster_id = route_id

* Controls: baseline thesis covariates excluding the route-passenger outcome itself
local covars_route "average_dist route_hhi ln_geo_mean_pop ln_geo_mean_income origin_leisure_share_emp dest_leisure_share_emp big_city_route hub_route"

quietly count if first_treat > 0
local n_treated = r(N)
quietly count if first_treat == 0
local n_control = r(N)
quietly levelsof route_id if first_treat > 0, local(rt_t)
quietly levelsof route_id if first_treat == 0, local(rt_c)
local n_rt_t : word count `rt_t'
local n_rt_c : word count `rt_c'

di as result "======================================================"
di as result "MAIN | ln_route_pax_sa (SA) | covars_small (no pax) | all carriers"
di as result "Covariates: `covars_route'"
di as result "======================================================"
di as result "Treated obs:  `n_treated'  |  Treated routes: `n_rt_t'"
di as result "Control obs:  `n_control'  |  Control routes: `n_rt_c'"
di as result "======================================================"

* ---------------------------------------------------------------------------
* Step 3: CSDID2 on seasonally-adjusted outcome
* ---------------------------------------------------------------------------
local model_stub "route_pax_full_sa_maincov_never_dripw"

cd "`out_ster'"
csdid2 ln_route_pax_sa `covars_route', ///
    ivar(route_id) time(${tvar}) gvar(${gvar}) ///
    method(dripw) cluster(route_cluster_id) short

if _rc != 0 {
    di as error "CSDID FAILED (rc=`_rc')"
    exit `_rc'
}

estimates save "`model_stub'", replace

di as result _newline "=== OVERALL ATT ==="
estat simple, wboot reps(${wb_reps}) rseed(${seed_std})

estat event, window(-${wpre_main} ${wpost_main}) wboot reps(${wb_reps}) rseed(${seed_std})

* ---------------------------------------------------------------------------
* Extract event-time estimates into .dta and .csv
* ---------------------------------------------------------------------------
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

* ---------------------------------------------------------------------------
* Event study plot
* ---------------------------------------------------------------------------
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
    ytitle("Estimated Treatment Effect (log pts, SA)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/es_`model_stub'.pdf", replace
di as result "DONE: `model_stub'"
di as result "Event CSV: `out_event'/event_`model_stub'.csv"
