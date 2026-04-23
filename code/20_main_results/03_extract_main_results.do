********************************************************************************
* 40_extract_results.do
* Main ATT extraction now happens directly in 02_main_atts.do because csdid2
* postestimation relies on live objects rather than csdid rif files.
********************************************************************************

version 18
set more off

do "${package_root}/code/shared/paths.do"

capture confirm file "${results_main}/extracted/att/main/att_main.csv"
if _rc != 0 {
    di as error "Main ATT output not found. Run 02_main_atts.do first."
    exit 601
}

di as text "Main ATT extraction already written by 02_main_atts.do."
di as text "Output: ${results_main}/extracted/att/main/att_main.csv"
