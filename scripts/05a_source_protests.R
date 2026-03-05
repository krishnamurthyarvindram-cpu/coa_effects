##############################################################################
# 05a_source_protests.R
# Source and clean protest data from the Crowd Counting Consortium (CCC)
#
# The CCC compiles data on political crowds in the US from Jan 2017 onward.
# We aggregate to city-year counts of:
#   - All protests
#   - Police/racial-justice protests specifically
#   - Estimated total participation
#
# For pre-2017 years we use ACLED US data (2020+) and set earlier = NA.
#
# Data source: https://ash.harvard.edu/programs/crowd-counting-consortium/
# The CCC releases data as Google Sheets / CSV downloads.
# Place the downloaded CSV at: raw_data/ccc_protests.csv
#
# If you don't have the CCC file, this script will attempt to download it.
# Alternatively, you can use ACLED data (requires API key).
#
# Output: merged_data/protests_city_year.rds
##############################################################################

library(data.table)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
raw_dir  <- file.path(base_dir, "raw_data")
out_dir  <- file.path(base_dir, "merged_data")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("======================================================================\n")
cat("Step 05a: Source and Clean Protest Data\n")
cat("======================================================================\n")

# ── 1. Try to load CCC data ─────────────────────────────────────────────────
ccc_path <- file.path(raw_dir, "ccc_protests.csv")

if (!file.exists(ccc_path)) {
  cat("\nCCC protest data not found at:", ccc_path, "\n")
  cat("Attempting to download from Harvard Dataverse...\n")

  # CCC data is hosted at Harvard Ash Center. The URL changes with updates,
  # so we provide multiple fallback strategies.
  download_ok <- FALSE

  # Strategy 1: Try Harvard Dataverse API (CCC dataset)
  # The CCC dataset DOI: 10.7910/DVN/PEWUAJ (example)
  tryCatch({
    # The CCC distributes data via Google Sheets. We try a known export URL.
    # Users should update this URL if it changes.
    url <- "https://github.com/nonviolent-action-lab/crowd-counting-consortium/raw/main/ccc_compiled.csv"
    download.file(url, ccc_path, mode = "wb", quiet = FALSE)
    if (file.info(ccc_path)$size > 1000) {
      download_ok <- TRUE
      cat("Downloaded CCC data from GitHub.\n")
    }
  }, error = function(e) {
    cat("  GitHub download failed:", e$message, "\n")
  })

  if (!download_ok) {
    cat("\n================================================================\n")
    cat("MANUAL DOWNLOAD REQUIRED\n")
    cat("================================================================\n")
    cat("Please download the CCC protest data manually:\n")
    cat("  1. Go to: https://ash.harvard.edu/programs/crowd-counting-consortium/\n")
    cat("  2. Click 'View/Download the Data'\n")
    cat("  3. Download the compiled CSV\n")
    cat("  4. Save as:", ccc_path, "\n")
    cat("  5. Re-run this script\n\n")
    cat("Expected columns: Date, City, State, Type, Claim, Size_Mean, etc.\n")
    cat("================================================================\n")

    # Create a template with expected structure so downstream scripts don't break
    template <- data.table(
      city_lower = character(), state_clean = character(), year = integer(),
      n_protests_total = integer(), n_protests_police = integer(),
      protest_participants_total = numeric(), protest_participants_police = numeric(),
      has_protest_data = integer()
    )
    saveRDS(template, file.path(out_dir, "protests_city_year.rds"))
    cat("Saved empty template to merged_data/protests_city_year.rds\n")
    cat("The adoption predictors script will still run but protest vars will be NA.\n")
    stop("CCC data not available. See instructions above.", call. = FALSE)
  }
}

# ── 2. Read and clean CCC data ──────────────────────────────────────────────
cat("\nReading CCC data from:", ccc_path, "\n")
ccc <- fread(ccc_path, fill = TRUE)
cat("  Raw rows:", format(nrow(ccc), big.mark = ","), "\n")
cat("  Columns:", paste(names(ccc)[1:min(15, ncol(ccc))], collapse = ", "), "...\n")

# CCC column names vary across versions. Standardize.
setnames(ccc, tolower(names(ccc)))

# Identify key columns (CCC uses various naming conventions)
date_col <- intersect(names(ccc), c("date", "event_date", "start_date"))[1]
city_col <- intersect(names(ccc), c("city", "locality", "location"))[1]
state_col <- intersect(names(ccc), c("state", "state_abb", "admin1"))[1]
type_col <- intersect(names(ccc), c("type", "event_type", "claim", "issue"))[1]
size_col <- intersect(names(ccc), c("size_mean", "best", "size_est",
                                     "size_low", "estimated_size",
                                     "adjusted_size", "attendance"))[1]

cat("  Date column:", date_col, "\n")
cat("  City column:", city_col, "\n")
cat("  State column:", state_col, "\n")
cat("  Type/claim column:", type_col, "\n")
cat("  Size column:", size_col, "\n")

if (is.na(city_col) || is.na(state_col)) {
  stop("Cannot identify city/state columns in CCC data. ",
       "Available columns: ", paste(names(ccc), collapse = ", "))
}

