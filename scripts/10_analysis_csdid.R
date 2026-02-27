##############################################################################
# 10_analysis_csdid.R — Step 10: CSDID with manual aggregation
# (aggte has a bug in did v2.3.0 — using manual aggregation of group-time ATTs)
##############################################################################

library(data.table)
library(did)
library(ggplot2)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 10: CSDID Estimation ==========")
wlog("NOTE: Using manual aggregation due to aggte() bug in did v2.3.0")

panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

# Prepare CSDID data
cs_dt <- panel[year >= 2000 & year <= 2020]
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
# Exclude units treated before panel start
cs_dt <- cs_dt[gname == 0 | gname >= 2002]
cs_dt[gname > 2020, gname := 0]

wlog("CSDID panel: ", nrow(cs_dt), " rows, ", length(unique(cs_dt$unit_id)), " units")
wlog("Treated: ", length(unique(cs_dt[gname > 0]$unit_id)))
wlog("Control: ", length(unique(cs_dt[gname == 0]$unit_id)))

outcomes <- c("violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
              "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
              "black_share_violent_arrests", "black_share_drug_arrests")

bandwidths <- c(3, 4, 5)
annualized_results <- list()
pooled_results <- list()
cohort_results <- list()

for (outcome in outcomes) {
  if (!outcome %in% names(cs_dt)) next
  n_valid <- sum(!is.na(cs_dt[[outcome]]))
  if (n_valid < 100) {
    wlog("SKIP ", outcome, ": only ", n_valid, " non-NA")
    next
  }

  wlog("\n--- Outcome: ", outcome, " ---")

  for (cov_name in c("none", "with_covs")) {
    tryCatch({
      cs_sub <- cs_dt[!is.na(get(outcome))]
      if (cov_name == "with_covs") {
        cs_sub <- cs_sub[!is.na(log_population) & !is.na(pct_black) &
                           is.finite(log_population)]
      }

      # Need at least 10 obs per unit
      cs_sub[, n_obs := .N, by = unit_id]
      cs_sub <- cs_sub[n_obs >= 10]

      if (nrow(cs_sub) < 100) {
        wlog("  SKIP ", cov_name, ": too few rows")
        next
      }

      cs_df <- as.data.frame(cs_sub)

      xf <- if (cov_name == "with_covs") ~ log_population + pct_black else ~ 1

      gt <- att_gt(
        yname = outcome,
        tname = "year",
        idname = "unit_id",
        gname = "gname",
        xformla = xf,
        data = cs_df,
        est_method = "reg",
        control_group = "nevertreated",
        panel = FALSE,
        bstrap = TRUE,
        biters = 200,
        print_details = FALSE
      )

      wlog("  att_gt succeeded (", cov_name, "): ", length(gt$att), " group-time ATTs")

      # Manual aggregation of group-time ATTs
      gt_dt <- data.table(group = gt$group, t = gt$t, att = gt$att, se = gt$se)
      gt_dt[, event_time := t - group]

      # Remove NA or infinite ATTs
      gt_dt <- gt_dt[!is.na(att) & is.finite(att) & !is.na(se) & se > 0]

      for (bw in bandwidths) {
        # Event study (annualized): weighted average by event_time
        es_dt <- gt_dt[event_time >= -5 & event_time <= bw]
        es_agg <- es_dt[, .(
          att = mean(att, na.rm=TRUE),
          # SE: use the average SE (approximation since we don't have full bootstrap)
          se = sqrt(mean(se^2, na.rm=TRUE) / .N),
          n_gt = .N
        ), by = event_time]
        setorder(es_agg, event_time)

        for (i in 1:nrow(es_agg)) {
          annualized_results[[length(annualized_results) + 1]] <- data.table(
            outcome = outcome, bandwidth = bw,
            covariates = cov_name, control_group = "nevertreated",
            est_method = "dr",
            event_time = es_agg$event_time[i],
            att = es_agg$att[i],
            se = es_agg$se[i],
            ci_lower = es_agg$att[i] - 1.96 * es_agg$se[i],
            ci_upper = es_agg$att[i] + 1.96 * es_agg$se[i]
          )
        }

        # Pre-trends check
        pre <- es_agg[event_time < 0]
        if (nrow(pre) > 0) {
          any_sig <- any(abs(pre$att / pre$se) > 1.96, na.rm=TRUE)
          wlog("    BW=", bw, " ", cov_name, " pre-trends: ",
               ifelse(any_sig, "SIGNIFICANT", "ok"))
        }

        # Pooled: average post-treatment ATTs
        post_gt <- gt_dt[event_time >= 0 & event_time <= bw]
        if (nrow(post_gt) > 0) {
          pooled_att <- mean(post_gt$att, na.rm=TRUE)
          pooled_se <- sqrt(mean(post_gt$se^2, na.rm=TRUE) / nrow(post_gt))

          pooled_results[[length(pooled_results) + 1]] <- data.table(
            outcome = outcome, bandwidth = bw,
            covariates = cov_name, control_group = "nevertreated",
            est_method = "dr",
            pooled_att = pooled_att, pooled_se = pooled_se,
            ci_lower = pooled_att - 1.96 * pooled_se,
            ci_upper = pooled_att + 1.96 * pooled_se
          )
          wlog("    BW=", bw, " ", cov_name, ": Pooled ATT=", round(pooled_att, 4),
               " SE=", round(pooled_se, 4))
        }
      }

      # Cohort-level (for no covs only)
      if (cov_name == "none") {
        cohort_agg <- gt_dt[event_time >= 0 & event_time <= 5,
                             .(att = mean(att, na.rm=TRUE),
                               se = sqrt(mean(se^2, na.rm=TRUE) / .N)),
                             by = group]
        cohort_results[[length(cohort_results) + 1]] <- data.table(
          outcome = outcome, bandwidth = 5,
          group = cohort_agg$group,
          att = cohort_agg$att,
          se = cohort_agg$se,
          ci_lower = cohort_agg$att - 1.96 * cohort_agg$se,
          ci_upper = cohort_agg$att + 1.96 * cohort_agg$se
        )
      }

      # Event study plot (for no covs, bw=5)
      if (cov_name == "none") {
        for (bw in bandwidths) {
          es_plot <- gt_dt[event_time >= -5 & event_time <= bw]
          es_plot_agg <- es_plot[, .(att = mean(att, na.rm=TRUE),
                                      se = sqrt(mean(se^2, na.rm=TRUE) / .N)),
                                  by = event_time]
          setorder(es_plot_agg, event_time)
          es_plot_agg[, ci_lower := att - 1.96 * se]
          es_plot_agg[, ci_upper := att + 1.96 * se]

          p <- ggplot(es_plot_agg, aes(x = event_time, y = att)) +
            geom_hline(yintercept = 0, color = "gray60") +
            geom_vline(xintercept = -0.5, linetype = "dashed", color = "red") +
            geom_ribbon(aes(ymin = ci_lower, ymax = ci_upper), alpha = 0.2, fill = "steelblue") +
            geom_line(color = "steelblue") +
            geom_point(color = "steelblue") +
            labs(title = paste0("CSDID Event Study: ", outcome, " (bw=", bw, ")"),
                 x = "Event Time", y = "ATT") +
            theme_minimal()

          ggsave(file.path(base_dir, paste0("output/figures/eventstudy_csdid_",
                                             outcome, "_bw", bw, ".png")),
                 p, width = 8, height = 5, dpi = 150)
        }
      }

    }, error = function(e) {
      wlog("  ERROR (", cov_name, "): ", e$message)
    })
  }
}

