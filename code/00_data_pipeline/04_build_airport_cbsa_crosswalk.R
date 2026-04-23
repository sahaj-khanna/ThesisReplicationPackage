### Build final airport-CBSA-population-county panel

rm(list = ls())
options(scipen = 999)

suppressPackageStartupMessages({
  library(data.table)
  library(dplyr)
  library(readr)
  library(stringr)
  library(sf)
  library(fst)
})

# ------------------------------ CONFIG ------------------------------------- #

source(file.path(Sys.getenv("REPLICATION_PACKAGE_ROOT", getwd()), "code", "shared", "paths.R"))
wd <- file.path(repo_root, "data_work")

airport_coord_path <- file.path(raw_data_dir, "CBSA", "airport_master_coordinates.csv")
cbsa_shapefile_path <- file.path(raw_data_dir, "CBSA", "NTAD_CBSA_ShapeFIle", "Core_Based_Statistical_Areas.shp")
cbsa_population_path <- file.path(raw_data_dir, "CBSA", "population", "csa-est2020-alldata.csv")
cbsa_fips_xwalk_path <- file.path(raw_data_dir, "CBSA", "cbsa2fipsxw_2020.csv")
cainc1_path <- file.path(raw_data_dir, "CBSA", "CAINC1", "CAINC1__ALL_AREAS_1969_2024.csv")
qcew_dir <- file.path(raw_data_dir, "CBSA", "QCEW")

output_dir <- file.path(intermediate_data_dir, "crosswalks")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

final_csv <- file.path(output_dir, "airport_id_cbsa_population_county_panel.csv")
final_fst <- file.path(output_dir, "airport_id_cbsa_population_county_panel.fst")
qcew_county_cache_csv <- file.path(output_dir, "qcew_private_county_year_quarter_filtered_2010_2020.csv")
qcew_county_cache_fst <- file.path(output_dir, "qcew_private_county_year_quarter_filtered_2010_2020.fst")
qcew_cbsa_csv <- file.path(output_dir, "leisure_employment_share_cbsa_year_quarter.csv")
qcew_cbsa_fst <- file.path(output_dir, "leisure_employment_share_cbsa_year_quarter.fst")

# ----------------------------- HELPERS ------------------------------------- #

stop_if_missing <- function(path, label) {
  if (!file.exists(path)) {
    stop(paste0(label, " not found at: ", path), call. = FALSE)
  }
}

clean_names_local <- function(x) {
  x %>%
    str_replace_all("[^A-Za-z0-9]+", "_") %>%
    str_replace_all("^_+|_+$", "") %>%
    tolower()
}

assert_unique_keys <- function(df, keys, df_name) {
  dupes <- df %>%
    count(across(all_of(keys)), name = "n") %>%
    filter(n > 1)

  if (nrow(dupes) > 0) {
    stop(
      paste0(
        df_name, " has duplicate keys on [", paste(keys, collapse = ", "), "]. ",
        "This would create many-to-many joins downstream."
      ),
      call. = FALSE
    )
  }
}

first_non_missing <- function(x) {
  x <- x[!is.na(x) & x != ""]
  if (length(x) == 0) return(NA_character_)
  x[[1]]
}

read_qcew_csv <- function(path) {
  cols_needed <- c(
    "area_fips", "own_code", "industry_code", "agglvl_code", "size_code", "year", "qtr",
    "month1_emplvl", "month2_emplvl", "month3_emplvl"
  )
  hdr <- names(fread(path, nrows = 0, showProgress = FALSE))
  use_cols <- intersect(cols_needed, hdr)
  if (length(use_cols) == 0) {
    stop(paste0("No required QCEW columns found in CSV: ", path), call. = FALSE)
  }
  dt <- fread(
    path,
    select = use_cols,
    showProgress = FALSE,
    colClasses = "character"
  )
  as_tibble(dt)
}

# ------------------------ AIRPORT -> CBSA CROSSWALK ------------------------ #

stop_if_missing(airport_coord_path, "Airport coordinate file")
stop_if_missing(cbsa_shapefile_path, "CBSA shapefile")

airport_raw <- read_csv(airport_coord_path, show_col_types = FALSE)
names(airport_raw) <- clean_names_local(names(airport_raw))

