* Pre-treatment seasonal-adjustment quantity robustness block
version 18
set more off

do "${package_root}/code/shared/paths.do"

local in_dta   "${datawork_dir}/analysis_panel.dta"
local out_root "${results_rob}/incumbent_quantity_pretreat_sa"
local out_ster "`out_root'/models"
local out_csv  "`out_root'/summary/incumbent_quantity_pretreat_sa.csv"

capture mkdir "`out_root'"
capture mkdir "`out_ster'"
capture mkdir "`out_root'/summary"

use "`in_dta'", clear
set seed ${seed_std}

gen byte qoy = mod(${tvar} - 1, 4) + 1
gen long cluster_id = route_id
gen byte pre_treat = (${gvar} == 0 | ${tvar} < ${gvar})

capture confirm variable ln_total_departures_performed
if _rc != 0 gen double ln_total_departures_performed = log(total_departures_performed) if total_departures_performed > 0
capture confirm variable ln_total_passengers
if _rc != 0 gen double ln_total_passengers = log(total_passengers) if total_passengers > 0
capture confirm variable ln_total_seats
if _rc != 0 gen double ln_total_seats = log(total_seats) if total_seats > 0

tempname p
postfile `p' ///
    str24 seasonal_adjustment ///
    str40 outcome ///
    str40 model_stub ///
    double att se pvalue ll ul ///
    long n_obs n_clusters using "`out_root'/summary/incumbent_quantity_pretreat_sa.dta", replace

local outcomes "ln_total_departures_performed ln_total_passengers ln_total_seats"

forvalues i = 1/3 {
    local outcome : word `i' of `outcomes'
    if `i' == 1 {
        local label "Log Departures"
        local base_stub "lndep"
    }
    else if `i' == 2 {
        local label "Log Passengers"
        local base_stub "lnpax"
    }
    else {
        local label "Log Seats"
        local base_stub "lnseats"
    }

    capture drop __mean_pre sa_pre
    bysort ${ivar} qoy: egen double __mean_pre = mean(cond(pre_treat, `outcome', .))
    gen double sa_pre = `outcome' - __mean_pre

    quietly count if !missing(sa_pre)
    local n_obs = r(N)
    quietly levelsof route_id if !missing(sa_pre), local(route_list)
    local n_clusters : word count `route_list'

    local model_stub "`base_stub'_pretreat_sa_maincov_never_dripw"

    cd "`out_ster'"
    csdid2 sa_pre ${covars_small}, ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(dripw) cluster(cluster_id) short
    estimates save "`model_stub'", replace

    estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
    matrix A = r(table)
    post `p' ///
        ("Pre-entry only") ///
        ("`label'") ///
        ("`model_stub'") ///
        (A[1,1]) (A[2,1]) (A[4,1]) (A[5,1]) (A[6,1]) ///
        (`n_obs') (`n_clusters')

    drop __mean_pre sa_pre
}

postclose `p'
use "`out_root'/summary/incumbent_quantity_pretreat_sa.dta", clear
sort outcome seasonal_adjustment
export delimited using "`out_csv'", replace
