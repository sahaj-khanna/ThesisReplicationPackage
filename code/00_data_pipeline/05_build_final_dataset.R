### econ 495 final data set file
# last updated: 10 February, 2026

################################################################################
#                          SECTION 1: SETUP                                    #
################################################################################

### system instructions
rm(list = ls())
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))
wd <- file.path(repo_root, "data_work")

input <- intermediate_data_dir
output <- input_final_dir

### loading packages
library(data.table)
library(readr)
library(tidyverse)
library(janitor)
library(zoo)
library(fst)
library(ggplot2)
library(dplyr)
library(haven)

################################################################################
#                   SECTION 2: LOAD & MERGE DATASETS                           #
################################################################################

### T-100 data
t_100 <- read_fst(paste0(input, "/T-100/t_100_all.fst"))

t_100_clean <- t_100 %>%
  rename(carrier = unique_carrier) %>%
  mutate(year_quarter = as.yearqtr(year_quarter))

### DB1B data
db1b <- read_fst(file.path(input, "DB1B/db1b_all.fst"))

db1b_clean <- db1b %>%
  clean_names() %>% 
  rename(carrier = op_carrier) %>%
  mutate(year_quarter = as.yearqtr(year_quarter),
         year_quarter_str = format(year_quarter, "%Y Q%q"))

### OTP data
otp <- read_fst(file.path(input, "OTP/otp_all.fst"))

otp_clean <- otp %>%
  rename(carrier = reporting_airline) %>%
  mutate(year_quarter = as.yearqtr(year_quarter),
         year_quarter_str = format(year_quarter, "%Y Q%q"))

### Merge datasets (inner joins to keep only matched observations)
cat("\n=== MERGE DIAGNOSTICS ===\n")

cat("T-100 units:", format(nrow(t_100_clean %>%  distinct(carrier, route)), big.mark = ","), "\n")
cat("DB1B units:", format(nrow(db1b_clean %>%  distinct(carrier, route)), big.mark = ","), "\n")
cat("OTP units:", format(nrow(otp_clean %>%  distinct(carrier, route)), big.mark = ","), "\n\n")

# Merge 1: T-100 x DB1B
final_dataset <- t_100_clean %>%
  inner_join(db1b_clean, by = c("year_quarter", "carrier", "route"),
             suffix = c("_t100", "_db1b"))
cat("After T-100 x DB1B inner join:", format(nrow(final_dataset), big.mark = ","), "rows\n")
cat("  T-100 rows dropped (no DB1B match):",
    format(nrow(t_100_clean) - n_distinct(final_dataset$year_quarter, final_dataset$carrier, final_dataset$route), big.mark = ","), "\n")

# Merge 2: (T-100 x DB1B) x OTP
n_before_otp <- nrow(final_dataset)
final_dataset <- final_dataset %>%
  inner_join(otp_clean, by = c("year_quarter", "carrier", "route"),
             suffix = c("", "_otp"))
cat("After OTP inner join:", format(nrow(final_dataset), big.mark = ","), "rows\n")
cat("  Rows dropped (no OTP match):",
    format(n_before_otp - nrow(final_dataset), big.mark = ","), "\n\n")

# Coalesce duplicate columns from merges
final_dataset <- final_dataset %>%
  mutate(
    route_ident = coalesce(route_ident, route_ident_db1b),
    city_route = coalesce(city_route, city_route_otp),
    year_quarter_str = coalesce(year_quarter_str, year_quarter_str_db1b)
  ) %>%
  select(-route_ident_db1b, -city_route_otp, -year_quarter_str_db1b)

################################################################################
#         SECTION 3: MARKET STRUCTURE & VARIABLE CONSTRUCTION                  #
################################################################################

# --- 3a: Route-level aggregations and market concentration ---

