### ECON 495 DB1B Data Cleaning - Year-by-Year Pipeline
# last updated: 10 February, 2026
#
# USAGE: Set year at bottom of script, then source entire file
#   process_db1b_year(2011)
#   process_db1b_year(2012)
#   ... etc.
#
# After each year completes successfully, you can delete raw data for that year
# and upload the .fst output or csv input files to cloud storage.

### system instructions
rm(list = ls())
gc()
options(scipen = 999)

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))
wd <- file.path(repo_root, "data_work")

input_market <- file.path(raw_data_dir, "DB1B", "Market")
input_coupon <- file.path(raw_data_dir, "DB1B", "Coupon")
input_ticket <- file.path(raw_data_dir, "DB1B", "Ticket")
output <- file.path(intermediate_data_dir, "DB1B")

### loading packages
library(data.table)
library(fst)
library(zoo)

# ==============================================================================
# COLUMN DEFINITIONS
# ==============================================================================

market_cols <- c(
 "ItinID", "MktID", "Year", "Quarter",
 "OriginAirportID", "Origin", "DestAirportID", "Dest",
 "TkCarrier", "OpCarrier", "Passengers",
 "MktFare", "MktDistance", "MktGeoType", "MktCoupons",
 "NonStopMiles"
)

coupon_cols <- c(
 "ItinID", "MktID", "SeqNum", "Coupons", "FareClass"
)

