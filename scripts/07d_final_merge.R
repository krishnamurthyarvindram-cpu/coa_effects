##############################################################################
# 07d_final_merge.R — Final merge with manual city name fixes
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

wlog("\n========== STEP 7d: Final Merge with Manual Fixes ==========")

# Better standardize that keeps "city" when it's part of the name
standardize_city2 <- function(x) {
  x <- tolower(trimws(x))
  # Remove only trailing " city" that's a suffix (e.g., "new york city" -> "new york")
  # But keep "kansas city", "oklahoma city" etc. where "city" IS the name
  # Strategy: only remove " city" if preceded by a word that's a real place
  # Actually, simplest approach: just clean whitespace/punctuation but keep all words
  x <- gsub("-", " ", x)  # Hyphens to spaces
  x <- gsub("\\s+", " ", x)
  x <- trimws(x)
  return(x)
}

# Load panel
panel <- as.data.table(readRDS(file.path(base_dir, "raw_data/data_panel_post1990.rds")))
panel[, city_lower := tolower(trimws(city))]
panel[, city_lower := gsub("-", " ", city_lower)]
panel[, city_lower := gsub("\\s+", " ", trimws(city_lower))]
panel[, state_clean := tolower(trimws(abb))]
panel[, city_state := paste0(city_lower, "_", state_clean)]
city_ids <- unique(panel$city_state)
panel[, agency_id := match(city_state, city_ids)]

# Select needed columns
actual_cols <- grep("^actual_", names(panel), value=TRUE)
actual_cols <- actual_cols[!grepl("_lag|_lead|_delta|_ln|_tr|_avg|_term", actual_cols)]
clr_cols <- grep("^tot_clr_", names(panel), value=TRUE)
clr_cols <- clr_cols[!grepl("_lag|_lead|_delta|_ln|_tr|_avg|_term", clr_cols)]
unfound_cols <- grep("^unfound_", names(panel), value=TRUE)

keep_cols <- unique(c("place_fips", "year", "city", "abb", "city_lower", "state_clean",
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
               actual_cols, clr_cols, unfound_cols))
keep_cols <- intersect(keep_cols, names(panel))
panel_slim <- panel[, ..keep_cols]
rm(panel); gc()

# Print panel cities for verification
panel_cities <- unique(panel_slim[, .(city_lower, state_clean)])
wlog("Panel has ", nrow(panel_cities), " unique city-state pairs")

# Load COA - start fresh from raw
coa_raw <- fread(file.path(base_dir, "raw_data/coa_creation_data.csv"))
setnames(coa_raw, c("ORI_raw", "city_num", "city_raw", "state_raw", "population",
                      "state_abb", "has_oversight_board", "oversight_powers",
                      "charter_found", "link", "year_created",
                      "can_investigate", "can_discipline",
                      "created_via_election", "selection_method"))

coa_raw[, year_created_clean := suppressWarnings(as.integer(year_created))]
coa_raw[, treatment_year := fifelse(!is.na(year_created_clean) & year_created_clean > 0,
                                     year_created_clean, 0L)]
coa_raw[, has_board := fifelse(toupper(trimws(has_oversight_board)) == "Y", 1L, 0L)]
coa_raw[, invest_power := fifelse(toupper(trimws(can_investigate)) == "Y", 1L, 0L)]
coa_raw[, discipline_power := fifelse(toupper(trimws(can_discipline)) == "Y", 1L, 0L)]
coa_raw[, election_created := fifelse(toupper(trimws(created_via_election)) == "Y", 1L, 0L)]

# Standardize COA city names to match panel format
coa_raw[, city_lower := tolower(trimws(city_raw))]
coa_raw[, city_lower := gsub("-", " ", city_lower)]
coa_raw[, city_lower := gsub("\\s+", " ", trimws(city_lower))]
coa_raw[, state_clean := tolower(trimws(state_abb))]

# Fix Nebraska
coa_raw[state_clean == "nb", state_clean := "ne"]

# Show what COA names look like vs panel names
wlog("\nCOA treated cities and their names:")
treated_coa <- coa_raw[treatment_year > 0]
for (i in 1:nrow(treated_coa)) {
  cat(treated_coa$city_lower[i], " (", treated_coa$state_clean[i], ")\n")
}

