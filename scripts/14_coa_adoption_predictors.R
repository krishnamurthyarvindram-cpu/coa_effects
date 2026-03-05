##############################################################################
# 14_coa_adoption_predictors.R
# What predicts COA adoption?
#
# Cross-sectional and panel models examining city-level predictors of
# civilian oversight agency (COA) creation. Predictors include:
#   1. City demographics (population, racial composition, region)
#   2. Political context (Dem share, party in power, council/mayor
#      composition by race and party)
#   3. Crime statistics (violent crime rate, drug arrest rate, clearances)
#   4. Police violence (police killings per capita, racial disparities)
#   5. Protest activity (total protests, police/BLM protests — from CCC)
#   6. Google Trends (search interest for police reform/oversight terms)
#
# Models:
#   A. Cross-sectional logit/LPM: Ever-adopt COA by 2025 (city-level)
#   B. Panel hazard/LPM: Year of COA adoption (city-year with year FEs),
#      conditional on not yet having adopted
#   C. Summary statistics and balance tables by adoption status
#
# Prerequisites: Run 05a_source_protests.R and 05b_source_google_trends.R
# Required packages: data.table, fixest, ggplot2, sandwich
##############################################################################

library(data.table)
library(ggplot2)

# ── Paths ────────────────────────────────────────────────────────────────────
base_dir <- "C:/Users/arvind/Desktop/coa_effects"
output_dir <- file.path(base_dir, "output")
tables_dir <- file.path(output_dir, "tables")
figures_dir <- file.path(output_dir, "figures")
log_file <- file.path(output_dir, "coa_adoption_predictors_log.txt")

dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

cat("", file = log_file)

wlog("======================================================================")
wlog("What Predicts COA Adoption? (R version)")
wlog("======================================================================")

# ── 1. Load data ─────────────────────────────────────────────────────────────
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
wlog("Analysis panel: ", format(nrow(panel), big.mark = ","), " city-year obs, ",
     length(unique(panel$agency_id)), " cities")

# Load LEDB candidate-level data for council/mayor composition
ledb <- fread(file.path(base_dir, "raw_data/ledb_candidatelevel.csv"))
wlog("LEDB loaded: ", format(nrow(ledb), big.mark = ","), " rows")

# ── 2. Build city council and mayor composition from LEDB ────────────────────
wlog("\n--- Building council/mayor composition from LEDB ---")

# City Council winners
cc_win <- ledb[office_consolidated == "City Council" & winner == "win"]
cc_win[, geo_clean := tolower(trimws(geo_name))]
cc_win[, state_clean := tolower(trimws(state_abb))]

council_comp <- cc_win[, .(
  council_n_members = .N,
  council_pct_black = mean(prob_black, na.rm = TRUE),
  council_pct_hispanic = mean(prob_hispanic, na.rm = TRUE),
  council_pct_white = mean(prob_white, na.rm = TRUE),
  council_pct_female = mean(prob_female, na.rm = TRUE),
  council_pct_dem = mean(prob_democrat, na.rm = TRUE)
), by = .(geo_clean, state_clean, year)]

wlog("Council composition: ", format(nrow(council_comp), big.mark = ","),
     " city-year obs from ", length(unique(council_comp$geo_clean)), " cities")

# Mayor winners
m_win <- ledb[office_consolidated == "Mayor" & winner == "win"]
m_win[, geo_clean := tolower(trimws(geo_name))]
m_win[, state_clean := tolower(trimws(state_abb))]

mayor_comp <- m_win[, .(
  mayor_black = mean(prob_black, na.rm = TRUE),
  mayor_hispanic = mean(prob_hispanic, na.rm = TRUE),
  mayor_female = mean(prob_female, na.rm = TRUE),
  mayor_dem = mean(prob_democrat, na.rm = TRUE)
), by = .(geo_clean, state_clean, year)]

wlog("Mayor composition: ", format(nrow(mayor_comp), big.mark = ","),
     " city-year obs from ", length(unique(mayor_comp$geo_clean)), " cities")

