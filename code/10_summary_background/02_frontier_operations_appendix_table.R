### Frontier annual operations appendix table
# Builds annual Frontier summary metrics from final_dataset.fst

rm(list = ls())
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))

input <- input_final_dir
output <- file.path(summary_output_dir, "tables")

dir.create(output, recursive = TRUE, showWarnings = FALSE)

suppressPackageStartupMessages({
  library(dplyr)
  library(fst)
  library(readr)
})

start_year <- 2011
end_year <- 2019

final_dataset <- read_fst(file.path(input, "final_dataset.fst"))

frontier_ops <- final_dataset %>%
  filter(
    carrier == "F9",
    year >= start_year,
    year <= end_year
  ) %>%
  mutate(
    total_flights_row = total_flights,
    total_departures_scheduled_row = total_departures_scheduled
  ) %>%
  group_by(year) %>%
  summarise(
    number_routes = n_distinct(route),
    mean_fare_route_quarter = mean(mean_fare, na.rm = TRUE),
    sd_fare_route_quarter = sd(mean_fare, na.rm = TRUE),
    mean_passengers_route_quarter = mean(total_passengers, na.rm = TRUE),
    total_passengers = sum(total_passengers, na.rm = TRUE),
    total_flights = sum(total_flights_row, na.rm = TRUE),
    mean_distance_route_quarter = mean(average_dist, na.rm = TRUE),
    late_flights_numerator = sum(arrival_15 * total_flights_row, na.rm = TRUE),
    late_flights_denominator = sum(total_flights_row[!is.na(arrival_15)], na.rm = TRUE),
    sd_share_flights_late_route_quarter = sd(arrival_15, na.rm = TRUE),
    cancelled_flights_numerator = sum(cancellation * total_departures_scheduled_row, na.rm = TRUE),
    cancelled_flights_denominator = sum(total_departures_scheduled_row[!is.na(cancellation)], na.rm = TRUE),
    sd_share_flights_cancelled_route_quarter = sd(cancellation, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    pct_flights_late = 100 * (late_flights_numerator / late_flights_denominator),
    pct_flights_on_time = 100 - pct_flights_late,
    pct_flights_cancelled = 100 * (cancelled_flights_numerator / cancelled_flights_denominator),
    sd_pct_flights_late_route_quarter = 100 * sd_share_flights_late_route_quarter,
    sd_pct_flights_cancelled_route_quarter = 100 * sd_share_flights_cancelled_route_quarter
  ) %>%
  select(
    year,
    number_routes,
    mean_fare_route_quarter,
    sd_fare_route_quarter,
    mean_passengers_route_quarter,
    total_passengers,
    total_flights,
    mean_distance_route_quarter,
    pct_flights_on_time,
    pct_flights_late,
    sd_pct_flights_late_route_quarter,
    pct_flights_cancelled,
    sd_pct_flights_cancelled_route_quarter
  ) %>%
  arrange(year)

output_file <- file.path(output, "frontier_operations_appendix_2011_2019.csv")
write_csv(frontier_ops, output_file)

cat("Saved:", output_file, "\n")
