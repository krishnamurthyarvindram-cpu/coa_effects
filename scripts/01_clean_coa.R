##############################################################################
# 01_clean_coa.R — Step 1: Clean COA Treatment Data
##############################################################################

library(data.table)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 1: Clean COA Treatment Data ==========")

# Load COA data
coa <- fread(file.path(base_dir, "raw_data/coa_creation_data.csv"))
wlog("Raw COA data: ", nrow(coa), " rows x ", ncol(coa), " cols")
wlog("Columns: ", paste(names(coa), collapse=", "))

# Rename columns for easier use
setnames(coa, old = names(coa),
         new = c("ORI_raw", "city_num", "city_raw", "state_raw", "population",
                 "state_abb", "has_oversight_board", "oversight_powers",
                 "charter_found", "link", "year_created",
                 "can_investigate", "can_discipline",
                 "created_via_election", "selection_method"))

wlog("Column mapping applied:")
wlog("  Name -> city_raw")
wlog("  State -> state_raw")
wlog("  STATE_ABB -> state_abb")
wlog("  Year created -> year_created")
wlog("  oversight-board (y/n) -> has_oversight_board")
wlog("  Independently Investigate (y/n) -> can_investigate")
wlog("  Independently Discipline Officers (y/n) -> can_discipline")

# Check year_created
wlog("\nYear created values (raw): ")
wlog("  Unique: ", paste(sort(unique(coa$year_created))[1:20], collapse=", "), "...")

# Clean year_created — convert to numeric
coa[, year_created_clean := suppressWarnings(as.integer(year_created))]
wlog("Year created NAs after conversion: ", sum(is.na(coa$year_created_clean)))
wlog("Non-NA year range: ", min(coa$year_created_clean, na.rm=TRUE), " - ",
     max(coa$year_created_clean, na.rm=TRUE))

# Rows where year_created is empty or non-numeric
no_year <- coa[is.na(year_created_clean)]
wlog("Cities without valid creation year: ", nrow(no_year))
if (nrow(no_year) > 0) {
  wlog("  These cities: ", paste(head(no_year$city_raw, 10), collapse=", "))
}

# Standardize city names
standardize_city <- function(x) {
  x <- tolower(trimws(x))
  # Remove "city", "town", "village" suffixes
  x <- gsub("\\s+city$", "", x)
  x <- gsub("\\s+town$", "", x)
  x <- gsub("\\s+village$", "", x)
  # Standardize common abbreviations
  x <- gsub("^st\\.?\\s+", "saint ", x)
  x <- gsub("^ft\\.?\\s+", "fort ", x)
  x <- gsub("^mt\\.?\\s+", "mount ", x)
  # Remove extra spaces and punctuation
  x <- gsub("[[:punct:]]", " ", x)
  x <- gsub("\\s+", " ", x)
  x <- trimws(x)
  return(x)
}

coa[, city_clean := standardize_city(city_raw)]

# Standardize state — the panel uses lowercase 2-letter abbreviations
coa[, state_clean := tolower(trimws(state_abb))]

# Check oversight board
wlog("\nOversight board distribution:")
print(table(coa$has_oversight_board, useNA="ifany"))

# Clean power variables
coa[, has_board := fifelse(toupper(trimws(has_oversight_board)) == "Y", 1L, 0L)]
coa[, invest_power := fifelse(toupper(trimws(can_investigate)) == "Y", 1L, 0L)]
coa[, discipline_power := fifelse(toupper(trimws(can_discipline)) == "Y", 1L, 0L)]
coa[, election_created := fifelse(toupper(trimws(created_via_election)) == "Y", 1L, 0L)]

# Define treatment: cities with a valid creation year AND oversight board
# Keep only cities that actually have oversight (has_board == 1 or at least a creation year)
treated <- coa[!is.na(year_created_clean) & year_created_clean > 0]
wlog("\nTreated cities (with valid creation year): ", nrow(treated))
wlog("Year distribution of COA creation:")
yr_tab <- table(treated$year_created_clean)
for (yr in names(yr_tab)) wlog("  ", yr, ": ", yr_tab[yr])

# Create treatment_year variable (0 for never-treated, for CSDID gname)
coa[, treatment_year := fifelse(!is.na(year_created_clean) & year_created_clean > 0,
                                 year_created_clean, 0L)]

# Select key columns for merge
coa_clean <- coa[, .(city_clean, state_clean, city_raw, state_raw, state_abb,
                      treatment_year, has_board, invest_power, discipline_power,
                      election_created, selection_method, population)]

# Remove duplicates (some cities might appear multiple times)
# Keep the one with earliest treatment year if duplicated
coa_clean <- coa_clean[order(city_clean, state_clean, -treatment_year)]
coa_clean <- coa_clean[!duplicated(paste0(city_clean, "_", state_clean))]

wlog("\nFinal cleaned COA data: ", nrow(coa_clean), " unique city-state pairs")
wlog("Treated (treatment_year > 0): ", sum(coa_clean$treatment_year > 0))
wlog("Never-treated (treatment_year == 0): ", sum(coa_clean$treatment_year == 0))

# Geographic distribution
wlog("\nState distribution of treated cities:")
state_tab <- table(coa_clean[treatment_year > 0]$state_clean)
for (st in names(sort(state_tab, decreasing=TRUE))[1:15]) {
  wlog("  ", st, ": ", state_tab[st])
}

# Power breakdown
wlog("\nCOA power breakdown (treated cities):")
wlog("  Can investigate: ", sum(coa_clean[treatment_year > 0]$invest_power, na.rm=TRUE))
wlog("  Can discipline: ", sum(coa_clean[treatment_year > 0]$discipline_power, na.rm=TRUE))
wlog("  Has board: ", sum(coa_clean[treatment_year > 0]$has_board, na.rm=TRUE))

# Save
saveRDS(coa_clean, file.path(base_dir, "cleaned_data/coa_treatment.rds"))
fwrite(coa_clean, file.path(base_dir, "cleaned_data/coa_treatment.csv"))
wlog("Saved cleaned COA data to cleaned_data/coa_treatment.rds")
wlog("Step 1 complete.\n")