# ── 3. Merge council/mayor composition onto panel ────────────────────────────
wlog("\n--- Merging council/mayor composition onto panel ---")

# Prepare panel merge keys
panel[, geo_clean := tolower(trimws(city_lower))]
panel[, st_clean := tolower(trimws(state_clean))]

# Merge council
setnames(council_comp, "state_clean", "st_clean")
panel <- merge(panel, council_comp, by.x = c("geo_clean", "st_clean", "year"),
               by.y = c("geo_clean", "st_clean", "year"), all.x = TRUE,
               suffixes = c("", "_cc"))

# Remove any duplicated cols from merge
dup_cols <- grep("_cc$", names(panel), value = TRUE)
if (length(dup_cols) > 0) panel[, (dup_cols) := NULL]

# Merge mayor
setnames(mayor_comp, "state_clean", "st_clean")
panel <- merge(panel, mayor_comp, by.x = c("geo_clean", "st_clean", "year"),
               by.y = c("geo_clean", "st_clean", "year"), all.x = TRUE,
               suffixes = c("", "_m"))

dup_cols <- grep("_m$", names(panel), value = TRUE)
if (length(dup_cols) > 0) panel[, (dup_cols) := NULL]

# Forward-fill within city (election results persist until next election)
setorder(panel, agency_id, year)

council_cols <- c("council_n_members", "council_pct_black", "council_pct_hispanic",
                  "council_pct_white", "council_pct_female", "council_pct_dem")
mayor_cols <- c("mayor_black", "mayor_hispanic", "mayor_female", "mayor_dem")

# Only fill columns that exist
fill_cols <- intersect(c(council_cols, mayor_cols), names(panel))

nafill_locf <- function(x) {
  # Last observation carried forward
  idx <- which(!is.na(x))
  if (length(idx) == 0) return(x)
  x[idx[1]:length(x)] <- x[idx][cumsum(!is.na(x[idx[1]:length(x)]))]
  # More robust: use zoo::na.locf logic
  for (i in 2:length(x)) {
    if (is.na(x[i]) && !is.na(x[i - 1])) x[i] <- x[i - 1]
  }
  return(x)
}

for (col in fill_cols) {
  if (col %in% names(panel)) {
    panel[, (col) := nafill_locf(get(col)), by = agency_id]
  }
}

cc_matched <- sum(!is.na(panel[[fill_cols[1]]]))
wlog("Council comp matched: ", format(cc_matched, big.mark = ","), " / ",
     format(nrow(panel), big.mark = ","), " panel rows (",
     round(cc_matched / nrow(panel) * 100, 1), "%)")

if ("mayor_black" %in% names(panel)) {
  m_matched <- sum(!is.na(panel$mayor_black))
  wlog("Mayor comp matched: ", format(m_matched, big.mark = ","), " / ",
       format(nrow(panel), big.mark = ","), " panel rows (",
       round(m_matched / nrow(panel) * 100, 1), "%)")
}

# ── 4. Construct predictor variables ─────────────────────────────────────────
panel[, log_pop := log(pmax(population, 1))]
panel[, killings_pc := police_killings_pc]
panel[, black_arrest_disparity := black_share_violent_arrests]
panel[, dem_power := as.numeric(dem_in_power)]

south_states <- c("al", "ar", "fl", "ga", "ky", "la", "ms", "nc", "sc", "tn", "tx", "va", "wv")
panel[, south := as.integer(st_clean %in% south_states)]

# ── 4b. Merge Protest Data (from 05a_source_protests.R) ─────────────────────
wlog("\n--- Merging Protest Data ---")

