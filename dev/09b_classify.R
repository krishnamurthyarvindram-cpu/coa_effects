## Re-run classification using the saved per-ORI x year report
suppressPackageStartupMessages({ library(data.table); library(stringr) })

cw <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.rds") |> as.data.table()
m  <- readRDS("C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.rds") |> as.data.table()
ucr <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/ucr_agency_year_report.rds") |> as.data.table()

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
# Known aliases used by UCR
alias <- list(
  c("san buenaventura", "ventura")
)
for (a in alias) cw_miss[city_clean == a[1], city_clean := a[2]]

# Build summary per ORI
ucr[, place_fips_built := sprintf("%02d%05d", as.integer(fips_state_code),
                                  as.integer(fips_place_code))]
ucr_summary <- ucr[, .(
  n_years_seen          = .N,
  n_years_with_months   = sum(!is.na(months_reported) & months_reported > 0, na.rm = TRUE),
  n_years_full_12       = sum(!is.na(months_reported) & months_reported == 12, na.rm = TRUE),
  n_years_zero_data     = sum(!is.na(any_zero_data_ind) & any_zero_data_ind == 1, na.rm = TRUE),
  n_years_with_arrests  = sum(sum_arrests_all > 0, na.rm = TRUE),
  yrs_seen              = paste(sort(unique(year)), collapse = ","),
  yrs_with_arrests      = paste(sort(unique(year[sum_arrests_all > 0])), collapse = ","),
  agency_name           = paste(unique(agency_name)[1:min(2, uniqueN(agency_name))], collapse = " | "),
  state_abb             = first(state_abb),
  fips_built            = first(place_fips_built),
  pop_max               = suppressWarnings(max(population, na.rm = TRUE))
), by = ori9]

# Bound: in panel period
ucr_summary_p <- ucr[year %in% 1990:2021, .(
  n_years_with_months_p   = sum(!is.na(months_reported) & months_reported > 0, na.rm = TRUE),
  n_years_with_arrests_p  = sum(sum_arrests_all > 0, na.rm = TRUE),
  yrs_with_arrests_p      = paste(sort(unique(year[sum_arrests_all > 0])), collapse = ",")
), by = ori9]
ucr_summary <- merge(ucr_summary, ucr_summary_p, by = "ori9", all.x = TRUE)

classify_one <- function(coa_id_in, ori9_in, place_fips_in, city_in, state_in) {
  result <- list(coa_id = coa_id_in, ori9_input = ori9_in, place_fips_input = place_fips_in,
                 ori9_matched = NA_character_, match_method = "NONE",
                 agency_found = NA_character_, agency_pop = NA_integer_,
                 n_yrs_w_months_1990_2021 = NA_integer_,
                 n_yrs_w_arrests_1990_2021 = NA_integer_,
                 n_yrs_w_arrests_total = NA_integer_,
                 yrs_w_arrests = NA_character_,
                 classification = "NOT_IN_UCR")
  hit <- NULL
  if (!is.na(ori9_in)) {
    hit <- ucr_summary[ori9 == ori9_in]
    if (nrow(hit)) result$match_method <- "by_ori9"
  }
  if (is.null(hit) || !nrow(hit)) {
    if (!is.na(place_fips_in)) {
      hit <- ucr_summary[fips_built == place_fips_in]
      if (nrow(hit) > 0) {
        hit <- hit[order(-n_years_with_arrests)][1]
        result$match_method <- "by_place_fips"
      }
    }
  }
  if (is.null(hit) || !nrow(hit)) {
    state_up <- toupper(state_in)
    # Filter out non-municipal agencies that share city names (universities, airports, etc.)
    EXCL <- "univ|college|school|airport|campus|transit|park serv|metro park|sheriff|district atty|district attorney|forestry|conserv|fire dist|water dist|isd|h\\.s\\.|jr coll|board of educat|housing auth|community coll|hospital"
    hit <- ucr_summary[state_abb == state_up &
                        grepl(paste0("(^|\\W)", city_in, "(\\W|$)"),
                              tolower(agency_name)) &
                        !grepl(EXCL, tolower(agency_name))]
    if (nrow(hit) > 0) {
      hit <- hit[order(-pop_max, -n_years_with_arrests)][1]
      result$match_method <- "by_name_state"
    }
  }
  # Special case: consolidated city-counties often use fips_place_code=99991
  # so by_place_fips misses them. Try by state + city-name in agency_name with 99991.
  if ((is.null(hit) || !nrow(hit) || hit$pop_max < 50000) && !is.na(state_in)) {
    state_up <- toupper(state_in)
    EXCL <- "univ|college|school|airport|campus|transit|park serv|metro park|sheriff"
    hit_co <- ucr_summary[state_abb == state_up &
                           grepl(city_in, tolower(agency_name), fixed = TRUE) &
                           !grepl(EXCL, tolower(agency_name)) &
                           pop_max >= 50000]
    if (nrow(hit_co) > 0) {
      hit <- hit_co[order(-pop_max, -n_years_with_arrests)][1]
      result$match_method <- "by_name_state_largepop"
    }
  }
  if (is.null(hit) || !nrow(hit)) return(result)
  hit <- hit[1]
  result$ori9_matched <- hit$ori9
  result$agency_found <- hit$agency_name
  result$agency_pop <- hit$pop_max
  result$n_yrs_w_months_1990_2021 <- hit$n_years_with_months_p
  result$n_yrs_w_arrests_1990_2021 <- hit$n_years_with_arrests_p
  result$n_yrs_w_arrests_total <- hit$n_years_with_arrests
  result$yrs_w_arrests <- hit$yrs_with_arrests_p
  result$classification <- if (hit$n_years_with_arrests_p > 0)
    "MERGE_GAP_in_UCR_with_data"
  else if (hit$n_years_with_months_p > 0)
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

cat("\n=== Classification breakdown ===\n")
print(table(cls$classification, cls$match_method, useNA = "ifany"))

cat("\n=== MERGE GAP cities (in UCR with arrests data, missed by panel) ===\n")
print(cls[classification == "MERGE_GAP_in_UCR_with_data",
          .(coa_id, agency_found, agency_pop, n_yrs_w_arrests_1990_2021,
            match_method)][order(-n_yrs_w_arrests_1990_2021)])

cat("\n=== REPORTS_BUT_ZERO_ARRESTS ===\n")
print(cls[classification == "REPORTS_BUT_ZERO_ARRESTS",
          .(coa_id, agency_found, agency_pop, n_yrs_w_months_1990_2021)])

cat("\n=== GENUINE NON-REPORTERS ===\n")
print(cls[classification == "GENUINE_NON_REPORTER",
          .(coa_id, agency_found, agency_pop)])

cat("\n=== NOT IN UCR ===\n")
print(cls[classification == "NOT_IN_UCR",
          .(coa_id, ori9_input, place_fips_input)])

fwrite(cls, "C:/Users/arvind/Desktop/coa_effects/dev/ucr_missing_classification.csv")
cat("\nWrote dev/ucr_missing_classification.csv\n")
