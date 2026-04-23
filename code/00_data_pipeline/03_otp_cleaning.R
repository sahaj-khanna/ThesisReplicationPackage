### econ 495 OTP data cleaning
# last updated: 9 February, 2026

### system instructions
rm(list = ls())
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))

input <- file.path(raw_data_dir, "OTP")
output <- file.path(intermediate_data_dir, "OTP")

### loading packages
library(data.table)
library(readr)
library(tidyverse)
library(janitor)
library(zoo)
library(fst)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# list CSV files for a given year
list_files_csv <- function(year) {
  files <- list.files(
    path = file.path(input, as.character(year)),
    pattern = "\\.csv$",
    full.names = TRUE
  )
  return(files)
}

# ==============================================================================
# PROCESS MONTHLY OTP FILES
# ==============================================================================

process_otp_month <- function(file_path) {

  otp_raw <- read_csv(file_path, col_types = cols(.default = "c"), show_col_types = FALSE) %>%
    clean_names() %>%
    type_convert(col_types = cols())

  # filter diverted flights early (not relevant to analysis)
  otp_clean <- otp_raw %>%
    filter(diverted != 1) %>%
    filter(
      (is.na(arr_delay_minutes) | (arr_delay_minutes <= 600)),
      (is.na(dep_delay_minutes) | (dep_delay_minutes <= 600))) %>% 
    mutate(
      year_quarter = as.yearqtr(paste0(year, "-", quarter), format = "%Y-%q"),
      route = paste0(origin_airport_id, "-", dest_airport_id),
      route_ident = paste0(origin, "-", dest),
      city_route = paste0(origin_city_name, "-", dest_city_name),
      dep_del30 = if_else(departure_delay_groups >= 2, 1L, 0L, missing = NA_integer_),
      arr_del30 = if_else(arrival_delay_groups >= 2, 1L, 0L, missing = NA_integer_),
      cancel_carrier = if_else(cancellation_code == "A", 1L, 0L, missing = 0L)
    )

  # aggregate to carrier-route-quarter level (monthly granularity preserved via n_flights)
  otp_grouped <- otp_clean %>%
    group_by(year_quarter, route, reporting_airline) %>%
    summarise(
      departure_delay = weighted.mean(dep_delay_minutes, flights, na.rm = TRUE),
      arrival_delay   = weighted.mean(arr_delay_minutes, flights, na.rm = TRUE),
      carrier_delay   = weighted.mean(carrier_delay, flights, na.rm = TRUE),
      delay_15        = weighted.mean(dep_del15, flights, na.rm = TRUE),
      delay_30        = weighted.mean(dep_del30, flights, na.rm = TRUE),
      arrival_15      = weighted.mean(arr_del15, flights, na.rm = TRUE),
      arrival_30      = weighted.mean(arr_del30, flights, na.rm = TRUE),
      scheduled_time  = weighted.mean(crs_elapsed_time, flights, na.rm = TRUE),
      travel_time     = weighted.mean(actual_elapsed_time, flights, na.rm = TRUE),
      cancellation    = weighted.mean(cancelled, flights, na.rm = TRUE),
      cancel_carrier  = weighted.mean(cancel_carrier, flights, na.rm = TRUE),
      n_flights       = sum(flights),
      route_ident     = first(route_ident),
      city_route      = first(city_route),
      month           = first(month),
      .groups = "drop"
    )

  return(otp_grouped)
}

# ==============================================================================
# PROCESS ANNUAL OTP FILES
# ==============================================================================

process_otp_year <- function(year) {

  # list all monthly files for this year
 otp_files <- list_files_csv(year)

  # process each month and combine
  otp_year <- map_dfr(otp_files, process_otp_month)

  # aggregate months to quarterly level
  otp_quarterly <- otp_year %>%
    group_by(year_quarter, route, reporting_airline) %>%
    summarise(
      across(
        c(departure_delay, arrival_delay, carrier_delay,
          delay_15, delay_30, arrival_15, arrival_30,
          scheduled_time, travel_time, cancellation, cancel_carrier),
        ~ weighted.mean(.x, w = n_flights, na.rm = TRUE)
      ),
      total_flights = sum(n_flights),
      city_route = first(city_route),
      route_ident = first(route_ident),
      .groups = "drop"
    )

  return(otp_quarterly)
}

# ==============================================================================
# PROCESS ALL YEARS
# ==============================================================================

years <- 2011:2019
otp_all <- map_dfr(years, process_otp_year)

# save unfiltered version (reload this to experiment with different filters)
write_fst(otp_all, file.path(input, "otp_unfiltered.fst"))
cat("Saved unfiltered data:", file.path(input, "otp_unfiltered.fst"), "\n")

# ==============================================================================
# FINAL FILTERS AND FLAGS
# ==============================================================================

# add year_quarter string for readability
otp_all <- otp_all %>%
  mutate(year_quarter_str = format(year_quarter, "%Y Q%q"))

# drop rows with missing airline
otp_all <- otp_all %>%
  filter(!is.na(reporting_airline))

# ==============================================================================
# VALIDATION CHECKS
# ==============================================================================

cat("\n=== OTP CLEANING VALIDATION ===\n")
cat("Total observations:", nrow(otp_all), "\n")
cat("Unique airlines:", n_distinct(otp_all$reporting_airline), "\n")
cat("Unique routes:", n_distinct(otp_all$route), "\n")
cat("Year-quarter range:",
    as.character(min(otp_all$year_quarter)), "to",
    as.character(max(otp_all$year_quarter)), "\n")
cat("Frontier (F9) observations:", sum(otp_all$reporting_airline == "F9", na.rm = TRUE), "\n")

# ==============================================================================
# SAVE OUTPUT
# ==============================================================================

write_fst(otp_all, file.path(output, "otp_all.fst"))
cat("\nSaved:", file.path(output, "otp_all.fst"), "\n")