final_dataset <- final_dataset %>%
  group_by(year_quarter, route) %>%
  mutate(
    # Total route-level metrics
    route_capacity_departures = sum(total_departures_performed, na.rm = TRUE),
    route_capacity_passengers = sum(total_passengers, na.rm = TRUE),
    route_capacity_seats = sum(total_seats, na.rm = TRUE),

    # Market structure
    market_share = (total_passengers / route_capacity_passengers) * 100,
    route_hhi = sum(market_share^2, na.rm = TRUE),
    n_carriers = n_distinct(carrier),
    n_carriers_excl_frontier = n_distinct(carrier[carrier != "F9"])
  ) %>%
  ungroup() %>%
  mutate(ln_average_fare = log(average_fare))

# --- 3b: Seasonally-adjusted quality ---

final_dataset <- final_dataset %>%
  mutate(quarter = quarter(as.Date(year_quarter)),
         year = year(as.Date(year_quarter)))

quality_metrics <- c("arrival_delay", "arrival_15", "arrival_30", "travel_time","scheduled_time", "cancellation")

for (metric in quality_metrics) {

  formula_str <- as.formula(paste(metric, "~ factor(quarter)"))
  temp_model <- lm(formula_str, data = final_dataset, na.action = na.exclude)
  new_col_name <- paste0("sa_", metric)

  # Calculate Adjusted Value = Residual + Global Mean
  final_dataset[[new_col_name]] <- residuals(temp_model) + mean(final_dataset[[metric]], na.rm = TRUE)
}

# --- 3c: Origin/destination airport traffic ---

final_dataset <- final_dataset %>%
  group_by(origin, year_quarter) %>%
  mutate(origin_passengers = sum(total_passengers, na.rm = TRUE)) %>%
  group_by(dest, year_quarter) %>%
  mutate(dest_passengers = sum(total_passengers, na.rm = TRUE)) %>%
  ungroup()

# --- 3d: Hub airport identification (TRB 1991 definition) ---

# Origin hubs
hub_airports <- final_dataset %>%
  group_by(origin, year_quarter, carrier) %>%
  summarise(carrier_origin_pax = sum(total_passengers, na.rm = TRUE), .groups = "drop") %>%
  group_by(origin, year_quarter) %>%
  mutate(
    total_airport_pax = sum(carrier_origin_pax),
    airport_carrier_share = carrier_origin_pax / total_airport_pax * 100) %>%
  arrange(origin, year_quarter, desc(airport_carrier_share)) %>%
  mutate(carrier_rank = row_number()) %>%
  mutate(top2_share = sum(airport_carrier_share[carrier_rank <= 2])) %>%
  summarise(
    top_carrier_share = max(airport_carrier_share),
    top2_share = first(top2_share),
    dominant_carrier = carrier[which.max(airport_carrier_share)],
    is_hub = (max(airport_carrier_share) > 50) | (first(top2_share) > 75),
    .groups = "drop")

origin_hubs <- hub_airports %>%
  select(origin, year_quarter,
         origin_is_hub = is_hub,
         origin_dominant_carrier = dominant_carrier,
         origin_top_carrier_share = top_carrier_share)

# Destination hubs
dest_hubs <- final_dataset %>%
  group_by(dest, year_quarter, carrier) %>%
  summarise(carrier_dest_pax = sum(total_passengers, na.rm = TRUE), .groups = "drop") %>%
  group_by(dest, year_quarter) %>%
  mutate(
    total_airport_pax = sum(carrier_dest_pax),
    carrier_share = carrier_dest_pax / total_airport_pax * 100
  ) %>%
  arrange(dest, year_quarter, desc(carrier_share)) %>%
  mutate(carrier_rank = row_number()) %>%
  mutate(top2_share = sum(carrier_share[carrier_rank <= 2])) %>%
  summarise(
    top_carrier_share = max(carrier_share),
    top2_share = first(top2_share),
    dominant_carrier = carrier[which.max(carrier_share)],
    is_hub = (max(carrier_share) > 50) | (first(top2_share) > 75),
    .groups = "drop"
  ) %>%
  select(dest, year_quarter,
         dest_is_hub = is_hub,
         dest_dominant_carrier = dominant_carrier,
         dest_top_carrier_share = top_carrier_share)

