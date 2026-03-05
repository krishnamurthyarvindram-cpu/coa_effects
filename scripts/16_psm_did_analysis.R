##############################################################################
# 16_psm_did_analysis.R — Propensity Score Matching + DiD Estimation
#
# Matches treated and control cities on pre-treatment characteristics:
#   - City population (log)
#   - Demographics (pct_black)
#   - Pre-treatment violent crime rate (per capita)
#   - Pre-treatment property clearance rate
#   - Pre-treatment drug arrest rate (per capita)
#
# Then re-estimates CSDID and TWFE on the matched sample.
#
# Required packages: data.table, MatchIt, did, ggplot2, fixest, cobalt
# Install: install.packages(c("MatchIt", "cobalt", "fixest"))
##############################################################################

library(data.table)
library(ggplot2)

# ── Paths ────────────────────────────────────────────────────────────────────
base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/psm_analysis_log.txt")

dir.create(file.path(base_dir, "output/tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(base_dir, "output/figures"), recursive = TRUE, showWarnings = FALSE)

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

# Clear log
cat("", file = log_file)

wlog("======================================================================")
wlog("STEP 16: Propensity Score Matching + DiD Analysis (R)")
wlog("======================================================================")

# ── 1. Load Data ─────────────────────────────────────────────────────────────
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]
wlog("Panel loaded: ", nrow(panel), " rows x ", ncol(panel), " cols")
wlog("Unique agencies: ", length(unique(panel$agency_id)))
wlog("Treated: ", length(unique(panel[treated == 1]$agency_id)))
wlog("Control: ", length(unique(panel[treated == 0]$agency_id)))
wlog("Year range: ", min(panel$year), " - ", max(panel$year))

# ── 2. Construct Pre-Treatment City-Level Covariates ─────────────────────────
wlog("\n--- Constructing Pre-Treatment City-Level Covariates ---")

outcomes <- c("violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
              "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
              "black_share_violent_arrests", "black_share_drug_arrests")

# PSM matching covariates
psm_vars <- c("log_population", "pct_black", "violent_crime_pc",
              "property_clearance_rate", "drug_arrests_pc")

# Keep only those that exist
psm_vars <- psm_vars[psm_vars %in% names(panel)]
wlog("PSM covariates: ", paste(psm_vars, collapse = ", "))

# For treated: average over pre-treatment years (year < treatment_year, year >= 2000)
# For control: average over 2000-2015
treated_pre <- panel[treated == 1 & year < treatment_year & year >= 2000]
control_pre <- panel[treated == 0 & year >= 2000 & year <= 2015]

# Cities with no qualifying pre-treatment obs: use their earliest 5 years
treated_ids_all <- unique(panel[treated == 1]$agency_id)
treated_ids_pre <- unique(treated_pre$agency_id)
missing_ids <- setdiff(treated_ids_all, treated_ids_pre)
if (length(missing_ids) > 0) {
  wlog("  ", length(missing_ids), " treated cities with no pre-treatment data after 2000; using earliest years")
  for (aid in missing_ids) {
    city_data <- panel[agency_id == aid][order(year)][1:min(.N, 5)]
    treated_pre <- rbind(treated_pre, city_data, fill = TRUE)
  }
}

# Compute city-level averages
compute_city_avgs <- function(dt, vars) {
  dt[, lapply(.SD, function(x) mean(x, na.rm = TRUE)), by = agency_id, .SDcols = vars]
}

treated_covs <- compute_city_avgs(treated_pre, psm_vars)
treated_covs[, treated := 1L]

control_covs <- compute_city_avgs(control_pre, psm_vars)
control_covs[, treated := 0L]

city_cross <- rbind(treated_covs, control_covs, fill = TRUE)
wlog("City-level cross-section: ", nrow(city_cross), " cities")
wlog("  Treated: ", sum(city_cross$treated == 1))
wlog("  Control: ", sum(city_cross$treated == 0))

# Drop cities with missing covariates
n_before <- nrow(city_cross)
city_cross <- city_cross[complete.cases(city_cross[, ..psm_vars])]
n_after <- nrow(city_cross)
wlog("  After dropping NAs: ", n_after, " cities (", n_before - n_after, " dropped)")
wlog("    Treated: ", sum(city_cross$treated == 1))
wlog("    Control: ", sum(city_cross$treated == 0))

# ── 3. Propensity Score Matching ─────────────────────────────────────────────
wlog("\n--- Propensity Score Matching ---")

# Check for MatchIt
if (!requireNamespace("MatchIt", quietly = TRUE)) {
  wlog("Installing MatchIt...")
  install.packages("MatchIt", repos = "https://cloud.r-project.org")
}
library(MatchIt)

# Propensity score formula
psm_formula <- as.formula(paste("treated ~", paste(psm_vars, collapse = " + ")))
wlog("PSM formula: ", deparse(psm_formula))

# Run matching: nearest neighbor with caliper = 0.25 SD of logit pscore
m_out <- matchit(
  psm_formula,
  data = as.data.frame(city_cross),
  method = "nearest",
  distance = "glm",       # logistic regression
  link = "logit",
  caliper = 0.25,         # in SD of logit propensity score
  replace = TRUE,         # with replacement
  ratio = 1               # 1:1 matching
)

wlog("\nMatching summary:")
print(summary(m_out))
capture.output(summary(m_out), file = log_file, append = TRUE)

# Extract matched data
matched_cities <- match.data(m_out)
matched_cities <- as.data.table(matched_cities)

n_treated_matched <- sum(matched_cities$treated == 1)
n_control_matched <- sum(matched_cities$treated == 0)
wlog("\nMatched cities:")
wlog("  Treated: ", n_treated_matched)
wlog("  Control: ", n_control_matched)

# ── 4. Covariate Balance ────────────────────────────────────────────────────
wlog("\n--- Covariate Balance ---")

balance_rows <- list()
for (v in psm_vars) {
  # Before
  t_before <- city_cross[treated == 1, get(v)]
  c_before <- city_cross[treated == 0, get(v)]
  pooled_sd <- sqrt((var(t_before, na.rm = TRUE) + var(c_before, na.rm = TRUE)) / 2)
  smd_before <- (mean(t_before, na.rm = TRUE) - mean(c_before, na.rm = TRUE)) / pooled_sd

  # After
  t_after <- matched_cities[treated == 1, get(v)]
  c_after <- matched_cities[treated == 0, get(v)]
  pooled_sd_after <- sqrt((var(t_after, na.rm = TRUE) + var(c_after, na.rm = TRUE)) / 2)
  smd_after <- (mean(t_after, na.rm = TRUE) - mean(c_after, na.rm = TRUE)) / pooled_sd_after

  pct_red <- (1 - abs(smd_after) / abs(smd_before)) * 100

  balance_rows[[length(balance_rows) + 1]] <- data.table(
    variable = v,
    treated_mean_before = mean(t_before, na.rm = TRUE),
    control_mean_before = mean(c_before, na.rm = TRUE),
    smd_before = smd_before,
    treated_mean_after = mean(t_after, na.rm = TRUE),
    control_mean_after = mean(c_after, na.rm = TRUE),
    smd_after = smd_after,
    pct_reduction = pct_red
  )

  wlog(sprintf("  %-35s  SMD before=%.4f  after=%.4f  (%.1f%% reduction)",
               v, smd_before, smd_after, pct_red))
}

balance_dt <- rbindlist(balance_rows)
fwrite(balance_dt, file.path(base_dir, "output/tables/psm_balance_table.csv"))
wlog("Saved balance table")

# Balance plot (love plot)
tryCatch({
  if (requireNamespace("cobalt", quietly = TRUE)) {
    library(cobalt)
    lp <- love.plot(m_out, binary = "std", thresholds = c(m = 0.1),
                    title = "Covariate Balance: Before vs After PSM")
    ggsave(file.path(base_dir, "output/figures/psm_love_plot.png"),
           lp, width = 8, height = 5, dpi = 150)
    wlog("Saved love plot")
  }
}, error = function(e) wlog("  Love plot skipped: ", e$message))

# Propensity score overlap plot
pscore_dt <- data.table(
  pscore = m_out$distance,
  group = ifelse(city_cross$treated == 1, "Treated", "Control")
)
p_overlap <- ggplot(pscore_dt, aes(x = pscore, fill = group)) +
  geom_density(alpha = 0.5) +
  labs(title = "Propensity Score Distribution (Before Matching)",
       x = "Propensity Score", y = "Density", fill = "Group") +
  theme_minimal()
ggsave(file.path(base_dir, "output/figures/psm_overlap.png"),
       p_overlap, width = 8, height = 5, dpi = 150)
wlog("Saved propensity score overlap plot")

# ── 5. Build Matched Panel ───────────────────────────────────────────────────
wlog("\n--- Building Matched Panel ---")

matched_agency_ids <- unique(matched_cities$agency_id)
matched_panel <- panel[agency_id %in% matched_agency_ids & year >= 2000 & year <= 2020]

wlog("Matched panel: ", nrow(matched_panel), " city-years")
wlog("  Agencies: ", length(unique(matched_panel$agency_id)))
wlog("  Treated: ", length(unique(matched_panel[treated == 1]$agency_id)))
wlog("  Control: ", length(unique(matched_panel[treated == 0]$agency_id)))

# ── 6. TWFE DiD on Matched Sample (fixest) ───────────────────────────────────
wlog("\n======================================================================")
wlog("TWFE DiD on PSM-Matched Sample (fixest)")
wlog("======================================================================")

if (!requireNamespace("fixest", quietly = TRUE)) {
  wlog("Installing fixest...")
  install.packages("fixest", repos = "https://cloud.r-project.org")
}
library(fixest)

twfe_results <- list()

for (outcome in outcomes) {
  if (!outcome %in% names(matched_panel)) next
  n_valid <- sum(!is.na(matched_panel[[outcome]]))
  if (n_valid < 100) {
    wlog("SKIP ", outcome, ": only ", n_valid, " non-NA")
    next
  }

  wlog("\n--- Outcome: ", outcome, " ---")

  # Without covariates
  tryCatch({
    fml <- as.formula(paste0(outcome, " ~ post | agency_id + year"))
    fit <- feols(fml, data = matched_panel, cluster = ~agency_id)

    beta <- coef(fit)["post"]
    se_val <- se(fit)["post"]
    pval <- pvalue(fit)["post"]
    ci <- confint(fit)["post", ]

    stars <- ""
    if (pval < 0.01) stars <- "***"
    else if (pval < 0.05) stars <- "**"
    else if (pval < 0.10) stars <- "*"

    wlog(sprintf("  TWFE (no covs): ATT=%.4f%s (SE=%.4f, p=%.4f) [%.4f, %.4f]",
                 beta, stars, se_val, pval, ci[1], ci[2]))

    twfe_results[[length(twfe_results) + 1]] <- data.table(
      model = "PSM + TWFE", outcome = outcome,
      att = beta, se = se_val, p_value = pval,
      ci_lower = ci[1], ci_upper = ci[2], significance = stars,
      n_obs = nobs(fit),
      n_treated = length(unique(matched_panel[treated == 1 & !is.na(get(outcome))]$agency_id)),
      n_control = length(unique(matched_panel[treated == 0 & !is.na(get(outcome))]$agency_id))
    )
  }, error = function(e) wlog("  ERROR (no covs): ", e$message))

  # With covariates
  tryCatch({
    cov_vars <- intersect(c("log_population", "pct_black"), names(matched_panel))
    if (length(cov_vars) > 0) {
      fml_cov <- as.formula(paste0(outcome, " ~ post + ",
                                    paste(cov_vars, collapse = " + "),
                                    " | agency_id + year"))
      fit_cov <- feols(fml_cov, data = matched_panel, cluster = ~agency_id)

      beta <- coef(fit_cov)["post"]
      se_val <- se(fit_cov)["post"]
      pval <- pvalue(fit_cov)["post"]
      ci <- confint(fit_cov)["post", ]

      stars <- ""
      if (pval < 0.01) stars <- "***"
      else if (pval < 0.05) stars <- "**"
      else if (pval < 0.10) stars <- "*"

      wlog(sprintf("  TWFE (with covs): ATT=%.4f%s (SE=%.4f, p=%.4f)",
                   beta, stars, se_val, pval))

      twfe_results[[length(twfe_results) + 1]] <- data.table(
        model = "PSM + TWFE + Covariates", outcome = outcome,
        att = beta, se = se_val, p_value = pval,
        ci_lower = ci[1], ci_upper = ci[2], significance = stars,
        n_obs = nobs(fit_cov),
        n_treated = length(unique(matched_panel[treated == 1 & !is.na(get(outcome))]$agency_id)),
        n_control = length(unique(matched_panel[treated == 0 & !is.na(get(outcome))]$agency_id))
      )
    }
  }, error = function(e) wlog("  ERROR (with covs): ", e$message))
}

# ── 7. CSDID on Matched Sample ───────────────────────────────────────────────
wlog("\n======================================================================")
wlog("CSDID on PSM-Matched Sample")
wlog("======================================================================")

if (!requireNamespace("did", quietly = TRUE)) {
  wlog("Installing did...")
  install.packages("did", repos = "https://cloud.r-project.org")
}
library(did)

# Prepare CSDID data
cs_dt <- copy(matched_panel)
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
cs_dt <- cs_dt[gname == 0 | gname >= 2002]
cs_dt[gname > 2020, gname := 0]

# Ensure enough obs per unit
cs_dt[, n_obs := .N, by = unit_id]
cs_dt <- cs_dt[n_obs >= 5]

wlog("CSDID matched panel: ", nrow(cs_dt), " rows, ",
     length(unique(cs_dt$unit_id)), " units")
wlog("  Treated: ", length(unique(cs_dt[gname > 0]$unit_id)))
wlog("  Control: ", length(unique(cs_dt[gname == 0]$unit_id)))

csdid_pooled <- list()
csdid_es <- list()
bandwidths <- c(3, 5)

for (outcome in outcomes) {
  if (!outcome %in% names(cs_dt)) next
  n_valid <- sum(!is.na(cs_dt[[outcome]]))
  if (n_valid < 100) next

  wlog("\n--- CSDID Outcome: ", outcome, " ---")

  for (cov_name in c("none", "with_covs")) {
    tryCatch({
      cs_sub <- cs_dt[!is.na(get(outcome))]
      if (cov_name == "with_covs") {
        cs_sub <- cs_sub[!is.na(log_population) & !is.na(pct_black) & is.finite(log_population)]
      }
      cs_sub[, n_obs := .N, by = unit_id]
      cs_sub <- cs_sub[n_obs >= 5]

      if (nrow(cs_sub) < 100) {
        wlog("  SKIP ", cov_name, ": too few rows")
        next
      }

      xf <- if (cov_name == "with_covs") ~ log_population + pct_black else ~ 1

      gt <- att_gt(
        yname = outcome,
        tname = "year",
        idname = "unit_id",
        gname = "gname",
        xformla = xf,
        data = as.data.frame(cs_sub),
        est_method = "reg",
        control_group = "nevertreated",
        panel = FALSE,
        bstrap = TRUE,
        biters = 200,
        print_details = FALSE
      )

      wlog("  att_gt (", cov_name, "): ", length(gt$att), " group-time ATTs")

      # Manual aggregation
      gt_dt <- data.table(group = gt$group, t = gt$t, att = gt$att, se = gt$se)
      gt_dt[, event_time := t - group]
      gt_dt <- gt_dt[!is.na(att) & is.finite(att) & !is.na(se) & se > 0]

      for (bw in bandwidths) {
        # Event study
        es_dt <- gt_dt[event_time >= -5 & event_time <= bw]
        es_agg <- es_dt[, .(att = mean(att, na.rm = TRUE),
                            se = sqrt(mean(se^2, na.rm = TRUE) / .N),
                            n_gt = .N), by = event_time]
        setorder(es_agg, event_time)

        for (i in 1:nrow(es_agg)) {
          csdid_es[[length(csdid_es) + 1]] <- data.table(
            outcome = outcome, bandwidth = bw, covariates = cov_name,
            event_time = es_agg$event_time[i],
            att = es_agg$att[i], se = es_agg$se[i],
            ci_lower = es_agg$att[i] - 1.96 * es_agg$se[i],
            ci_upper = es_agg$att[i] + 1.96 * es_agg$se[i]
          )
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
                       bw, cov_name, pooled_att, stars, pooled_se))

          csdid_pooled[[length(csdid_pooled) + 1]] <- data.table(
            model = paste0("PSM + CSDID (", cov_name, ")"),
            outcome = outcome, bandwidth = bw,
            att = pooled_att, se = pooled_se,
            ci_lower = pooled_att - 1.96 * pooled_se,
            ci_upper = pooled_att + 1.96 * pooled_se,
            significance = stars
          )
        }

        # Event study plot (no covs only)
        if (cov_name == "none") {
          es_agg[, ci_lower := att - 1.96 * se]
          es_agg[, ci_upper := att + 1.96 * se]

          p <- ggplot(es_agg, aes(x = event_time, y = att)) +
            geom_hline(yintercept = 0, color = "gray60") +
            geom_vline(xintercept = -0.5, linetype = "dashed", color = "red") +
            geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "steelblue") +
            geom_line(color = "steelblue") +
            geom_point(color = "steelblue") +
            labs(title = paste0("PSM + CSDID Event Study: ", outcome, " (bw=", bw, ")"),
                 x = "Event Time", y = "ATT") +
            theme_minimal()

          ggsave(file.path(base_dir, paste0("output/figures/eventstudy_psm_csdid_",
                                             outcome, "_bw", bw, ".png")),
                 p, width = 8, height = 5, dpi = 150)
        }
      }
    }, error = function(e) {
      wlog("  ERROR (", cov_name, "): ", e$message)
    })
  }
}

