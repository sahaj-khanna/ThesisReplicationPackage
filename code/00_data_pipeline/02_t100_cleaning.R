### econ 495 T-100 data cleaning
# last updated: 8 February, 2026

### system instructions
rm(list = ls())
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))

input <- raw_data_dir
output <- file.path(intermediate_data_dir, "T-100")

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

# ensure one-to-one relationship between different carrier and route columns
is_one_to_one <- function(x, y) {
  id_1 = match(x, x)
  id_2 = match(y, y)
  identical(id_1, id_2)
}

# ==============================================================================
# PROCESS ANNUAL T-100 FILES
# ==============================================================================

process_t_100_year <- function(file_path) {

  # load raw data
  t_100_raw <- read_csv(file_path, show_col_types = FALSE)

  # clean and process
  t_100_clean <- t_100_raw %>%
    clean_names() %>%
    filter(class == "F") %>%                # keep scheduled passenger service only
    mutate(
      year_quarter = as.yearqtr(paste0(year, "-", quarter), format = "%Y-%q"),
      route = paste0(origin_airport_id, "-", dest_airport_id),
      route_ident = paste0(origin, "-", dest),
      city_route = paste0(origin_city_name, "-", dest_city_name)
    )

  # validation: carrier code should map 1-to-1 to carrier name
  if (!is_one_to_one(t_100_clean$unique_carrier, t_100_clean$unique_carrier_name)) {
    stop("unique_carrier does not map 1-to-1 to unique_carrier_name in: ",
         basename(file_path))
  }

  # aggregate to carrier-route-quarter level
  t_100_grouped <- t_100_clean %>%
    group_by(year_quarter, route, unique_carrier, unique_carrier_name) %>%
    summarise(
      total_seats = sum(seats, na.rm = TRUE),
      total_passengers = sum(passengers, na.rm = TRUE),
      total_departures_scheduled = sum(departures_scheduled, na.rm = TRUE),
      total_departures_performed = sum(departures_performed, na.rm = TRUE),
      city_route = first(city_route),
      route_ident = first(route_ident),
      .groups = "drop"
    ) %>%
    mutate(load_factor = ifelse(total_seats > 0, total_passengers / total_seats, 0))

  return(t_100_grouped)
}

# list all annual files
t_100_files <- list.files(
  path = file.path(input, "T-100/annual_data"),
  pattern = "\\.csv$",
  full.names = TRUE
)

# process and combine all years
t_100_all <- map_dfr(t_100_files, process_t_100_year)

# save unfiltered version (reload this to experiment with different filters)
setwd(input)
write_fst(t_100_all, file.path(input, "t_100_unfiltered.fst"))
cat("Saved unfiltered data:", file.path(input, "t_100_unfiltered.fst"), "\n")

# ==============================================================================
# FINAL FILTERS AND FLAGS
# ==============================================================================

# drop carrier-route-quarter observations with < 12 departures performed
t_100_all <- t_100_all %>%
  filter(total_departures_performed >= 12)

# drop observations with 0 passengers
t_100_all <- t_100_all %>%
  filter(total_passengers > 0)

# flag routes where Frontier is operating in each quarter
t_100_all <- t_100_all %>%
  left_join(
    t_100_all %>%
      filter(unique_carrier == "F9") %>%
      distinct(route, year_quarter) %>%
      mutate(f9_present = 1L),
    by = c("route", "year_quarter")
  ) %>%
  mutate(
    f9_present = coalesce(f9_present, 0L),
    year_quarter_str = format(year_quarter, "%Y Q%q")
  )

# drop rows with missing carrier
t_100_all <- t_100_all %>%
  filter(!is.na(unique_carrier))


# ==============================================================================
# VALIDATION CHECKS
# ==============================================================================

cat("\n=== T-100 CLEANING VALIDATION ===\n")
cat("Total observations:", nrow(t_100_all), "\n")
cat("Unique carriers:", n_distinct(t_100_all$unique_carrier), "\n")
cat("Unique routes:", n_distinct(t_100_all$route), "\n")
cat("Year-quarter range:",
    as.character(min(t_100_all$year_quarter)), "to",
    as.character(max(t_100_all$year_quarter)), "\n")
cat("Frontier (F9) observations:", sum(t_100_all$unique_carrier == "F9", na.rm = TRUE), "\n")
cat("Observations with Frontier on route:", sum(t_100_all$f9_present == 1), "\n")

# ==============================================================================
# SAVE OUTPUT
# ==============================================================================

setwd(output)
write_fst(t_100_all, file.path(output, "t_100_all.fst"))
cat("\nSaved:", file.path(output, "t_100_all.fst"), "\n")














