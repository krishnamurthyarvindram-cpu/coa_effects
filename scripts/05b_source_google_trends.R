##############################################################################
# 05b_source_google_trends.R
# Source Google Trends data for police oversight-related search terms
#
# Uses the gtrendsR package to pull Google Trends data at the US DMA
# (Designated Market Area) level, then maps DMAs to cities in our panel.
#
# Search terms:
#   - "police brutality"
#   - "police reform"
#   - "police oversight" / "civilian oversight"
#   - "defund the police"
#   - "police accountability"
#
# Google Trends returns relative search interest (0-100) at weekly or
# monthly frequency. We aggregate to DMA-year and merge to cities.
#
# NOTE: Google Trends API has rate limits (~5 queries per minute).
#       This script includes wait times between queries.
#       Full run takes ~10-15 minutes.
#
# Required: install.packages("gtrendsR")
# Output:   merged_data/google_trends_city_year.rds
##############################################################################

library(data.table)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
raw_dir  <- file.path(base_dir, "raw_data")
out_dir  <- file.path(base_dir, "merged_data")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

cat("======================================================================\n")
cat("Step 05b: Source Google Trends Data\n")
cat("======================================================================\n")

# ── 0. Check for pre-existing cache ─────────────────────────────────────────
cache_path <- file.path(raw_dir, "google_trends_raw.rds")

if (file.exists(cache_path)) {
  cat("Found cached Google Trends data at:", cache_path, "\n")
  cat("Delete this file to force a fresh download.\n")
  trends_raw <- readRDS(cache_path)
} else {
  # ── 1. Install/load gtrendsR ─────────────────────────────────────────────
  if (!requireNamespace("gtrendsR", quietly = TRUE)) {
    cat("Installing gtrendsR...\n")
    install.packages("gtrendsR", repos = "https://cloud.r-project.org")
  }
  library(gtrendsR)

  # ── 2. Define search terms and time window ────────────────────────────────
  search_terms <- list(
    police_brutality      = "police brutality",
    police_reform         = "police reform",
    police_oversight      = "police oversight",
    civilian_oversight    = "civilian oversight",
    defund_police         = "defund the police",
    police_accountability = "police accountability"
  )

  # Google Trends allows max 5 terms per query.
  # We'll query in batches and use "police brutality" as anchor for scaling.
  time_window <- "2004-01-01 2024-12-31"  # GT available from 2004+

  cat("\nSearch terms:\n")
  for (nm in names(search_terms)) {
    cat("  -", nm, ":", search_terms[[nm]], "\n")
  }
  cat("Time window:", time_window, "\n")

  # ── 3. Query Google Trends by US DMA ──────────────────────────────────────
  cat("\n--- Querying Google Trends (US DMA level) ---\n")
  cat("This may take several minutes due to API rate limits.\n\n")

  trends_raw <- list()

  # Batch 1: police brutality + police reform + police oversight (up to 5 terms)
  batch1_terms <- c("police brutality", "police reform", "police oversight")
  cat("Batch 1:", paste(batch1_terms, collapse = ", "), "\n")
  tryCatch({
    gt1 <- gtrends(
      keyword = batch1_terms,
      geo = "US",
      time = time_window,
      gprop = "web",
      onlyInterest = FALSE  # also get regional data
    )
    trends_raw[["batch1"]] <- gt1
    cat("  Success. Waiting 60s for rate limit...\n")
    Sys.sleep(60)
  }, error = function(e) {
    cat("  ERROR:", e$message, "\n")
    cat("  Google Trends API may be rate-limited. Try again later.\n")
  })

  # Batch 2: civilian oversight + defund + accountability
  batch2_terms <- c("civilian oversight", "defund the police", "police accountability")
  cat("Batch 2:", paste(batch2_terms, collapse = ", "), "\n")
  tryCatch({
    gt2 <- gtrends(
      keyword = batch2_terms,
      geo = "US",
      time = time_window,
      gprop = "web",
      onlyInterest = FALSE
    )
    trends_raw[["batch2"]] <- gt2
    cat("  Success. Waiting 60s for rate limit...\n")
    Sys.sleep(60)
  }, error = function(e) {
    cat("  ERROR:", e$message, "\n")
  })

  # ── 3b. Also query at national level for time series ──────────────────────
  cat("Batch 3: National time series (all terms)...\n")
  tryCatch({
    gt_nat <- gtrends(
      keyword = c("police brutality", "police reform", "police oversight"),
      geo = "US",
      time = time_window,
      gprop = "web",
      onlyInterest = TRUE
    )
    trends_raw[["national"]] <- gt_nat
    Sys.sleep(60)
  }, error = function(e) {
    cat("  ERROR:", e$message, "\n")
  })

  # Also query DMA-level interest_by_region
  # gtrendsR returns interest_by_region when onlyInterest=FALSE
  # For DMA-level, we need to query with resolution="dma"
  cat("Batch 4: DMA-level regional interest...\n")
  for (term_name in names(search_terms)) {
    term <- search_terms[[term_name]]
    cat("  Querying DMA for:", term, "\n")

    tryCatch({
      gt_dma <- gtrends(
        keyword = term,
        geo = "US",
        time = time_window,
        gprop = "web",
        onlyInterest = FALSE
      )

      # Extract interest_by_dma if available
      if (!is.null(gt_dma$interest_by_dma)) {
        trends_raw[[paste0("dma_", term_name)]] <- gt_dma$interest_by_dma
      } else if (!is.null(gt_dma$interest_by_region)) {
        trends_raw[[paste0("region_", term_name)]] <- gt_dma$interest_by_region
      }

      # Also store the time series
      if (!is.null(gt_dma$interest_over_time)) {
        trends_raw[[paste0("time_", term_name)]] <- gt_dma$interest_over_time
      }

      cat("    Done. Waiting 65s...\n")
      Sys.sleep(65)
    }, error = function(e) {
      cat("    ERROR:", e$message, "\n")
      Sys.sleep(30)
    })
  }

  # Cache raw results
  saveRDS(trends_raw, cache_path)
  cat("\nCached raw Google Trends data to:", cache_path, "\n")
}