# Parse date → year
if (!is.na(date_col)) {
  ccc[, event_date := as.Date(get(date_col), tryFormats = c("%Y-%m-%d", "%m/%d/%Y", "%m/%d/%y"))]
  ccc[, year := as.integer(format(event_date, "%Y"))]
} else {
  # If no date column, try to find year directly
  if ("year" %in% names(ccc)) {
    ccc[, year := as.integer(year)]
  } else {
    stop("No date or year column found in CCC data.")
  }
}

# Standardize city and state
ccc[, city_clean := tolower(trimws(get(city_col)))]
ccc[, state_clean := tolower(trimws(get(state_col)))]

# Convert state names to abbreviations if needed
state_lookup <- data.table(
  state_name = tolower(c(state.name, "district of columbia")),
  state_abb = tolower(c(state.abb, "dc"))
)

if (any(nchar(ccc$state_clean) > 2, na.rm = TRUE)) {
  ccc <- merge(ccc, state_lookup, by.x = "state_clean", by.y = "state_name", all.x = TRUE)
  ccc[!is.na(state_abb), state_clean := state_abb]
  ccc[, state_abb := NULL]
}

# Parse size estimate
if (!is.na(size_col)) {
  ccc[, size_est := suppressWarnings(as.numeric(gsub("[^0-9.]", "", get(size_col))))]
} else {
  ccc[, size_est := NA_real_]
}

# ── 3. Flag police/racial justice protests ───────────────────────────────────
cat("\n--- Classifying protest types ---\n")

# Keywords for police/racial justice protests
police_keywords <- c("polic", "blm", "black lives", "racial justice",
                      "george floyd", "breonna taylor", "police brutal",
                      "police reform", "police account", "police violen",
                      "defund", "oversight", "civilian review",
                      "use of force", "officer involved", "police kill",
                      "police shoot", "justice for", "say their name",
                      "hands up", "i can't breathe", "criminal justice",
                      "police misconduct", "police abuse")

# Check type/claim columns for keywords
if (!is.na(type_col)) {
  ccc[, type_text := tolower(get(type_col))]
} else {
  ccc[, type_text := ""]
}

# Also check claim/issue columns if they exist
claim_cols <- intersect(names(ccc), c("claim", "issues", "claims", "issue", "tags"))
if (length(claim_cols) > 0) {
  ccc[, claim_text := tolower(apply(.SD, 1, paste, collapse = " ")), .SDcols = claim_cols]
} else {
  ccc[, claim_text := ""]
}

ccc[, all_text := paste(type_text, claim_text)]
ccc[, is_police_protest := as.integer(
  grepl(paste(police_keywords, collapse = "|"), all_text)
)]

cat("  Total events:", format(nrow(ccc), big.mark = ","), "\n")
cat("  Police/racial justice protests:", format(sum(ccc$is_police_protest, na.rm = TRUE), big.mark = ","), "\n")
cat("  Year range:", min(ccc$year, na.rm = TRUE), "-", max(ccc$year, na.rm = TRUE), "\n")

# ── 4. Aggregate to city-year ────────────────────────────────────────────────
cat("\n--- Aggregating to city-year ---\n")

# Remove rows with missing city/state/year
ccc_valid <- ccc[!is.na(year) & city_clean != "" & state_clean != "" & nchar(state_clean) == 2]

protests_cy <- ccc_valid[, .(
  n_protests_total         = .N,
  n_protests_police        = sum(is_police_protest, na.rm = TRUE),
  protest_participants_total  = sum(size_est, na.rm = TRUE),
  protest_participants_police = sum(size_est * is_police_protest, na.rm = TRUE),
  max_protest_size          = max(size_est, na.rm = TRUE),
  has_protest_data          = 1L
), by = .(city_lower = city_clean, state_clean, year)]

# Fix infinite values from max of empty sets
protests_cy[is.infinite(max_protest_size), max_protest_size := NA_real_]

# Replace 0 participants where we just have no size data with NA
protests_cy[protest_participants_total == 0, protest_participants_total := NA_real_]
protests_cy[protest_participants_police == 0, protest_participants_police := NA_real_]

cat("  City-year observations:", format(nrow(protests_cy), big.mark = ","), "\n")
cat("  Unique cities:", length(unique(protests_cy$city_lower)), "\n")
cat("  Year range:", min(protests_cy$year), "-", max(protests_cy$year), "\n")

# Log-transform protest counts (for regression)
protests_cy[, log_protests_total := log(n_protests_total + 1)]
protests_cy[, log_protests_police := log(n_protests_police + 1)]

# ── 5. Summary statistics ───────────────────────────────────────────────────
cat("\nProtest data summary (city-year level):\n")
cat(sprintf("  %-35s %10s %10s %10s\n", "Variable", "Mean", "Median", "Max"))
cat(paste(rep("-", 70), collapse = ""), "\n")
for (v in c("n_protests_total", "n_protests_police",
            "protest_participants_total", "max_protest_size")) {
  vals <- protests_cy[[v]]
  vals <- vals[!is.na(vals) & is.finite(vals)]
  if (length(vals) > 0) {
    cat(sprintf("  %-35s %10.1f %10.1f %10.0f\n",
                v, mean(vals), median(vals), max(vals)))
  }
}

# ── 6. Save ──────────────────────────────────────────────────────────────────
out_path <- file.path(out_dir, "protests_city_year.rds")
saveRDS(protests_cy, out_path)
cat("\nSaved:", out_path, "\n")
cat("  ", format(nrow(protests_cy), big.mark = ","), " city-year observations\n")

cat("\nStep 05a complete.\n")
