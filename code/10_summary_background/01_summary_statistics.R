### econ 495 summary statistics file
# last updated: 21 February, 2026

################################################################################
#                          SECTION 1: SETUP                                    #
################################################################################

rm(list = ls())
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))

input <- input_final_dir
output <- summary_output_dir
plot_output <- file.path(output, "figures")
table_output <- file.path(output, "tables")

dir.create(output, recursive = TRUE, showWarnings = FALSE)
dir.create(plot_output, recursive = TRUE, showWarnings = FALSE)
dir.create(table_output, recursive = TRUE, showWarnings = FALSE)

library(tidyverse)
library(zoo)
library(fst)
library(readr)
library(scales)
library(showtext)

calibri_regular <- "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibri.ttf"
calibri_bold <- "/Applications/Microsoft Word.app/Contents/Resources/DFonts/Calibrib.ttf"
font_family <- "Helvetica"
if (file.exists(calibri_regular) && file.exists(calibri_bold)) {
  font_add("Calibri", regular = calibri_regular, bold = calibri_bold)
  font_family <- "Calibri"
}
showtext_auto()

################################################################################
#                   SECTION 2: LOAD DATASET                                    #
################################################################################

final_dataset <- read_fst(file.path(input, "final_dataset.fst"))

################################################################################
#                   SECTION 3: ACTIVE WORK AREA                                #
################################################################################

# Entry timing plot: number of Frontier post-shift route entry events by quarter
entry_events <- final_dataset %>%
  mutate(
    f9_entry_qtr = as.yearqtr(f9_entry_qtr)
  ) %>%
  filter(route_type == "F9 Entry (Post-Shift)", !is.na(f9_entry_qtr)) %>%
  distinct(route, f9_entry_qtr) %>%
  count(f9_entry_qtr, name = "n_entries") %>%
  arrange(f9_entry_qtr) %>%
  mutate(entry_date = as.Date(f9_entry_qtr))

total_entry_events <- sum(entry_events$n_entries)

entry_events_city <- final_dataset %>%
  mutate(
    f9_entry_qtr = as.yearqtr(f9_entry_qtr)
  ) %>%
  filter(route_type == "F9 Entry (Post-Shift)", !is.na(f9_entry_qtr), !is.na(city_route)) %>%
  distinct(city_route, f9_entry_qtr) %>%
  count(f9_entry_qtr, name = "n_entries") %>%
  arrange(f9_entry_qtr) %>%
  mutate(entry_date = as.Date(f9_entry_qtr))

entry_timing_plot <- ggplot(entry_events, aes(x = entry_date, y = n_entries)) +
  geom_col(fill = "black", alpha = 0.9, width = 75) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  scale_y_continuous(breaks = pretty_breaks()) +
  labs(
    x = "Entry Quarter",
    y = "Number of Entry Events"
  ) +
  theme_minimal() +
  theme(
    text = element_text(family = font_family),
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    plot.title = element_blank(),
    plot.subtitle = element_blank(),
    axis.title = element_text(size = 11),
    axis.text = element_text(size = 10),
    axis.line = element_line(color = "black", linewidth = 0.4),
    axis.line.x.top = element_blank(),
    axis.line.y.right = element_blank(),
    panel.grid = element_blank()
  )

entry_timing_plot_city <- ggplot(entry_events_city, aes(x = entry_date, y = n_entries)) +
  geom_col(fill = "black", alpha = 0.9, width = 75) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  scale_y_continuous(breaks = pretty_breaks()) +
  labs(
    x = "Entry Quarter",
    y = "Number of Entry Events"
  ) +
  theme_minimal() +
  theme(
    text = element_text(family = font_family),
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    plot.title = element_blank(),
    plot.subtitle = element_blank(),
    axis.title = element_text(size = 11),
    axis.text = element_text(size = 10),
    axis.line = element_line(color = "black", linewidth = 0.4),
    axis.line.x.top = element_blank(),
    axis.line.y.right = element_blank(),
    panel.grid = element_blank()
  )

ggsave(
  filename = paste0(plot_output, "/entry_timing_plot.pdf"),
  plot = entry_timing_plot,
  width = 10,
  height = 6,
  bg = "white"
)

ggsave(
  filename = paste0(plot_output, "/entry_timing_plot_city.pdf"),
  plot = entry_timing_plot_city,
  width = 10,
  height = 6,
  bg = "white"
)

################################################################################
#                   SECTION 3B: FRONTIER SERVICE FREQUENCY HISTOGRAM           #
################################################################################

weeks_in_quarter <- 13

frontier_weekly_frequency_2019q1 <- final_dataset %>%
  mutate(year_quarter = as.yearqtr(year_quarter)) %>%
  filter(
    carrier == "F9",
    year_quarter == as.yearqtr("2019 Q1"),
    total_departures_performed > 0
  ) %>%
  distinct(route, route_ident, total_departures_performed) %>%
  mutate(
    departures_per_week = total_departures_performed / weeks_in_quarter
  )

frontier_service_hist_2019q1 <- ggplot(
  frontier_weekly_frequency_2019q1,
  aes(x = departures_per_week)
) +
  geom_histogram(
    binwidth = 1,
    boundary = 0,
    closed = "left",
    fill = "black",
    color = "white",
    linewidth = 0.2
  ) +
  geom_vline(xintercept = 7, color = "#0F6744", linewidth = 0.6, linetype = "22") +
  geom_vline(xintercept = 14, color = "grey35", linewidth = 0.6, linetype = "22") +
  annotate("text", x = 7.2, y = Inf, label = "Daily", vjust = 1.6, hjust = 0, size = 3.6, color = "#0F6744") +
  annotate("text", x = 14.2, y = Inf, label = "Twice daily", vjust = 1.6, hjust = 0, size = 3.6, color = "grey25") +
  scale_x_continuous(
    breaks = seq(0, 28, by = 2),
    limits = c(0, 28),
    expand = expansion(mult = c(0, 0.02))
  ) +
  scale_y_continuous(expand = expansion(mult = c(0, 0.08))) +
  labs(
    x = "Average Departures per Week",
    y = "Number of Frontier Routes"
  ) +
  theme_minimal() +
  theme(
    text = element_text(family = font_family),
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    plot.title = element_blank(),
    plot.subtitle = element_blank(),
    axis.title = element_text(size = 11),
    axis.text = element_text(size = 10),
    axis.line = element_line(color = "black", linewidth = 0.4),
    axis.line.x.top = element_blank(),
    axis.line.y.right = element_blank(),
    panel.grid = element_blank()
  )

