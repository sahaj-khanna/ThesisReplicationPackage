********************************************************************************
* Fare-percentile heterogeneity using the baseline thesis specification.
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local farepct_dir  "${results_het}/farepct_dist"
local levels_dir   "`farepct_dir'/levels"
local logs_dir_res "`farepct_dir'/logs"
local plots_dir    "`farepct_dir'/plots"

capture mkdir "`farepct_dir'"
capture mkdir "`levels_dir'"
capture mkdir "`logs_dir_res'"
capture mkdir "`plots_dir'"

use "${datawork_dir}/analysis_panel.dta", clear
xtset ${ivar} ${tvar}

capture drop cluster_id
gen long cluster_id = ${clustvar}

foreach yp in fare_p10 fare_p25 fare_p75 fare_p90 {
    capture confirm variable `yp'
    if _rc != 0 {
        di as error "Variable `yp' not found in analysis_panel.dta."
        exit 1
    }
}

foreach yp in p10 p25 p75 p90 {
    capture drop ln_fare_`yp'
    gen double ln_fare_`yp' = ln(fare_`yp') if fare_`yp' > 0 & !missing(fare_`yp')
    label var ln_fare_`yp' "Log fare at `yp' percentile"
}

tempfile att_lev_tmp att_log_tmp
tempname plev plog

postfile `plev' ///
    int pctile str20 outcome str8 scale ///
    double att se z p ll ul ///
    using "`att_lev_tmp'", replace

postfile `plog' ///
    int pctile str20 outcome str8 scale ///
    double att se z p ll ul ///
    using "`att_log_tmp'", replace

local pvals 10 25 75 90
local ylevs fare_p10 fare_p25 fare_p75 fare_p90
local ylogs ln_fare_p10 ln_fare_p25 ln_fare_p75 ln_fare_p90

local i = 0
foreach yp of local ylevs {
    local ++i
    local pv : word `i' of `pvals'
    local model_id "farepct_`yp'_maincov_never_dripw"

    di as result "Running `model_id'"
    cd "`levels_dir'"
    capture noisily csdid2 `yp' ${covars_small}, ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(dripw) cluster(cluster_id) short
    if _rc != 0 {
        di as error "csdid2 failed for `yp' (rc=`_rc')"
        continue
    }

    estimates save "`levels_dir'/`model_id'", replace
    estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
    matrix A = r(table)
    post `plev' (`pv') ("`yp'") ("level") ///
        (A[1,1]) (A[2,1]) (A[3,1]) (A[4,1]) (A[5,1]) (A[6,1])
}
postclose `plev'

local i = 0
foreach yp of local ylogs {
    local ++i
    local pv : word `i' of `pvals'
    local model_id "farepct_`yp'_maincov_never_dripw"

    di as result "Running `model_id'"
    cd "`logs_dir_res'"
    capture noisily csdid2 `yp' ${covars_small}, ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(dripw) cluster(cluster_id) short
    if _rc != 0 {
        di as error "csdid2 failed for `yp' (rc=`_rc')"
        continue
    }

    estimates save "`logs_dir_res'/`model_id'", replace
    estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
    matrix A = r(table)
    post `plog' (`pv') ("`yp'") ("log") ///
        (A[1,1]) (A[2,1]) (A[3,1]) (A[4,1]) (A[5,1]) (A[6,1])
}
postclose `plog'

use "`att_lev_tmp'", clear
sort pctile
label var pctile  "Fare percentile (10/25/75/90)"
label var outcome "Outcome variable name"
label var scale   "Scale: level (USD)"
label var att     "ATT — average treatment effect on treated"
label var se      "Wild-bootstrap standard error"
label var z       "z-statistic"
label var p       "p-value"
label var ll      "95% CI lower bound"
label var ul      "95% CI upper bound"
save "`farepct_dir'/att_farepct_levels.dta", replace
export delimited using "`farepct_dir'/att_farepct_levels.csv", replace

use "`att_log_tmp'", clear
sort pctile
gen double att_pct = (exp(att) - 1) * 100
gen double ll_pct  = (exp(ll)  - 1) * 100
gen double ul_pct  = (exp(ul)  - 1) * 100
label var pctile  "Fare percentile (10/25/75/90)"
label var outcome "Outcome variable name"
label var scale   "Scale: log"
label var att     "ATT — log-point treatment effect"
label var se      "Wild-bootstrap standard error"
label var z       "z-statistic"
label var p       "p-value"
label var ll      "95% CI lower bound (log)"
label var ul      "95% CI upper bound (log)"
label var att_pct "ATT — exact percent effect"
label var ll_pct  "95% CI lower bound (%)"
label var ul_pct  "95% CI upper bound (%)"
save "`farepct_dir'/att_farepct_logs.dta", replace
export delimited using "`farepct_dir'/att_farepct_logs.csv", replace

use "`farepct_dir'/att_farepct_levels.dta", clear
gen int xpos = 1 if pctile == 10
replace xpos = 2 if pctile == 25
replace xpos = 3 if pctile == 75
replace xpos = 4 if pctile == 90

twoway ///
    (rcap ul ll xpos, lcolor(gs8) lwidth(thin)) ///
    (scatter att xpos, mcolor(gs3) msymbol(O) msize(medium)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xlabel(1 "10th" 2 "25th" 3 "75th" 4 "90th", nogrid labsize(medium)) ///
    xscale(range(0.5 4.5)) ///
    xtitle("Fare Percentile", size(medlarge)) ///
    ytitle("ATT (USD)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/farepct_dist_att_levels.pdf", replace

use "`farepct_dir'/att_farepct_logs.dta", clear
gen int xpos = 1 if pctile == 10
replace xpos = 2 if pctile == 25
replace xpos = 3 if pctile == 75
replace xpos = 4 if pctile == 90

twoway ///
    (rcap ul_pct ll_pct xpos, lcolor(gs8) lwidth(thin)) ///
    (scatter att_pct xpos, mcolor(gs3) msymbol(O) msize(medium)), ///
    yline(0, lcolor(gs6) lpattern(solid)) ///
    xlabel(1 "10th" 2 "25th" 3 "75th" 4 "90th", nogrid labsize(medium)) ///
    xscale(range(0.5 4.5)) ///
    xtitle("Fare Percentile", size(medlarge)) ///
    ytitle("Estimated Treatment Effects (%)", size(medlarge)) ///
    legend(off) ///
    graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
    xsize(12) ysize(8)

graph export "`plots_dir'/farepct_dist_att_logs.pdf", replace

use "`farepct_dir'/att_farepct_logs.dta", clear
quietly summarize att if pctile == 10
local att_p10 = r(mean)
quietly summarize att if pctile == 90
local att_p90 = r(mean)

di as text ""
di as text "======================== INTERPRETATION ========================"
di as text "Log ATT P10 = " %8.4f `att_p10' " (= " %6.2f (exp(`att_p10')-1)*100 " %)"
di as text "Log ATT P90 = " %8.4f `att_p90' " (= " %6.2f (exp(`att_p90')-1)*100 " %)"
if abs(`att_p10') > abs(`att_p90') {
    di as result "Conclusion: |ATT(P10)| > |ATT(P90)| — larger proportional effect at the bottom."
}
else {
    di as result "Conclusion: |ATT(P10)| <= |ATT(P90)| — no stronger proportional effect at low fares."
}
di as text "================================================================"

di as result "Fare-percentile heterogeneity complete."
