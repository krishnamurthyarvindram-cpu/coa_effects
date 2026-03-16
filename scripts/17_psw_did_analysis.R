##############################################################################
# 17_psw_did_analysis.R — Propensity Score Weighting (PSW) + DiD Estimation
#
# Re-estimates PanelMatch and CSDID models for:
#   - drug_arrests_pc (arrests)
#   - discretionary_arrests_pc (discretionary arrests)
#   - police_killings_pc (police killings)
#
# using inverse propensity score weighting (IPW) based on pre-treatment:
#   - City size (log_population)
#   - Demographics (pct_black, pct_white, pct_hispanic)
#   - Police spending per capita (if available from Austerity.dta)
#   - Violent crime rate (violent_crime_pc)
#
# Required packages: data.table, MatchIt, PanelMatch, did, ggplot2, fixest
##############################################################################

library(data.table)
library(ggplot2)

# ── Paths ────────────────────────────────────────────────────────────────────
base_dir <- getwd()
if (file.exists("C:/Users/arvind/Desktop/coa_effects/merged_data/analysis_panel.rds")) {
  base_dir <- "C:/Users/arvind/Desktop/coa_effects"
}
log_file <- file.path(base_dir, "output/psw_did_log.txt")

dir.create(file.path(base_dir, "output/tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(base_dir, "output/figures"), recursive = TRUE, showWarnings = FALSE)

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

cat("", file = log_file)

wlog("======================================================================")
wlog("STEP 17: Propensity Score Weighting (PSW) + DiD Analysis")
wlog("======================================================================")
wlog("Date: ", Sys.time())

# ── 1. Load Data ─────────────────────────────────────────────────────────────
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]
wlog("Panel loaded: ", nrow(panel), " rows x ", ncol(panel), " cols")
wlog("Unique agencies: ", length(unique(panel$agency_id)))
wlog("Treated: ", length(unique(panel[treated == 1]$agency_id)))
wlog("Control: ", length(unique(panel[treated == 0]$agency_id)))
wlog("Year range: ", min(panel$year), " - ", max(panel$year))

# ── 2. Try to Load Police Spending from Austerity.dta ───────────────────────
wlog("\n--- Attempting to Load Police Spending Data ---")
has_police_spending <- FALSE
austerity_path <- file.path(base_dir, "raw_data/Austerity.dta")

if (file.exists(austerity_path)) {
  tryCatch({
    if (requireNamespace("haven", quietly = TRUE)) {
      aust <- as.data.table(haven::read_dta(austerity_path))
      wlog("Austerity data loaded: ", nrow(aust), " x ", ncol(aust))

      # Look for police spending columns
      spend_cols <- grep("police|law_enf|protect|public_safe", names(aust),
                         ignore.case = TRUE, value = TRUE)
      wlog("Police spending columns found: ", paste(spend_cols, collapse = ", "))

      if (length(spend_cols) > 0) {
        # Try to merge on city/state/year or FIPS
        # Identify join keys in austerity data
        join_cols <- intersect(c("place_fips", "fips", "city", "state", "year",
                                  "city_clean", "state_clean"), names(aust))
        wlog("Potential join keys: ", paste(join_cols, collapse = ", "))

        if ("place_fips" %in% names(aust) && "year" %in% names(aust)) {
          # Merge on place_fips + year
          spend_var <- spend_cols[1]
          aust_slim <- aust[, c("place_fips", "year", spend_var), with = FALSE]
          setnames(aust_slim, spend_var, "police_spending_raw")
          panel <- merge(panel, aust_slim, by = c("place_fips", "year"), all.x = TRUE)
          panel[, police_spending_pc := fifelse(
            !is.na(police_spending_raw) & !is.na(population) & population > 0,
            police_spending_raw / population * 1000, NA_real_
          )]
          n_spend <- sum(!is.na(panel$police_spending_pc))
          wlog("Police spending merged: ", n_spend, " non-NA values")
          if (n_spend > 500) has_police_spending <- TRUE
        }
      }
    } else {
      wlog("haven package not available; skipping Austerity.dta")
    }
  }, error = function(e) {
    wlog("Could not load Austerity data: ", e$message)
  })
} else {
  wlog("Austerity.dta not found at: ", austerity_path)
}

if (!has_police_spending) {
  wlog("NOTE: Police spending data not available. PSW will use:")
  wlog("  - log_population (city size)")
  wlog("  - pct_black, pct_white, pct_hispanic (demographics)")
  wlog("  - violent_crime_pc (pre-treatment violent crime rate)")
  panel[, police_spending_pc := NA_real_]
}

# ── 3. Construct Pre-Treatment City-Level Covariates ─────────────────────────
wlog("\n--- Constructing Pre-Treatment City-Level Covariates ---")

# Target outcomes for this analysis
target_outcomes <- c("drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc")

# PSW covariates
psw_vars <- c("log_population", "pct_black", "pct_white", "pct_hispanic",
              "violent_crime_pc")
if (has_police_spending) {
  psw_vars <- c(psw_vars, "police_spending_pc")
}
psw_vars <- psw_vars[psw_vars %in% names(panel)]
wlog("PSW covariates: ", paste(psw_vars, collapse = ", "))

# Compute pre-treatment averages per city
# Treated: average over years before treatment (>= 2000)
# Control: average over 2000-2015
treated_pre <- panel[treated == 1 & year < treatment_year & year >= 2000]
control_pre <- panel[treated == 0 & year >= 2000 & year <= 2015]

# Fallback for treated cities with no pre-treatment data after 2000
treated_ids_all <- unique(panel[treated == 1]$agency_id)
treated_ids_pre <- unique(treated_pre$agency_id)
missing_ids <- setdiff(treated_ids_all, treated_ids_pre)
if (length(missing_ids) > 0) {
  wlog("  ", length(missing_ids), " treated cities using earliest available years")
  for (aid in missing_ids) {
    city_data <- panel[agency_id == aid][order(year)][1:min(.N, 5)]
    treated_pre <- rbind(treated_pre, city_data, fill = TRUE)
  }
}

compute_city_avgs <- function(dt, vars) {
  dt[, lapply(.SD, function(x) mean(x, na.rm = TRUE)), by = agency_id, .SDcols = vars]
}

treated_covs <- compute_city_avgs(treated_pre, psw_vars)
treated_covs[, treated := 1L]

control_covs <- compute_city_avgs(control_pre, psw_vars)
control_covs[, treated := 0L]

city_cross <- rbind(treated_covs, control_covs, fill = TRUE)
wlog("City-level cross-section: ", nrow(city_cross), " cities")
wlog("  Treated: ", sum(city_cross$treated == 1))
wlog("  Control: ", sum(city_cross$treated == 0))

# Drop cities with missing key covariates (keep those with some NAs in optional vars)
# Required: log_population and violent_crime_pc
required_vars <- intersect(c("log_population", "violent_crime_pc"), psw_vars)
optional_vars <- setdiff(psw_vars, required_vars)

n_before <- nrow(city_cross)
city_cross <- city_cross[complete.cases(city_cross[, ..required_vars])]
n_after <- nrow(city_cross)
wlog("  After dropping NAs in required vars: ", n_after, " (", n_before - n_after, " dropped)")

# Impute missing optional demographics with median
for (v in optional_vars) {
  n_miss <- sum(is.na(city_cross[[v]]))
  if (n_miss > 0 && n_miss < nrow(city_cross)) {
    med_val <- median(city_cross[[v]], na.rm = TRUE)
    city_cross[is.na(get(v)), (v) := med_val]
    wlog("  Imputed ", n_miss, " missing values for ", v, " with median=", round(med_val, 4))
  }
}

wlog("  Final: Treated=", sum(city_cross$treated == 1),
     " Control=", sum(city_cross$treated == 0))

# ── 4. Estimate Propensity Scores ───────────────────────────────────────────
wlog("\n--- Estimating Propensity Scores ---")

if (!requireNamespace("MatchIt", quietly = TRUE)) {
  install.packages("MatchIt", repos = "https://cloud.r-project.org")
}

# Use logistic regression for propensity scores
psw_formula <- as.formula(paste("treated ~", paste(psw_vars, collapse = " + ")))
wlog("PSW formula: ", deparse(psw_formula))

pscore_model <- glm(psw_formula, data = city_cross, family = binomial(link = "logit"))
wlog("\nPropensity score model summary:")
capture.output(summary(pscore_model), file = log_file, append = TRUE)
print(summary(pscore_model))

city_cross[, pscore := predict(pscore_model, type = "response")]

wlog("\nPropensity score distribution:")
wlog("  Overall: mean=", round(mean(city_cross$pscore), 4),
     " sd=", round(sd(city_cross$pscore), 4),
     " min=", round(min(city_cross$pscore), 4),
     " max=", round(max(city_cross$pscore), 4))
wlog("  Treated: mean=", round(mean(city_cross[treated == 1]$pscore), 4),
     " sd=", round(sd(city_cross[treated == 1]$pscore), 4))
wlog("  Control: mean=", round(mean(city_cross[treated == 0]$pscore), 4),
     " sd=", round(sd(city_cross[treated == 0]$pscore), 4))

# ── 5. Construct IPW Weights ────────────────────────────────────────────────
wlog("\n--- Constructing IPW Weights ---")

# ATT weights: treated get weight 1, controls get pscore/(1-pscore)
city_cross[, ipw_weight := fifelse(treated == 1, 1, pscore / (1 - pscore))]

# Trim extreme weights (at 1st and 99th percentile of control weights)
control_weights <- city_cross[treated == 0]$ipw_weight
q01 <- quantile(control_weights, 0.01, na.rm = TRUE)
q99 <- quantile(control_weights, 0.99, na.rm = TRUE)
city_cross[treated == 0 & ipw_weight < q01, ipw_weight := q01]
city_cross[treated == 0 & ipw_weight > q99, ipw_weight := q99]

# Normalize control weights to sum to number of treated
n_treated <- sum(city_cross$treated == 1)
sum_control_wt <- sum(city_cross[treated == 0]$ipw_weight)
city_cross[treated == 0, ipw_weight := ipw_weight * n_treated / sum_control_wt]

wlog("IPW weights (after trimming + normalization):")
wlog("  Treated: all weight=1, sum=", n_treated)
wlog("  Control: mean=", round(mean(city_cross[treated == 0]$ipw_weight), 4),
     " sd=", round(sd(city_cross[treated == 0]$ipw_weight), 4),
     " sum=", round(sum(city_cross[treated == 0]$ipw_weight), 2))

# Also compute common support
cs_min <- max(min(city_cross[treated == 1]$pscore), min(city_cross[treated == 0]$pscore))
cs_max <- min(max(city_cross[treated == 1]$pscore), max(city_cross[treated == 0]$pscore))
wlog("Common support: [", round(cs_min, 4), ", ", round(cs_max, 4), "]")

# Flag cities outside common support
city_cross[, in_common_support := pscore >= cs_min & pscore <= cs_max]
wlog("Cities in common support: ", sum(city_cross$in_common_support),
     " / ", nrow(city_cross))

# ── 6. Propensity Score Overlap Plot ────────────────────────────────────────
pscore_dt <- data.table(
  pscore = city_cross$pscore,
  group = ifelse(city_cross$treated == 1, "Treated", "Control")
)
p_overlap <- ggplot(pscore_dt, aes(x = pscore, fill = group)) +
  geom_density(alpha = 0.5) +
  geom_vline(xintercept = c(cs_min, cs_max), linetype = "dashed", color = "gray40") +
  labs(title = "Propensity Score Distribution (PSW)",
       subtitle = paste0("Covariates: ", paste(psw_vars, collapse = ", ")),
       x = "Propensity Score", y = "Density", fill = "Group") +
  theme_minimal()
ggsave(file.path(base_dir, "output/figures/psw_overlap.png"),
       p_overlap, width = 8, height = 5, dpi = 150)
wlog("Saved propensity score overlap plot")

# ── 7. Covariate Balance Check (Unweighted vs IPW-Weighted) ─────────────────
wlog("\n--- Covariate Balance: Unweighted vs IPW-Weighted ---")

balance_rows <- list()
for (v in psw_vars) {
  # Unweighted
  t_vals <- city_cross[treated == 1, get(v)]
  c_vals <- city_cross[treated == 0, get(v)]
  pooled_sd <- sqrt((var(t_vals, na.rm = TRUE) + var(c_vals, na.rm = TRUE)) / 2)
  smd_raw <- (mean(t_vals, na.rm = TRUE) - mean(c_vals, na.rm = TRUE)) / pooled_sd

  # IPW-weighted (for control group)
  c_wt <- city_cross[treated == 0]$ipw_weight
  c_vals_w <- city_cross[treated == 0, get(v)]
  c_mean_w <- weighted.mean(c_vals_w, c_wt, na.rm = TRUE)
  c_var_w <- sum(c_wt * (c_vals_w - c_mean_w)^2, na.rm = TRUE) / sum(c_wt, na.rm = TRUE)
  pooled_sd_w <- sqrt((var(t_vals, na.rm = TRUE) + c_var_w) / 2)
  smd_ipw <- (mean(t_vals, na.rm = TRUE) - c_mean_w) / pooled_sd_w

  pct_red <- (1 - abs(smd_ipw) / abs(smd_raw)) * 100

  balance_rows[[length(balance_rows) + 1]] <- data.table(
    variable = v,
    treated_mean = mean(t_vals, na.rm = TRUE),
    control_mean_raw = mean(c_vals, na.rm = TRUE),
    control_mean_ipw = c_mean_w,
    smd_raw = smd_raw,
    smd_ipw = smd_ipw,
    pct_reduction = pct_red
  )

  wlog(sprintf("  %-25s  SMD raw=%.4f  IPW=%.4f  (%.1f%% reduction)",
               v, smd_raw, smd_ipw, pct_red))
}

balance_dt <- rbindlist(balance_rows)
fwrite(balance_dt, file.path(base_dir, "output/tables/psw_balance_table.csv"))
wlog("Saved PSW balance table")

# Balance (love) plot
balance_long <- melt(balance_dt[, .(variable, smd_raw, smd_ipw)],
                     id.vars = "variable",
                     variable.name = "method", value.name = "smd")
balance_long[, method := fifelse(method == "smd_raw", "Unweighted", "IPW-Weighted")]

p_balance <- ggplot(balance_long, aes(x = abs(smd), y = variable, color = method, shape = method)) +
  geom_point(size = 3) +
  geom_vline(xintercept = 0.1, linetype = "dashed", color = "gray50") +
  labs(title = "Covariate Balance: Unweighted vs IPW-Weighted",
       x = "Absolute Standardized Mean Difference", y = "", color = "", shape = "") +
  theme_minimal() +
  theme(legend.position = "bottom")
ggsave(file.path(base_dir, "output/figures/psw_balance_plot.png"),
       p_balance, width = 8, height = 5, dpi = 150)
wlog("Saved balance plot")

# ── 8. Merge IPW Weights to Panel ───────────────────────────────────────────
wlog("\n--- Building IPW-Weighted Panel ---")

pscore_map <- city_cross[, .(agency_id, pscore, ipw_weight, in_common_support)]
ipw_panel <- merge(panel[year >= 2000 & year <= 2020],
                   pscore_map, by = "agency_id", all.x = FALSE)

# Restrict to common support
ipw_panel_cs <- ipw_panel[in_common_support == TRUE]

wlog("IPW panel (full): ", nrow(ipw_panel), " rows, ",
     length(unique(ipw_panel$agency_id)), " agencies")
wlog("IPW panel (common support): ", nrow(ipw_panel_cs), " rows, ",
     length(unique(ipw_panel_cs$agency_id)), " agencies")
wlog("  Treated: ", length(unique(ipw_panel_cs[treated == 1]$agency_id)))
wlog("  Control: ", length(unique(ipw_panel_cs[treated == 0]$agency_id)))


# ══════════════════════════════════════════════════════════════════════════════
# PART A: PanelMatch with PSW
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("PART A: PanelMatch with Propensity Score Weighting")
wlog("======================================================================")

if (!requireNamespace("PanelMatch", quietly = TRUE)) {
  install.packages("PanelMatch", repos = "https://cloud.r-project.org")
}
library(PanelMatch)

# Prepare PanelMatch data
pm_dt <- copy(ipw_panel_cs)
pm_dt[, treat := as.integer(post)]
pm_dt[treated == 0, treat := 0L]
pm_dt <- pm_dt[order(unit_id, year)]

wlog("PanelMatch PSW panel: ", nrow(pm_dt), " rows, ",
     length(unique(pm_dt$unit_id)), " units")

bandwidths <- c(3, 4, 5)
pm_psw_annualized <- list()
pm_psw_pooled <- list()

for (outcome in target_outcomes) {
  if (!outcome %in% names(pm_dt)) next
  n_valid <- sum(!is.na(pm_dt[[outcome]]))
  if (n_valid < 100) {
    wlog("SKIP ", outcome, ": only ", n_valid, " non-NA values")
    next
  }

  wlog("\n--- PanelMatch PSW Outcome: ", outcome, " ---")

  for (bw in bandwidths) {
    wlog("  BW=", bw)

    tryCatch({
      # Subset to non-missing outcome
      dt_sub <- pm_dt[!is.na(get(outcome))]

      # Build data frame with covariates for PSW refinement
      cov_vars <- intersect(c("log_population", "pct_black", "violent_crime_pc"), names(dt_sub))
      keep_vars <- c("unit_id", "year", "treat", outcome, cov_vars)
      df_sub <- as.data.frame(dt_sub[, ..keep_vars])

      # Remove rows with missing covariates
      df_sub <- df_sub[complete.cases(df_sub[, cov_vars]), ]

      if (nrow(df_sub) < 100) {
        wlog("    SKIP: too few complete rows (", nrow(df_sub), ")")
        next
      }

      # Create PanelData
      pd <- PanelData(
        panel.data = df_sub,
        unit.id = "unit_id",
        time.id = "year",
        treatment = "treat",
        outcome = outcome
      )

      # ── PanelMatch with PS weighting refinement ──
      # Use propensity score weighting via refinement.method = "ps.weight"
      pm_psw <- PanelMatch(
        panel.data = pd,
        lag = 4,
        refinement.method = "ps.weight",
        covs.formula = as.formula(paste("~", paste(cov_vars, collapse = " + "))),
        qoi = "att",
        lead = 0:bw,
        match.missing = TRUE,
        forbid.treatment.reversal = TRUE
      )

      pe_psw <- PanelEstimate(
        sets = pm_psw,
        panel.data = pd,
        se.method = "bootstrap",
        number.iterations = 500,
        confidence.level = 0.95
      )

      pe_summ <- summary(pe_psw)

      for (l in 0:bw) {
        pm_psw_annualized[[length(pm_psw_annualized) + 1]] <- data.table(
          model = "PanelMatch_PSW",
          outcome = outcome, bandwidth = bw, lag = 4,
          covariates = "psw",
          lead = l,
          att = pe_summ[l + 1, "estimate"],
          se = pe_summ[l + 1, "std.error"],
          ci_lower = pe_summ[l + 1, 3],
          ci_upper = pe_summ[l + 1, 4]
        )
      }

      pooled_att <- mean(pe_summ[1:(bw + 1), "estimate"])
      pooled_se <- sqrt(mean(pe_summ[1:(bw + 1), "std.error"]^2))

      stars <- ""
      if (abs(pooled_att / pooled_se) > 2.576) stars <- "***"
      else if (abs(pooled_att / pooled_se) > 1.96) stars <- "**"
      else if (abs(pooled_att / pooled_se) > 1.645) stars <- "*"

      pm_psw_pooled[[length(pm_psw_pooled) + 1]] <- data.table(
        model = "PanelMatch_PSW",
        outcome = outcome, bandwidth = bw, lag = 4,
        covariates = "psw",
        pooled_att = pooled_att, pooled_se = pooled_se,
        ci_lower = pooled_att - 1.96 * pooled_se,
        ci_upper = pooled_att + 1.96 * pooled_se,
        significance = stars
      )

      wlog(sprintf("    PSW: Pooled ATT=%.4f%s (SE=%.4f)", pooled_att, stars, pooled_se))

      # Event study plot
      tryCatch({
        png(file.path(base_dir, paste0("output/figures/eventstudy_panelmatch_psw_",
                                        outcome, "_bw", bw, ".png")),
            width = 800, height = 500)
        plot(pe_psw, main = paste0("PanelMatch PSW: ", outcome, " (bw=", bw, ")"))
        dev.off()
      }, error = function(e) {
        wlog("    Plot error: ", e$message)
        try(dev.off(), silent = TRUE)
      })

    }, error = function(e) {
      wlog("    ERROR: ", e$message)
    })

    # ── Also run PanelMatch with NO refinement on the IPW-weighted panel ──
    # (as a comparison: simple matching on IPW-restricted common support sample)
    tryCatch({
      dt_sub <- pm_dt[!is.na(get(outcome))]
      df_sub <- as.data.frame(dt_sub[, c("unit_id", "year", "treat", outcome), with = FALSE])

      pd_noc <- PanelData(
        panel.data = df_sub,
        unit.id = "unit_id", time.id = "year",
        treatment = "treat", outcome = outcome
      )

      pm_noc <- PanelMatch(
        panel.data = pd_noc,
        lag = 4,
        refinement.method = "none",
        qoi = "att",
        lead = 0:bw,
        match.missing = TRUE,
        forbid.treatment.reversal = TRUE
      )

      pe_noc <- PanelEstimate(
        sets = pm_noc, panel.data = pd_noc,
        se.method = "bootstrap", number.iterations = 500,
        confidence.level = 0.95
      )

      pe_noc_summ <- summary(pe_noc)
      pooled_att <- mean(pe_noc_summ[1:(bw + 1), "estimate"])
      pooled_se <- sqrt(mean(pe_noc_summ[1:(bw + 1), "std.error"]^2))

      stars <- ""
      if (abs(pooled_att / pooled_se) > 2.576) stars <- "***"
      else if (abs(pooled_att / pooled_se) > 1.96) stars <- "**"
      else if (abs(pooled_att / pooled_se) > 1.645) stars <- "*"

      pm_psw_pooled[[length(pm_psw_pooled) + 1]] <- data.table(
        model = "PanelMatch_CS_only",
        outcome = outcome, bandwidth = bw, lag = 4,
        covariates = "common_support",
        pooled_att = pooled_att, pooled_se = pooled_se,
        ci_lower = pooled_att - 1.96 * pooled_se,
        ci_upper = pooled_att + 1.96 * pooled_se,
        significance = stars
      )

      wlog(sprintf("    CS-only: Pooled ATT=%.4f%s (SE=%.4f)", pooled_att, stars, pooled_se))

    }, error = function(e) {
      wlog("    CS-only ERROR: ", e$message)
    })
  }
}


# ══════════════════════════════════════════════════════════════════════════════
# PART B: CSDID with Propensity Score Weighting
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("PART B: CSDID with Propensity Score Weighting")
wlog("======================================================================")

if (!requireNamespace("did", quietly = TRUE)) {
  install.packages("did", repos = "https://cloud.r-project.org")
}
library(did)

# Prepare CSDID data with IPW weights
cs_dt <- copy(ipw_panel_cs)
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
cs_dt <- cs_dt[gname == 0 | gname >= 2002]
cs_dt[gname > 2020, gname := 0]

cs_dt[, n_obs := .N, by = unit_id]
cs_dt <- cs_dt[n_obs >= 5]

wlog("CSDID PSW panel: ", nrow(cs_dt), " rows, ",
     length(unique(cs_dt$unit_id)), " units")
wlog("  Treated: ", length(unique(cs_dt[gname > 0]$unit_id)))
wlog("  Control: ", length(unique(cs_dt[gname == 0]$unit_id)))

csdid_psw_pooled <- list()
csdid_psw_es <- list()

for (outcome in target_outcomes) {
  if (!outcome %in% names(cs_dt)) next
  n_valid <- sum(!is.na(cs_dt[[outcome]]))
  if (n_valid < 100) {
    wlog("SKIP ", outcome, ": ", n_valid, " non-NA")
    next
  }

  wlog("\n--- CSDID PSW Outcome: ", outcome, " ---")

  # ── Method 1: CSDID with IPW estimation method (est_method = "ipw") ──
  # This is the did package's built-in inverse probability weighting estimator
  for (spec_name in c("ipw_nocov", "ipw_withcov", "dr_withcov")) {
    tryCatch({
      cs_sub <- cs_dt[!is.na(get(outcome))]

      # Set up covariates and estimation method based on spec
      if (spec_name == "ipw_nocov") {
        xf <- ~ 1
        est_meth <- "ipw"
        spec_label <- "IPW (no covs)"
      } else if (spec_name == "ipw_withcov") {
        cs_sub <- cs_sub[!is.na(log_population) & !is.na(pct_black) &
                           !is.na(violent_crime_pc) & is.finite(log_population)]
        xf <- ~ log_population + pct_black + violent_crime_pc
        est_meth <- "ipw"
        spec_label <- "IPW (with covs)"
      } else {
        # Doubly robust with covariates (combines outcome regression + IPW)
        cs_sub <- cs_sub[!is.na(log_population) & !is.na(pct_black) &
                           !is.na(violent_crime_pc) & is.finite(log_population)]
        xf <- ~ log_population + pct_black + violent_crime_pc
        est_meth <- "dr"
        spec_label <- "DR (with covs)"
      }

      cs_sub[, n_obs := .N, by = unit_id]
      cs_sub <- cs_sub[n_obs >= 5]

      if (nrow(cs_sub) < 100) {
        wlog("  SKIP ", spec_label, ": too few rows")
        next
      }

      gt <- att_gt(
        yname = outcome,
        tname = "year",
        idname = "unit_id",
        gname = "gname",
        xformla = xf,
        data = as.data.frame(cs_sub),
        est_method = est_meth,
        control_group = "nevertreated",
        panel = FALSE,
        bstrap = TRUE,
        biters = 500,
        print_details = FALSE
      )

      wlog("  att_gt (", spec_label, "): ", length(gt$att), " group-time ATTs")

      # Manual aggregation
      gt_dt <- data.table(group = gt$group, t = gt$t, att = gt$att, se = gt$se)
      gt_dt[, event_time := t - group]
      gt_dt <- gt_dt[!is.na(att) & is.finite(att) & !is.na(se) & se > 0]

      for (bw in bandwidths) {
        # Event study aggregation
        es_dt <- gt_dt[event_time >= -5 & event_time <= bw]
        es_agg <- es_dt[, .(
          att = mean(att, na.rm = TRUE),
          se = sqrt(mean(se^2, na.rm = TRUE) / .N),
          n_gt = .N
        ), by = event_time]
        setorder(es_agg, event_time)

        for (i in 1:nrow(es_agg)) {
          csdid_psw_es[[length(csdid_psw_es) + 1]] <- data.table(
            model = paste0("CSDID_PSW_", spec_name),
            outcome = outcome, bandwidth = bw,
            specification = spec_label,
            event_time = es_agg$event_time[i],
            att = es_agg$att[i], se = es_agg$se[i],
            ci_lower = es_agg$att[i] - 1.96 * es_agg$se[i],
            ci_upper = es_agg$att[i] + 1.96 * es_agg$se[i]
          )
        }

        # Pre-trends test
        pre <- es_agg[event_time < 0]
        if (nrow(pre) > 0) {
          any_sig <- any(abs(pre$att / pre$se) > 1.96, na.rm = TRUE)
          wlog("    BW=", bw, " ", spec_label, " pre-trends: ",
               ifelse(any_sig, "SIGNIFICANT (caution)", "ok (parallel trends hold)"))
        }

        # Pooled post-treatment
        post_gt <- gt_dt[event_time >= 0 & event_time <= bw]
        if (nrow(post_gt) > 0) {
          pooled_att <- mean(post_gt$att, na.rm = TRUE)
          pooled_se <- sqrt(mean(post_gt$se^2, na.rm = TRUE) / nrow(post_gt))

          stars <- ""
          if (abs(pooled_att / pooled_se) > 2.576) stars <- "***"
          else if (abs(pooled_att / pooled_se) > 1.96) stars <- "**"
          else if (abs(pooled_att / pooled_se) > 1.645) stars <- "*"

          wlog(sprintf("    BW=%d %s: Pooled ATT=%.4f%s (SE=%.4f)",
                       bw, spec_label, pooled_att, stars, pooled_se))

          csdid_psw_pooled[[length(csdid_psw_pooled) + 1]] <- data.table(
            model = paste0("CSDID_PSW_", spec_name),
            outcome = outcome, bandwidth = bw,
            specification = spec_label,
            pooled_att = pooled_att, pooled_se = pooled_se,
            ci_lower = pooled_att - 1.96 * pooled_se,
            ci_upper = pooled_att + 1.96 * pooled_se,
            significance = stars
          )
        }

        # Event study plots (for IPW with covs specification, all bandwidths)
        if (spec_name == "ipw_withcov") {
          es_agg[, ci_lower := att - 1.96 * se]
          es_agg[, ci_upper := att + 1.96 * se]

          p <- ggplot(es_agg, aes(x = event_time, y = att)) +
            geom_hline(yintercept = 0, color = "gray60") +
            geom_vline(xintercept = -0.5, linetype = "dashed", color = "red") +
            geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper),
                        alpha = 0.2, fill = "steelblue") +
            geom_line(color = "steelblue") +
            geom_point(color = "steelblue") +
            labs(title = paste0("CSDID PSW (IPW+Covs): ", outcome, " (bw=", bw, ")"),
                 subtitle = paste0("Covariates: ", paste(psw_vars, collapse = ", ")),
                 x = "Event Time (Years Relative to COA)", y = "ATT") +
            theme_minimal()

          ggsave(file.path(base_dir, paste0("output/figures/eventstudy_csdid_psw_",
                                             outcome, "_bw", bw, ".png")),
                 p, width = 8, height = 5, dpi = 150)
        }
      }
    }, error = function(e) {
      wlog("  ERROR (", spec_name, "): ", e$message)
    })
  }
}