ggsave(
  filename = paste0(plot_output, "/frontier_service_frequency_hist_2019q1.pdf"),
  plot = frontier_service_hist_2019q1,
  width = 9,
  height = 5.6,
  bg = "white"
)

write_csv(
  frontier_weekly_frequency_2019q1,
  file.path(table_output, "frontier_service_frequency_2019q1.csv")
)

################################################################################
#                   SECTION 4: NUMBER OF ROUTES BY TREATMENT BUCKET            #
################################################################################

route_bucket_counts <- final_dataset %>%
  distinct(route, route_type) %>%
  mutate(
    route_bucket = factor(
      route_type,
      levels = c("F9 Entry (Post-Shift)", "F9 Pre-Existing", "Never-Treated"),
      labels = c("Treated: Post-Shift Entry", "Treated: Pre-Existing", "Control: Never-Treated")
    )
  ) %>%
  count(route_bucket, name = "n_routes") %>%
  arrange(route_bucket)

################################################################################
#                   SECTION 5: ROUTE CHARACTERISTICS FOR TREATED AND CONTROL   #
################################################################################

baseline_qtr <- as.yearqtr("2013 Q4")

route_baseline_2013q4 <- final_dataset %>%
  mutate(year_quarter = as.yearqtr(year_quarter)) %>%
  filter(year_quarter == baseline_qtr) %>%
  # Exclude pre-existing Frontier routes by construction.
  filter(route_type %in% c("F9 Entry (Post-Shift)", "Never-Treated")) %>%
  mutate(
    comparison_group = case_when(
      route_type == "F9 Entry (Post-Shift)" ~ "Treated (Future Entry Routes)",
      route_type == "Never-Treated" ~ "Control (Never-Treated Routes)",
      TRUE ~ NA_character_
    )
  ) %>%
  group_by(route, comparison_group) %>% # still multiple carriers in each route — frontier should not be included in any of them
  summarise(
    baseline_avg_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
      sum(total_passengers, na.rm = TRUE),
    baseline_avg_distance = weighted.mean(average_dist, total_passengers, na.rm = TRUE),
    baseline_distance_2 = first(average_dist),
    baseline_num_carriers = first(n_carriers),
    baseline_hhi = first(route_hhi),
    baseline_hub_route = first(hub_route),
    baseline_n_legacy_carriers = first(n_legacy_carriers),
    baseline_legacy_carrier_share = first(legacy_carrier_share) * 100,
    baseline_n_lcc_carriers = first(n_lcc),
    baseline_avg_delay = weighted.mean(sa_arrival_delay, total_flights, na.rm = TRUE),
    baseline_delay_15_rate = weighted.mean(sa_arrival_15, total_flights, na.rm = TRUE) * 100,
    baseline_cancellation_rate = weighted.mean(sa_cancellation, total_flights, na.rm = TRUE) * 100,
    baseline_avg_scheduled_flights = sum(total_departures_performed, na.rm = TRUE),
    baseline_avg_seat_capacity = first(route_capacity_seats),
    baseline_load_factor = (sum(total_passengers, na.rm = TRUE) /
      sum(total_seats, na.rm = TRUE)) * 100,
    baseline_route_size = first(route_capacity_passengers), 
    .groups = "drop"
  )

route_characteristics_baseline <- route_baseline_2013q4 %>%
  group_by(comparison_group) %>%
  summarise(
    n_routes = n_distinct(route),
    avg_fare = mean(baseline_avg_fare, na.rm = TRUE),
    avg_distance = mean(baseline_avg_distance, na.rm = TRUE),
    avg_distance_2 = mean(baseline_distance_2, na.rm = TRUE),
    avg_num_carriers = mean(baseline_num_carriers, na.rm = TRUE),
    avg_hhi = mean(baseline_hhi, na.rm = TRUE),
    prop_hub_routes = mean(baseline_hub_route, na.rm = TRUE) * 100,
    avg_n_legacy_carriers = mean(baseline_n_legacy_carriers, na.rm = TRUE),
    avg_legacy_carrier_share = mean(baseline_legacy_carrier_share, na.rm = TRUE),
    avg_n_lcc_carriers = mean(baseline_n_lcc_carriers, na.rm = TRUE),
    avg_delay = mean(baseline_avg_delay, na.rm = TRUE),
    avg_delay_15_rate = mean(baseline_delay_15_rate, na.rm = TRUE),
    avg_cancellation_rate = mean(baseline_cancellation_rate, na.rm = TRUE),
    avg_scheduled_flights = mean(baseline_avg_scheduled_flights, na.rm = TRUE),
    avg_seat_capacity = mean(baseline_avg_seat_capacity, na.rm = TRUE),
    avg_load_factor = mean(baseline_load_factor, na.rm = TRUE),
    avg_route_size = mean(baseline_route_size, na.rm = TRUE), 
    .groups = "drop"
  )

# Standardized mean differences (SMD) at route baseline level
smd_metrics <- c(
  "baseline_avg_fare",
  "baseline_avg_distance",
  "baseline_num_carriers",
  "baseline_hhi",
  "baseline_hub_route",
  "baseline_n_legacy_carriers",
  "baseline_legacy_carrier_share",
  "baseline_n_lcc_carriers",
  "baseline_avg_delay",
  "baseline_delay_15_rate",
  "baseline_cancellation_rate",
  "baseline_avg_scheduled_flights",
  "baseline_avg_seat_capacity",
  "baseline_load_factor"
)

