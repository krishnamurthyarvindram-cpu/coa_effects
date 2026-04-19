## Stream all yearly UCR arrests CSVs (1990-2024) and produce a per-ORI x year
## reporting summary, then classify the 56 cities flagged as "missing UCR arrests"
## in the master panel.
##
## Output: dev/ucr_agency_year_report.rds and dev/ucr_missing_classification.csv
suppressPackageStartupMessages({
  library(data.table); library(stringr)
})

raw_dir <- "C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year"
cw <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.rds") |> as.data.table()
m  <- readRDS("C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.rds") |> as.data.table()

# --- Identify the COA cities currently flagged as missing UCR arrests ---
cols_arr <- c("drug_tot_arrests","drug_tot_black","drug_tot_white",
              "index_tot_arrests","index_tot_black","index_tot_white",
              "vio_tot_arrests","vio_tot_black","vio_tot_white",
              "prop_tot_arrests","prop_tot_black","prop_tot_white",
              "oth_tot_arrests","oth_tot_black","oth_tot_white",
              "total_tot_arrests","total_tot_black","total_tot_white")
present_per_city <- m[year %in% 1990:2021,
                       .(any_arrests = any(!is.na(.SD))),
                       by = coa_id, .SDcols = cols_arr]
missing_cities <- present_per_city[any_arrests == FALSE, coa_id]
cat("# COA cities missing UCR arrests in master panel:", length(missing_cities), "\n")

cw_miss <- cw[key %in% missing_cities,
              .(coa_id = key, city_clean, state_clean, ori9, place_fips_str)]
print(cw_miss)

# --- Stream all yearly UCR CSVs 1990-2024 ---
files <- list.files(raw_dir, pattern = "arrests_yearly_\\d{4}\\.csv$", full.names = TRUE)
years_avail <- as.integer(gsub(".*_(\\d{4})\\.csv$", "\\1", basename(files)))
keep <- years_avail >= 1990
files <- files[keep]
years_avail <- years_avail[keep]
cat("Scanning", length(files), "yearly files (years", min(years_avail), "-", max(years_avail), ")\n")

# We only need a handful of cols — and we aggregate to one row per (ori9, year)
needed <- c("ori9","year","number_of_months_reported","zero_data_indicator_binary",
            "total_arrests","agency_name","state_abb",
            "fips_state_code","fips_place_code","population")

agg_all <- vector("list", length(files))
for (i in seq_along(files)) {
  f  <- files[i]; yr <- years_avail[i]
  t0 <- Sys.time()
  d  <- fread(f, select = needed, showProgress = FALSE)
  # Reduce to one row per ori9+year (yearly file has 1 row per agency x offense_code)
  agg <- d[, .(
    months_reported   = suppressWarnings(max(number_of_months_reported, na.rm = TRUE)),
    any_zero_data_ind = suppressWarnings(max(zero_data_indicator_binary, na.rm = TRUE)),
    sum_arrests_all   = sum(total_arrests, na.rm = TRUE),
    agency_name       = first(agency_name),
    state_abb         = first(state_abb),
    fips_state_code   = first(fips_state_code),
    fips_place_code   = first(fips_place_code),
    population        = suppressWarnings(max(population, na.rm = TRUE))
  ), by = .(ori9, year)]
  # Replace -Inf from max(NA) with NA
  for (c in c("months_reported","any_zero_data_ind","population"))
    agg[is.infinite(get(c)), (c) := NA_integer_]
  agg_all[[i]] <- agg
  cat(sprintf("  %d : %d agencies, %.1fs\n", yr, nrow(agg),
              as.numeric(Sys.time() - t0, units = "secs")))
}
ucr <- rbindlist(agg_all)
cat("Total per-ORI x year rows:", nrow(ucr), "\n")
saveRDS(ucr, "C:/Users/arvind/Desktop/coa_effects/dev/ucr_agency_year_report.rds")

# --- Build per-ORI overall summary across years ---
ucr[, place_fips_built := sprintf("%02d%05d", as.integer(fips_state_code),
                                  as.integer(fips_place_code))]
ucr_summary <- ucr[, .(
  n_years_seen          = .N,
  n_years_with_months   = sum(!is.na(months_reported) & months_reported > 0, na.rm = TRUE),
  n_years_zero_data     = sum(!is.na(any_zero_data_ind) & any_zero_data_ind == 1, na.rm = TRUE),
  n_years_with_arrests  = sum(sum_arrests_all > 0, na.rm = TRUE),
  yrs_seen              = paste(sort(unique(year)), collapse = ","),
  yrs_with_arrests      = paste(sort(unique(year[sum_arrests_all > 0])), collapse = ","),
  agency_name           = paste(unique(agency_name)[1:min(2, uniqueN(agency_name))], collapse = " | "),
  state_abb             = first(state_abb),
  fips_built            = first(place_fips_built),
  pop_max               = suppressWarnings(max(population, na.rm = TRUE))
), by = ori9]

# --- Classify each missing COA city -----------------------------------------
classify_one <- function(coa_id_in, ori9_in, place_fips_in, city_in, state_in) {
  result <- list(coa_id = coa_id_in, ori9_used = ori9_in, place_fips_used = place_fips_in,
                 match_method = NA_character_, agency_found = NA_character_,
                 yrs_w_arrests = NA_character_, n_years_with_months = NA_integer_,
                 n_years_with_arrests = NA_integer_, classification = NA_character_)
  hit <- NULL
  if (!is.na(ori9_in)) {
    hit <- ucr_summary[ori9 == ori9_in]
    if (nrow(hit)) result$match_method <- "by_ori9"
  }
  if (is.null(hit) || !nrow(hit)) {
    if (!is.na(place_fips_in)) {
      hit <- ucr_summary[fips_built == place_fips_in]
      if (nrow(hit)) result$match_method <- "by_place_fips"
    }
  }
  if (is.null(hit) || !nrow(hit)) {
    state_up <- toupper(state_in)
    hit <- ucr_summary[state_abb == state_up &
                        grepl(city_in, tolower(agency_name), fixed = TRUE)]
    if (nrow(hit) > 0) {
      hit <- hit[order(-n_years_with_arrests)][1]
      result$match_method <- "by_name_state"
    }
  }
  if (is.null(hit) || !nrow(hit)) {
    result$classification <- "NOT_IN_UCR"
    return(result)
  }
  hit <- hit[1]
  result$agency_found        <- hit$agency_name
  result$yrs_w_arrests       <- hit$yrs_with_arrests
  result$n_years_with_months <- hit$n_years_with_months
  result$n_years_with_arrests<- hit$n_years_with_arrests
  result$ori9_used           <- hit$ori9
  result$classification <- if (hit$n_years_with_arrests > 0)
    "MERGE_GAP_in_UCR_with_data"
  else if (hit$n_years_with_months > 0)
    "REPORTS_BUT_ZERO_ARRESTS"
  else
    "GENUINE_NON_REPORTER"
  result
}

cls <- rbindlist(lapply(seq_len(nrow(cw_miss)), function(i) {
  classify_one(cw_miss$coa_id[i], cw_miss$ori9[i],
                cw_miss$place_fips_str[i],
                cw_miss$city_clean[i], cw_miss$state_clean[i])
}))
print(table(cls$classification, useNA = "ifany"))

fwrite(cls, "C:/Users/arvind/Desktop/coa_effects/dev/ucr_missing_classification.csv")
cat("\nWrote classification to dev/ucr_missing_classification.csv\n")
