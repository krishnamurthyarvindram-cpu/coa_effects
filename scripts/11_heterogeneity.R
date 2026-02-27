##############################################################################
# 11_heterogeneity.R — Step 11: Heterogeneity Analysis
# Subgroup CSDID estimation by COA power type, city size, race, and region
##############################################################################

library(data.table)
library(did)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 11: Heterogeneity Analysis ==========")

panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

# Prepare CSDID data (same restrictions as Step 10)
cs_dt <- panel[year >= 2000 & year <= 2020]
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
cs_dt <- cs_dt[gname == 0 | gname >= 2002]
cs_dt[gname > 2020, gname := 0]

wlog("Heterogeneity panel: ", nrow(cs_dt), " rows, ", length(unique(cs_dt$unit_id)), " units")

# ---------------------------------------------------------------
# Define subgroup splits
# ---------------------------------------------------------------

# Southern states (Census South region)
south_states <- c("al", "ar", "de", "fl", "ga", "ky", "la", "md", "ms",
                   "nc", "ok", "sc", "tn", "tx", "va", "wv", "dc")
cs_dt[, is_south := as.integer(state_clean %in% south_states)]

# City size: above/below median population (using agency-level median)
agency_pop <- cs_dt[, .(med_pop = median(population, na.rm=TRUE)), by = unit_id]
overall_med_pop <- median(agency_pop$med_pop, na.rm=TRUE)
cs_dt <- merge(cs_dt, agency_pop, by = "unit_id", all.x = TRUE)
cs_dt[, large_city := as.integer(med_pop >= overall_med_pop)]
wlog("Median population cutoff: ", round(overall_med_pop))

# Racial composition: above/below median % Black (using agency-level median)
agency_black <- cs_dt[, .(med_black = median(pct_black, na.rm=TRUE)), by = unit_id]
overall_med_black <- median(agency_black$med_black, na.rm=TRUE)
cs_dt <- merge(cs_dt, agency_black, by = "unit_id", all.x = TRUE)
cs_dt[, high_black := as.integer(med_black >= overall_med_black)]
wlog("Median % Black cutoff: ", round(overall_med_black, 4))

# Define subgroup specifications
# Each: list(name, filter_expr for treated units — controls always all included)
subgroups <- list(
  # By COA power type
  list(name = "invest_power_1", label = "Investigative Power: Yes",
       dim = "coa_power", filter = "invest_power == 1"),
  list(name = "invest_power_0", label = "Investigative Power: No",
       dim = "coa_power", filter = "invest_power == 0"),
  list(name = "discipline_power_1", label = "Disciplinary Power: Yes",
       dim = "coa_power", filter = "discipline_power == 1"),
  list(name = "discipline_power_0", label = "Disciplinary Power: No",
       dim = "coa_power", filter = "discipline_power == 0"),

  # By city size
  list(name = "large_city", label = "Large City (above median pop)",
       dim = "city_size", filter = "large_city == 1"),
  list(name = "small_city", label = "Small City (below median pop)",
       dim = "city_size", filter = "large_city == 0"),

  # By racial composition
  list(name = "high_black", label = "High % Black (above median)",
       dim = "race", filter = "high_black == 1"),
  list(name = "low_black", label = "Low % Black (below median)",
       dim = "race", filter = "high_black == 0"),

  # By region
  list(name = "south", label = "South",
       dim = "region", filter = "is_south == 1"),
  list(name = "non_south", label = "Non-South",
       dim = "region", filter = "is_south == 0")
)

outcomes <- c("violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
              "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
              "black_share_violent_arrests", "black_share_drug_arrests")

bandwidths <- c(3, 4, 5)
het_results <- list()

