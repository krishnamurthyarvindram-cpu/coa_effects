##############################################################################
# 07_merge_all.R — Steps 6-7: Use Pre-Built Panel as Backbone + Merge
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

merge_report <- function(left_n, right_n, merged_n, stage_name) {
  wlog("\n=== ", stage_name, " ===")
  wlog("Left rows: ", left_n, " | Right rows: ", right_n)
  wlog("Merged rows: ", merged_n)
  wlog("Match rate (of left): ", round(merged_n / left_n * 100, 1), "%")
}

wlog("\n========== STEP 6-7: Merge All Datasets ==========")

# ---------------------------------------------------------------
# Load the panel backbone
# ---------------------------------------------------------------
wlog("Loading pre-built panel (data_panel_post1990.rds)...")
panel <- as.data.table(readRDS(file.path(base_dir, "raw_data/data_panel_post1990.rds")))
wlog("Panel dimensions: ", nrow(panel), " x ", ncol(panel))
wlog("Year range: ", min(panel$year), " - ", max(panel$year))
wlog("Unique cities: ", length(unique(panel$city)))

# Standardize city names in panel
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

# Create a unique agency ID (numeric for PanelMatch/CSDID)
panel[, city_state := paste0(city_clean, "_", state_clean)]
city_ids <- unique(panel$city_state)
panel[, agency_id := match(city_state, city_ids)]

wlog("Unique agency IDs: ", length(unique(panel$agency_id)))

# ---------------------------------------------------------------
# Select key columns from panel to keep it manageable
# ---------------------------------------------------------------
# Identify columns we need
keep_cols <- c("place_fips", "year", "city", "abb", "city_clean", "state_clean",
               "city_state", "agency_id",
               "population_est", "population_2010", "population_2020",
               "ori", "ori9.x", "agency_name.x",
               "fips_state_code.x", "fips_place_code.x",
               # Arrest data
               "drug_tot_arrests", "drug_tot_black", "drug_tot_white",
               "vio_tot_arrests", "vio_tot_black", "vio_tot_white",
               "prop_tot_arrests", "prop_tot_black", "prop_tot_white",
               "oth_tot_arrests", "oth_tot_black", "oth_tot_white",
               "total_tot_arrests", "total_tot_black", "total_tot_white",
               "index_tot_arrests", "index_tot_black", "index_tot_white",
               # Black shares
               "drug_black_share", "vio_black_share", "prop_black_share",
               "oth_black_share", "total_black_share", "index_black_share",
               # Per capita
               "drug_tot_arrests_p100c", "vio_tot_arrests_p100c",
               "prop_tot_arrests_p100c", "oth_tot_arrests_p100c",
               "total_tot_arrests_p100c", "index_tot_arrests_p100c",
               # Months reported
               "number_of_months_reported",
               # Demographics
               "percent_black.x", "percent_white.x",
               "percent_black_2010", "percent_white_2010",
               "population_base",
               # Political
               "dem_in_power", "rep_in_power",
               "demshare")

# Also grab offense/clearance data
actual_cols <- grep("^actual_", names(panel), value=TRUE)
actual_cols <- actual_cols[!grepl("_lag|_lead|_delta|_ln|_tr|_avg|_term", actual_cols)]
# Also get tot_clr columns
clr_cols <- grep("^tot_clr_", names(panel), value=TRUE)
clr_cols <- clr_cols[!grepl("_lag|_lead|_delta|_ln|_tr|_avg|_term", clr_cols)]
unfound_cols <- grep("^unfound_", names(panel), value=TRUE)

keep_cols <- unique(c(keep_cols, actual_cols, clr_cols, unfound_cols))

# Only keep columns that actually exist
keep_cols <- intersect(keep_cols, names(panel))
wlog("Keeping ", length(keep_cols), " columns from panel")

panel_slim <- panel[, ..keep_cols]
rm(panel); gc()

wlog("Slim panel: ", nrow(panel_slim), " x ", ncol(panel_slim))

# ---------------------------------------------------------------
# Merge COA Treatment Data
# ---------------------------------------------------------------
wlog("\n--- Merging COA Treatment Data ---")
coa <- readRDS(file.path(base_dir, "cleaned_data/coa_treatment.rds"))
wlog("COA data: ", nrow(coa), " rows")