# ── 4. Process time series data → year-level national trends ─────────────────
cat("\n--- Processing Google Trends time series ---\n")

time_series_list <- list()

for (nm in names(trends_raw)) {
  if (!grepl("^time_", nm)) next
  term_name <- sub("^time_", "", nm)
  dt <- as.data.table(trends_raw[[nm]])

  if (nrow(dt) == 0 || !"hits" %in% names(dt)) next

  # Parse date and extract year
  dt[, date := as.Date(date)]
  dt[, year := as.integer(format(date, "%Y"))]
  dt[, hits_num := suppressWarnings(as.numeric(gsub("<1", "0.5", hits)))]

  # Aggregate to year
  yearly <- dt[, .(
    gt_mean = mean(hits_num, na.rm = TRUE),
    gt_max = max(hits_num, na.rm = TRUE),
    n_weeks = .N
  ), by = year]

  setnames(yearly, "gt_mean", paste0("gt_", term_name, "_mean"))
  setnames(yearly, "gt_max", paste0("gt_", term_name, "_max"))
  yearly[, n_weeks := NULL]

  time_series_list[[term_name]] <- yearly
  cat("  ", term_name, ": ", nrow(yearly), " years\n")
}

# Merge all time series into one national-level yearly dataset
if (length(time_series_list) > 0) {
  gt_national <- Reduce(function(x, y) merge(x, y, by = "year", all = TRUE),
                        time_series_list)
  cat("National Google Trends: ", nrow(gt_national), " years, ",
      ncol(gt_national) - 1, " variables\n")
} else {
  cat("WARNING: No time series data extracted. Creating empty frame.\n")
  gt_national <- data.table(year = 2004:2024)
}

# ── 5. Process DMA/region data → geographic variation ────────────────────────
cat("\n--- Processing DMA/regional data ---\n")

