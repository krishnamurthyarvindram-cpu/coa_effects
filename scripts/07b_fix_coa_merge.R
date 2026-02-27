##############################################################################
# 07b_fix_coa_merge.R — Fix unmatched COA cities and re-merge
##############################################################################

library(data.table)
library(stringdist)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 7b: Fix COA Merge Issues ==========")

# Reload the original data
coa <- readRDS(file.path(base_dir, "cleaned_data/coa_treatment.rds"))

# Fix known COA city name issues
# 1. Names with missing spaces
coa[city_clean == "jerseycity", city_clean := "jersey city"]
coa[city_clean == "kansascity" & state_clean == "ks", city_clean := "kansas city"]
coa[city_clean == "kansascity" & state_clean == "mo", city_clean := "kansas city"]
coa[city_clean == "oklahomacity", city_clean := "oklahoma city"]
coa[city_clean == "salt lakecity", city_clean := "salt lake city"]
coa[city_clean == "west valleycity", city_clean := "west valley"]
coa[city_clean == "boisecity", city_clean := "boise"]

# 2. Fix Nebraska abbreviation (nb -> ne)
coa[state_clean == "nb", state_clean := "ne"]

# 3. Fix long government names
coa[grepl("nashville davidson", city_clean), city_clean := "nashville"]
coa[grepl("louisville jefferson", city_clean), city_clean := "louisville"]
coa[grepl("lexington fayette", city_clean), city_clean := "lexington"]
coa[grepl("athens clarke", city_clean), city_clean := "athens"]
coa[city_clean == "urban honolulu", city_clean := "honolulu"]

# Save updated COA
saveRDS(coa, file.path(base_dir, "cleaned_data/coa_treatment.rds"))
wlog("Fixed COA city names")

# Reload panel and re-merge
panel <- as.data.table(readRDS(file.path(base_dir, "raw_data/data_panel_post1990.rds")))

# Same standardization as before
standardize_city <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("\\s+city$", "", x)
  x <- gsub("\\s+town$", "", x)
  x <- gsub("\\s+village$", "", x)
  x <- gsub("^st\\.?\\s+", "saint ", x)
  x <- gsub("^ft\\.?\\s+", "fort ", x)
  x <- gsub("^mt\\.?\\s+", "mount ", x)
  x <- gsub("[[:punct:]]", " ", x)
  x <- gsub("\\s+", " ", x)
  x <- trimws(x)
  return(x)
}

panel[, city_clean := standardize_city(city)]
panel[, state_clean := tolower(trimws(abb))]
panel[, city_state := paste0(city_clean, "_", state_clean)]
city_ids <- unique(panel$city_state)
panel[, agency_id := match(city_state, city_ids)]

# Select columns
actual_cols <- grep("^actual_", names(panel), value=TRUE)
actual_cols <- actual_cols[!grepl("_lag|_lead|_delta|_ln|_tr|_avg|_term", actual_cols)]
clr_cols <- grep("^tot_clr_", names(panel), value=TRUE)
clr_cols <- clr_cols[!grepl("_lag|_lead|_delta|_ln|_tr|_avg|_term", clr_cols)]
unfound_cols <- grep("^unfound_", names(panel), value=TRUE)

keep_cols <- c("place_fips", "year", "city", "abb", "city_clean", "state_clean",
               "city_state", "agency_id",
               "population_est", "population_2010", "population_2020",
               "ori", "ori9.x", "agency_name.x",
               "fips_state_code.x", "fips_place_code.x",
               "drug_tot_arrests", "drug_tot_black", "drug_tot_white",
               "vio_tot_arrests", "vio_tot_black", "vio_tot_white",
               "prop_tot_arrests", "prop_tot_black", "prop_tot_white",
               "oth_tot_arrests", "oth_tot_black", "oth_tot_white",
               "total_tot_arrests", "total_tot_black", "total_tot_white",
               "index_tot_arrests", "index_tot_black", "index_tot_white",
               "drug_black_share", "vio_black_share", "prop_black_share",
               "oth_black_share", "total_black_share", "index_black_share",
               "drug_tot_arrests_p100c", "vio_tot_arrests_p100c",
               "prop_tot_arrests_p100c", "oth_tot_arrests_p100c",
               "total_tot_arrests_p100c", "index_tot_arrests_p100c",
               "number_of_months_reported",
               "percent_black.x", "percent_white.x",
               "percent_black_2010", "percent_white_2010",
               "population_base",
               "dem_in_power", "rep_in_power", "demshare",
               actual_cols, clr_cols, unfound_cols)

keep_cols <- unique(intersect(keep_cols, names(panel)))
panel_slim <- panel[, ..keep_cols]
rm(panel); gc()

# Merge COA
panel_slim <- merge(panel_slim,
                     coa[, .(city_clean, state_clean, treatment_year, has_board,
                             invest_power, discipline_power, election_created,
                             selection_method)],
                     by = c("city_clean", "state_clean"),
                     all.x = TRUE)

# Fuzzy matching for remaining unmatched treated cities
unmatched_panel <- panel_slim[is.na(treatment_year)]
treated_coa <- coa[treatment_year > 0]