# Merge on city_clean + state_clean
panel_n_before <- nrow(panel_slim)
panel_slim <- merge(panel_slim,
                     coa[, .(city_clean, state_clean, treatment_year, has_board,
                             invest_power, discipline_power, election_created,
                             selection_method)],
                     by = c("city_clean", "state_clean"),
                     all.x = TRUE)

# For unmatched rows: try fuzzy matching
unmatched_panel <- panel_slim[is.na(treatment_year)]
matched_panel <- panel_slim[!is.na(treatment_year)]

wlog("Exact match: ", nrow(matched_panel), " of ", panel_n_before, " panel rows")
wlog("Unmatched: ", nrow(unmatched_panel))

# For unmatched panel cities, try fuzzy match to treated COA cities only
treated_coa <- coa[treatment_year > 0]
if (nrow(unmatched_panel) > 0 && nrow(treated_coa) > 0) {
  # Get unique unmatched cities
  unmatched_cities <- unique(unmatched_panel[, .(city_clean, state_clean)])

  # For each unmatched city, check if any treated city in same state has similar name
  fuzzy_matches <- data.table()
  for (st in unique(unmatched_cities$state_clean)) {
    um_cities <- unmatched_cities[state_clean == st]$city_clean
    tr_cities <- treated_coa[state_clean == st]$city_clean
    if (length(tr_cities) > 0 && length(um_cities) > 0) {
      dists <- stringdistmatrix(um_cities, tr_cities, method = "jw")
      for (i in seq_along(um_cities)) {
        best_j <- which.min(dists[i, ])
        if (length(best_j) > 0 && dists[i, best_j] < 0.1) {
          fuzzy_matches <- rbind(fuzzy_matches, data.table(
            city_panel = um_cities[i],
            city_coa = tr_cities[best_j],
            state = st,
            dist = dists[i, best_j]
          ))
        }
      }
    }
  }

  if (nrow(fuzzy_matches) > 0) {
    wlog("\nFuzzy matches found (JW distance < 0.1):")
    for (i in 1:nrow(fuzzy_matches)) {
      wlog("  ", fuzzy_matches$city_panel[i], " (", fuzzy_matches$state[i],
           ") -> ", fuzzy_matches$city_coa[i], " (dist=",
           round(fuzzy_matches$dist[i], 4), ")")
    }

    # Apply fuzzy matches
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

# All remaining unmatched panel cities are controls (never-treated)
panel_slim[is.na(treatment_year), treatment_year := 0L]
panel_slim[is.na(has_board), has_board := 0L]
panel_slim[is.na(invest_power), invest_power := 0L]
panel_slim[is.na(discipline_power), discipline_power := 0L]
panel_slim[is.na(election_created), election_created := 0L]

wlog("\nAfter COA merge:")
wlog("  Total panel rows: ", nrow(panel_slim))
wlog("  Treated cities (treatment_year > 0): ",
     length(unique(panel_slim[treatment_year > 0]$city_state)))
wlog("  Control cities (treatment_year == 0): ",
     length(unique(panel_slim[treatment_year == 0]$city_state)))

# CHECK: which treated COA cities did NOT match?
treated_cities_in_panel <- unique(panel_slim[treatment_year > 0, .(city_clean, state_clean)])
treated_cities_in_coa <- coa[treatment_year > 0, .(city_clean, state_clean)]
unmatched_treated <- treated_cities_in_coa[!treated_cities_in_panel, on = c("city_clean", "state_clean")]
wlog("\nTreated COA cities NOT found in panel: ", nrow(unmatched_treated))
if (nrow(unmatched_treated) > 0) {
  for (i in 1:min(nrow(unmatched_treated), 30)) {
    wlog("  WARNING: ", unmatched_treated$city_clean[i], ", ", unmatched_treated$state_clean[i])
  }
}

merge_report(panel_n_before, nrow(coa),
             sum(panel_slim$treatment_year > 0) / length(unique(panel_slim[treatment_year > 0]$year)),
             "Panel ↔ COA Treatment")

# ---------------------------------------------------------------
# Merge Police Killings
# ---------------------------------------------------------------
wlog("\n--- Merging Police Killings ---")
pk <- readRDS(file.path(base_dir, "cleaned_data/police_killings.rds"))
wlog("Police killings data: ", nrow(pk), " rows")

panel_n_before <- nrow(panel_slim)
panel_slim <- merge(panel_slim, pk,
                     by = c("city_clean", "state_clean", "year"),
                     all.x = TRUE)

# Fill unmatched with 0 (city-years with no killings)
panel_slim[is.na(total_killings), total_killings := 0L]
panel_slim[is.na(black_killings), black_killings := 0L]
panel_slim[is.na(nonwhite_killings), nonwhite_killings := 0L]

wlog("After police killings merge:")
wlog("  Panel rows: ", nrow(panel_slim))
wlog("  City-years with killings > 0: ", sum(panel_slim$total_killings > 0))
wlog("  Total killings in panel: ", sum(panel_slim$total_killings))

merge_report(panel_n_before, nrow(pk), sum(panel_slim$total_killings > 0),
             "Panel ↔ Police Killings")

# ---------------------------------------------------------------
# Add Demographics from cities_historical_demographics.rds
# ---------------------------------------------------------------
wlog("\n--- Merging Additional Demographics ---")
demo <- as.data.table(readRDS(file.path(base_dir, "raw_data/cities_historical_demographics.rds")))
wlog("Demographics data: ", nrow(demo), " rows")

# Demographics has place_fips and year — merge on these
# Panel already has percent_black.x etc from prior merge, but demographics
# has time-varying demographics
# Check what the panel already has vs what demo adds

# Merge on place_fips + year
panel_slim[, place_fips_char := as.character(place_fips)]
demo[, place_fips_char := as.character(place_fips)]

panel_n_before <- nrow(panel_slim)
panel_slim <- merge(panel_slim,
                     demo[, .(place_fips_char, year,
                              pct_black_demo = percent_black,
                              pct_white_demo = percent_white,
                              pct_hispanic_demo = percent_hispanic,
                              pct_asian_demo = percent_asian_american,
                              pct_women_demo = percent_women)],
                     by = c("place_fips_char", "year"),
                     all.x = TRUE)

wlog("After demographics merge:")
wlog("  Panel rows: ", nrow(panel_slim))
wlog("  Demographics matched: ", sum(!is.na(panel_slim$pct_black_demo)))
wlog("  Demographics missing: ", sum(is.na(panel_slim$pct_black_demo)))

# Use panel's existing percent_black as fallback
panel_slim[, pct_black := fifelse(!is.na(pct_black_demo), pct_black_demo, percent_black.x)]
panel_slim[, pct_white := fifelse(!is.na(pct_white_demo), pct_white_demo, percent_white.x)]
panel_slim[, pct_hispanic := pct_hispanic_demo]  # May be NA if not available

# ---------------------------------------------------------------
# Save merge diagnostics
# ---------------------------------------------------------------
wlog("\n--- Saving Merge Diagnostics ---")

diag <- data.table(
  Stage = c("Panel base", "Panel + COA Treatment", "Panel + Police Killings", "Panel + Demographics"),
  Left_N = c(nrow(panel_slim), nrow(panel_slim), panel_n_before, nrow(panel_slim)),
  Matched_N = c(nrow(panel_slim),
                length(unique(panel_slim[treatment_year > 0]$city_state)),
                sum(panel_slim$total_killings > 0),
                sum(!is.na(panel_slim$pct_black_demo))),
  Notes = c(paste0(length(unique(panel_slim$city_state)), " unique cities, ",
                    min(panel_slim$year), "-", max(panel_slim$year)),
            paste0(length(unique(panel_slim[treatment_year > 0]$city_state)),
                   " treated cities matched, ",
                   nrow(unmatched_treated), " COA cities unmatched"),
            paste0(sum(panel_slim$total_killings > 0), " city-years with killings"),
            paste0(sum(!is.na(panel_slim$pct_black_demo)), " rows with time-varying demographics"))
)

fwrite(diag, file.path(base_dir, "output/tables/merge_diagnostics.csv"))
wlog("Saved merge diagnostics to output/tables/merge_diagnostics.csv")

# Save merged data
saveRDS(panel_slim, file.path(base_dir, "merged_data/panel_merged.rds"))
wlog("\nFinal merged panel: ", nrow(panel_slim), " rows x ", ncol(panel_slim), " cols")
wlog("Saved to merged_data/panel_merged.rds")
wlog("Step 7 complete.\n")