# ── 8. Full-Sample TWFE for Comparison ───────────────────────────────────────
wlog("\n======================================================================")
wlog("Full-Sample TWFE (no PSM) for Comparison")
wlog("======================================================================")

full_panel <- panel[year >= 2000 & year <= 2020]

for (outcome in outcomes) {
  if (!outcome %in% names(full_panel)) next
  n_valid <- sum(!is.na(full_panel[[outcome]]))
  if (n_valid < 100) next

  tryCatch({
    fml <- as.formula(paste0(outcome, " ~ post | agency_id + year"))
    fit <- feols(fml, data = full_panel, cluster = ~agency_id)

    beta <- coef(fit)["post"]
    se_val <- se(fit)["post"]
    pval <- pvalue(fit)["post"]
    ci <- confint(fit)["post", ]

    stars <- ""
    if (pval < 0.01) stars <- "***"
    else if (pval < 0.05) stars <- "**"
    else if (pval < 0.10) stars <- "*"

    wlog(sprintf("  %s: ATT=%.4f%s (SE=%.4f, p=%.4f, n=%d)",
                 outcome, beta, stars, se_val, pval, nobs(fit)))

    twfe_results[[length(twfe_results) + 1]] <- data.table(
      model = "Full Sample TWFE (no PSM)", outcome = outcome,
      att = beta, se = se_val, p_value = pval,
      ci_lower = ci[1], ci_upper = ci[2], significance = stars,
      n_obs = nobs(fit),
      n_treated = length(unique(full_panel[treated == 1 & !is.na(get(outcome))]$agency_id)),
      n_control = length(unique(full_panel[treated == 0 & !is.na(get(outcome))]$agency_id))
    )
  }, error = function(e) wlog("  ERROR: ", e$message))
}