dma_list <- list()

for (nm in names(trends_raw)) {
  if (!grepl("^(dma_|region_)", nm)) next
  term_name <- sub("^(dma_|region_)", "", nm)
  dt <- as.data.table(trends_raw[[nm]])

  if (nrow(dt) == 0 || !"hits" %in% names(dt)) next

  dt[, hits_num := suppressWarnings(as.numeric(gsub("<1", "0.5", hits)))]

  # DMA data has 'location' column with DMA names
  if ("location" %in% names(dt)) {
    setnames(dt, "location", "dma_name", skip_absent = TRUE)
  }

  dt[, dma_clean := tolower(trimws(dma_name))]

  # Keep the term-specific hits
  dt_slim <- dt[, .(dma_clean, hits_num)]
  setnames(dt_slim, "hits_num", paste0("gt_", term_name))

  dma_list[[term_name]] <- dt_slim
  cat("  ", term_name, ": ", nrow(dt_slim), " DMAs\n")
}

# Merge DMA data across terms
if (length(dma_list) > 0) {
  gt_dma <- Reduce(function(x, y) merge(x, y, by = "dma_clean", all = TRUE),
                   dma_list)
  cat("DMA-level data: ", nrow(gt_dma), " DMAs, ",
      ncol(gt_dma) - 1, " variables\n")
} else {
  cat("WARNING: No DMA-level data extracted.\n")
  gt_dma <- data.table(dma_clean = character())
}

# ── 6. Build DMA-to-city crosswalk ──────────────────────────────────────────
cat("\n--- Building DMA-to-city crosswalk ---\n")

# Google Trends DMA names are like "New York NY", "Los Angeles CA", etc.
# We'll build a fuzzy crosswalk to our panel cities.

# Load the panel to get our city list
panel <- as.data.table(readRDS(file.path(out_dir, "analysis_panel.rds")))
city_list <- unique(panel[, .(city_lower, state_clean)])

# Major DMA-to-city mapping (covers the largest DMAs)
# DMA names from Google Trends use the format "City, State" or "City ST"
dma_city_map <- data.table(
  dma_pattern = c(
    "new york", "los angeles", "chicago", "philadelphia", "dallas",
    "houston", "washington", "atlanta", "boston", "phoenix",
    "san francisco", "seattle", "tampa", "minneapolis", "miami",
    "denver", "orlando", "cleveland", "sacramento", "st. louis",
    "portland", "charlotte", "pittsburgh", "raleigh", "baltimore",
    "nashville", "san antonio", "columbus", "milwaukee", "cincinnati",
    "kansas city", "las vegas", "san jose", "austin", "virginia beach",
    "san diego", "jacksonville", "memphis", "oklahoma city", "louisville",
    "richmond", "new orleans", "buffalo", "birmingham", "salt lake city",
    "norfolk", "hartford", "greensboro", "albuquerque", "tucson",
    "fresno", "tulsa", "omaha", "el paso", "detroit", "indianapolis"
  ),
  city_lower = c(
    "new york", "los angeles", "chicago", "philadelphia", "dallas",
    "houston", "washington", "atlanta", "boston", "phoenix",
    "san francisco", "seattle", "tampa", "minneapolis", "miami",
    "denver", "orlando", "cleveland", "sacramento", "st. louis",
    "portland", "charlotte", "pittsburgh", "raleigh", "baltimore",
    "nashville davidson county", "san antonio", "columbus", "milwaukee", "cincinnati",
    "kansas city", "las vegas", "san jose", "austin", "virginia beach",
    "san diego", "jacksonville", "memphis", "oklahoma city", "louisville jefferson county",
    "richmond", "new orleans", "buffalo", "birmingham", "salt lake city",
    "norfolk", "hartford", "greensboro", "albuquerque", "tucson",
    "fresno", "tulsa", "omaha", "el paso", "detroit", "indianapolis"
  )
)