# ══════════════════════════════════════════════════════════════════════════════
# PART C: IPW-Weighted TWFE (fixest) for Comparison
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("PART C: IPW-Weighted TWFE (fixest) for Comparison")
wlog("======================================================================")

if (!requireNamespace("fixest", quietly = TRUE)) {
  install.packages("fixest", repos = "https://cloud.r-project.org")
}
library(fixest)

twfe_psw_results <- list()

for (outcome in target_outcomes) {
  if (!outcome %in% names(ipw_panel_cs)) next
  n_valid <- sum(!is.na(ipw_panel_cs[[outcome]]))
  if (n_valid < 100) next

  wlog("\n--- TWFE PSW Outcome: ", outcome, " ---")

  # IPW-Weighted TWFE (no additional covariates)
  tryCatch({
    fml <- as.formula(paste0(outcome, " ~ post | agency_id + year"))
    fit <- feols(fml, data = ipw_panel_cs, weights = ipw_panel_cs$ipw_weight,
                 cluster = ~agency_id)

    beta <- coef(fit)["post"]
    se_val <- se(fit)["post"]
    pval <- pvalue(fit)["post"]
    ci <- confint(fit)["post", ]

    stars <- ""
    if (pval < 0.01) stars <- "***"
    else if (pval < 0.05) stars <- "**"
    else if (pval < 0.10) stars <- "*"

    wlog(sprintf("  IPW-TWFE (no covs): ATT=%.4f%s (SE=%.4f, p=%.4f)",
                 beta, stars, se_val, pval))

    twfe_psw_results[[length(twfe_psw_results) + 1]] <- data.table(
      model = "IPW-TWFE (no covs)", outcome = outcome,
      att = beta, se = se_val, p_value = pval,
      ci_lower = ci[1], ci_upper = ci[2], significance = stars,
      n_obs = nobs(fit),
      n_treated = length(unique(ipw_panel_cs[treated == 1 & !is.na(get(outcome))]$agency_id)),
      n_control = length(unique(ipw_panel_cs[treated == 0 & !is.na(get(outcome))]$agency_id))
    )
  }, error = function(e) wlog("  ERROR (no covs): ", e$message))

  # IPW-Weighted TWFE + covariates
  tryCatch({
    cov_vars <- intersect(c("log_population", "pct_black", "violent_crime_pc"),
                          names(ipw_panel_cs))
    ipw_sub <- ipw_panel_cs[complete.cases(ipw_panel_cs[, ..cov_vars]) & !is.na(get(outcome))]

    if (nrow(ipw_sub) >= 100) {
      fml_cov <- as.formula(paste0(outcome, " ~ post + ",
                                    paste(cov_vars, collapse = " + "),
                                    " | agency_id + year"))
      fit_cov <- feols(fml_cov, data = ipw_sub,
                       weights = ipw_sub$ipw_weight, cluster = ~agency_id)

      beta <- coef(fit_cov)["post"]
      se_val <- se(fit_cov)["post"]
      pval <- pvalue(fit_cov)["post"]
      ci <- confint(fit_cov)["post", ]

      stars <- ""
      if (pval < 0.01) stars <- "***"
      else if (pval < 0.05) stars <- "**"
      else if (pval < 0.10) stars <- "*"

      wlog(sprintf("  IPW-TWFE (with covs): ATT=%.4f%s (SE=%.4f, p=%.4f)",
                   beta, stars, se_val, pval))

      twfe_psw_results[[length(twfe_psw_results) + 1]] <- data.table(
        model = "IPW-TWFE (with covs)", outcome = outcome,
        att = beta, se = se_val, p_value = pval,
        ci_lower = ci[1], ci_upper = ci[2], significance = stars,
        n_obs = nobs(fit_cov),
        n_treated = length(unique(ipw_sub[treated == 1]$agency_id)),
        n_control = length(unique(ipw_sub[treated == 0]$agency_id))
      )
    }
  }, error = function(e) wlog("  ERROR (with covs): ", e$message))
}