# Create manual mapping for known mismatches
# Panel name -> COA name mappings
# The panel has the city names, COA has different forms
# Let's see which panel cities match COA cities
matched_exact <- merge(panel_cities, treated_coa[, .(city_lower, state_clean)],
                        by = c("city_lower", "state_clean"))
wlog("\nExact matches: ", nrow(matched_exact), " of ", nrow(treated_coa), " treated cities")

# Unmatched treated cities
unmatched_coa <- treated_coa[!paste0(city_lower, "_", state_clean) %in%
                               paste0(matched_exact$city_lower, "_", matched_exact$state_clean)]
wlog("Unmatched treated COA cities: ", nrow(unmatched_coa))
for (i in 1:min(nrow(unmatched_coa), 50)) {
  wlog("  ", unmatched_coa$city_lower[i], " (", unmatched_coa$state_clean[i], ")")
}

# Manual mapping: COA city_lower -> panel city_lower
# Based on debug_cities output
manual_map <- data.table(
  coa_city = c("nashville davidson metropolitan government balance city",
               "louisville jefferson county metro government balance city",
               "lexington fayette urban county city",
               "athens clarke county unified government balance city",
               "arlington city"),
  panel_city = c("nashville davidson county",
                 "louisville jefferson county",
                 "lexington fayette county",
                 "athens clarke county",
                 "arlington"),
  state = c("tn", "ky", "ky", "ga", "va")
)

# Apply manual mappings
for (i in 1:nrow(manual_map)) {
  mm <- manual_map[i]
  coa_raw[city_lower == mm$coa_city & state_clean == mm$state,
           city_lower := mm$panel_city]
}

# Also try removing common suffixes from COA names to match panel
coa_raw[, city_lower := gsub("\\s+city$", "", city_lower)]
coa_raw[, city_lower := gsub("\\s+town$", "", city_lower)]
# But restore "city" for places where it's part of the name and panel keeps it
city_names_with_city <- panel_cities[grepl("city$", city_lower)]$city_lower
for (cn in city_names_with_city) {
  base <- gsub("\\s+city$", "", cn)
  coa_raw[city_lower == base & paste0(city_lower, " city") == cn, city_lower := cn]
  # Also check if the state matches
}

# More targeted: for each COA name that doesn't match, find closest panel name in same state
coa_treated <- coa_raw[treatment_year > 0]
coa_treated[, matched := paste0(city_lower, "_", state_clean) %in%
              paste0(panel_cities$city_lower, "_", panel_cities$state_clean)]

unmatched_coa2 <- coa_treated[matched == FALSE]
wlog("\nAfter suffix removal, still unmatched: ", nrow(unmatched_coa2))

# Fuzzy match remaining
for (i in 1:nrow(unmatched_coa2)) {
  um <- unmatched_coa2[i]
  candidates <- panel_cities[state_clean == um$state_clean]
  if (nrow(candidates) > 0) {
    dists <- stringdist(um$city_lower, candidates$city_lower, method = "jw")
    best <- which.min(dists)
    if (dists[best] < 0.2) {
      wlog("  Fuzzy: '", um$city_lower, "' -> '", candidates$city_lower[best],
           "' (", um$state_clean, ", d=", round(dists[best], 4), ")")
      coa_raw[city_lower == um$city_lower & state_clean == um$state_clean,
               city_lower := candidates$city_lower[best]]
    } else {
      wlog("  NO MATCH: '", um$city_lower, "' (", um$state_clean,
           ") best='", candidates$city_lower[best], "' d=", round(dists[best], 4))
    }
  } else {
    wlog("  NO CANDIDATES: '", um$city_lower, "' (", um$state_clean, ")")
  }
}

# Deduplicate COA
coa_clean <- coa_raw[, .(city_lower, state_clean, treatment_year, has_board,
                          invest_power, discipline_power, election_created,
                          selection_method)]
coa_clean <- coa_clean[order(city_lower, state_clean, -treatment_year)]
coa_clean <- coa_clean[!duplicated(paste0(city_lower, "_", state_clean))]