# Save results
if (length(annualized_results) > 0) {
  ann_dt <- rbindlist(annualized_results, fill = TRUE)
  fwrite(ann_dt, file.path(base_dir, "output/tables/csdid_annualized.csv"))
  wlog("\nSaved ", nrow(ann_dt), " CSDID annualized results")
} else {
  fwrite(data.table(note = "No results"), file.path(base_dir, "output/tables/csdid_annualized.csv"))
}

if (length(pooled_results) > 0) {
  pool_dt <- rbindlist(pooled_results, fill = TRUE)
  fwrite(pool_dt, file.path(base_dir, "output/tables/csdid_pooled.csv"))
  wlog("Saved ", nrow(pool_dt), " CSDID pooled results")
  cat("\nCSCID Pooled Results:\n")
  print(pool_dt)
} else {
  fwrite(data.table(note = "No results"), file.path(base_dir, "output/tables/csdid_pooled.csv"))
}

if (length(cohort_results) > 0) {
  coh_dt <- rbindlist(cohort_results, fill = TRUE)
  fwrite(coh_dt, file.path(base_dir, "output/tables/csdid_by_cohort.csv"))
  wlog("Saved CSDID cohort results")
} else {
  fwrite(data.table(note = "No results"), file.path(base_dir, "output/tables/csdid_by_cohort.csv"))
}

wlog("Step 10 complete.\n")
