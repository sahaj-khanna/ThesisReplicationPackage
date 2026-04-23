#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export REPLICATION_PACKAGE_ROOT="$PACKAGE_ROOT"

RUN_DATA_PIPELINE="${RUN_DATA_PIPELINE:-0}"
RUN_SUMMARY_BACKGROUND="${RUN_SUMMARY_BACKGROUND:-1}"
RUN_MAIN_RESULTS="${RUN_MAIN_RESULTS:-1}"
RUN_MECHANISMS="${RUN_MECHANISMS:-1}"
RUN_HETEROGENEITY="${RUN_HETEROGENEITY:-1}"
RUN_ROBUSTNESS="${RUN_ROBUSTNESS:-1}"

export RUN_DATA_PIPELINE
export RUN_SUMMARY_BACKGROUND
export RUN_MAIN_RESULTS
export RUN_MECHANISMS
export RUN_HETEROGENEITY
export RUN_ROBUSTNESS

mkdir -p "$PACKAGE_ROOT/output/logs"
LOG_FILE="$PACKAGE_ROOT/output/logs/run_replication.log"

exec > >(tee "$LOG_FILE") 2>&1

echo "Replication package root: $PACKAGE_ROOT"
echo "Starting run at: $(date)"

run_r_script() {
  local rel_path="$1"
  echo "Running R script: $rel_path"
  Rscript "$PACKAGE_ROOT/$rel_path"
}

run_stata_driver() {
  local stata_bin="${STATA_BIN:-stata-mp}"
  echo "Running Stata driver with: $stata_bin"
  "$stata_bin" -b do "$PACKAGE_ROOT/code/shared/run_replication.do"
}

if [[ "$RUN_DATA_PIPELINE" == "1" ]]; then
  run_r_script "code/00_data_pipeline/01_db1b_cleaning.R"
  run_r_script "code/00_data_pipeline/02_t100_cleaning.R"
  run_r_script "code/00_data_pipeline/03_otp_cleaning.R"
  run_r_script "code/00_data_pipeline/04_build_airport_cbsa_crosswalk.R"
  run_r_script "code/00_data_pipeline/05_build_final_dataset.R"
fi

if [[ "$RUN_SUMMARY_BACKGROUND" == "1" ]]; then
  run_r_script "code/10_summary_background/01_summary_statistics.R"
  run_r_script "code/10_summary_background/02_frontier_operations_appendix_table.R"
  run_r_script "code/10_summary_background/03_route_network_map.R"
  run_r_script "code/10_summary_background/04_frontier_operations_figure.R"
fi

if [[ "$RUN_MAIN_RESULTS" == "1" || "$RUN_MECHANISMS" == "1" || "$RUN_HETEROGENEITY" == "1" || "$RUN_ROBUSTNESS" == "1" ]]; then
  run_stata_driver
fi

echo "Finished run at: $(date)"