smd_table <- purrr::map_dfr(smd_metrics, function(metric_name) {
  treated_vals <- route_baseline_2013q4 %>%
    filter(comparison_group == "Treated (Future Entry Routes)") %>%
    pull(all_of(metric_name))

  control_vals <- route_baseline_2013q4 %>%
    filter(comparison_group == "Control (Never-Treated Routes)") %>%
    pull(all_of(metric_name))

  pooled_sd <- sqrt((var(treated_vals, na.rm = TRUE) + var(control_vals, na.rm = TRUE)) / 2)

  tibble(
    metric = metric_name,
    treated_mean = mean(treated_vals, na.rm = TRUE),
    control_mean = mean(control_vals, na.rm = TRUE),
    smd = (mean(treated_vals, na.rm = TRUE) - mean(control_vals, na.rm = TRUE)) / pooled_sd
  )
}) %>%
  mutate(
    metric = recode(
      metric,
      "baseline_avg_fare" = "Average Fare",
      "baseline_avg_distance" = "Average Distance",
      "baseline_num_carriers" = "Number of Carriers",
      "baseline_hhi" = "HHI",
      "baseline_hub_route" = "Hub Route Share",
      "baseline_n_legacy_carriers" = "Number of Legacy Carriers",
      "baseline_legacy_carrier_share" = "Legacy Carrier Share",
      "baseline_n_lcc_carriers" = "Number of LCC Carriers",
      "baseline_avg_delay" = "SA Average Delay",
      "baseline_delay_15_rate" = "SA Flights Delayed >15 Min",
      "baseline_cancellation_rate" = "SA Cancellation Rate",
      "baseline_avg_scheduled_flights" = "Scheduled Flights",
      "baseline_avg_seat_capacity" = "Seat Capacity",
      "baseline_load_factor" = "Load Factor"
    )
  ) %>%
  arrange(desc(abs(smd)))

smd_plot <- ggplot(
  smd_table,
  aes(x = smd, y = reorder(metric, abs(smd)), color = abs(smd) > 0.1)
) +
  geom_vline(xintercept = 0, linetype = "dashed", color = "grey40") +
  geom_vline(xintercept = c(-0.1, 0.1), linetype = "dotted", color = "grey60") +
  geom_point(size = 2.7) +
  scale_color_manual(values = c("TRUE" = "#9d0208", "FALSE" = "#1b4332"), guide = "none") +
  labs(
    title = "Standardized Mean Differences Between Treated and Never-Treated Groups in Baseline Period",
    subtitle = "Red points exceed |SMD| = 0.10",
    x = "Standardized Mean Difference",
    y = NULL
  ) +
  theme_classic() +
  theme(
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    plot.title = element_text(face = "bold", size = 13)
  )

ggsave(paste0(plot_output, "/smd_plot_baseline_2013q4.pdf"),
       plot = smd_plot, width = 10, height = 7, bg = "white")

################################################################################
#                   SECTION 5B: BALANCE TABLE FOR EXCEL                        #
################################################################################

# Build a route-quarter balance table for:
# 1) Full sample (treated + never-treated, all quarters),
# 2) Treated and never-treated in pre-2014 baseline period,
# 3) Significance tests for treated vs never-treated (pre-2014).
#
# TODO [RC.22a / RCl.4.7]: Add standardized differences to this table build.
# The revision plan explicitly asks for standardized differences, and they are
# more publication-standard here than relying on p-values alone.
#
# TODO [writing rules / tables]: Export the exact sample sizes used in the paper
# table. The manuscript should show both the number of route-quarter observations
# and the number of distinct routes for each comparison group.
#
# Weighting choices:
# - Fare and delay are first collapsed to route-quarter using carrier weights:
#   passenger-weighted fare; flight-weighted delay.
# - Final table means/SD/tests are then computed across route-quarter observations.

weighted_mean_safe <- function(x, w) {
  keep <- is.finite(x) & is.finite(w) & w > 0
  if (!any(keep)) {
    return(NA_real_)
  }
  weighted.mean(x[keep], w = w[keep], na.rm = TRUE)
}

route_quarter_sample <- final_dataset %>%
  mutate(year_quarter = as.yearqtr(year_quarter)) %>%
  filter(route_type %in% c("F9 Entry (Post-Shift)", "Never-Treated")) %>%
  mutate(
    treated_flag = if_else(route_type == "F9 Entry (Post-Shift)", 1L, 0L),
    avg_od_population = (origin_cainc_pop + dest_cainc_pop) / 2,
    small_od_population = pmin(origin_cainc_pop, dest_cainc_pop),
    large_od_population = pmax(origin_cainc_pop, dest_cainc_pop),
    avg_od_per_capita_income = (origin_cainc_per_capita_income + dest_cainc_per_capita_income) / 2,
    small_od_per_capita_income = pmin(origin_cainc_per_capita_income, dest_cainc_per_capita_income),
    large_od_per_capita_income = pmax(origin_cainc_per_capita_income, dest_cainc_per_capita_income),
    route_has_lcc = if_else(n_lcc > 0, 1L, 0L)
  ) %>%
  group_by(route, year_quarter, treated_flag) %>%
  summarise(
    average_fare = weighted_mean_safe(average_fare, total_passengers),
    carrier_delay = weighted_mean_safe(coalesce(carrier_delay, 0), total_departures_performed),
    total_departures_performed = sum(total_departures_performed, na.rm = TRUE),
    average_dist = first(average_dist),
    route_hhi = first(route_hhi),
    route_has_lcc = as.integer(any(route_has_lcc == 1, na.rm = TRUE)),
    n_carriers = first(n_carriers),
    total_passengers = sum(total_passengers, na.rm = TRUE),
    avg_od_population = first(avg_od_population),
    small_od_population = first(small_od_population),
    large_od_population = first(large_od_population),
    avg_od_per_capita_income = first(avg_od_per_capita_income),
    small_od_per_capita_income = first(small_od_per_capita_income),
    large_od_per_capita_income = first(large_od_per_capita_income),
    .groups = "drop"
  )

pre2014_sample <- route_quarter_sample %>%
  filter(year_quarter < as.yearqtr("2014 Q1"))

