##############################################################################
# 09_analysis_panelmatch.R — Step 9: PanelMatch Estimation (v3 API, fixed)
##############################################################################

library(data.table)
library(PanelMatch)
library(ggplot2)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 9: PanelMatch Estimation ==========")

panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))

# Prepare
panel[, unit_id := as.integer(as.factor(agency_id))]
panel[, treat := as.integer(post)]
panel[treated == 0, treat := 0L]

# Use 2000-2020 to have a reasonably balanced panel
pm_dt <- panel[year >= 2000 & year <= 2020]
pm_dt <- pm_dt[order(unit_id, year)]

wlog("PM panel: ", nrow(pm_dt), " rows, ", length(unique(pm_dt$unit_id)), " units")

# Outcomes
outcomes <- c("violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
              "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
              "black_share_violent_arrests", "black_share_drug_arrests")

bandwidths <- c(3, 4, 5)
annualized_results <- list()
pooled_results <- list()

for (outcome in outcomes) {
  if (!outcome %in% names(pm_dt)) next
  n_valid <- sum(!is.na(pm_dt[[outcome]]))
  if (n_valid < 100) {
    wlog("SKIP ", outcome, ": only ", n_valid, " non-NA values")
    next
  }

  wlog("\n--- Outcome: ", outcome, " ---")

  for (bw in bandwidths) {
    wlog("  BW=", bw)

    tryCatch({
      # Prepare data
      dt_sub <- pm_dt[!is.na(get(outcome))]
      df_sub <- as.data.frame(dt_sub[, c("unit_id", "year", "treat", outcome,
                                           "log_population", "pct_black"), with = FALSE])

      # Create PanelData
      pd <- PanelData(
        panel.data = df_sub,
        unit.id = "unit_id",
        time.id = "year",
        treatment = "treat",
        outcome = outcome
      )

      # --- No covariates ---
      pm_nocov <- PanelMatch(
        panel.data = pd,
        lag = 4,
        refinement.method = "none",
        qoi = "att",
        lead = 0:bw,
        match.missing = TRUE,
        forbid.treatment.reversal = TRUE
      )

      pe_nocov <- PanelEstimate(
        sets = pm_nocov,
        panel.data = pd,
        se.method = "bootstrap",
        number.iterations = 300,
        confidence.level = 0.95
      )

      pe_summ <- summary(pe_nocov)

      for (l in 0:bw) {
        annualized_results[[length(annualized_results) + 1]] <- data.table(
          outcome = outcome, bandwidth = bw, lag = 4,
          match_size = 5, covariates = "none",
          lead = l,
          att = pe_summ[l + 1, "estimate"],
          se = pe_summ[l + 1, "std.error"],
          ci_lower = pe_summ[l + 1, 3],
          ci_upper = pe_summ[l + 1, 4]
        )
      }

      pooled_att <- mean(pe_summ[1:(bw+1), "estimate"])
      pooled_se <- sqrt(mean(pe_summ[1:(bw+1), "std.error"]^2))

      pooled_results[[length(pooled_results) + 1]] <- data.table(
        outcome = outcome, bandwidth = bw, lag = 4,
        match_size = 5, covariates = "none",
        pooled_att = pooled_att, pooled_se = pooled_se,
        ci_lower = pooled_att - 1.96 * pooled_se,
        ci_upper = pooled_att + 1.96 * pooled_se
      )

      wlog("    No covs: Pooled ATT=", round(pooled_att, 4), " SE=", round(pooled_se, 4))

      # Plot
      tryCatch({
        png(file.path(base_dir, paste0("output/figures/eventstudy_panelmatch_",
                                        outcome, "_bw", bw, ".png")),
            width = 800, height = 500)
        plot(pe_nocov, main = paste0("PanelMatch: ", outcome, " (bw=", bw, ")"))
        dev.off()
      }, error = function(e) {
        wlog("    Plot error: ", e$message)
        try(dev.off(), silent = TRUE)
      })

      # --- With covariates ---
      tryCatch({
        df_cov <- df_sub[!is.na(df_sub$log_population) & !is.na(df_sub$pct_black), ]
        if (nrow(df_cov) < 100) {
          wlog("    SKIP with_covs: too few rows")
        } else {
          pd_cov <- PanelData(
            panel.data = df_cov,
            unit.id = "unit_id", time.id = "year",
            treatment = "treat", outcome = outcome
          )

          pm_cov <- PanelMatch(
            panel.data = pd_cov, lag = 4,
            refinement.method = "mahalanobis",
            covs.formula = ~ log_population + pct_black,
            size.match = 5, qoi = "att", lead = 0:bw,
            match.missing = TRUE, forbid.treatment.reversal = TRUE
          )

          pe_cov <- PanelEstimate(
            sets = pm_cov, panel.data = pd_cov,
            se.method = "bootstrap", number.iterations = 300,
            confidence.level = 0.95
          )

          pe_sc <- summary(pe_cov)

          for (l in 0:bw) {
            annualized_results[[length(annualized_results) + 1]] <- data.table(
              outcome = outcome, bandwidth = bw, lag = 4,
              match_size = 5, covariates = "with_covs",
              lead = l,
              att = pe_sc[l + 1, "estimate"],
              se = pe_sc[l + 1, "std.error"],
              ci_lower = pe_sc[l + 1, 3],
              ci_upper = pe_sc[l + 1, 4]
            )
          }

          pa_c <- mean(pe_sc[1:(bw+1), "estimate"])
          ps_c <- sqrt(mean(pe_sc[1:(bw+1), "std.error"]^2))

          pooled_results[[length(pooled_results) + 1]] <- data.table(
            outcome = outcome, bandwidth = bw, lag = 4,
            match_size = 5, covariates = "with_covs",
            pooled_att = pa_c, pooled_se = ps_c,
            ci_lower = pa_c - 1.96 * ps_c,
            ci_upper = pa_c + 1.96 * ps_c
          )

          wlog("    With covs: Pooled ATT=", round(pa_c, 4), " SE=", round(ps_c, 4))
        }
      }, error = function(e) {
        wlog("    Covariates ERROR: ", e$message)
      })

    }, error = function(e) {
      wlog("    ERROR: ", e$message)
    })
  }
}

# Save
if (length(annualized_results) > 0) {
  ann_dt <- rbindlist(annualized_results, fill = TRUE)
  fwrite(ann_dt, file.path(base_dir, "output/tables/panelmatch_annualized.csv"))
  wlog("\nSaved ", nrow(ann_dt), " annualized results")
} else {
  fwrite(data.table(note = "No results"), file.path(base_dir, "output/tables/panelmatch_annualized.csv"))
}

if (length(pooled_results) > 0) {
  pool_dt <- rbindlist(pooled_results, fill = TRUE)
  fwrite(pool_dt, file.path(base_dir, "output/tables/panelmatch_pooled.csv"))
  wlog("\nSaved ", nrow(pool_dt), " pooled results")
  cat("\nPooled Results:\n")
  print(pool_dt)
} else {
  fwrite(data.table(note = "No results"), file.path(base_dir, "output/tables/panelmatch_pooled.csv"))
}

wlog("Step 9 complete.\n")