# Merge hub indicators to main dataset
final_dataset <- final_dataset %>%
  left_join(origin_hubs, by = c("origin", "year_quarter")) %>%
  left_join(dest_hubs, by = c("dest", "year_quarter")) %>%
  mutate(
    hub_route = as.numeric(origin_is_hub | dest_is_hub),
    hub_to_hub = as.numeric(origin_is_hub & dest_is_hub),
    non_hub_route = as.numeric(!origin_is_hub & !dest_is_hub))

# --- 3e: Legacy and LCC carrier competition ---

legacy_carriers <- c("AA", "DL", "UA", "US", "AS", "CO") # quote Bachwich and Whittmann for this definition
low_cost_carriers <- c("WN", "B6", "FL", "VX")

carrier_dict <- final_dataset %>%
  select(carrier, unique_carrier_name) %>%
  distinct(carrier, .keep_all = TRUE)

final_dataset <- final_dataset %>%
  group_by(year_quarter, route) %>%
  mutate(is_legacy = carrier %in% legacy_carriers,
         n_legacy_carriers = n_distinct(carrier[is_legacy == TRUE]),
         legacy_carrier_share = sum(total_passengers[is_legacy == TRUE], na.rm = TRUE) /
           sum(total_passengers, na.rm = TRUE),
         is_lcc = carrier %in% low_cost_carriers,
         n_lcc = n_distinct(carrier[is_lcc == TRUE])) %>%
  ungroup()

################################################################################
#              SECTION 4: FRONTIER ROUTE TENURE ANALYSIS                       #
################################################################################

# Calculate F9 entry/exit quarters and service continuity
route_tenure <- final_dataset %>%
  filter(carrier == "F9") %>%
  group_by(route) %>%
  summarise(
    f9_entry_qtr = min(year_quarter),
    f9_exit_qtr = max(year_quarter),
    f9_total_qtrs = n_distinct(year_quarter),
    f9_continuous_service = (f9_total_qtrs ==
                              as.numeric(f9_exit_qtr - f9_entry_qtr) * 4 + 1)
  ) %>%
  mutate(f9_continuous_service = if_else(f9_continuous_service, 1L, 0L, missing = 0L))

# Calculate F9's maximum consecutive quarters on each route
frontier_consecutive <- final_dataset %>%
  filter(carrier == "F9") %>%
  arrange(route, year_quarter) %>%
  group_by(route) %>%
  mutate(is_consecutive = c(1, diff(as.numeric(year_quarter)) == 0.25)) %>%
  mutate(streak_id = cumsum(!is_consecutive)) %>%
  group_by(route, streak_id) %>%
  summarize(streak_length = n(), .groups = "drop") %>%
  group_by(route) %>%
  summarize(f9_max_consec_qtrs = max(streak_length)) %>%
  left_join(route_tenure, by = "route")

# Merge route tenure info back to main dataset
final_dataset <- final_dataset %>%
  left_join(frontier_consecutive, by = "route")

################################################################################
#           SECTION 5: TREATMENT VARIABLE DEFINITIONS                          #
################################################################################

### Key dates and route lists

# Business model shift date (Indigo Partners acquisition)
ulcc_shift_date <- as.yearqtr("2014 Q1")

# All routes F9 ever operated during sample period
all_f9_routes <- route_tenure %>%
  distinct(route) %>%
  pull(route)

# Routes F9 served immediately before ULCC shift (2013 Q4)
frontier_existing_routes <- final_dataset %>%
  filter(carrier == "F9", year_quarter == (ulcc_shift_date - 0.25)) %>%
  distinct(route) %>%
  pull(route)

### Treatment 1: Staggered F9 Route Entry (main specification for did package)