balance_vars <- tribble(
  ~panel, ~variable, ~source_var, ~weight_var,
  "Panel A: Outcome Variables", "Average Fare ($)", "average_fare", NA_character_,
  "Panel A: Outcome Variables", "Mean Carrier Delay (Minutes)", "carrier_delay", NA_character_,
  "Panel A: Outcome Variables", "Total Departures", "total_departures_performed", NA_character_,
  "Panel B: Route Covariates", "Route Distance", "average_dist", NA_character_,
  "Panel B: Route Covariates", "Route Herfindahl Hirschmann Index (HHI)", "route_hhi", NA_character_,
  "Panel B: Route Covariates", "Routes with Low Cost Carriers", "route_has_lcc", NA_character_,
  "Panel B: Route Covariates", "Number of Carriers on Route", "n_carriers", NA_character_,
  "Panel B: Route Covariates", "Number of Passengers on Routes", "total_passengers", NA_character_,
  "Panel B: Route Covariates", "Average Origin & Destination Population", "avg_od_population", NA_character_,
  "Panel B: Route Covariates", "Small Endpoint Population", "small_od_population", NA_character_,
  "Panel B: Route Covariates", "Large Endpoint Population", "large_od_population", NA_character_,
  "Panel B: Route Covariates", "Average Origin & Destination Per Capita Income", "avg_od_per_capita_income", NA_character_,
  "Panel B: Route Covariates", "Small Endpoint Per Capita Income", "small_od_per_capita_income", NA_character_,
  "Panel B: Route Covariates", "Large Endpoint Per Capita Income", "large_od_per_capita_income", NA_character_
)

# TODO [RC.22b]: Keep the final manuscript table in this same Panel A / Panel B
# structure. The current writing file already uses panels, so the remaining work
# is to pipe the computed values into LaTeX instead of maintaining the table by hand.
#
# TODO [Claude feedback]: HHI is already included in the script but not in the
# current LaTeX table. Make sure the manuscript version actually displays it.

safe_weighted_stats <- function(data, value_var, weight_var = NA_character_) {
  if (is.na(weight_var)) {
    x <- data[[value_var]]
    x <- x[is.finite(x)]
    n <- length(x)
    if (n == 0) {
      return(tibble(mean = NA_real_, sd_route = NA_real_, n = 0L, n_routes = 0L))
    }
    route_means <- data %>%
      filter(is.finite(.data[[value_var]])) %>%
      group_by(route) %>%
      summarise(route_mean = mean(.data[[value_var]], na.rm = TRUE), .groups = "drop")
    return(tibble(
      mean = mean(x, na.rm = TRUE),
      sd_route = sd(route_means$route_mean, na.rm = TRUE),
      n = n,
      n_routes = nrow(route_means)
    ))
  }

  x <- data[[value_var]]
  w <- data[[weight_var]]
  keep <- is.finite(x) & is.finite(w) & w > 0
  x <- x[keep]
  w <- w[keep]
  n <- length(x)
  if (n == 0) {
    return(tibble(mean = NA_real_, sd_route = NA_real_, n = 0L, n_routes = 0L))
  }

  route_means <- data %>%
    filter(is.finite(.data[[value_var]]), is.finite(.data[[weight_var]]), .data[[weight_var]] > 0) %>%
    group_by(route) %>%
    summarise(route_mean = weighted_mean_safe(.data[[value_var]], .data[[weight_var]]), .groups = "drop")

  tibble(
    mean = weighted.mean(x, w = w, na.rm = TRUE),
    sd_route = sd(route_means$route_mean, na.rm = TRUE),
    n = n,
    n_routes = nrow(route_means)
  )
}

# TODO [RC.22a]: Add a helper here to compute standardized differences between
# treated and never-treated routes in the pre-2014 sample. Export that value as
# its own column so the manuscript can report balance without leaning only on
# significance stars or t-tests.

cluster_vcov <- function(fit, cluster_vec) {
  X <- model.matrix(fit)
  if (is.null(dim(X))) {
    X <- matrix(X, ncol = 1)
  }

  # Score contribution for WLS: x_i * w_i * e_i; for OLS: x_i * e_i.
  u <- residuals(fit)
  w <- fit$weights
  if (!is.null(w)) {
    u <- u * w
  }

  cluster_fac <- as.factor(cluster_vec)
  g_levels <- levels(cluster_fac)
  G <- length(g_levels)
  N <- nrow(X)
  K <- ncol(X)

  if (G <= 1 || N <= K) {
    return(matrix(NA_real_, nrow = K, ncol = K))
  }

  meat <- matrix(0, nrow = K, ncol = K)
  for (g in g_levels) {
    idx <- which(cluster_fac == g)
    Xg <- X[idx, , drop = FALSE]
    ug <- u[idx]
    xugu <- t(Xg) %*% ug
    meat <- meat + xugu %*% t(xugu)
  }

  bread <- qr.solve(crossprod(X))
  df_correction <- (G / (G - 1)) * ((N - 1) / (N - K))
  vc <- df_correction * bread %*% meat %*% bread
  coef_names <- colnames(X)
  dimnames(vc) <- list(coef_names, coef_names)
  vc
}

safe_cluster_p_value <- function(data, value_var, weight_var = NA_character_) {
  model_df <- data %>%
    select(route, treated_flag, all_of(value_var)) %>%
    filter(is.finite(.data[[value_var]]))

  if (!is.na(weight_var)) {
    model_df <- data %>%
      select(route, treated_flag, all_of(value_var), all_of(weight_var)) %>%
      filter(is.finite(.data[[value_var]])) %>%
      filter(is.finite(.data[[weight_var]]), .data[[weight_var]] > 0)
  }

  if (nrow(model_df) < 3 || dplyr::n_distinct(model_df$treated_flag) < 2) {
    return(NA_real_)
  }

  fml <- as.formula(paste(value_var, "~ treated_flag"))
  fit <- if (is.na(weight_var)) {
    lm(fml, data = model_df)
  } else {
    lm(fml, data = model_df, weights = model_df[[weight_var]])
  }

  vc <- cluster_vcov(fit, model_df$route)
  se <- sqrt(diag(vc))
  beta <- coef(fit)

  if (!("treated_flag" %in% names(beta)) || !("treated_flag" %in% names(se))) {
    return(NA_real_)
  }
  if (!is.finite(se["treated_flag"]) || se["treated_flag"] <= 0) {
    return(NA_real_)
  }

  t_stat <- beta["treated_flag"] / se["treated_flag"]
  df <- dplyr::n_distinct(model_df$route) - 1
  if (!is.finite(df) || df <= 0) {
    return(NA_real_)
  }
  2 * stats::pt(abs(t_stat), df = df, lower.tail = FALSE)
}