protests_path <- file.path(base_dir, "merged_data/protests_city_year.rds")
if (file.exists(protests_path)) {
  protests <- as.data.table(readRDS(protests_path))
  wlog("Protest data loaded: ", nrow(protests), " city-year obs")

  if (nrow(protests) > 0 && "city_lower" %in% names(protests)) {
    # Standardize merge keys
    protests[, city_lower := tolower(trimws(city_lower))]
    protests[, state_clean := tolower(trimws(state_clean))]

    # Merge protests onto panel using city_lower (panel's geo_clean) + state
    panel_pre_n <- nrow(panel)
    panel <- merge(panel, protests,
                   by.x = c("geo_clean", "st_clean", "year"),
                   by.y = c("city_lower", "state_clean", "year"),
                   all.x = TRUE)

    # Fill missing protest years with 0 (no protests = 0 protests, not NA)
    protest_vars <- c("n_protests_total", "n_protests_police",
                      "protest_participants_total", "protest_participants_police",
                      "log_protests_total", "log_protests_police")
    for (pv in intersect(protest_vars, names(panel))) {
      panel[is.na(get(pv)) & year >= 2017, (pv) := 0]
    }

    n_matched <- sum(!is.na(panel$n_protests_total) & panel$n_protests_total > 0)
    wlog("  Protest data matched: ", format(n_matched, big.mark = ","),
         " city-years with > 0 protests")
    wlog("  Coverage: years ", min(protests$year, na.rm = TRUE), "-",
         max(protests$year, na.rm = TRUE))
  } else {
    wlog("  Protest data is empty. Protest variables will be NA.")
  }
} else {
  wlog("  Protest data not found. Run 05a_source_protests.R first.")
  wlog("  Protest variables will be NA.")
}

# Ensure protest vars exist (as NA if not merged)
for (pv in c("n_protests_total", "n_protests_police", "log_protests_total",
             "log_protests_police")) {
  if (!pv %in% names(panel)) panel[, (pv) := NA_real_]
}

# ── 4c. Merge Google Trends Data (from 05b_source_google_trends.R) ───────────
wlog("\n--- Merging Google Trends Data ---")

gt_path <- file.path(base_dir, "merged_data/google_trends_city_year.rds")
if (file.exists(gt_path)) {
  gt_data <- as.data.table(readRDS(gt_path))
  wlog("Google Trends data loaded: ", nrow(gt_data), " city-year obs")

  if (nrow(gt_data) > 0 && "city_lower" %in% names(gt_data)) {
    # Identify GT columns to merge (exclude merge keys)
    gt_merge_cols <- grep("^gt_", names(gt_data), value = TRUE)
    gt_merge_dt <- unique(gt_data[, c("city_lower", "year", gt_merge_cols), with = FALSE])

    panel <- merge(panel, gt_merge_dt,
                   by.x = c("geo_clean", "year"),
                   by.y = c("city_lower", "year"),
                   all.x = TRUE)

    n_gt <- sum(!is.na(panel[[gt_merge_cols[1]]]))
    wlog("  Google Trends matched: ", format(n_gt, big.mark = ","), " city-years")
    wlog("  GT columns added: ", paste(gt_merge_cols, collapse = ", "))
  } else {
    wlog("  Google Trends data is empty.")
  }
} else {
  wlog("  Google Trends data not found. Run 05b_source_google_trends.R first.")
  wlog("  GT variables will be NA.")
}

# Ensure key GT vars exist
for (gv in c("gt_national_index", "gt_local_index", "gt_interaction")) {
  if (!gv %in% names(panel)) panel[, (gv) := NA_real_]
}

# ══════════════════════════════════════════════════════════════════════════════
# PART A: Cross-Sectional Analysis — What predicts ever adopting a COA?
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("PART A: Cross-Sectional Analysis — What predicts ever adopting a COA?")
wlog("======================================================================")

# Restrict to 2000-2020 window
panel_window <- panel[year >= 2000 & year <= 2020]

# Pre-period: for treated cities, years before treatment; for control, 2000-2015
panel_window[, pre_period := fifelse(
  treatment_year > 0 & treatment_year >= 2000,
  year < treatment_year,
  fifelse(treatment_year > 0, FALSE, year <= 2015)
)]

pre_data <- panel_window[pre_period == TRUE]