# ══════════════════════════════════════════════════════════════════════════════
# Save All Results
# ══════════════════════════════════════════════════════════════════════════════
wlog("\n======================================================================")
wlog("Saving Results")
wlog("======================================================================")

# PanelMatch PSW results
if (length(pm_psw_annualized) > 0) {
  pm_ann_dt <- rbindlist(pm_psw_annualized, fill = TRUE)
  fwrite(pm_ann_dt, file.path(base_dir, "output/tables/psw_panelmatch_annualized.csv"))
  wlog("Saved ", nrow(pm_ann_dt), " PanelMatch PSW annualized results")
}

if (length(pm_psw_pooled) > 0) {
  pm_pool_dt <- rbindlist(pm_psw_pooled, fill = TRUE)
  fwrite(pm_pool_dt, file.path(base_dir, "output/tables/psw_panelmatch_pooled.csv"))
  wlog("Saved ", nrow(pm_pool_dt), " PanelMatch PSW pooled results")
  cat("\nPanelMatch PSW Pooled Results:\n")
  print(pm_pool_dt)
}

# CSDID PSW results
if (length(csdid_psw_pooled) > 0) {
  cs_pool_dt <- rbindlist(csdid_psw_pooled, fill = TRUE)
  fwrite(cs_pool_dt, file.path(base_dir, "output/tables/psw_csdid_pooled.csv"))
  wlog("Saved ", nrow(cs_pool_dt), " CSDID PSW pooled results")
  cat("\nCSCID PSW Pooled Results:\n")
  print(cs_pool_dt)
}