fmt_mean_sd <- function(m, s, digits = 2) {
  if (is.na(m) || is.na(s)) {
    return(NA_character_)
  }
  paste0(format(round(m, digits), nsmall = digits), " (", format(round(s, digits), nsmall = digits), ")")
}

balance_table_excel <- balance_vars %>%
  rowwise() %>%
  mutate(
    full_stats = list(safe_weighted_stats(route_quarter_sample, source_var, weight_var)),
    treated_stats = list(safe_weighted_stats(pre2014_sample %>% filter(treated_flag == 1), source_var, weight_var)),
    control_stats = list(safe_weighted_stats(pre2014_sample %>% filter(treated_flag == 0), source_var, weight_var)),
    p_value = safe_cluster_p_value(pre2014_sample, source_var, weight_var)
  ) %>%
  mutate(
    full_mean = full_stats$mean,
    full_sd = full_stats$sd_route,
    full_n = full_stats$n,
    full_n_routes = full_stats$n_routes,
    treated_pre2014_mean = treated_stats$mean,
    treated_pre2014_sd = treated_stats$sd_route,
    treated_pre2014_n = treated_stats$n,
    treated_pre2014_n_routes = treated_stats$n_routes,
    never_treated_pre2014_mean = control_stats$mean,
    never_treated_pre2014_sd = control_stats$sd_route,
    never_treated_pre2014_n = control_stats$n,
    never_treated_pre2014_n_routes = control_stats$n_routes,
    diff_treated_minus_never = treated_pre2014_mean - never_treated_pre2014_mean,
    full_sample_mean_sd = fmt_mean_sd(full_mean, full_sd),
    treated_pre2014_mean_sd = fmt_mean_sd(treated_pre2014_mean, treated_pre2014_sd),
    never_treated_pre2014_mean_sd = fmt_mean_sd(never_treated_pre2014_mean, never_treated_pre2014_sd),
    test_used = if_else(
      is.na(weight_var),
      "OLS difference test (route-clustered SE)",
      "Weighted OLS difference test (route-clustered SE)"
    )
  ) %>%
  ungroup() %>%
  select(
    panel,
    variable,
    full_sample_mean_sd,
    treated_pre2014_mean_sd,
    never_treated_pre2014_mean_sd,
    diff_treated_minus_never,
    p_value,
    test_used,
    full_mean,
    full_sd,
    treated_pre2014_mean,
    treated_pre2014_sd,
    never_treated_pre2014_mean,
    never_treated_pre2014_sd,
    full_n,
    treated_pre2014_n,
    never_treated_pre2014_n,
    full_n_routes,
    treated_pre2014_n_routes,
    never_treated_pre2014_n_routes
  )

# TODO [RC.22a]: Extend this exported object with:
# - standardized_difference
# - formatted N / route counts for each group
# - any display-ready labels needed by the LaTeX table
#
# TODO [writing rules / tables]: The paper should discuss the main balance
# patterns directly in prose, not just say "Table X shows summary statistics."
# This export should therefore make it easy to identify the largest differences
# to mention in the text: traffic, competition, distance, and any HHI gap.

write_csv(balance_table_excel, paste0(output, "/treated_vs_never_treated_balance_table.csv"))

# TODO [workflow]: Replace the hand-entered summary-statistics values in
# components/data_summary_stats.tex with values generated from this file. Right
# now the script and manuscript table can drift apart.

if (requireNamespace("writexl", quietly = TRUE)) {
  writexl::write_xlsx(
    list("balance_table" = balance_table_excel),
    path = paste0(output, "/treated_vs_never_treated_balance_table.xlsx")
  )
} else {
  message("Package 'writexl' not installed. Wrote CSV only for balance table.")
}

################################################################################
#                   SECTION 6: COHORT VS CONTROL OVER CALENDAR TIME            #
################################################################################

# Change this quarter to inspect a different treated cohort.
cohort_entry_qtr <- as.yearqtr("2014 Q4")

cohort_routes <- final_dataset %>%
  mutate(f9_entry_qtr = as.yearqtr(f9_entry_qtr)) %>%
  filter(route_type == "F9 Entry (Post-Shift)", f9_entry_qtr == cohort_entry_qtr) %>%
  distinct(route) %>%
  pull(route)

if (length(cohort_routes) == 0) {
  stop(paste0("No post-shift entry routes found for cohort ", format(cohort_entry_qtr, "%Y Q%q")))
}

cohort_vs_control_counts <- tibble(
  group = c("Selected Cohort", "Never-Treated Control"),
  n_routes = c(
    length(cohort_routes),
    final_dataset %>% filter(route_type == "Never-Treated") %>% distinct(route) %>% nrow()
  )
)