# ── 9. IPW (Inverse Propensity Weighting) Robustness ─────────────────────────
wlog("\n======================================================================")
wlog("Robustness: Inverse Propensity Weighting (IPW)")
wlog("======================================================================")

# Attach propensity scores to city_cross
city_cross[, pscore := m_out$distance]

# Merge to panel
pscore_map <- city_cross[, .(agency_id, pscore)]
ipw_panel <- merge(full_panel, pscore_map, by = "agency_id", all.x = FALSE)

# Trim common support
ipw_panel <- ipw_panel[pscore >= 0.05 & pscore <= 0.95]
wlog("IPW panel (trimmed [0.05, 0.95]): ", nrow(ipw_panel), " rows, ",
     length(unique(ipw_panel$agency_id)), " agencies")

# IPW weights
ipw_panel[, ipw_weight := fifelse(treated == 1, 1, pscore / (1 - pscore))]

for (outcome in outcomes) {
  if (!outcome %in% names(ipw_panel)) next
  n_valid <- sum(!is.na(ipw_panel[[outcome]]))
  if (n_valid < 100) next

  tryCatch({
    fml <- as.formula(paste0(outcome, " ~ post | agency_id + year"))
    fit <- feols(fml, data = ipw_panel, weights = ipw_panel$ipw_weight, cluster = ~agency_id)

    beta <- coef(fit)["post"]
    se_val <- se(fit)["post"]
    pval <- pvalue(fit)["post"]

    stars <- ""
    if (pval < 0.01) stars <- "***"
    else if (pval < 0.05) stars <- "**"
    else if (pval < 0.10) stars <- "*"

    wlog(sprintf("  IPW %s: ATT=%.4f%s (SE=%.4f)", outcome, beta, stars, se_val))

    twfe_results[[length(twfe_results) + 1]] <- data.table(
      model = "IPW + TWFE", outcome = outcome,
      att = beta, se = se_val, p_value = pval,
      ci_lower = beta - 1.96 * se_val,
      ci_upper = beta + 1.96 * se_val,
      significance = stars,
      n_obs = nobs(fit),
      n_treated = length(unique(ipw_panel[treated == 1 & !is.na(get(outcome))]$agency_id)),
      n_control = length(unique(ipw_panel[treated == 0 & !is.na(get(outcome))]$agency_id))
    )
  }, error = function(e) wlog("  IPW ERROR: ", e$message))
}