airport_coords <- airport_raw %>%
  filter(airport_country_code_iso == "US") %>% 
  transmute(
    airport_id = suppressWarnings(as.integer(airport_id)),
    airport_seq_id = suppressWarnings(as.integer(airport_seq_id)),
    airport_code = toupper(trimws(as.character(airport))),
    is_latest = suppressWarnings(as.integer(airport_is_latest)),
    latitude = suppressWarnings(as.numeric(latitude)),
    longitude = suppressWarnings(as.numeric(longitude))
  ) %>%
  filter(is_latest == 1) %>%
  filter(!is.na(airport_id), !is.na(latitude), !is.na(longitude)) %>%
  filter(latitude >= -90, latitude <= 90, longitude >= -180, longitude <= 180)

assert_unique_keys(airport_coords, "airport_id", "Airport coordinate table")

cbsa_sf <- st_read(cbsa_shapefile_path, quiet = TRUE)
names(cbsa_sf) <- clean_names_local(names(cbsa_sf))

cbsa_sf <- cbsa_sf %>%
  transmute(
    cbsa_code = as.character(cbsafp),
    cbsa_name = as.character(name),
    geometry
  ) %>%
  st_transform(4326)

assert_unique_keys(st_drop_geometry(cbsa_sf), "cbsa_code", "CBSA polygons")

airport_cbsa <- airport_coords %>%
  st_as_sf(coords = c("longitude", "latitude"), crs = 4326, remove = FALSE) %>%
  st_join(cbsa_sf, join = st_within, left = TRUE) %>%
  st_drop_geometry() %>%
  mutate(cbsa_code = na_if(cbsa_code, "")) %>%
  distinct() 

airport_cbsa <- airport_cbsa %>% 
  filter(!is.na(cbsa_code))

assert_unique_keys(airport_cbsa, "airport_id", "Airport->CBSA crosswalk")

# --------------------------- CBSA POPULATION ------------------------------- #

stop_if_missing(cbsa_population_path, "CBSA population file")

pop_raw <- read_csv(cbsa_population_path, show_col_types = FALSE)
names(pop_raw) <- clean_names_local(names(pop_raw))

pop_year_cols <- paste0("popestimate", 2010:2020)

missing_pop_year_cols <- setdiff(pop_year_cols, names(pop_raw))
if (length(missing_pop_year_cols) > 0) {
  stop(
    paste0(
      "Missing expected population year columns: ",
      paste(missing_pop_year_cols, collapse = ", ")
    ),
    call. = FALSE
  )
}

cbsa_population <- pop_raw %>% 
  filter(lsad %in% c("Metropolitan Statistical Area",
                     "Micropolitan Statistical Area")) %>% 
  transmute(
    cbsa_code = str_pad(as.character(cbsa), 5, side = "left", pad = "0"),
    cbsa_name = as.character(name),
    across(all_of(pop_year_cols))
  ) %>%
  tidyr::pivot_longer(
    cols = all_of(pop_year_cols),
    names_to = "year_raw",
    values_to = "population"
  ) %>%
  mutate(
    year = suppressWarnings(as.integer(str_remove(year_raw, "^popestimate"))),
    population = suppressWarnings(as.numeric(population))
  ) %>%
  select(cbsa_code, cbsa_name, year, population) %>%
  filter(!is.na(cbsa_code), cbsa_code != "", !is.na(year), !is.na(population)) %>%
  group_by(cbsa_code, year) %>%
  summarise(
    population = sum(population, na.rm = TRUE),
    cbsa_name = first_non_missing(cbsa_name),
    .groups = "drop"
  )

assert_unique_keys(cbsa_population, c("cbsa_code", "year"), "CBSA population table")

airport_cbsa_pop <- airport_cbsa %>%
  filter(!is.na(cbsa_code)) %>%
  tidyr::crossing(year = 2010:2020, quarter = 1:4) %>%
  left_join(cbsa_population, by = c("cbsa_code", "year"), relationship = "many-to-one") %>%
  mutate(cbsa_name = coalesce(cbsa_name.x, cbsa_name.y)) %>%
  select(-cbsa_name.x, -cbsa_name.y) %>%
  relocate(cbsa_name, .after = cbsa_code)