cohort_vs_control_ts <- final_dataset %>%
  mutate(year_quarter = as.yearqtr(year_quarter)) %>%
  filter(route %in% cohort_routes | route_type == "Never-Treated") %>%
  mutate(
    comparison_group = case_when(
      route %in% cohort_routes ~ paste0("Cohort: ", format(cohort_entry_qtr, "%Y Q%q")),
      route_type == "Never-Treated" ~ "Never-Treated Control",
      TRUE ~ NA_character_
    )
  ) %>%
  filter(!is.na(comparison_group)) %>%
  group_by(year_quarter, comparison_group) %>%
  summarise(
    avg_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
      sum(total_passengers, na.rm = TRUE),
    fare_p90_p10_ratio = weighted.mean(fare_ratio_90_10, total_passengers, na.rm = TRUE),
    avg_arrival_delay = weighted.mean(sa_arrival_delay, total_flights, na.rm = TRUE),
    avg_load_factor = weighted.mean(load_factor, total_departures_performed, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(date = as.Date(year_quarter))

cohort_vs_control_ts_long <- cohort_vs_control_ts %>%
  pivot_longer(
    cols = c(avg_fare, fare_p90_p10_ratio, avg_arrival_delay, avg_load_factor),
    names_to = "metric",
    values_to = "value"
  ) %>%
  mutate(
    metric = factor(
      metric,
      levels = c("avg_fare", "fare_p90_p10_ratio", "avg_arrival_delay", "avg_load_factor"),
      labels = c(
        "Average Fare ($)",
        "Average Fare Dispersion (P90 / P10)",
        "Average SA Arrival Delay (Min)",
        "Average Load Factor (%)"
      )
    )
  )

cohort_vs_control_plot <- ggplot(
  cohort_vs_control_ts_long,
  aes(x = date, y = value, color = comparison_group)
) +
  geom_line(linewidth = 1) +
  geom_vline(
    xintercept = as.Date(cohort_entry_qtr),
    linetype = "dashed",
    color = "grey40",
    linewidth = 0.6
  ) +
  facet_wrap(~ metric, scales = "free_y", ncol = 2) +
  scale_color_manual(values = setNames(
    c("#0b2545", "#1b4332"),
    c("Never-Treated Control", paste0("Cohort: ", format(cohort_entry_qtr, "%Y Q%q")))
  )) +
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(
    title = paste0("Cohort vs Control Over Calendar Time (Entry Cohort: ", format(cohort_entry_qtr, "%Y Q%q"), ")"),
    subtitle = "Dashed vertical line marks the selected cohort entry quarter",
    x = "Calendar Time",
    y = NULL,
    color = NULL
  ) +
  theme_classic() +
  theme(
    panel.background = element_rect(fill = "white", color = NA),
    plot.background = element_rect(fill = "white", color = NA),
    strip.background = element_rect(fill = "white", color = "black", linewidth = 0.2),
    strip.text = element_text(face = "bold"),
    legend.position = "top",
    plot.title = element_text(face = "bold", size = 13)
  )

cohort_vs_control_plot

ggsave(paste0(plot_output, "/cohort_vs_control_", gsub(" ", "_", format(cohort_entry_qtr, "%Y Q%q")), ".pdf"),
       plot = cohort_vs_control_plot, width = 12, height = 8, bg = "white")

write_csv(route_baseline_2013q4, paste0(output, "/route_baseline_2013q4.csv"))
write_csv(route_characteristics_baseline, paste0(output, "/route_characteristics_baseline_2013q4.csv"))







################################################################################
#                   SECTION 99: ARCHIVE (OLD CODE)                             #
################################################################################

if (FALSE) {

  # --- Archived compatibility checks and derived columns used for older tables/plots ---
  required_cols <- c(
    "year_quarter", "route", "carrier", "average_fare", "total_passengers",
    "route_hhi", "n_carriers", "route_capacity_passengers", "route_capacity_departures",
    "arrival_delay", "arrival_15", "arrival_30", "cancellation", "total_flights",
    "total_seats", "average_dist", "total_revenue", "total_pax", "route_type",
    "qtrs_since_f9_entry"
  )

  missing_cols <- setdiff(required_cols, names(final_dataset))
  if (length(missing_cols) > 0) {
    stop(paste("Missing required columns in final_dataset.fst:",
               paste(missing_cols, collapse = ", ")))
  }

  final_dataset <- final_dataset %>%
    mutate(
      year_quarter = as.yearqtr(year_quarter),
      rel_entry_qtr = qtrs_since_f9_entry,
      event_period = case_when(
        rel_entry_qtr >= -8 & rel_entry_qtr <= -1 ~ "Quarters [t-8, t-1]",
        rel_entry_qtr >= 0 & rel_entry_qtr <= 3 ~ "Quarters [t, t+3]",
        rel_entry_qtr >= 4 & rel_entry_qtr <= 7 ~ "Quarters [t+4, t+7]",
        TRUE ~ NA_character_
      ),
      route_group = case_when(
        route_type == "F9 Pre-Existing" ~ "Existing Routes (Treated)",
        route_type == "Never-Treated" ~ "Never-Treated Control",
        route_type == "F9 Entry (Post-Shift)" ~ "Treated Earlier or Later",
        TRUE ~ "Other"
      ),
      time_period_label = case_when(
        year_quarter >= as.yearqtr("2011 Q1") & year_quarter <= as.yearqtr("2013 Q4") ~ "Baseline (Pre-Shift)",
        year_quarter >= as.yearqtr("2014 Q1") & year_quarter <= as.yearqtr("2014 Q4") ~ "Transition Year",
        year_quarter >= as.yearqtr("2015 Q1") & year_quarter <= as.yearqtr("2016 Q4") ~ "Established ULCC",
        TRUE ~ "Other"
      ),
      time_period_label = factor(
        time_period_label,
        levels = c("Baseline (Pre-Shift)", "Transition Year", "Established ULCC", "Other")
      ),
      route_carrier_class = case_when(
        carrier == "F9" & route_group == "Existing Routes (Treated)" ~ "Frontier (Treated)",
        carrier != "F9" & route_group == "Existing Routes (Treated)" ~ "Incumbents (Treated)",
        carrier != "F9" & route_group == "Never-Treated Control" ~ "Control Routes",
        TRUE ~ "Other/F9 New Entry"
      )
    )

  # --- Archived summary tables ---
  missing_check <- final_dataset %>%
    group_by(year_quarter) %>%
    summarise(
      total_obs = n(),
      pct_missing_fare = mean(is.na(average_fare)) * 100,
      pct_missing_otp = mean(is.na(departure_delay)) * 100,
      .groups = "drop"
    )

  entry_summary_stats <- final_dataset %>%
    filter(!is.na(event_period)) %>%
    group_by(event_period) %>%
    summarise(
      n_obs = n(),
      unique_routes = n_distinct(route),
      mean_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
        sum(total_passengers, na.rm = TRUE),
      sd_fare = sd(average_fare, na.rm = TRUE),
      num_carriers = mean(n_carriers, na.rm = TRUE),
      num_carriers_sd = sd(n_carriers, na.rm = TRUE),
      market_hhi = mean(route_hhi, na.rm = TRUE),
      market_hhi_sd = sd(route_hhi, na.rm = TRUE),
      mean_route_pax = mean(route_capacity_passengers, na.rm = TRUE),
      sd_route_pax = sd(route_capacity_passengers, na.rm = TRUE),
      mean_route_deps = mean(route_capacity_departures, na.rm = TRUE),
      sd_route_deps = sd(route_capacity_departures, na.rm = TRUE),
      arr_delay = weighted.mean(arrival_delay, total_flights, na.rm = TRUE),
      arr_delay_sd = sd(arrival_delay, na.rm = TRUE),
      prop_delay_15 = weighted.mean(arrival_15, total_flights, na.rm = TRUE) * 100,
      prop_delay_15_sd = sd(arrival_15, na.rm = TRUE) * 100,
      cancellation = weighted.mean(cancellation, total_flights, na.rm = TRUE) * 100,
      cancellation_sd = sd(cancellation, na.rm = TRUE) * 100,
      load_factor = (sum(total_passengers, na.rm = TRUE) /
                       sum(total_seats, na.rm = TRUE)) * 100,
      distance = weighted.mean(average_dist, total_passengers, na.rm = TRUE),
      distance_sd = sd(average_dist, na.rm = TRUE),
      .groups = "drop"
    )

  control_entry_summary_stats <- final_dataset %>%
    filter(route_type == "Never-Treated") %>%
    filter(year_quarter >= as.yearqtr("2014 Q1")) %>%
    summarise(
      n_obs = n(),
      unique_routes = n_distinct(route),
      mean_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
        sum(total_passengers, na.rm = TRUE),
      sd_fare = sd(average_fare, na.rm = TRUE),
      num_carriers = mean(n_carriers, na.rm = TRUE),
      market_hhi = mean(route_hhi, na.rm = TRUE),
      mean_route_pax = mean(route_capacity_passengers, na.rm = TRUE),
      mean_route_deps = mean(route_capacity_departures, na.rm = TRUE),
      arr_delay = weighted.mean(arrival_delay, total_flights, na.rm = TRUE),
      arr_delay_sd = sd(arrival_delay, na.rm = TRUE),
      prop_delay_15 = weighted.mean(arrival_15, total_flights, na.rm = TRUE) * 100,
      prop_delay_15_sd = sd(arrival_15, na.rm = TRUE) * 100,
      distance = weighted.mean(average_dist, total_passengers, na.rm = TRUE)
    )

  route_served_analysis <- final_dataset %>%
    filter(route_group %in% c("Existing Routes (Treated)", "Never-Treated Control")) %>%
    filter(!is.na(time_period_label) & time_period_label != "Other") %>%
    group_by(route_group, time_period_label) %>%
    summarise(
      no_of_routes = n_distinct(route),
      observations = n(),
      num_carriers = mean(n_carriers, na.rm = TRUE),
      market_hhi = mean(route_hhi, na.rm = TRUE),
      passengers = mean(total_passengers, na.rm = TRUE),
      mean_route_pax = mean(route_capacity_passengers, na.rm = TRUE),
      departures = mean(total_departures_performed, na.rm = TRUE),
      mean_route_departures = mean(route_capacity_departures, na.rm = TRUE),
      fare = sum(total_revenue, na.rm = TRUE) / sum(total_pax, na.rm = TRUE),
      fare_2 = sum(average_fare * total_passengers, na.rm = TRUE) /
        sum(total_passengers, na.rm = TRUE),
      fare_sd = sd(average_fare, na.rm = TRUE),
      arr_delay = weighted.mean(arrival_delay, total_flights, na.rm = TRUE),
      arr_delay_sd = sd(arrival_delay, na.rm = TRUE),
      prop_delay_15 = weighted.mean(arrival_15, total_flights, na.rm = TRUE) * 100,
      prop_delay_15_sd = sd(arrival_15, na.rm = TRUE) * 100,
      prop_delay_30 = weighted.mean(arrival_30, total_flights, na.rm = TRUE) * 100,
      cancellation = weighted.mean(cancellation, total_flights, na.rm = TRUE) * 100,
      load_factor = sum(total_passengers, na.rm = TRUE) /
        sum(total_seats, na.rm = TRUE) * 100,
      distance = weighted.mean(average_dist, total_pax, na.rm = TRUE),
      .groups = "drop"
    )

  write_csv(missing_check, paste0(output, "/missing_check.csv"))
  write_csv(entry_summary_stats, paste0(output, "/entry_summary_stats.csv"))
  write_csv(control_entry_summary_stats, paste0(output, "/control_entry_summary_stats.csv"))
  write_csv(route_served_analysis, paste0(output, "/route_served_analysis.csv"))

  # --- Archived visualizations ---
  dual_plot_data <- final_dataset %>%
    filter(!is.na(rel_entry_qtr)) %>%
    filter(rel_entry_qtr >= -8 & rel_entry_qtr <= 8) %>%
    group_by(rel_entry_qtr) %>%
    summarise(
      mean_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
        sum(total_passengers, na.rm = TRUE),
      se = sd(average_fare, na.rm = TRUE) / sqrt(n()),
      lower = mean_fare - 1.96 * se,
      upper = mean_fare + 1.96 * se,
      mean_delay = weighted.mean(arrival_delay, total_flights, na.rm = TRUE),
      se_delay = sd(arrival_delay, na.rm = TRUE) / sqrt(n()),
      delay_low = mean_delay - 1.96 * se_delay,
      delay_high = mean_delay + 1.96 * se_delay,
      .groups = "drop"
    )

  fare_min <- min(dual_plot_data$mean_fare, na.rm = TRUE)
  fare_max <- max(dual_plot_data$mean_fare, na.rm = TRUE)
  delay_min <- min(dual_plot_data$mean_delay, na.rm = TRUE)
  delay_max <- max(dual_plot_data$mean_delay, na.rm = TRUE)

  auto_scale <- (fare_max - fare_min) / (delay_max - delay_min)
  auto_shift <- fare_min - (delay_min * auto_scale)

  plot_entry_fare_delay <- ggplot(dual_plot_data, aes(x = rel_entry_qtr)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), fill = "#006633", alpha = 0.1) +
    geom_line(aes(y = mean_fare, color = "Mean Fare"), linewidth = 1) +
    geom_ribbon(
      aes(
        ymin = (delay_low * auto_scale) + auto_shift,
        ymax = (delay_high * auto_scale) + auto_shift
      ),
      fill = "#2980b9", alpha = 0.1
    ) +
    geom_line(aes(y = (mean_delay * auto_scale) + auto_shift,
                  color = "Arrival Delay"), linewidth = 1) +
    geom_vline(xintercept = 0, linetype = "dotted", color = "red") +
    scale_y_continuous(
      name = "Mean Fare ($)",
      sec.axis = sec_axis(~ (. - auto_shift) / auto_scale,
                          name = "Mean Arrival Delay (Min)")
    ) +
    scale_color_manual(
      name = "Metric",
      values = c("Mean Fare" = "#006633", "Arrival Delay" = "#2980b9")
    ) +
    scale_x_continuous(breaks = seq(-8, 8, 1)) +
    labs(
      title = "Price and Quality on Routes Around Frontier Entry",
      subtitle = "Treated and control observations pooled by relative quarter",
      x = "Quarters Relative to Frontier Entry (t=0)"
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")

  control_baseline <- final_dataset %>%
    filter(route_type == "Never-Treated", year_quarter >= as.yearqtr("2014 Q1")) %>%
    group_by(year_quarter) %>%
    summarise(
      avg_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
        sum(total_passengers, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    mutate(date = as.Date(year_quarter))

  plot_control_baseline <- ggplot(control_baseline, aes(x = date, y = avg_fare)) +
    geom_line(color = "#2c3e50", linewidth = 1.2) +
    geom_point(color = "#2c3e50", size = 2.2) +
    scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
    labs(
      title = "Industry Baseline: Never-Treated Control Group Fares",
      subtitle = "Quarterly passenger-weighted mean fares (2014-2019)",
      x = "Calendar Year",
      y = "Mean Fare ($)"
    ) +
    theme_minimal() +
    theme(
      panel.grid.minor = element_blank(),
      plot.title = element_text(face = "bold", size = 14),
      axis.title = element_text(size = 11)
    )

  plot_data <- final_dataset %>%
    filter(route_carrier_class != "Other/F9 New Entry") %>%
    filter(time_period_label != "Other") %>%
    group_by(year_quarter, route_carrier_class) %>%
    summarise(
      mean_fare = sum(average_fare * total_passengers, na.rm = TRUE) /
        sum(total_passengers, na.rm = TRUE),
      se = sd(average_fare, na.rm = TRUE) / sqrt(n()),
      lower = mean_fare - 1.96 * se,
      upper = mean_fare + 1.96 * se,
      mean_delay = weighted.mean(arrival_delay, total_flights, na.rm = TRUE),
      se_delay = sd(arrival_delay, na.rm = TRUE) / sqrt(n()),
      delay_lower = mean_delay - 1.96 * se_delay,
      delay_upper = mean_delay + 1.96 * se_delay,
      .groups = "drop"
    ) %>%
    mutate(date = as.Date(as.yearqtr(year_quarter)))

  plot_shift_fares <- ggplot(plot_data, aes(x = date, y = mean_fare,
                                            color = route_carrier_class,
                                            fill = route_carrier_class)) +
    geom_ribbon(aes(ymin = lower, ymax = upper), alpha = 0.1, color = NA) +
    geom_line(linewidth = 1) +
    geom_vline(xintercept = as.Date("2014-01-01"), linetype = "longdash",
               color = "grey50", linewidth = 0.5) +
    scale_color_manual(values = c(
      "Frontier (Treated)" = "#1b4332",
      "Incumbents (Treated)" = "#4682B4",
      "Control Routes" = "#7f8c8d"
    )) +
    scale_fill_manual(values = c(
      "Frontier (Treated)" = "#1b4332",
      "Incumbents (Treated)" = "#4682B4",
      "Control Routes" = "#7f8c8d"
    )) +
    scale_y_continuous(labels = label_dollar(),
                       expand = expansion(mult = c(0.05, 0.05))) +
    scale_x_date(date_labels = "%Y", date_breaks = "1 year") +
    labs(
      title = "Fare Evolution: The 2014 ULCC Pivot",
      subtitle = "Mean fares with 95% confidence intervals",
      y = "Average Fare ($)",
      x = "Year",
      color = "Carrier Group",
      fill = "Carrier Group"
    ) +
    theme_classic() +
    theme(
      axis.title = element_text(size = 10, face = "bold"),
      legend.position = "top",
      legend.justification = "left",
      plot.title = element_text(size = 14, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 10, color = "grey40", margin = margin(b = 15))
    )

  plot_shift_delay <- ggplot(plot_data, aes(x = date, y = mean_delay,
                                            color = route_carrier_class,
                                            fill = route_carrier_class)) +
    geom_ribbon(aes(ymin = delay_lower, ymax = delay_upper), alpha = 0.1, color = NA) +
    geom_line(linewidth = 1) +
    geom_vline(xintercept = as.Date("2014-01-01"), linetype = "longdash",
               color = "grey50", linewidth = 0.5) +
    scale_color_manual(values = c(
      "Frontier (Treated)" = "#1b4332",
      "Incumbents (Treated)" = "#4682B4",
      "Control Routes" = "#7f8c8d"
    )) +
    scale_fill_manual(values = c(
      "Frontier (Treated)" = "#1b4332",
      "Incumbents (Treated)" = "#4682B4",
      "Control Routes" = "#7f8c8d"
    )) +
    scale_x_date(date_labels = "%Y", date_breaks = "1 year") +
    labs(
      title = "Delay Evolution: The 2014 ULCC Pivot",
      subtitle = "Mean arrival delay with 95% confidence intervals",
      y = "Mean Arrival Delay (Minutes)",
      x = "Year",
      color = "Carrier Group",
      fill = "Carrier Group"
    ) +
    theme_classic() +
    theme(
      axis.title = element_text(size = 10, face = "bold"),
      legend.position = "top",
      legend.justification = "left",
      plot.title = element_text(size = 14, face = "bold", hjust = 0),
      plot.subtitle = element_text(size = 10, color = "grey40", margin = margin(b = 15))
    )

  ggsave(paste0(plot_output, "/entry_fare_delay_dual_axis.png"),
         plot = plot_entry_fare_delay, width = 10, height = 6, dpi = 300)

  ggsave(paste0(plot_output, "/control_group_baseline_fares.png"),
         plot = plot_control_baseline, width = 10, height = 6, dpi = 300)

  ggsave(paste0(plot_output, "/business_shift_fares.png"),
         plot = plot_shift_fares, width = 10, height = 6, dpi = 300)

  ggsave(paste0(plot_output, "/business_shift_delay.png"),
         plot = plot_shift_delay, width = 10, height = 6, dpi = 300)

  cat("\nSaved summary tables to:", output, "\n")
  cat("Saved plots to:", plot_output, "\n")
}