# Collapse to city-level averages
predictor_vars <- c("log_pop", "pct_black", "pct_hispanic", "south",
                     "violent_crime_pc", "drug_arrests_pc", "discretionary_arrests_pc",
                     "violent_clearance_rate", "property_clearance_rate",
                     "killings_pc", "black_arrest_disparity",
                     "dem_power",
                     "council_pct_black", "council_pct_dem", "council_pct_female",
                     "mayor_black", "mayor_dem", "mayor_female",
                     "log_protests_total", "log_protests_police",
                     "gt_national_index", "gt_local_index")

# Only keep vars that exist
predictor_vars <- predictor_vars[predictor_vars %in% names(pre_data)]

city_cross <- pre_data[, c(lapply(.SD, function(x) mean(x, na.rm = TRUE)),
                            list(treatment_year = first(treatment_year),
                                 n_pre_years = .N)),
                        by = agency_id, .SDcols = predictor_vars]

city_cross[, ever_adopt := as.integer(treatment_year >= 2000)]

wlog("Cross-sectional dataset: ", nrow(city_cross), " cities")
wlog("  Adopted COA (2000+): ", sum(city_cross$ever_adopt))
wlog("  Never adopted: ", sum(city_cross$ever_adopt == 0))

# ── Cross-sectional regression helper ────────────────────────────────────────
results_list <- list()

run_cross_model <- function(data, predictors, label, model_type = "logit") {
  cols <- c("ever_adopt", predictors)
  cols <- cols[cols %in% names(data)]
  df <- na.omit(data[, ..cols])

  if (length(unique(df$ever_adopt)) < 2) {
    wlog("  [", label, "] Skipping: no variation in outcome")
    return(NULL)
  }

  y <- df$ever_adopt
  X <- as.matrix(df[, ..predictors])
  X <- cbind(const = 1, X)

  if (model_type == "logit") {
    fit <- tryCatch({
      glm(ever_adopt ~ ., data = df, family = binomial(link = "logit"))
    }, error = function(e) {
      wlog("  [", label, "] Logit failed: ", e$message, ". Falling back to LPM.")
      NULL
    })

    if (is.null(fit)) {
      model_type <- "lpm"
    }
  }

  if (model_type == "lpm") {
    fit <- lm(ever_adopt ~ ., data = df)
  }

  # Get robust SEs for LPM
  if (model_type == "lpm" && requireNamespace("sandwich", quietly = TRUE)) {
    library(sandwich)
    library(lmtest)
    ct <- coeftest(fit, vcov = vcovHC(fit, type = "HC1"))
  } else {
    ct <- summary(fit)$coefficients
  }

  wlog("\n  [", label, "] (", toupper(model_type), ", N=", nrow(df), ")")
  wlog(sprintf("  %-35s %10s %10s %8s", "Variable", "Coef", "SE", "p"))
  wlog("  ", paste(rep("-", 65), collapse = ""))

  for (v in predictors) {
    if (v %in% rownames(ct)) {
      coef_val <- ct[v, 1]
      se_val <- ct[v, 2]
      p_val <- ct[v, ncol(ct)]  # last column is p-value

      stars <- ""
      if (p_val < 0.01) stars <- "***"
      else if (p_val < 0.05) stars <- "**"
      else if (p_val < 0.10) stars <- "*"

      wlog(sprintf("  %-35s %10.5f %10.5f %8.4f %s", v, coef_val, se_val, p_val, stars))

      results_list[[length(results_list) + 1]] <<- data.table(
        panel = "A. Cross-Section",
        model = label,
        model_type = toupper(model_type),
        variable = v,
        coef = round(coef_val, 6),
        se = round(se_val, 6),
        p_value = round(p_val, 4),
        significance = stars,
        n_obs = nrow(df),
        n_adopt = sum(y)
      )
    }
  }

  if (model_type == "logit") {
    null_dev <- fit$null.deviance
    res_dev <- fit$deviance
    pseudo_r2 <- 1 - res_dev / null_dev
    wlog(sprintf("  Pseudo R²: %.4f", pseudo_r2))
  } else {
    wlog(sprintf("  R²: %.4f", summary(fit)$r.squared))
  }

  return(fit)
}