final_dataset <- final_dataset %>%
  mutate(
    # Binary indicators
    is_f9_entry_route = if_else(!is.na(f9_entry_qtr) & f9_entry_qtr >= ulcc_shift_date,
                                1L, 0L, missing = 0L),
    is_never_f9_route = if_else(!(route %in% all_f9_routes), 1L, 0L),

    # Quarters relative to F9 entry/exit (for descriptive event studies)
    qtrs_since_f9_entry = as.integer((year_quarter - f9_entry_qtr) * 4),
    qtrs_since_f9_exit = as.integer((year_quarter - f9_exit_qtr) * 4),

    # Simple route classification
    route_type = case_when(
      is.na(f9_entry_qtr) ~ "Never-Treated",
      f9_entry_qtr >= ulcc_shift_date ~ "F9 Entry (Post-Shift)",
      TRUE ~ "F9 Pre-Existing"
    )
  )

### did-compatible variables (Callaway & Sant'Anna)

final_dataset <- final_dataset %>%
  mutate(
    # Numeric time period: 2011Q1 = 1, 2011Q2 = 2, ..., 2019Q4 = 36
    time_period = as.integer(
      (as.numeric(year_quarter) - as.numeric(as.yearqtr("2011 Q1"))) * 4) + 1,

    # Carrier-route panel ID
    carrier_route = paste0(carrier, "_", route),

    # Group variable: numeric F9 entry quarter (0 = never-treated)
    first_treat = ifelse(is.na(f9_entry_qtr), 0L,
      as.integer(
        (as.numeric(f9_entry_qtr) - as.numeric(as.yearqtr("2011 Q1"))) * 4) + 1)
  )

# Save unfiltered file
setwd(output)
write_fst(final_dataset, "final_dataset_unfiltered.fst")

################################################################################
#                    SECTION 6: DATA FILTERING                                 #
################################################################################


# Apply filters:
final_dataset <- final_dataset %>%
  # 1. Drop carrier-route-quarter observations with fewer than 5 passengers
  filter(total_passengers >= 5) %>% # does not change anything. already filtered
  ungroup()

# Robustness: uncomment below to drop routes where F9 operated <4 consecutive quarters
# final_dataset <- final_dataset %>%
#   group_by(route) %>%
#   filter(!any(carrier == "F9" & f9_max_consec_qtrs < 4)) %>%
#   ungroup()

# total number of routes <- 1200
final_dataset %>% 
  filter(carrier == "F9") %>%  
  pull(route) %>% 
  n_distinct()
  
# 5. Drop routes that Frontier entered too late in the sample
last_entry_date <- as.yearqtr("2018 Q4")

final_dataset <- final_dataset %>%
  filter(is.na(f9_entry_qtr) | !(f9_entry_qtr > last_entry_date))


################################################################################
#      SECTION 7: MERGE AIRPORT-CBSA POPULATION/INCOME CONTROLS               #
################################################################################

# Parse DOT airport IDs from route string (e.g., "10135-10397")
final_dataset <- final_dataset %>%
  mutate(
    origin_airport_id = suppressWarnings(as.integer(str_extract(route, "^[0-9]+"))),
    dest_airport_id = suppressWarnings(as.integer(str_extract(route, "(?<=-)[0-9]+")))
  )

cbsa_panel_path <- file.path(wd, "output/crosswalks/airport_id_cbsa_population_county_panel.csv")
cbsa_airport_year <- read_csv(cbsa_panel_path, show_col_types = FALSE) %>%
  transmute(
    airport_id = suppressWarnings(as.integer(airport_id)),
    year = suppressWarnings(as.integer(year)),
    quarter = suppressWarnings(as.integer(quarter)),
    population_census = suppressWarnings(as.numeric(population_census)),
    population_cainc = suppressWarnings(as.numeric(population_cainc)),
    per_capita_income_dollars = suppressWarnings(as.numeric(per_capita_income_dollars)),
    leisure_emp_cbsa = suppressWarnings(as.numeric(leisure_emp_cbsa)),
    total_emp_cbsa = suppressWarnings(as.numeric(total_emp_cbsa)),
    leisure_share_emp_cbsa = suppressWarnings(as.numeric(leisure_share_emp_cbsa))
  ) %>%
  filter(!is.na(airport_id), !is.na(year), !is.na(quarter)) %>%
  distinct()

