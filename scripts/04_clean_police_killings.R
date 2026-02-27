##############################################################################
# 04_clean_police_killings.R — Step 4: Clean Police Killings Data
##############################################################################

library(data.table)
library(readxl)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 4: Clean Police Killings Data ==========")

# Load police killings
pk <- as.data.table(read_excel(file.path(base_dir, "raw_data/police_killings.xlsx")))
wlog("Raw police killings: ", nrow(pk), " rows x ", ncol(pk), " cols")
wlog("Columns: ", paste(names(pk), collapse=", "))

# Identify key columns — from exploration we know the column names
# Date column, City, State, Race
date_col <- grep("Date.*injury|date.*death|Date", names(pk), value=TRUE)[1]
city_col <- grep("Location.*city|city", names(pk), ignore.case=TRUE, value=TRUE)[1]
state_col <- grep("^State$", names(pk), value=TRUE)[1]
race_col <- grep("^Race$", names(pk), value=TRUE)[1]
race_imp_col <- grep("Race with imp", names(pk), value=TRUE)[1]
name_col <- grep("^Name$", names(pk), value=TRUE)[1]

wlog("Date column: ", date_col)
wlog("City column: ", city_col)
wlog("State column: ", state_col)
wlog("Race column: ", race_col)
wlog("Race imputed column: ", race_imp_col)

# Extract year from date
if (!is.null(date_col) && !is.na(date_col)) {
  pk[, year := as.integer(format(as.Date(get(date_col)), "%Y"))]
} else {
  # Try year column
  yr_col <- grep("year", names(pk), ignore.case=TRUE, value=TRUE)[1]
  pk[, year := as.integer(get(yr_col))]
}

wlog("Year range: ", min(pk$year, na.rm=TRUE), " - ", max(pk$year, na.rm=TRUE))
wlog("Total killings: ", nrow(pk))

# Get city and state
pk[, city_raw := get(city_col)]
pk[, state_raw := get(state_col)]

# Use race with imputations if available, else plain race
if (!is.null(race_imp_col) && !is.na(race_imp_col)) {
  pk[, race := get(race_imp_col)]
  # Fill in from plain Race where imputed is NA
  pk[is.na(race), race := get(race_col)]
} else {
  pk[, race := get(race_col)]
}

wlog("\nRace distribution:")
race_tab <- table(pk$race, useNA="ifany")
for (r in names(sort(race_tab, decreasing=TRUE))) {
  wlog("  ", r, ": ", race_tab[r])
}

# Standardize city names (same function as COA)
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

# Create state abbreviation mapping
state_name_to_abb <- c(
  "alabama"="al","alaska"="ak","arizona"="az","arkansas"="ar","california"="ca",
  "colorado"="co","connecticut"="ct","delaware"="de","district of columbia"="dc",
  "florida"="fl","georgia"="ga","hawaii"="hi","idaho"="id","illinois"="il",
  "indiana"="in","iowa"="ia","kansas"="ks","kentucky"="ky","louisiana"="la",
  "maine"="me","maryland"="md","massachusetts"="ma","michigan"="mi","minnesota"="mn",
  "mississippi"="ms","missouri"="mo","montana"="mt","nebraska"="ne","nevada"="nv",
  "new hampshire"="nh","new jersey"="nj","new mexico"="nm","new york"="ny",
  "north carolina"="nc","north dakota"="nd","ohio"="oh","oklahoma"="ok",
  "oregon"="or","pennsylvania"="pa","rhode island"="ri","south carolina"="sc",
  "south dakota"="sd","tennessee"="tn","texas"="tx","utah"="ut","vermont"="vt",
  "virginia"="va","washington"="wa","west virginia"="wv","wisconsin"="wi","wyoming"="wy"
)

pk[, city_clean := standardize_city(city_raw)]

# State: could be full name or abbreviation
pk[, state_lower := tolower(trimws(state_raw))]
pk[, state_clean := fifelse(nchar(state_lower) == 2, state_lower,
                             state_name_to_abb[state_lower])]

# Classify race
pk[, is_black := as.integer(grepl("black|african", race, ignore.case=TRUE))]
pk[, is_nonwhite := as.integer(!grepl("european|white", race, ignore.case=TRUE) & !is.na(race))]

# Aggregate to city-state-year level
pk_agg <- pk[!is.na(year) & !is.na(city_clean) & !is.na(state_clean),
              .(total_killings = .N,
                black_killings = sum(is_black, na.rm=TRUE),
                nonwhite_killings = sum(is_nonwhite, na.rm=TRUE)),
              by = .(city_clean, state_clean, year)]

wlog("\nAggregated police killings:")
wlog("  Unique city-state-year observations: ", nrow(pk_agg))
wlog("  Unique cities: ", length(unique(paste0(pk_agg$city_clean, "_", pk_agg$state_clean))))
wlog("  Year range: ", min(pk_agg$year), " - ", max(pk_agg$year))
wlog("  Total killings in data: ", sum(pk_agg$total_killings))
wlog("  Mean killings per city-year: ", round(mean(pk_agg$total_killings), 2))

# Save
saveRDS(pk_agg, file.path(base_dir, "cleaned_data/police_killings.rds"))
wlog("Saved cleaned police killings to cleaned_data/police_killings.rds")
wlog("Step 4 complete.\n")