# Model A1: City Demographics
wlog("\n── A1: City Demographics ──")
demo_vars <- c("log_pop", "pct_black", "pct_hispanic", "south")
demo_vars <- demo_vars[demo_vars %in% names(city_cross)]
run_cross_model(city_cross, demo_vars, "Demographics Only")

# Model A2: Demographics + Crime/Policing
wlog("\n── A2: Demographics + Crime/Policing ──")
crime_vars <- c(demo_vars, intersect(c("violent_crime_pc", "drug_arrests_pc",
                                        "killings_pc", "black_arrest_disparity"),
                                      names(city_cross)))
run_cross_model(city_cross, crime_vars, "Demographics + Crime")

# Model A3: Demographics + Political Context
wlog("\n── A3: Demographics + Political Context ──")
pol_vars <- c(demo_vars, intersect(c("dem_power", "council_pct_dem", "council_pct_black",
                                      "mayor_dem", "mayor_black"),
                                    names(city_cross)))
run_cross_model(city_cross, pol_vars, "Demographics + Politics")

# Model A4: Protest Activity
wlog("\n── A4: Demographics + Protest Activity ──")
protest_vars <- c(demo_vars, intersect(c("log_protests_total", "log_protests_police",
                                          "killings_pc"),
                                        names(city_cross)))
run_cross_model(city_cross, protest_vars, "Demographics + Protests")

# Model A5: Google Trends
wlog("\n── A5: Demographics + Google Trends ──")
gt_vars <- c(demo_vars, intersect(c("gt_national_index", "gt_local_index",
                                      "killings_pc"),
                                    names(city_cross)))
run_cross_model(city_cross, gt_vars, "Demographics + Google Trends")

# Model A6: Kitchen Sink (all predictors)
wlog("\n── A6: Full Model ──")
full_vars <- c("log_pop", "pct_black", "pct_hispanic", "south",
               "violent_crime_pc", "drug_arrests_pc",
               "killings_pc", "black_arrest_disparity",
               "dem_power", "council_pct_dem", "council_pct_black",
               "mayor_dem", "mayor_black",
               "log_protests_police", "gt_local_index")
full_vars <- full_vars[full_vars %in% names(city_cross)]
run_cross_model(city_cross, full_vars, "Full Model")

# Model A7: LPM for robustness
wlog("\n── A7: LPM — Full Model ──")
run_cross_model(city_cross, full_vars, "Full Model (LPM)", model_type = "lpm")

# ══════════════════════════════════════════════════════════════════════════════
# PART B: Panel Hazard Model — When do cities adopt?
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("PART B: Panel Hazard Model — Year of COA Adoption")
wlog("======================================================================")

# Build discrete-time hazard panel: each city-year until adoption
hazard_panel <- copy(panel_window)
hazard_panel[, adopt_this_year := as.integer(treatment_year > 0 & year == treatment_year)]

# Drop post-adoption years for treated cities
hazard_panel <- hazard_panel[treatment_year == 0 | year <= treatment_year]

wlog("Hazard panel: ", format(nrow(hazard_panel), big.mark = ","), " city-year obs")
wlog("  Adoption events: ", sum(hazard_panel$adopt_this_year))
wlog("  Cities: ", length(unique(hazard_panel$agency_id)))

# ── Hazard model helper (LPM + year FEs, clustered SEs) ─────────────────────
if (!requireNamespace("fixest", quietly = TRUE)) {
  install.packages("fixest", repos = "https://cloud.r-project.org")
}
library(fixest)