# Match DMA data to cities
if (nrow(gt_dma) > 0) {
  # For each DMA, try to match to our city list via the crosswalk
  gt_dma[, matched_city := NA_character_]

  for (i in 1:nrow(dma_city_map)) {
    pattern <- dma_city_map$dma_pattern[i]
    city <- dma_city_map$city_lower[i]
    gt_dma[grepl(pattern, dma_clean) & is.na(matched_city), matched_city := city]
  }

  n_matched <- sum(!is.na(gt_dma$matched_city))
  cat("  Matched", n_matched, "of", nrow(gt_dma), "DMAs to panel cities\n")

  gt_dma_matched <- gt_dma[!is.na(matched_city)]
  setnames(gt_dma_matched, "matched_city", "city_lower")
} else {
  gt_dma_matched <- data.table(city_lower = character())
}

# ── 7. Combine into city-year dataset ────────────────────────────────────────
cat("\n--- Building city-year Google Trends dataset ---\n")

# Strategy: Each city gets:
#   (a) DMA-level cross-sectional search interest (time-invariant geographic variation)
#   (b) National yearly trends (time-varying, same for all cities)
#   (c) Interaction: DMA interest × national trend (city-year variation)

# Create the panel structure from our data
years <- 2004:2024
city_ids <- unique(city_list[, .(city_lower, state_clean)])

gt_panel <- CJ(city_lower = city_ids$city_lower, year = years)
gt_panel <- merge(gt_panel, city_ids, by = "city_lower", all.x = TRUE, allow.cartesian = TRUE)

# Merge DMA-level geographic interest
gt_cols <- setdiff(names(gt_dma_matched), c("dma_clean", "city_lower"))
if (length(gt_cols) > 0 && nrow(gt_dma_matched) > 0) {
  gt_panel <- merge(gt_panel, gt_dma_matched[, c("city_lower", gt_cols), with = FALSE],
                    by = "city_lower", all.x = TRUE)
  cat("  Merged DMA-level data for", sum(!is.na(gt_panel[[gt_cols[1]]])), "city-year rows\n")
}

# Merge national time series
if (nrow(gt_national) > 0) {
  gt_panel <- merge(gt_panel, gt_national, by = "year", all.x = TRUE)
  cat("  Merged national trends for", nrow(gt_national), "years\n")
}

# Create composite index: average across available terms
gt_mean_cols <- grep("^gt_.*_mean$", names(gt_panel), value = TRUE)
gt_dma_cols <- grep("^gt_(?!.*_mean$|.*_max$)", names(gt_panel), value = TRUE, perl = TRUE)

if (length(gt_mean_cols) > 0) {
  gt_panel[, gt_national_index := rowMeans(.SD, na.rm = TRUE), .SDcols = gt_mean_cols]
}

if (length(gt_dma_cols) > 0) {
  gt_panel[, gt_local_index := rowMeans(.SD, na.rm = TRUE), .SDcols = gt_dma_cols]
}

# Interaction: local salience × national trend
if ("gt_national_index" %in% names(gt_panel) && "gt_local_index" %in% names(gt_panel)) {
  gt_panel[, gt_interaction := gt_local_index * gt_national_index / 100]
}

gt_panel[, has_gt_data := as.integer(
  !is.na(get(names(gt_panel)[min(which(grepl("^gt_", names(gt_panel))))])))
]

cat("\nFinal Google Trends panel:\n")
cat("  Rows:", format(nrow(gt_panel), big.mark = ","), "\n")
cat("  Cities:", length(unique(gt_panel$city_lower)), "\n")
cat("  Years:", min(gt_panel$year), "-", max(gt_panel$year), "\n")
cat("  Columns:", paste(grep("^gt_", names(gt_panel), value = TRUE), collapse = ", "), "\n")

# ── 8. Save ──────────────────────────────────────────────────────────────────
out_path <- file.path(out_dir, "google_trends_city_year.rds")
saveRDS(gt_panel, out_path)
cat("\nSaved:", out_path, "\n")

cat("\nStep 05b complete.\n")