if (nrow(unmatched_panel) > 0 && nrow(treated_coa) > 0) {
  unmatched_cities <- unique(unmatched_panel[, .(city_clean, state_clean)])
  fuzzy_matches <- data.table()
  for (st in unique(unmatched_cities$state_clean)) {
    um_cities <- unmatched_cities[state_clean == st]$city_clean
    tr_cities <- treated_coa[state_clean == st]$city_clean
    if (length(tr_cities) > 0 && length(um_cities) > 0) {
      dists <- stringdistmatrix(um_cities, tr_cities, method = "jw")
      for (i in seq_along(um_cities)) {
        best_j <- which.min(dists[i, ])
        if (length(best_j) > 0 && dists[i, best_j] < 0.15) {
          fuzzy_matches <- rbind(fuzzy_matches, data.table(
            city_panel = um_cities[i], city_coa = tr_cities[best_j],
            state = st, dist = dists[i, best_j]
          ))
        }
      }
    }
  }

  if (nrow(fuzzy_matches) > 0) {
    wlog("Fuzzy matches (JW < 0.15):")
    for (i in 1:nrow(fuzzy_matches)) {
      wlog("  ", fuzzy_matches$city_panel[i], " -> ", fuzzy_matches$city_coa[i],
           " (", fuzzy_matches$state[i], ", d=", round(fuzzy_matches$dist[i], 4), ")")
    }
    for (i in 1:nrow(fuzzy_matches)) {
      fm <- fuzzy_matches[i]
      coa_row <- treated_coa[city_clean == fm$city_coa & state_clean == fm$state]
      if (nrow(coa_row) > 0) {
        panel_slim[city_clean == fm$city_panel & state_clean == fm$state,
                    `:=`(treatment_year = coa_row$treatment_year[1],
                         has_board = coa_row$has_board[1],
                         invest_power = coa_row$invest_power[1],
                         discipline_power = coa_row$discipline_power[1],
                         election_created = coa_row$election_created[1],
                         selection_method = coa_row$selection_method[1])]
      }
    }
  }
}

# Set never-treated
panel_slim[is.na(treatment_year), treatment_year := 0L]
panel_slim[is.na(has_board), has_board := 0L]
panel_slim[is.na(invest_power), invest_power := 0L]
panel_slim[is.na(discipline_power), discipline_power := 0L]
panel_slim[is.na(election_created), election_created := 0L]

# Report
n_treated <- length(unique(panel_slim[treatment_year > 0]$city_state))
n_control <- length(unique(panel_slim[treatment_year == 0]$city_state))
wlog("\nAfter fixed COA merge:")
wlog("  Treated cities in panel: ", n_treated)
wlog("  Control cities in panel: ", n_control)

# Check unmatched treated COA cities
treated_in_panel <- unique(panel_slim[treatment_year > 0, .(city_clean, state_clean)])
treated_in_coa <- coa[treatment_year > 0, .(city_clean, state_clean)]
still_unmatched <- treated_in_coa[!treated_in_panel, on = c("city_clean", "state_clean")]
wlog("Still unmatched treated COA cities: ", nrow(still_unmatched))
if (nrow(still_unmatched) > 0) {
  for (i in 1:nrow(still_unmatched)) {
    wlog("  ", still_unmatched$city_clean[i], ", ", still_unmatched$state_clean[i])
  }
}

# Treatment year distribution in panel
wlog("\nTreatment year distribution in final panel:")
tr_tab <- table(unique(panel_slim[treatment_year > 0, .(city_state, treatment_year)])$treatment_year)
for (yr in names(tr_tab)) wlog("  ", yr, ": ", tr_tab[yr])

# Merge police killings
pk <- readRDS(file.path(base_dir, "cleaned_data/police_killings.rds"))
panel_slim <- merge(panel_slim, pk,
                     by = c("city_clean", "state_clean", "year"), all.x = TRUE)
panel_slim[is.na(total_killings), total_killings := 0L]
panel_slim[is.na(black_killings), black_killings := 0L]
panel_slim[is.na(nonwhite_killings), nonwhite_killings := 0L]

# Merge demographics
demo <- as.data.table(readRDS(file.path(base_dir, "raw_data/cities_historical_demographics.rds")))
panel_slim[, place_fips_char := as.character(place_fips)]
demo[, place_fips_char := as.character(place_fips)]
panel_slim <- merge(panel_slim,
                     demo[, .(place_fips_char, year,
                              pct_black_demo = percent_black,
                              pct_white_demo = percent_white,
                              pct_hispanic_demo = percent_hispanic,
                              pct_asian_demo = percent_asian_american)],
                     by = c("place_fips_char", "year"), all.x = TRUE)
panel_slim[, pct_black := fifelse(!is.na(pct_black_demo), pct_black_demo, percent_black.x)]
panel_slim[, pct_white := fifelse(!is.na(pct_white_demo), pct_white_demo, percent_white.x)]
panel_slim[, pct_hispanic := pct_hispanic_demo]

# Save
saveRDS(panel_slim, file.path(base_dir, "merged_data/panel_merged.rds"))
wlog("\nFinal panel: ", nrow(panel_slim), " x ", ncol(panel_slim))
wlog("Step 7b complete.\n")

# Save diagnostics
diag <- data.table(
  Stage = c("Panel base", "COA Treatment matched",
            "Police Killings city-years", "Demographics matched"),
  N = c(nrow(panel_slim), n_treated,
        sum(panel_slim$total_killings > 0),
        sum(!is.na(panel_slim$pct_black_demo))),
  Details = c(paste0(length(unique(panel_slim$city_state)), " cities, ",
                      min(panel_slim$year), "-", max(panel_slim$year)),
              paste0(n_treated, " treated, ", nrow(still_unmatched), " COA cities unmatched"),
              paste0(sum(panel_slim$total_killings), " total killings in panel"),
              paste0(round(100*mean(!is.na(panel_slim$pct_black_demo)), 1), "% rows with demographics"))
)
fwrite(diag, file.path(base_dir, "output/tables/merge_diagnostics.csv"))