ticket_cols <- c(
 "ItinID", "RoundTrip", "OnLine", "DollarCred", "Coupons"
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# list CSV files for Market (direct in year folder)
list_market_files <- function(year) {
 files <- list.files(
   path = file.path(input_market, as.character(year)),
   pattern = "\\.csv$",
   full.names = TRUE
 )
 return(files)
}

# list CSV files for Coupon/Ticket (direct in year folder, same as Market)
list_coupon_files <- function(year) {
 files <- list.files(
   path = file.path(input_coupon, as.character(year)),
   pattern = "\\.csv$",
   full.names = TRUE
 )
 return(files)
}

list_ticket_files <- function(year) {
 files <- list.files(
   path = file.path(input_ticket, as.character(year)),
   pattern = "\\.csv$",
   full.names = TRUE
 )
 return(files)
}

# ==============================================================================
# FILTER SETTINGS
# ==============================================================================

# Fare classes to KEEP (coach + unknown)
# X = Restricted Coach, Y = Unrestricted Coach
# Drops: "-" (Ground), C/D (Business), F/G (First), U = Unknown
valid_fare_classes <- c("X", "Y")

# Top percentile trimming (from paper methodology)
top_trim_pct <- 0.01  # top 1%

# ==============================================================================
# PROCESSING FUNCTIONS
# ==============================================================================

process_market_quarter <- function(file_path) {
 cat("  Market:", basename(file_path), "\n")

 dt <- fread(file_path, select = market_cols)

 # Early filters
 dt <- dt[
   MktGeoType == 2 &        # lower 48 states only
   MktFare >= 10 &          # drop frequent-flyer tickets
   TkCarrier != "99" &      # online itineraries only
   OpCarrier != "99" &
   MktCoupons == 1          # non-stop flights only
 ]

 return(dt)
}

process_coupon_quarter <- function(file_path) {
 cat("  Coupon:", basename(file_path), "\n")
 dt <- fread(file_path, select = coupon_cols)
 return(dt)
}

process_ticket_quarter <- function(file_path) {
 cat("  Ticket:", basename(file_path), "\n")
 dt <- fread(file_path, select = ticket_cols)
 return(dt)
}

# ==============================================================================
# MAIN FUNCTION: PROCESS ONE YEAR
# ==============================================================================

process_db1b_year <- function(year) {

 cat("\n")
 cat("==============================================================================\n")
 cat("PROCESSING YEAR:", year, "\n")
 cat("==============================================================================\n\n")

 # --------------------------------------------------------------------------
 # STEP 1: Load Market data
 # --------------------------------------------------------------------------
 cat("Loading Market data...\n")
 market_files <- list_market_files(year)
 cat("Found", length(market_files), "Market files\n")

 if (length(market_files) == 0) {
   stop("No Market files found for year ", year)
 }

 market <- rbindlist(lapply(market_files, process_market_quarter))
 cat("Market rows after early filters:", format(nrow(market), big.mark = ","), "\n\n")

 # --------------------------------------------------------------------------
 # STEP 2: Load Coupon data
 # --------------------------------------------------------------------------
 cat("Loading Coupon data...\n")
 coupon_files <- list_coupon_files(year)
 cat("Found", length(coupon_files), "Coupon files\n")

 if (length(coupon_files) == 0) {
   stop("No Coupon files found for year ", year)
 }

 coupon <- rbindlist(lapply(coupon_files, process_coupon_quarter))
 cat("Coupon rows:", format(nrow(coupon), big.mark = ","), "\n\n")

 # --------------------------------------------------------------------------
 # STEP 3: Load Ticket data
 # --------------------------------------------------------------------------
 cat("Loading Ticket data...\n")
 ticket_files <- list_ticket_files(year)
 cat("Found", length(ticket_files), "Ticket files\n")

 if (length(ticket_files) == 0) {
   stop("No Ticket files found for year ", year)
 }

 ticket <- rbindlist(lapply(ticket_files, process_ticket_quarter))
 cat("Ticket rows:", format(nrow(ticket), big.mark = ","), "\n\n")

 # --------------------------------------------------------------------------
 # STEP 4: Merge datasets on ItinID
 # --------------------------------------------------------------------------
 cat("Merging datasets...\n")

 # Get valid ItinIDs from Market (already filtered)
 valid_itins <- unique(market$ItinID)
 cat("Unique ItinIDs in Market:", format(length(valid_itins), big.mark = ","), "\n")

 # Filter Coupon and Ticket to valid ItinIDs
 coupon <- coupon[ItinID %in% valid_itins]
 ticket <- ticket[ItinID %in% valid_itins]

 cat("Coupon rows after ItinID filter:", format(nrow(coupon), big.mark = ","), "\n")
 cat("Ticket rows after ItinID filter:", format(nrow(ticket), big.mark = ","), "\n")

 # Merge: Market -> Coupon -> Ticket
 # First merge Market with Coupon on (ItinID, MktID) - same granularity
 coupon_unique <- unique(coupon[, .(ItinID, MktID, SeqNum, FareClass, Coupons)])
 setnames(coupon_unique, "Coupons", "CouponSegments")

 db1b <- merge(market, coupon_unique, by = c("ItinID", "MktID"), all.x = FALSE)
 cat("After Market-Coupon merge:", format(nrow(db1b), big.mark = ","), "rows\n")

 # Then merge with Ticket on ItinID (adds itinerary-level attributes)
 db1b <- merge(db1b, ticket, by = "ItinID", all.x = FALSE)
 cat("After Ticket merge:", format(nrow(db1b), big.mark = ","), "rows\n\n")

 # Clean up
 rm(market, coupon, ticket, coupon_unique, valid_itins)
 gc()

 # --------------------------------------------------------------------------
 # STEP 5: Create derived variables
 # --------------------------------------------------------------------------
 cat("Creating derived variables...\n")

 db1b[, `:=`(
   year_quarter = as.yearqtr(paste0(Year, "-", Quarter), format = "%Y-%q"),
   route = paste0(OriginAirportID, "-", DestAirportID),
   route_ident = paste0(Origin, "-", Dest)
 )]

 # --------------------------------------------------------------------------
 # STEP 6: Save UNFILTERED version (before applying deferred filters)
 # --------------------------------------------------------------------------
 cat("Saving unfiltered version...\n")
 unfiltered_path <- file.path(output, paste0("db1b_unfiltered_", year, ".fst"))
 write_fst(db1b, unfiltered_path)
 cat("Saved:", unfiltered_path, "\n")
 cat("Size:", round(file.size(unfiltered_path) / 1e9, 3), "GB\n\n")

 # --------------------------------------------------------------------------
 # STEP 7: Apply deferred filters
 # --------------------------------------------------------------------------
 cat("Applying deferred filters...\n")
 n_before <- nrow(db1b)

 # Filter 1: Keep only itineraries with 4 or fewer total coupons
 # Complex multi-city itineraries have less reliable fare proration
 db1b <- db1b[Coupons <= 4]
 cat("  After Coupons <= 4 filter:", format(nrow(db1b), big.mark = ","),
     "(dropped", format(n_before - nrow(db1b), big.mark = ","), ")\n")
 n_before <- nrow(db1b)

 # Filter 2: DollarCred (credible dollar amount)
 db1b <- db1b[DollarCred == 1]
 cat("  After DollarCred filter:", format(nrow(db1b), big.mark = ","),
     "(dropped", format(n_before - nrow(db1b), big.mark = ","), ")\n")
 n_before <- nrow(db1b)

 # Filter 3: Keep only coach class (X, Y)
 # Drops: Ground (-), Business (C, D), First (F, G), Unknown (U)
 db1b <- db1b[FareClass %in% valid_fare_classes]
 cat("  After fare class filter:", format(nrow(db1b), big.mark = ","),
     "(dropped", format(n_before - nrow(db1b), big.mark = ","), ")\n")
 n_before <- nrow(db1b)

 # Filter 4: Keep only first market per itinerary (avoid double counting)
 # MktID is sequential; keeping min(MktID) retains the outbound/first leg
 db1b <- db1b[, .SD[MktID == min(MktID)], by = ItinID]
 cat("  After first-leg filter:", format(nrow(db1b), big.mark = ","),
     "(dropped", format(n_before - nrow(db1b), big.mark = ","), ")\n")
 n_before <- nrow(db1b)

 # Filter 5: Top 1% price trimming per carrier-route-quarter
 db1b[, fare_pctl := frank(MktFare) / .N, by = .(OpCarrier, route, year_quarter)]
 db1b <- db1b[fare_pctl <= (1 - top_trim_pct)]
 db1b[, fare_pctl := NULL]
 cat("  After top", top_trim_pct * 100, "% trim:", format(nrow(db1b), big.mark = ","),
     "(dropped", format(n_before - nrow(db1b), big.mark = ","), ")\n")

 cat("\n")

 # --------------------------------------------------------------------------
 # STEP 8: Aggregate to carrier-route-quarter level
 # --------------------------------------------------------------------------
 cat("Aggregating to carrier-route-quarter level...\n")

 db1b_agg <- db1b[, .(
   # Core metrics
   total_pax = sum(Passengers, na.rm = TRUE),
   total_revenue = sum(MktFare * Passengers, na.rm = TRUE),
   n_itineraries = .N,

   # Distance
   average_dist = weighted.mean(NonStopMiles, Passengers, na.rm = TRUE),

   # Fare statistics (average_fare calculated after as total_revenue/total_pax)
   median_fare = median(MktFare),
   mean_fare = weighted.mean(MktFare, Passengers, na.rm = TRUE), 

   # Fare percentiles (unweighted for simplicity, can weight if needed)
   fare_p10 = quantile(MktFare, 0.10, na.rm = TRUE),
   fare_p25 = quantile(MktFare, 0.25, na.rm = TRUE),
   fare_p50 = quantile(MktFare, 0.50, na.rm = TRUE),
   fare_p75 = quantile(MktFare, 0.75, na.rm = TRUE),
   fare_p90 = quantile(MktFare, 0.90, na.rm = TRUE),

   # Route identifiers (keep first)
   route_ident = first(route_ident),
   Origin = first(Origin),
   Dest = first(Dest)

 ), by = .(year_quarter, OpCarrier, route)]

 # Calculate average fare and fare dispersion metrics
 db1b_agg[, `:=`(
   average_fare = total_revenue / total_pax,
   # Absolute spreads
   fare_spread_90_10 = fare_p90 - fare_p10,
   fare_spread_50_10 = fare_p50 - fare_p10,
   fare_spread_90_50 = fare_p90 - fare_p50,
   fare_iqr = fare_p75 - fare_p25,
   # Ratios (from Gerardi & Shapiro methodology)
   fare_ratio_50_10 = fare_p50 / fare_p10,
   fare_ratio_90_10 = fare_p90 / fare_p10,
   fare_ratio_90_50 = fare_p90 / fare_p50
 )]

 # Add year_quarter string for readability
 db1b_agg[, year_quarter_str := format(year_quarter, "%Y Q%q")]

 cat("Aggregated rows:", format(nrow(db1b_agg), big.mark = ","), "\n\n")

 # --------------------------------------------------------------------------
 # STEP 9: Save FILTERED/AGGREGATED version
 # --------------------------------------------------------------------------
 cat("Saving filtered/aggregated version...\n")
 filtered_path <- file.path(output, paste0("db1b_", year, ".fst"))
 write_fst(db1b_agg, filtered_path)
 cat("Saved:", filtered_path, "\n")
 cat("Size:", round(file.size(filtered_path) / 1e6, 2), "MB\n\n")

 # --------------------------------------------------------------------------
 # STEP 10: Validation
 # --------------------------------------------------------------------------
 cat("=== VALIDATION FOR YEAR", year, "===\n")
 cat("Carrier-route-quarter observations:", format(nrow(db1b_agg), big.mark = ","), "\n")
 cat("Unique carriers:", uniqueN(db1b_agg$OpCarrier), "\n")
 cat("Unique routes:", uniqueN(db1b_agg$route), "\n")
 cat("Total passengers:", format(sum(db1b_agg$total_pax), big.mark = ","), "\n")
 cat("Frontier (F9) observations:", sum(db1b_agg$OpCarrier == "F9", na.rm = TRUE), "\n")
 cat("Average fare range: $", round(min(db1b_agg$average_fare), 2),
     "to $", round(max(db1b_agg$average_fare), 2), "\n")

 cat("\nOutput files:\n")
 cat("  Unfiltered:", unfiltered_path, "\n")
 cat("  Filtered:  ", filtered_path, "\n")

 cat("\n=== YEAR", year, "COMPLETE ===\n")
 cat("You can now delete raw data for", year, "and upload .fst files to cloud.\n\n")

 # Clean up
 rm(db1b, db1b_agg)
 gc()

 return(invisible(TRUE))
}

# ==============================================================================
# COMBINE YEARLY FILES (run after all years are processed)
# ==============================================================================

combine_yearly_files <- function(years = 2011:2019) {

 cat("\n=== COMBINING YEARLY FILES ===\n")

 # Check which files exist
 existing_files <- c()
 for (year in years) {
   fpath <- file.path(output, paste0("db1b_", year, ".fst"))
   if (file.exists(fpath)) {
     existing_files <- c(existing_files, fpath)
     cat("Found:", basename(fpath), "\n")
   } else {
     cat("Missing:", basename(fpath), "\n")
   }
 }

 if (length(existing_files) == 0) {
   stop("No yearly files found!")
 }

 # Load and combine
 cat("\nCombining", length(existing_files), "files...\n")
 db1b_all <- rbindlist(lapply(existing_files, read_fst, as.data.table = TRUE))

 # Save combined file
 combined_path <- file.path(output, "db1b_all.fst")
 write_fst(db1b_all, combined_path)

 cat("\n=== COMBINED FILE VALIDATION ===\n")
 cat("Total observations:", format(nrow(db1b_all), big.mark = ","), "\n")
 cat("Unique carriers:", uniqueN(db1b_all$OpCarrier), "\n")
 cat("Unique routes:", uniqueN(db1b_all$route), "\n")
 cat("Year-quarter range:",
     as.character(min(db1b_all$year_quarter)), "to",
     as.character(max(db1b_all$year_quarter)), "\n")
 cat("Frontier (F9) observations:", sum(db1b_all$OpCarrier == "F9", na.rm = TRUE), "\n")
 cat("\nSaved:", combined_path, "\n")
 cat("Size:", round(file.size(combined_path) / 1e6, 2), "MB\n")

 return(invisible(db1b_all))
}

# ==============================================================================
# RUN SCRIPT
# ==============================================================================

# Process one year at a time:
#process_db1b_year(2019)

# After all years are done, combine:
# combine_yearly_files(2011:2019)
