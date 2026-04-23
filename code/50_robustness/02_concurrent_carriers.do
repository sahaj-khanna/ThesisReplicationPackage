* Concurrent-carrier robustness at the route-quarter level.
version 18
clear all
set more off

do "${package_root}/code/shared/paths.do"
set seed ${seed_std}

local out_root "${results_rob}/concurrent_carriers"
local models_dir "`out_root'/models"
local plots_dir "`out_root'/plots"
local event_dir "`out_root'/event"

capture mkdir "`out_root'"
capture mkdir "`models_dir'"
capture mkdir "`plots_dir'"
capture mkdir "`event_dir'"

capture program drop run_carrier_event
program define run_carrier_event
    syntax varname, modelstub(string) gtitle(string) saveas(string) modeldir(string) eventdir(string)

    capture drop route_cluster_id
    gen long route_cluster_id = route_id

    csdid2 `varlist' ${covars_small}, ///
        ivar(route_id) time(time_period) gvar(first_treat) ///
        method(dripw) cluster(route_cluster_id) short
    estimates save "`modeldir'/`modelstub'", replace

    estat simple, wboot reps(${wb_reps}) rseed(${seed_std})
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
        local n = _N + 1
        set obs `n'
        replace event_time = -1 in `n'
        replace coef = 0 in `n'
        replace se = 0 in `n'
        replace ll = 0 in `n'
        replace ul = 0 in `n'
        sort event_time
        save "`eventdir'/event_`modelstub'.dta", replace
        export delimited using "`eventdir'/event_`modelstub'.csv", replace

        twoway ///
            (rarea ul ll event_time, color(gs8%40) lwidth(none)) ///
            (connected coef event_time, sort lcolor(gs4) mcolor(gs4) msymbol(O) msize(small) lwidth(medthick)), ///
            yline(0, lcolor(gs6) lpattern(solid)) ///
            xline(0, lcolor(gs10) lpattern(shortdash)) ///
            xlabel(-${wpre_main}(2)${wpost_main}) ///
            xtitle("Quarters Relative to Frontier Entry") ///
            ytitle("ATT (number of carriers)") ///
            title("`gtitle'", size(medium) color(black) margin(b=3)) ///
            graphregion(color(white)) plotregion(color(white)) legend(off)

        graph export "`saveas'", replace as(pdf)
    restore

    drop route_cluster_id
end

use "${input_dir}/final_dataset.dta", clear
keep if is_f9_entry_route == 1 | is_never_f9_route == 1

capture drop ln_geo_mean_pop ln_geo_mean_income
gen double ln_geo_mean_pop    = 0.5 * (log(origin_cainc_pop) + log(dest_cainc_pop))
gen double ln_geo_mean_income = 0.5 * (log(origin_cainc_per_capita_income) + log(dest_cainc_per_capita_income))

capture drop origin_big_city dest_big_city big_city_route

preserve
    keep origin time_period origin_cainc_pop
    duplicates drop
    gsort time_period -origin_cainc_pop origin
    by time_period: gen int __orig_rank = _n
    gen byte origin_big_city = (__orig_rank <= 30) if !missing(origin_cainc_pop)
    keep origin time_period origin_big_city
    tempfile orig_bc
    save `orig_bc'
restore
merge m:1 origin time_period using `orig_bc', nogen keep(master match)

preserve
    keep dest time_period dest_cainc_pop
    duplicates drop
    gsort time_period -dest_cainc_pop dest
    by time_period: gen int __dest_rank = _n
    gen byte dest_big_city = (__dest_rank <= 30) if !missing(dest_cainc_pop)
    keep dest time_period dest_big_city
    tempfile dest_bc
    save `dest_bc'
restore
merge m:1 dest time_period using `dest_bc', nogen keep(master match)

gen byte big_city_route = (origin_big_city == 1 & dest_big_city == 1)
replace big_city_route = . if missing(origin_big_city) | missing(dest_big_city)

collapse ///
    (max)   n_carriers n_carriers_excl_frontier first_treat ///
    (first) average_dist route_hhi ///
    (first) ln_geo_mean_pop ln_geo_mean_income ///
    (first) origin_leisure_share_emp dest_leisure_share_emp ///
    (first) big_city_route hub_route, ///
    by(route time_period)

capture confirm variable route_id
if _rc != 0 encode route, gen(route_id)

run_carrier_event n_carriers, ///
    modelstub("n_carriers_all_maincov_never_dripw") ///
    gtitle("(a) All carriers (including Frontier)") ///
    saveas("`plots_dir'/es_n_carriers_all_maincov_never_dripw.pdf") ///
    modeldir("`models_dir'") ///
    eventdir("`event_dir'")

run_carrier_event n_carriers_excl_frontier, ///
    modelstub("n_carriers_excl_frontier_maincov_never_dripw") ///
    gtitle("(b) Carriers excluding Frontier") ///
    saveas("`plots_dir'/es_n_carriers_excl_frontier.pdf") ///
    modeldir("`models_dir'") ///
    eventdir("`event_dir'")

copy "`plots_dir'/es_n_carriers_excl_frontier.pdf" "`plots_dir'/es_n_carriers.pdf", replace

di as result ""
di as result "Done. Concurrent-carrier outputs saved under `out_root'."