run_hazard_model <- function(data, predictors, label) {
  predictors <- predictors[predictors %in% names(data)]
  cols <- c("adopt_this_year", "agency_id", "year", predictors)
  df <- na.omit(data[, ..cols])

  if (length(unique(df$adopt_this_year)) < 2) {
    wlog("  [", label, "] Skipping: no variation in outcome")
    return(NULL)
  }

  # LPM with year FEs and clustered SEs
  fml <- as.formula(paste0("adopt_this_year ~ ",
                            paste(predictors, collapse = " + "),
                            " | year"))

  fit <- tryCatch({
    feols(fml, data = df, cluster = ~agency_id)
  }, error = function(e) {
    wlog("  [", label, "] ERROR: ", e$message)
    NULL
  })

  if (is.null(fit)) return(NULL)

  ct <- summary(fit)$coeftable

  wlog(sprintf("\n  [%s] (LPM + Year FEs, N=%d, Clusters=%d)",
               label, nobs(fit), length(unique(df$agency_id))))
  wlog(sprintf("  %-35s %10s %10s %8s", "Variable", "Coef", "SE", "p"))
  wlog("  ", paste(rep("-", 65), collapse = ""))

  for (v in predictors) {
    if (v %in% rownames(ct)) {
      coef_val <- ct[v, "Estimate"]
      se_val <- ct[v, "Std. Error"]
      p_val <- ct[v, "Pr(>|t|)"]

      stars <- ""
      if (p_val < 0.01) stars <- "***"
      else if (p_val < 0.05) stars <- "**"
      else if (p_val < 0.10) stars <- "*"

      wlog(sprintf("  %-35s %10.5f %10.5f %8.4f %s", v, coef_val, se_val, p_val, stars))

      results_list[[length(results_list) + 1]] <<- data.table(
        panel = "B. Panel Hazard",
        model = label,
        model_type = "LPM+YearFE",
        variable = v,
        coef = round(coef_val, 6),
        se = round(se_val, 6),
        p_value = round(p_val, 4),
        significance = stars,
        n_obs = nobs(fit),
        n_adopt = sum(df$adopt_this_year)
      )
    }
  }

  wlog(sprintf("  R² (within): %.4f", fitstat(fit, "r2")[[1]]))
  return(fit)
}

# Model B1: City Demographics
wlog("\n── B1: City Demographics ──")
run_hazard_model(hazard_panel, demo_vars, "Demographics Only")

# Model B2: Demographics + Crime/Policing
wlog("\n── B2: Demographics + Crime/Policing ──")
hazard_crime_vars <- c(demo_vars, "violent_crime_pc", "drug_arrests_pc",
                       "killings_pc", "black_arrest_disparity")
run_hazard_model(hazard_panel, hazard_crime_vars, "Demographics + Crime")

# Model B3: Demographics + Political Context
wlog("\n── B3: Demographics + Political Context ──")
hazard_pol_vars <- c(demo_vars, "dem_power", "council_pct_dem",
                     "council_pct_black", "mayor_dem", "mayor_black")
run_hazard_model(hazard_panel, hazard_pol_vars, "Demographics + Politics")

# Model B4: Protest Activity
wlog("\n── B4: Demographics + Protest Activity ──")
hazard_protest_vars <- c(demo_vars, "log_protests_total", "log_protests_police", "killings_pc")
run_hazard_model(hazard_panel, hazard_protest_vars, "Demographics + Protests")

# Model B5: Google Trends
wlog("\n── B5: Demographics + Google Trends ──")
hazard_gt_vars <- c(demo_vars, "gt_national_index", "gt_local_index", "killings_pc")
run_hazard_model(hazard_panel, hazard_gt_vars, "Demographics + Google Trends")

# Model B6: Full Model (all predictors)
wlog("\n── B6: Full Model ──")
hazard_full_vars <- c("log_pop", "pct_black", "pct_hispanic", "south",
                      "violent_crime_pc", "drug_arrests_pc",
                      "killings_pc", "black_arrest_disparity",
                      "dem_power", "council_pct_dem", "council_pct_black",
                      "mayor_dem", "mayor_black",
                      "log_protests_police", "gt_local_index")
run_hazard_model(hazard_panel, hazard_full_vars, "Full Model")