if (length(csdid_psw_es) > 0) {
  cs_es_dt <- rbindlist(csdid_psw_es, fill = TRUE)
  fwrite(cs_es_dt, file.path(base_dir, "output/tables/psw_csdid_event_study.csv"))
  wlog("Saved ", nrow(cs_es_dt), " CSDID PSW event study results")
}

# TWFE PSW results
if (length(twfe_psw_results) > 0) {
  twfe_dt <- rbindlist(twfe_psw_results, fill = TRUE)
  fwrite(twfe_dt, file.path(base_dir, "output/tables/psw_twfe_results.csv"))
  wlog("Saved ", nrow(twfe_dt), " TWFE PSW results")
  cat("\nTWFE PSW Results:\n")
  print(twfe_dt)
}

# ── Comparison summary table ────────────────────────────────────────────────
wlog("\n======================================================================")
wlog("RESULTS COMPARISON: PSW Models")
wlog("======================================================================")

for (out in target_outcomes) {
  wlog("\n  ", out, ":")
  wlog("  ", paste(rep("-", 70), collapse = ""))

  # PanelMatch PSW
  if (length(pm_psw_pooled) > 0) {
    pm_sub <- rbindlist(pm_psw_pooled, fill = TRUE)[outcome == out & bandwidth == 5]
    for (i in seq_len(nrow(pm_sub))) {
      wlog(sprintf("    %-30s ATT=%10.4f%-3s (SE=%.4f) [%.4f, %.4f]",
                   pm_sub$model[i], pm_sub$pooled_att[i], pm_sub$significance[i],
                   pm_sub$pooled_se[i], pm_sub$ci_lower[i], pm_sub$ci_upper[i]))
    }
  }

  # CSDID PSW
  if (length(csdid_psw_pooled) > 0) {
    cs_sub <- rbindlist(csdid_psw_pooled, fill = TRUE)[outcome == out & bandwidth == 5]
    for (i in seq_len(nrow(cs_sub))) {
      wlog(sprintf("    %-30s ATT=%10.4f%-3s (SE=%.4f) [%.4f, %.4f]",
                   cs_sub$model[i], cs_sub$pooled_att[i], cs_sub$significance[i],
                   cs_sub$pooled_se[i], cs_sub$ci_lower[i], cs_sub$ci_upper[i]))
    }
  }

  # TWFE PSW
  if (length(twfe_psw_results) > 0) {
    tw_sub <- rbindlist(twfe_psw_results, fill = TRUE)[outcome == out]
    for (i in seq_len(nrow(tw_sub))) {
      wlog(sprintf("    %-30s ATT=%10.4f%-3s (SE=%.4f) [%.4f, %.4f] N=%s",
                   tw_sub$model[i], tw_sub$att[i], tw_sub$significance[i],
                   tw_sub$se[i], tw_sub$ci_lower[i], tw_sub$ci_upper[i],
                   format(tw_sub$n_obs[i], big.mark = ",")))
    }
  }
}

wlog("\n======================================================================")
wlog("ANALYSIS COMPLETE")
wlog("======================================================================")
wlog("\nOutput files:")
wlog("  - output/tables/psw_panelmatch_annualized.csv")
wlog("  - output/tables/psw_panelmatch_pooled.csv")
wlog("  - output/tables/psw_csdid_pooled.csv")
wlog("  - output/tables/psw_csdid_event_study.csv")
wlog("  - output/tables/psw_twfe_results.csv")
wlog("  - output/tables/psw_balance_table.csv")
wlog("  - output/figures/psw_overlap.png")
wlog("  - output/figures/psw_balance_plot.png")
wlog("  - output/figures/eventstudy_panelmatch_psw_*.png")
wlog("  - output/figures/eventstudy_csdid_psw_*.png")
wlog("  - output/psw_did_log.txt")

wlog("\nNOTE: Police spending data was ",
     ifelse(has_police_spending, "INCLUDED", "NOT AVAILABLE"),
     " in the propensity score model.")
wlog("PSW covariates used: ", paste(psw_vars, collapse = ", "))

wlog("\nStep 17 complete.\n")