# MERGE
panel_slim <- merge(panel_slim,
                     coa_clean[, .(city_lower, state_clean, treatment_year, has_board,
                                   invest_power, discipline_power, election_created,
                                   selection_method)],
                     by = c("city_lower", "state_clean"),
                     all.x = TRUE)

panel_slim[is.na(treatment_year), treatment_year := 0L]
panel_slim[is.na(has_board), has_board := 0L]
panel_slim[is.na(invest_power), invest_power := 0L]
panel_slim[is.na(discipline_power), discipline_power := 0L]
panel_slim[is.na(election_created), election_created := 0L]

n_treated <- length(unique(panel_slim[treatment_year > 0]$city_state))
n_control <- length(unique(panel_slim[treatment_year == 0]$city_state))
wlog("\n=== FINAL MERGE RESULT ===")
wlog("Treated cities in panel: ", n_treated)
wlog("Control cities in panel: ", n_control)
wlog("Total panel rows: ", nrow(panel_slim))

# Final check of unmatched
treated_in_panel <- unique(panel_slim[treatment_year > 0, .(city_lower, state_clean)])
treated_in_coa <- coa_clean[treatment_year > 0, .(city_lower, state_clean)]
still_unmatched <- treated_in_coa[!paste0(city_lower, "_", state_clean) %in%
                                    paste0(treated_in_panel$city_lower, "_", treated_in_panel$state_clean)]
wlog("Final unmatched treated COA cities: ", nrow(still_unmatched))
if (nrow(still_unmatched) > 0) {
  for (i in 1:nrow(still_unmatched)) {
    wlog("  ", still_unmatched$city_lower[i], " (", still_unmatched$state_clean[i], ")")
  }
}

# Treatment year distribution
wlog("\nTreatment year distribution:")
tr_years <- unique(panel_slim[treatment_year > 0, .(city_state, treatment_year)])
print(table(tr_years$treatment_year))

# ---- Merge police killings ----
pk <- readRDS(file.path(base_dir, "cleaned_data/police_killings.rds"))
# Need to also standardize pk city names
pk[, city_lower := tolower(trimws(city_clean))]
pk[, city_lower := gsub("-", " ", city_lower)]
pk[, city_lower := gsub("\\s+", " ", trimws(city_lower))]

# Rename to avoid collision
setnames(pk, "state_clean", "state_clean_pk")
pk[, state_clean := state_clean_pk]

panel_slim <- merge(panel_slim, pk[, .(city_lower, state_clean, year,
                                        total_killings, black_killings, nonwhite_killings)],
                     by = c("city_lower", "state_clean", "year"), all.x = TRUE)
panel_slim[is.na(total_killings), total_killings := 0L]
panel_slim[is.na(black_killings), black_killings := 0L]
panel_slim[is.na(nonwhite_killings), nonwhite_killings := 0L]

wlog("\nPolice killings merged: ", sum(panel_slim$total_killings > 0), " city-years with killings")

# ---- Merge demographics ----
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

wlog("Demographics merged: ", sum(!is.na(panel_slim$pct_black_demo)), " rows with time-varying data")

# ---- Save ----
saveRDS(panel_slim, file.path(base_dir, "merged_data/panel_merged.rds"))
wlog("\nFinal merged panel saved: ", nrow(panel_slim), " x ", ncol(panel_slim))

# Save diagnostics
diag <- data.table(
  Stage = c("Panel base", "COA Treatment", "Police Killings", "Demographics"),
  N = c(length(unique(panel_slim$city_state)),
        n_treated, sum(panel_slim$total_killings > 0),
        sum(!is.na(panel_slim$pct_black_demo))),
  Details = c(paste0(length(unique(panel_slim$city_state)), " cities, ",
                      min(panel_slim$year), "-", max(panel_slim$year)),
              paste0(n_treated, " treated, ", nrow(still_unmatched), " unmatched"),
              paste0(sum(panel_slim$total_killings), " total killings"),
              paste0(round(100*mean(!is.na(panel_slim$pct_black_demo)), 1), "% matched"))
)
fwrite(diag, file.path(base_dir, "output/tables/merge_diagnostics.csv"))
wlog("Step 7 FINAL complete.\n")