# ---------------------------------------------------------------
# Run CSDID for each subgroup × outcome × bandwidth
# ---------------------------------------------------------------
for (sg in subgroups) {
  wlog("\n====== Subgroup: ", sg$label, " ======")

  # Subset: keep all controls + treated units matching filter
  controls <- cs_dt[gname == 0]
  treated_sub <- cs_dt[gname > 0 & eval(parse(text = sg$filter))]
  n_treated <- length(unique(treated_sub$unit_id))
  wlog("  Treated units in subgroup: ", n_treated)

  if (n_treated < 3) {
    wlog("  SKIP: fewer than 3 treated units")
    next
  }

  sub_dt <- rbind(controls, treated_sub)
  # Re-create unit_id for this subset
  sub_dt[, sub_unit_id := as.integer(as.factor(paste0(unit_id, "_", agency_id)))]

  for (outcome in outcomes) {
    if (!outcome %in% names(sub_dt)) next
    n_valid <- sum(!is.na(sub_dt[[outcome]]))
    if (n_valid < 50) next

    for (bw in bandwidths) {
      tryCatch({
        cs_sub <- sub_dt[!is.na(get(outcome))]
        cs_sub[, n_obs := .N, by = sub_unit_id]
        cs_sub <- cs_sub[n_obs >= 10]

        if (nrow(cs_sub) < 50) next

        cs_df <- as.data.frame(cs_sub)

        gt <- att_gt(
          yname = outcome,
          tname = "year",
          idname = "sub_unit_id",
          gname = "gname",
          xformla = ~ 1,
          data = cs_df,
          est_method = "reg",
          control_group = "nevertreated",
          panel = FALSE,
          bstrap = TRUE,
          biters = 200,
          print_details = FALSE
        )

        # Manual aggregation
        gt_dt <- data.table(group = gt$group, t = gt$t, att = gt$att, se = gt$se)
        gt_dt[, event_time := t - group]
        gt_dt <- gt_dt[!is.na(att) & is.finite(att) & !is.na(se) & se > 0]

        # Annualized (event study)
        es_dt <- gt_dt[event_time >= -5 & event_time <= bw]
        es_agg <- es_dt[, .(
          att = mean(att, na.rm=TRUE),
          se = sqrt(mean(se^2, na.rm=TRUE) / .N),
          n_gt = .N
        ), by = event_time]

        for (i in 1:nrow(es_agg)) {
          het_results[[length(het_results) + 1]] <- data.table(
            subgroup = sg$name, subgroup_label = sg$label,
            dimension = sg$dim, result_type = "annualized",
            outcome = outcome, bandwidth = bw,
            event_time = es_agg$event_time[i],
            att = es_agg$att[i], se = es_agg$se[i],
            ci_lower = es_agg$att[i] - 1.96 * es_agg$se[i],
            ci_upper = es_agg$att[i] + 1.96 * es_agg$se[i],
            n_treated = n_treated
          )
        }

        # Pooled
        post_gt <- gt_dt[event_time >= 0 & event_time <= bw]
        if (nrow(post_gt) > 0) {
          pooled_att <- mean(post_gt$att, na.rm=TRUE)
          pooled_se <- sqrt(mean(post_gt$se^2, na.rm=TRUE) / nrow(post_gt))

          het_results[[length(het_results) + 1]] <- data.table(
            subgroup = sg$name, subgroup_label = sg$label,
            dimension = sg$dim, result_type = "pooled",
            outcome = outcome, bandwidth = bw,
            event_time = NA_real_,
            att = pooled_att, se = pooled_se,
            ci_lower = pooled_att - 1.96 * pooled_se,
            ci_upper = pooled_att + 1.96 * pooled_se,
            n_treated = n_treated
          )

          wlog("    ", outcome, " bw=", bw, ": ATT=", round(pooled_att, 4),
               " SE=", round(pooled_se, 4))
        }

      }, error = function(e) {
        wlog("    ERROR (", outcome, " bw=", bw, "): ", e$message)
      })
    }
  }
}

# ---------------------------------------------------------------
# Save results
# ---------------------------------------------------------------
if (length(het_results) > 0) {
  het_dt <- rbindlist(het_results, fill = TRUE)
  fwrite(het_dt, file.path(base_dir, "output/tables/heterogeneity_results.csv"))
  wlog("\nSaved ", nrow(het_dt), " heterogeneity results")

  # Print pooled summary
  pooled <- het_dt[result_type == "pooled"]
  cat("\nHeterogeneity Pooled Results (bw=5):\n")
  print(pooled[bandwidth == 5, .(subgroup_label, outcome, att = round(att, 4),
                                   se = round(se, 4), n_treated)])
} else {
  fwrite(data.table(note = "No results"), file.path(base_dir, "output/tables/heterogeneity_results.csv"))
  wlog("WARNING: No heterogeneity results produced")
}

wlog("Step 11 complete.\n")