# Model B7: Full Model with Lagged Predictors (t-1) to avoid simultaneity
wlog("\n── B7: Full Model with Lagged Predictors ──")

lag_vars <- c("violent_crime_pc", "drug_arrests_pc", "killings_pc",
              "black_arrest_disparity", "council_pct_dem", "council_pct_black",
              "mayor_dem", "mayor_black",
              "log_protests_police", "gt_local_index")
lag_vars <- lag_vars[lag_vars %in% names(hazard_panel)]

setorder(hazard_panel, agency_id, year)
for (v in lag_vars) {
  lag_name <- paste0("L_", v)
  hazard_panel[, (lag_name) := shift(get(v), n = 1, type = "lag"), by = agency_id]
}

lagged_full_vars <- c("log_pop", "pct_black", "pct_hispanic", "south",
                      paste0("L_", lag_vars))
run_hazard_model(hazard_panel, lagged_full_vars, "Full Model (Lagged)")

# ══════════════════════════════════════════════════════════════════════════════
# PART C: Summary Statistics by Adoption Status
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("PART C: Summary Statistics by Adoption Status")
wlog("======================================================================")

summary_vars <- c("log_pop", "pct_black", "pct_hispanic", "south",
                  "violent_crime_pc", "drug_arrests_pc",
                  "killings_pc", "black_arrest_disparity",
                  "dem_power", "council_pct_dem", "council_pct_black",
                  "mayor_dem", "mayor_black",
                  "log_protests_total", "log_protests_police",
                  "gt_national_index", "gt_local_index")
summary_vars <- summary_vars[summary_vars %in% names(city_cross)]

summary_rows <- list()

for (v in summary_vars) {
  for (adopt_val in c(1, 0)) {
    adopt_label <- ifelse(adopt_val == 1, "Adopted COA", "Never Adopted")
    vals <- city_cross[ever_adopt == adopt_val, get(v)]
    vals <- vals[!is.na(vals)]
    if (length(vals) == 0) next

    summary_rows[[length(summary_rows) + 1]] <- data.table(
      variable = v, group = adopt_label,
      n = length(vals),
      mean = round(mean(vals), 4),
      sd = round(sd(vals), 4),
      median = round(median(vals), 4)
    )
  }
}

# Difference-in-means tests
wlog(sprintf("\n%-35s %12s %12s %10s %8s", "Variable", "Adopted", "Never", "Diff", "p-val"))
wlog(paste(rep("-", 80), collapse = ""))

for (v in summary_vars) {
  adopt_vals <- city_cross[ever_adopt == 1, get(v)]
  adopt_vals <- adopt_vals[!is.na(adopt_vals)]
  control_vals <- city_cross[ever_adopt == 0, get(v)]
  control_vals <- control_vals[!is.na(control_vals)]

  if (length(adopt_vals) > 5 & length(control_vals) > 5) {
    tt <- t.test(adopt_vals, control_vals)
    diff_val <- mean(adopt_vals) - mean(control_vals)
    p_val <- tt$p.value

    stars <- ""
    if (p_val < 0.01) stars <- "***"
    else if (p_val < 0.05) stars <- "**"
    else if (p_val < 0.10) stars <- "*"

    wlog(sprintf("%-35s %12.4f %12.4f %10.4f %8.4f %s",
                 v, mean(adopt_vals), mean(control_vals), diff_val, p_val, stars))

    summary_rows[[length(summary_rows) + 1]] <- data.table(
      variable = v, group = "Difference",
      n = length(adopt_vals) + length(control_vals),
      mean = round(diff_val, 4),
      sd = round(p_val, 4),
      median = NA_real_
    )
  }
}

summary_dt <- rbindlist(summary_rows, fill = TRUE)

# ── Visualization: coefficient plot for full model ───────────────────────────
wlog("\n--- Generating coefficient plots ---")

