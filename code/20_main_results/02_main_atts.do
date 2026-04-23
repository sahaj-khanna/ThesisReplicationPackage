********************************************************************************
* 02_main_atts.do
* Main CSDID estimates for primary outcomes.
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

use "${datawork_dir}/analysis_panel.dta", clear
xtset ${ivar} ${tvar}
gen long cluster_id = ${clustvar}

* Main spec (typically "small")
local main_spec "$covar_spec_main"
local main_covars "${covars_`main_spec'}"
local main_method "dripw"
local wb_opts "wboot reps(${wb_reps}) rseed(${seed_std})"

capture mkdir "${results_main}/baseline"
capture mkdir "${results_main}/extended"
capture mkdir "${results_main}/nocov"
capture mkdir "${results_main}/extracted"
capture mkdir "${results_main}/extracted/att"
capture mkdir "${results_main}/extracted/att/main"

tempfile att_tmp
tempname patt
postfile `patt' ///
    str16 spec str32 outcome str16 method ///
    double att se z p ll ul ///
    using "`att_tmp'", replace

* ------ Loop 1: baseline spec (small) ------

di as text "Running main outcomes: baseline spec (`main_spec')"

local i = 0
foreach y of global outcomes_main {
    local ++i
    local nn = string(`i', "%02.0f")
    di as result "Outcome `nn': `y' | Spec: `main_spec' | Method: `main_method'"
    cd "${results_main}/baseline"
    capture noisily csdid2 `y' `main_covars', ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(`main_method') cluster(cluster_id) short
    if _rc == 0 {
        estimates save "${results_main}/baseline/main_`y'_`main_spec'_`main_method'", replace
        capture noisily estat simple, `wb_opts'
        if _rc == 0 {
            matrix A = r(table)
            post `patt' ///
                ("baseline") ("`y'") ("`main_method'") ///
                (A[1,1]) (A[2,1]) (A[3,1]) (A[4,1]) (A[5,1]) (A[6,1])
        }
    }
    else {
        di as error "Skipped `y' (return code " _rc ")"
    }
}

* ------ Loop 2: extended spec (large) ------

local large_spec "large"
local large_covars "${covars_large}"

di as text "Running main outcomes: extended spec (`large_spec')"

local i = 0
foreach y of global outcomes_main {
    local ++i
    local nn = string(`i', "%02.0f")
    di as result "Outcome `nn': `y' | Spec: `large_spec' | Method: `main_method'"
    cd "${results_main}/extended"
    capture noisily csdid2 `y' `large_covars', ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(`main_method') cluster(cluster_id) short
    if _rc == 0 {
        estimates save "${results_main}/extended/main_`y'_`large_spec'_`main_method'", replace
        capture noisily estat simple, `wb_opts'
        if _rc == 0 {
            matrix A = r(table)
            post `patt' ///
                ("extended") ("`y'") ("`main_method'") ///
                (A[1,1]) (A[2,1]) (A[3,1]) (A[4,1]) (A[5,1]) (A[6,1])
        }
    }
    else {
        di as error "Skipped `y' (return code " _rc ")"
    }
}

* ------ Loop 3: no-covariate baseline ------

di as text "Running no-covariate baseline"

local i = 0
foreach y of global outcomes_no_covars {
    local ++i
    local nn = string(`i', "%02.0f")
    di as result "Outcome `nn': `y' | Spec: none | Method: reg"
    cd "${results_main}/nocov"
    capture noisily csdid2 `y', ///
        ivar(${ivar}) time(${tvar}) gvar(${gvar}) ///
        method(reg) cluster(cluster_id) short
    if _rc == 0 {
        estimates save "${results_main}/nocov/main_`y'_none_reg", replace
        capture noisily estat simple, `wb_opts'
        if _rc == 0 {
            matrix A = r(table)
            post `patt' ///
                ("nocov") ("`y'") ("reg") ///
                (A[1,1]) (A[2,1]) (A[3,1]) (A[4,1]) (A[5,1]) (A[6,1])
        }
    }
    else {
        di as error "Skipped `y' no-covariate baseline (return code " _rc ")"
    }
}

postclose `patt'
use "`att_tmp'", clear
sort outcome spec
save "${results_main}/extracted/att/main/att_main.dta", replace
export delimited using "${results_main}/extracted/att/main/att_main.csv", replace

* SA outcomes removed — direct seasonal-adjustment scripts handle those outcomes explicitly.