# ── 10. Save All Results ──────────────────────────────────────────────────────
wlog("\n--- Saving Results ---")

# TWFE results
if (length(twfe_results) > 0) {
  twfe_dt <- rbindlist(twfe_results, fill = TRUE)
  fwrite(twfe_dt, file.path(base_dir, "output/tables/psm_did_results.csv"))
  wlog("Saved ", nrow(twfe_dt), " TWFE results to psm_did_results.csv")
}

# CSDID pooled
if (length(csdid_pooled) > 0) {
  csdid_pool_dt <- rbindlist(csdid_pooled, fill = TRUE)
  fwrite(csdid_pool_dt, file.path(base_dir, "output/tables/psm_csdid_pooled.csv"))
  wlog("Saved ", nrow(csdid_pool_dt), " CSDID pooled results")
}

# CSDID event study
if (length(csdid_es) > 0) {
  csdid_es_dt <- rbindlist(csdid_es, fill = TRUE)
  fwrite(csdid_es_dt, file.path(base_dir, "output/tables/psm_csdid_event_study.csv"))
  wlog("Saved ", nrow(csdid_es_dt), " CSDID event study results")
}

# ── 11. Print Comparison Table ────────────────────────────────────────────────
wlog("\n======================================================================")
wlog("RESULTS COMPARISON TABLE")
wlog("======================================================================")

if (length(twfe_results) > 0) {
  for (out in outcomes) {
    sub <- twfe_dt[outcome == out]
    if (nrow(sub) == 0) next
    wlog("\n  ", out, ":")
    for (i in 1:nrow(sub)) {
      wlog(sprintf("    %-35s  ATT=%10.4f%-3s  (SE=%.4f)  N=%s  [%d T / %d C]",
                   sub$model[i], sub$att[i], sub$significance[i], sub$se[i],
                   format(sub$n_obs[i], big.mark = ","),
                   sub$n_treated[i], sub$n_control[i]))
    }
  }
}

wlog("\n======================================================================")
wlog("ANALYSIS COMPLETE")
wlog("======================================================================")
wlog("\nOutput files:")
wlog("  - output/tables/psm_did_results.csv")
wlog("  - output/tables/psm_csdid_pooled.csv")
wlog("  - output/tables/psm_csdid_event_study.csv")
wlog("  - output/tables/psm_balance_table.csv")
wlog("  - output/figures/psm_overlap.png")
wlog("  - output/figures/psm_love_plot.png")
wlog("  - output/figures/eventstudy_psm_csdid_*.png")
wlog("  - output/psm_analysis_log.txt")

wlog("\nStep 16 complete.\n")
