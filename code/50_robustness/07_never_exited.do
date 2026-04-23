* 98b_never_exited_routes_csdid2.do
* Exit robustness: restrict treated sample to routes where Frontier maintained
* service through end of sample (2019Q4).
*
* Motivation: F9 exited 237/576 (41%) treated routes, median tenure only 3 qtrs.
* On exit routes, treatment effectively "turns off." This check ensures main
* results are not driven by or attenuated by treatment reversal.
*
* Definition: keep treated routes where f9_exit_qtr >= 2019.75 (still serving).
* Never-treated routes: keep all (unaffected by F9 exit).
*
* Outcomes:
*   1. Log average fare
*   2. SA log departures
*   3. Carrier delay (mean)
*   4. Share of flights late (arrival_15)
*   5. Cancellation rate
*   6. SA log total passengers
*   7. SA log total seats
*
* Uses the standardized csdid2 + wild-bootstrap package settings.
version 18
set more off
do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${results_rob}/frontier_exit/never_exited"
local out_ster  "`out_root'/models"
local out_event "`out_root'/event"
local plots_dir "`out_root'/plots"
local out_summary "`out_root'/summary"

capture mkdir "${results_rob}/frontier_exit"
capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_event'"
capture mkdir "`plots_dir'"
capture mkdir "`out_summary'"

* ==========================================================================
*  LOAD DATA & RESTRICT TO NEVER-EXITED TREATED ROUTES
* ==========================================================================

use "`in_dta'", clear

* Flag treated routes where F9 exited before end of sample
* f9_exit_qtr is in yearquarter format: 2019.75 = 2019Q4
gen byte f9_exited = (f9_exit_qtr < 2019.75) if is_f9_entry_route == 1

* Drop treated routes where F9 exited; keep all never-treated routes
drop if f9_exited == 1

di as result "=== Sample after dropping F9-exited treated routes ==="
di as result "Observations: " _N

* Diagnostics
preserve
    keep if is_f9_entry_route == 1
    bysort route_id: keep if _n == 1
    quietly count
    local n_treated = r(N)
restore
preserve
    keep if is_f9_entry_route == 0
    bysort route_id: keep if _n == 1
    quietly count
    local n_control = r(N)
restore

di as result "Treated routes (F9 never exited): `n_treated'"
di as result "Control routes (never-treated):   `n_control'"

* Re-set panel structure
xtset ${ivar} ${tvar}

* ==========================================================================
*  CONSTRUCT VARIABLES
* ==========================================================================

* Quarter of year for seasonal adjustment
gen byte qoy = mod(${tvar} - 1, 4) + 1

* --- Log variables ---
capture drop ln_total_passengers
gen double ln_total_passengers = log(total_passengers) if total_passengers > 0

* ln_total_seats should already exist; create if missing
capture confirm variable ln_total_seats
if _rc != 0 {
    gen double ln_total_seats = log(total_seats) if total_seats > 0
}

* --- Seasonal adjustment: carrier-route x quarter-of-year demeaning ---
di as result _newline "=== Seasonal adjustment ==="

* SA departures
bysort ${ivar} qoy: egen double __m_dep = mean(ln_total_departures_performed)
gen double sa_ln_total_departures_performed = ln_total_departures_performed - __m_dep
drop __m_dep
di as result "  SA complete: sa_ln_total_departures_performed"

* SA passengers
bysort ${ivar} qoy: egen double __m_pax = mean(ln_total_passengers)
gen double sa_ln_total_passengers = ln_total_passengers - __m_pax
drop __m_pax
di as result "  SA complete: sa_ln_total_passengers"

* SA seats
bysort ${ivar} qoy: egen double __m_seats = mean(ln_total_seats)
gen double sa_ln_total_seats = ln_total_seats - __m_seats
drop __m_seats
di as result "  SA complete: sa_ln_total_seats"

* csdid2 requires cluster variable name to differ from ivar
gen long cluster_id = route_id

* ==========================================================================
*  DEFINE OUTCOMES
* ==========================================================================

* Outcome variables, model stubs, labels, y-axis titles, and whether to x100
local n_outcomes = 7

local var1  "ln_average_fare"
local var2  "sa_ln_total_departures_performed"
local var3  "carrier_delay"
local var4  "arrival_15"
local var5  "cancellation"
local var6  "sa_ln_total_passengers"
local var7  "sa_ln_total_seats"

local stub1 "noexit_lnfare_maincov_never_dripw"
local stub2 "noexit_sa_lndep_maincov_never_dripw"
local stub3 "noexit_carrdelay_maincov_never_dripw"
local stub4 "noexit_arrival15_maincov_never_dripw"
local stub5 "noexit_cancel_maincov_never_dripw"
local stub6 "noexit_sa_lnpax_maincov_never_dripw"
local stub7 "noexit_sa_lnseats_maincov_never_dripw"

local lab1  "Log Average Fare"
local lab2  "SA Log Departures"
local lab3  "Mean Carrier Delay (min)"
local lab4  "Share Flights Late"
local lab5  "Cancellation Rate"
local lab6  "SA Log Passengers"
local lab7  "SA Log Seats"

* Which outcomes to multiply by 100 for % interpretation (log outcomes)
local pct1  1
local pct2  1
local pct3  0
local pct4  0
local pct5  0
local pct6  1
local pct7  1