if (length(results_list) > 0) {
  res_dt <- rbindlist(results_list, fill = TRUE)

  # Plot: Full model coefficients (cross-section logit)
  full_cs <- res_dt[panel == "A. Cross-Section" & model == "Full Model" & variable != "(Intercept)"]
  if (nrow(full_cs) > 0) {
    full_cs[, ci_lower := coef - 1.96 * se]
    full_cs[, ci_upper := coef + 1.96 * se]
    full_cs[, variable := factor(variable, levels = rev(variable))]

    p1 <- ggplot(full_cs, aes(x = coef, y = variable)) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "gray60") +
      geom_errorbarh(aes(xmin = ci_lower, xmax = ci_upper), height = 0.2, color = "steelblue") +
      geom_point(color = "steelblue", size = 2) +
      labs(title = "Logit: Predictors of COA Adoption (Cross-Section)",
           x = "Coefficient", y = "") +
      theme_minimal()

    ggsave(file.path(figures_dir, "coa_adoption_coefplot_cross_section.png"),
           p1, width = 9, height = 6, dpi = 150)
    wlog("Saved cross-section coefficient plot")
  }

  # Plot: Full model coefficients (panel hazard)
  full_hz <- res_dt[panel == "B. Panel Hazard" & model == "Full Model" & variable != "(Intercept)"]
  if (nrow(full_hz) > 0) {
    full_hz[, ci_lower := coef - 1.96 * se]
    full_hz[, ci_upper := coef + 1.96 * se]
    full_hz[, variable := factor(variable, levels = rev(variable))]

    p2 <- ggplot(full_hz, aes(x = coef, y = variable)) +
      geom_vline(xintercept = 0, linetype = "dashed", color = "gray60") +
      geom_errorbarh(aes(xmin = ci_lower, xmax = ci_upper), height = 0.2, color = "darkred") +
      geom_point(color = "darkred", size = 2) +
      labs(title = "LPM Hazard: Predictors of COA Adoption (Panel)",
           x = "Coefficient (LPM + Year FEs, Clustered SEs)", y = "") +
      theme_minimal()

    ggsave(file.path(figures_dir, "coa_adoption_coefplot_hazard.png"),
           p2, width = 9, height = 6, dpi = 150)
    wlog("Saved hazard model coefficient plot")
  }
}

# ── Save results ─────────────────────────────────────────────────────────────
wlog("\n--- Saving results ---")

if (length(results_list) > 0) {
  res_dt <- rbindlist(results_list, fill = TRUE)
  fwrite(res_dt, file.path(tables_dir, "coa_adoption_predictors.csv"))
  wlog("Saved ", nrow(res_dt), " regression results to coa_adoption_predictors.csv")
}

fwrite(summary_dt, file.path(tables_dir, "coa_adoption_balance_table.csv"))
wlog("Saved balance table")

# ── Print all regression results ─────────────────────────────────────────────
wlog("\n======================================================================")
wlog("ALL REGRESSION RESULTS")
wlog("======================================================================")

if (length(results_list) > 0) {
  for (i in 1:nrow(res_dt)) {
    r <- res_dt[i]
    wlog(sprintf("  %-18s %-30s %-35s %10.5f %10.5f %8.4f %s",
                 r$panel, r$model, r$variable, r$coef, r$se, r$p_value, r$significance))
  }
}

wlog("\n======================================================================")
wlog("Analysis complete.")
wlog("======================================================================")
wlog("\nOutput files:")
wlog("  - output/tables/coa_adoption_predictors.csv")
wlog("  - output/tables/coa_adoption_balance_table.csv")
wlog("  - output/figures/coa_adoption_coefplot_cross_section.png")
wlog("  - output/figures/coa_adoption_coefplot_hazard.png")
wlog("  - output/coa_adoption_predictors_log.txt")

wlog("\nNote: Protest data requires CCC download (see 05a_source_protests.R).")
wlog("Google Trends data requires gtrendsR + API access (see 05b_source_google_trends.R).")
wlog("If these data files are missing, protest/GT variables will be NA and")
wlog("models using them will run on reduced samples or be skipped.")