# Ensure merge keys are unique in CBSA panel.
cbsa_dupes <- cbsa_airport_year %>%
  count(airport_id, year, quarter, name = "n") %>%
  filter(n > 1)

if (nrow(cbsa_dupes) > 0) {
  stop(
    "CBSA airport-year-quarter panel has duplicate keys on (airport_id, year, quarter); merge would be many-to-many.",
    call. = FALSE
  )
}

# create local copy
data_copy <- final_dataset

# Merge origin controls
final_dataset <- final_dataset %>%
  mutate(quarter = suppressWarnings(as.integer(quarter))) %>%
  left_join(
    cbsa_airport_year %>%
      rename(
        origin_airport_id = airport_id,
        origin_census_pop = population_census,
        origin_cainc_pop = population_cainc,
        origin_cainc_per_capita_income = per_capita_income_dollars,
        origin_leisure_emp = leisure_emp_cbsa,
        origin_total_emp = total_emp_cbsa,
        origin_leisure_share_emp = leisure_share_emp_cbsa
      ),
    by = c("origin_airport_id", "year", "quarter"),
    relationship = "many-to-one"
  )

# Merge destination controls
final_dataset <- final_dataset %>%
  left_join(
    cbsa_airport_year %>%
      rename(
        dest_airport_id = airport_id,
        dest_census_pop = population_census,
        dest_cainc_pop = population_cainc,
        dest_cainc_per_capita_income = per_capita_income_dollars,
        dest_leisure_emp = leisure_emp_cbsa,
        dest_total_emp = total_emp_cbsa,
        dest_leisure_share_emp = leisure_share_emp_cbsa
      ),
    by = c("dest_airport_id", "year", "quarter"),
    relationship = "many-to-one"
  )

# Drop observations with missing CAINC population controls
final_dataset <- final_dataset %>%
  mutate(
    route_leisure_share_emp = (origin_leisure_share_emp + dest_leisure_share_emp) / 2
  ) %>%
  filter(!is.na(origin_cainc_pop), !is.na(dest_cainc_pop))


################################################################################
#                    SECTION 8: SAVE FINAL DATASET                             #
################################################################################

setwd(output)

# Convert yearqtr to numeric for Stata compatibility
final_dataset <- final_dataset %>%
  mutate(
    year_quarter_num = as.numeric(year_quarter),
    f9_entry_qtr_num = as.numeric(f9_entry_qtr),
    f9_exit_qtr_num = as.numeric(f9_exit_qtr)
  )

# Save as .fst (for R) and .dta (for Stata)
write_fst(final_dataset, "final_dataset.fst")
write_dta(final_dataset, "final_dataset.dta")

cat("\n=== FINAL DATASET SUMMARY ===\n")
cat("Total observations:", format(nrow(final_dataset), big.mark = ","), "\n")
cat("Unique carriers:", n_distinct(final_dataset$carrier), "\n")
cat("Unique routes:", n_distinct(final_dataset$route), "\n")
cat("Unique carrier-routes:", n_distinct(final_dataset$carrier_route), "\n")
cat("Time periods:", min(final_dataset$time_period), "to", max(final_dataset$time_period), "\n")
cat("Frontier (F9) observations:", sum(final_dataset$carrier == "F9", na.rm = TRUE), "\n")
cat("F9 entry routes (post-shift):",
    n_distinct(final_dataset$route[final_dataset$is_f9_entry_route == 1]), "\n")
cat("Never-treated routes:",
    n_distinct(final_dataset$route[final_dataset$is_never_f9_route == 1]), "\n")
cat("\nSaved: final_dataset.fst & final_dataset.dta\n")

################################################################################
#                              END OF SCRIPT                                   #
################################################################################