* Y-axis titles
local ytit1 "Estimated Treatment Effect (%)"
local ytit2 "Estimated Treatment Effect (%)"
local ytit3 "Estimated Treatment Effect (min)"
local ytit4 "Estimated Treatment Effect (pp)"
local ytit5 "Estimated Treatment Effect (pp)"
local ytit6 "Estimated Treatment Effect (%)"
local ytit7 "Estimated Treatment Effect (%)"

* ==========================================================================
*  ESTIMATION LOOP
* ==========================================================================

tempname psumm
postfile `psumm' ///
    str40 outcome str60 model_stub ///
    double att se pvalue ll ul using "`out_summary'/noexit_att_summary.dta", replace

forvalues i = 1/`n_outcomes' {
    local outcome    "`var`i''"
    local model_stub "`stub`i''"
    local ylab       "`lab`i''"
    local ytit       "`ytit`i''"
    local dopct      "`pct`i''"

    di as result _newline(3)
    di as result "================================================================"
    di as result "  OUTCOME `i'/`n_outcomes': `ylab' (never-exited routes)"
    di as result "  Variable: `outcome'"
    di as result "================================================================"

    * ------------------------------------------------------------------
    *  Estimate CSDID2
    * ------------------------------------------------------------------

    cd "`out_ster'"
    csdid2 `outcome' ${covars_small}, ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(dripw) cluster(cluster_id) short

    if _rc != 0 {
        di as error "ESTIMATION FAILED for `outcome' (rc=`_rc'). Skipping."
        continue
    }

    estimates save "`model_stub'", replace

    * ------------------------------------------------------------------
    *  Overall ATT
    * ------------------------------------------------------------------

    di as result _newline "=== OVERALL ATT: `ylab' ==="
    estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
    matrix A = r(table)
    post `psumm' ("`ylab'") ("`model_stub'") (A[1,1]) (A[2,1]) (A[4,1]) (A[5,1]) (A[6,1])

    * ------------------------------------------------------------------
    *  Event study
    * ------------------------------------------------------------------

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

    * Scale for plotting
    if `dopct' == 1 {
        gen double coef_plot = coef * 100
        gen double ll_plot   = ll * 100
        gen double ul_plot   = ul * 100
    }
    else {
        gen double coef_plot = coef
        gen double ll_plot   = ll
        gen double ul_plot   = ul
    }

    save "`out_event'/event_`model_stub'.dta", replace
    export delimited using "`out_event'/event_`model_stub'.csv", replace

    * ------------------------------------------------------------------
    *  Plot
    * ------------------------------------------------------------------

    quietly sum ll_plot
    local ymin_raw = r(min)
    quietly sum ul_plot
    local ymax_raw = r(max)

    * Adaptive y-axis scaling
    local yrange = `ymax_raw' - `ymin_raw'
    if `yrange' > 20 {
        local ystep = 5
    }
    else if `yrange' > 5 {
        local ystep = 2
    }
    else if `yrange' > 1 {
        local ystep = 0.5
    }
    else {
        local ystep = 0.2
    }
    local ymin = floor(`ymin_raw'/`ystep')*`ystep' - `ystep'
    local ymax = ceil(`ymax_raw'/`ystep')*`ystep' + `ystep'

    twoway ///
        (rarea ul_plot ll_plot event_time, color(gs8%40) lwidth(none)) ///
        (connected coef_plot event_time, sort lcolor(gs4) mcolor(gs4) ///
            msymbol(O) msize(small) lwidth(medthick)), ///
        yline(0, lcolor(gs6) lpattern(solid)) ///
        xline(0, lcolor(gs10) lpattern(shortdash)) ///
    xlabel(-${wpre_main}(2)${wpost_main}, labsize(medium)) ///
        ylabel(`ymin'(`ystep')`ymax', labsize(medium)) ///
        yscale(range(`ymin' `ymax')) ///
        xtitle("Quarters Relative to Frontier's Entry", size(medlarge)) ///
        ytitle("`ytit'", size(medlarge)) ///
        title("`ylab' — Never-Exited Routes", size(medium)) ///
        legend(off) ///
        graphregion(color(white)) plotregion(color(white)) bgcolor(white) ///
        xsize(12) ysize(8)

    graph export "`plots_dir'/es_`model_stub'.pdf", replace
    di as result "Saved: `plots_dir'/es_`model_stub'.pdf"

    restore
}

postclose `psumm'
use "`out_summary'/noexit_att_summary.dta", clear
export delimited using "`out_summary'/noexit_att_summary.csv", replace

* ==========================================================================
*  SUMMARY
* ==========================================================================

di as result _newline(3)
di as result "================================================================"
di as result "  EXIT ROBUSTNESS COMPLETE — 7 OUTCOMES"
di as result "================================================================"
di as result "  Sample: 339 treated routes where F9 still serving in 2019Q4"
di as result "  (dropped 237 routes where F9 exited, 41% of original treated)"
di as result ""
di as result "  Compare to main results:"
di as result "    Fare ATT (main):         -7.24%"
di as result "    Departures ATT (main):  +10.06%"
di as result "    Carrier delay (main):    +0.78 min (n.s.)"
di as result "    Share late (main):       -0.23 pp (n.s.)"
di as result "    Cancellation (main):     +0.17 pp (*)"
di as result ""
di as result "  Results in: `out_root'"
di as result "================================================================"
