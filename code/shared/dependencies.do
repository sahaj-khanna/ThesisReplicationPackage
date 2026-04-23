********************************************************************************
* replication_package/code/shared/dependencies.do
* Dependency checks for thesis-reported Stata scripts.
********************************************************************************

version 18

capture which csdid2
if _rc != 0 {
    di as error "Missing Stata package: csdid2"
    di as error "Install csdid2 in this Stata environment before running the package."
    exit 198
}