assert_unique_keys(airport_cbsa_pop, c("airport_id", "year", "quarter"), "Airport-CBSA-pop panel")

# ------------------------ CBSA -> COUNTY FIPS ------------------------------ #

stop_if_missing(cbsa_fips_xwalk_path, "CBSA to county FIPS crosswalk file")

cbsa_fips_raw <- read_csv(cbsa_fips_xwalk_path, show_col_types = FALSE)
names(cbsa_fips_raw) <- clean_names_local(names(cbsa_fips_raw))

cbsa_fips_xwalk <- cbsa_fips_raw %>%
  transmute(
    cbsa_code = str_pad(as.character(cbsacode), 5, side = "left", pad = "0"),
    county_fips = paste0(
      str_pad(as.character(fipsstatecode), 2, side = "left", pad = "0"),
      str_pad(as.character(fipscountycode), 3, side = "left", pad = "0")
    )
  ) %>%
  mutate(county_fips = str_extract(county_fips, "\\d{5}")) %>%
  filter(!is.na(cbsa_code), cbsa_code != "", !is.na(county_fips), county_fips != "") %>%
  distinct()

assert_unique_keys(cbsa_fips_xwalk, c("cbsa_code", "county_fips"), "CBSA->FIPS crosswalk")

# --------------------- QCEW LEISURE SHARE (CBSA-YEAR) ---------------------- #

qcew_years <- 2010:2020

if (file.exists(qcew_county_cache_fst)) {
  message("Using cached filtered QCEW county-year-quarter data: ", qcew_county_cache_fst)
  qcew_county_year <- read_fst(qcew_county_cache_fst, as.data.table = FALSE)
} else {
  if (!dir.exists(qcew_dir)) {
    stop(
      paste0(
        "QCEW directory not found at: ", qcew_dir, "\n",
        "Download BLS annual singlefile ZIPs (2010-2020) into this folder."
      ),
      call. = FALSE
    )
  }

  qcew_files <- list.files(
    qcew_dir,
    pattern = "\\.csv$",
    full.names = TRUE,
    recursive = TRUE,
    ignore.case = TRUE
  )

  if (length(qcew_files) == 0) {
    stop(
      paste0(
        "No QCEW CSV files found in: ", qcew_dir
      ),
      call. = FALSE
    )
  }

  qcew_files <- sort(unique(qcew_files))

  process_qcew_file <- function(path) {
    qcew_in <- read_qcew_csv(path)

    qcew_base <- qcew_in %>%
      transmute(
        county_fips = str_extract(area_fips, "\\d{5}"),
        own_code = suppressWarnings(as.integer(own_code)),
        industry_code = trimws(as.character(industry_code)),
        agglvl_code = trimws(as.character(agglvl_code)),
        size_code = trimws(as.character(size_code)),
        year = suppressWarnings(as.integer(year)),
        quarter = suppressWarnings(as.integer(qtr)),
        m1 = suppressWarnings(as.numeric(month1_emplvl)),
        m2 = suppressWarnings(as.numeric(month2_emplvl)),
        m3 = suppressWarnings(as.numeric(month3_emplvl))
      ) %>%
      mutate(
        month_sum = rowSums(cbind(m1, m2, m3), na.rm = TRUE),
        month_n = rowSums(!is.na(cbind(m1, m2, m3)))
      ) %>%
      group_by(county_fips, own_code, industry_code, agglvl_code, size_code, year, quarter) %>%
      summarise(
        qtr_avg_emplvl = if_else(
          sum(month_n, na.rm = TRUE) > 0,
          sum(month_sum, na.rm = TRUE) / sum(month_n, na.rm = TRUE),
          NA_real_
        ),
        .groups = "drop"
      )

    qcew_base %>%
      filter(
        !is.na(year), year %in% qcew_years,
        !is.na(quarter), quarter %in% 1:4,
        !is.na(county_fips), str_detect(county_fips, "^[0-9]{5}$"),
        !str_detect(county_fips, "000$"),
        size_code == "0",
        (
          (industry_code == "10" & own_code == 0L & agglvl_code == "70") |
          (industry_code == "1026" & own_code %in% c(1L, 2L, 3L, 4L, 5L) & agglvl_code == "73")
        ),
        !is.na(qtr_avg_emplvl)
      ) %>%
      group_by(county_fips, year, quarter, industry_code) %>%
      summarise(qtr_avg_emplvl = sum(qtr_avg_emplvl, na.rm = TRUE), .groups = "drop")
  }

  qcew_county_industry <- bind_rows(lapply(qcew_files, process_qcew_file)) %>%
    group_by(county_fips, year, quarter, industry_code) %>%
    summarise(qtr_avg_emplvl = sum(qtr_avg_emplvl, na.rm = TRUE), .groups = "drop")

  qcew_county_year <- qcew_county_industry %>%
    tidyr::pivot_wider(
      names_from = industry_code,
      values_from = qtr_avg_emplvl,
      names_prefix = "ind_",
      values_fill = NA
    ) %>%
    transmute(
      county_fips,
      year,
      quarter,
      total_emp_county = ind_10,
      leisure_emp_county = ind_1026,
      leisure_share_emp_county = if_else(
        !is.na(total_emp_county) & total_emp_county > 0,
        leisure_emp_county / total_emp_county,
        NA_real_
      )
    )

  assert_unique_keys(qcew_county_year, c("county_fips", "year", "quarter"), "QCEW county-year-quarter panel")

  write_csv(qcew_county_year, qcew_county_cache_csv, na = "")
  write_fst(qcew_county_year, qcew_county_cache_fst)

  message("Filtered QCEW county-year-quarter cache written")
  message(" - Rows: ", nrow(qcew_county_year))
  message(" - Wrote: ", qcew_county_cache_csv)
  message(" - Wrote: ", qcew_county_cache_fst)
}

qcew_cbsa_year <- qcew_county_year %>%
  left_join(
    cbsa_fips_xwalk %>% distinct(cbsa_code, county_fips),
    by = "county_fips",
    relationship = "many-to-one"
  ) %>%
  filter(!is.na(cbsa_code)) %>%
  group_by(cbsa_code, year, quarter) %>%
  summarise(
    leisure_emp_cbsa = sum(leisure_emp_county, na.rm = TRUE),
    total_emp_cbsa = sum(total_emp_county, na.rm = TRUE),
    leisure_share_emp_cbsa = if_else(
      total_emp_cbsa > 0,
      leisure_emp_cbsa / total_emp_cbsa,
      NA_real_
    ),
    .groups = "drop"
  )

assert_unique_keys(qcew_cbsa_year, c("cbsa_code", "year", "quarter"), "QCEW CBSA-year-quarter leisure share panel")

invalid_qcew_shares <- qcew_cbsa_year %>%
  filter(
    !is.na(leisure_share_emp_cbsa) &
      (leisure_share_emp_cbsa < 0 | leisure_share_emp_cbsa > 1)
  )
if (nrow(invalid_qcew_shares) > 0) {
  stop("QCEW leisure share outside [0,1] detected; inspect QCEW processing inputs.", call. = FALSE)
}

write_csv(qcew_cbsa_year, qcew_cbsa_csv, na = "")
write_fst(qcew_cbsa_year, qcew_cbsa_fst)

message("QCEW CBSA-year-quarter leisure share processing completed")
message(" - CBSA-year-quarter rows: ", nrow(qcew_cbsa_year))
message(" - Wrote: ", qcew_cbsa_csv)
message(" - Wrote: ", qcew_cbsa_fst)

# ---------------------- PERSONAL INCOME (CBSA-YEAR) ------------------------ #

stop_if_missing(cainc1_path, "CAINC1 personal income file")

pi_cbsa_csv <- file.path(output_dir, "personal_income_cbsa_year.csv")
pi_cbsa_fst <- file.path(output_dir, "personal_income_cbsa_year.fst")

cainc1_raw <- read_csv(
  cainc1_path,
  show_col_types = FALSE,
  col_types = cols(.default = col_character())
)
names(cainc1_raw) <- clean_names_local(names(cainc1_raw))

pi_year_cols <- as.character(1969:2024)
missing_pi_year_cols <- setdiff(pi_year_cols, names(cainc1_raw))
if (length(missing_pi_year_cols) > 0) {
  stop(
    paste0("Missing expected CAINC1 year columns: ", paste(missing_pi_year_cols, collapse = ", ")),
    call. = FALSE
  )
}

# Keep county-level population and per-capita income, then aggregate to CBSA.
pi_county_year <- cainc1_raw %>%
  transmute(
    county_fips = str_extract(geofips, "[0-9]{5}"),
    line_code = suppressWarnings(as.integer(linecode)),
    across(all_of(pi_year_cols))
  ) %>%
  filter(line_code %in% c(2L, 3L)) %>%
  filter(!is.na(county_fips), !str_detect(county_fips, "000$")) %>%
  tidyr::pivot_longer(
    cols = all_of(pi_year_cols),
    names_to = "year",
    values_to = "raw_value"
  ) %>%
  mutate(
    year = as.integer(year),
    value_num = suppressWarnings(as.numeric(str_replace_all(raw_value, ",", "")))
  ) %>%
  filter(!is.na(value_num), year %in% 2010:2020) %>%
  select(county_fips, year, line_code, value_num) %>%
  tidyr::pivot_wider(
    names_from = line_code,
    values_from = value_num,
    names_prefix = "line_"
  ) %>%
  transmute(
    county_fips,
    year,
    population_persons = line_2,
    per_capita_income_dollars = line_3
  ) %>%
  filter(!is.na(population_persons), !is.na(per_capita_income_dollars))

pi_cbsa <- pi_county_year %>%
  left_join(
    cbsa_fips_xwalk %>% distinct(cbsa_code, county_fips),
    by = "county_fips",
    relationship = "many-to-one"
  ) %>%
  filter(!is.na(cbsa_code)) %>%
  group_by(cbsa_code, year) %>%
  summarise(
    per_capita_income_dollars = weighted.mean(
      per_capita_income_dollars,
      w = population_persons,
      na.rm = TRUE
    ),
    .groups = "drop"
  )

assert_unique_keys(pi_cbsa, c("cbsa_code", "year"), "CAINC1 CBSA-year panel")

message("CAINC1 personal income processing completed")
message(" - CBSA-year rows: ", nrow(pi_cbsa))
message(" - Wrote: ", pi_cbsa_csv)


# ------------------------------ FINAL PANEL -------------------------------- #

airport_cbsa_pop_county <- airport_cbsa_pop %>%
  left_join(cbsa_fips_xwalk, by = "cbsa_code", relationship = "many-to-many") %>%
  mutate(county_fips = str_pad(as.character(county_fips), 5, side = "left", pad = "0")) %>%
  relocate(county_fips, .after = cbsa_name)

# Build CBSA-year personal income panel with CAINC population kept for comparison.
pi_cbsa_panel <- pi_county_year %>%
  left_join(
    cbsa_fips_xwalk %>% distinct(cbsa_code, county_fips),
    by = "county_fips",
    relationship = "many-to-one"
  ) %>%
  filter(!is.na(cbsa_code)) %>%
  group_by(cbsa_code, year) %>%
  summarise(
    per_capita_income_dollars = weighted.mean(
      per_capita_income_dollars,
      w = population_persons,
      na.rm = TRUE
    ),
    population_cainc = sum(population_persons, na.rm = TRUE),
    .groups = "drop"
  )

assert_unique_keys(pi_cbsa_panel, c("cbsa_code", "year"), "CAINC1 CBSA-year income panel")

airport_cbsa_pop_county_final <- airport_cbsa_pop_county %>%
  left_join(pi_cbsa_panel, by = c("cbsa_code", "year"), relationship = "many-to-one") %>%
  left_join(qcew_cbsa_year, by = c("cbsa_code", "year", "quarter"), relationship = "many-to-one") %>%
  rename(population_census = population) %>%
  select(
    airport_id, airport_seq_id, airport_code, is_latest, latitude, longitude,
    cbsa_code, cbsa_name, county_fips, year, quarter,
    population_census, population_cainc, per_capita_income_dollars,
    leisure_emp_cbsa, total_emp_cbsa, leisure_share_emp_cbsa
  )

write_csv(airport_cbsa_pop_county_final, final_csv, na = "")
write_fst(airport_cbsa_pop_county_final, final_fst)

message("Final panel built successfully")
message("Rows: ", nrow(airport_cbsa_pop_county_final))
message("Wrote: ", final_csv)
message("Wrote: ", final_fst)
