library(data.table)
library(did)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

cs_dt <- panel[year >= 2000 & year <= 2020]
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
cs_dt <- cs_dt[gname == 0 | gname >= 2002]
cs_dt[gname > 2020, gname := 0]

cs_sub <- cs_dt[!is.na(violent_clearance_rate)]
cs_sub[, n_obs := .N, by = unit_id]
cs_sub <- cs_sub[n_obs >= 10]
cs_df <- as.data.frame(cs_sub)

gt <- att_gt(
  yname = "violent_clearance_rate",
  tname = "year",
  idname = "unit_id",
  gname = "gname",
  data = cs_df,
  est_method = "reg",
  control_group = "nevertreated",
  panel = FALSE,
  bstrap = TRUE,
  biters = 100,
  print_details = FALSE
)

cat("inffunc class:", class(gt$inffunc), "\n")
cat("inffunc dim:", dim(gt$inffunc), "\n")
cat("inffunc is NULL:", is.null(gt$inffunc), "\n")

# Check if inffunc is a sparse matrix
if (inherits(gt$inffunc, "dgCMatrix") || inherits(gt$inffunc, "Matrix")) {
  cat("inffunc is sparse, converting...\n")
  gt$inffunc <- as.matrix(gt$inffunc)
}

# Also convert V_analytical
if (inherits(gt$V_analytical, "dgCMatrix") || inherits(gt$V_analytical, "Matrix")) {
  cat("V_analytical is sparse, converting...\n")
  gt$V_analytical <- as.matrix(gt$V_analytical)
}

# Try aggte again
es <- tryCatch(aggte(gt, type = "dynamic", min_e = -5, max_e = 5),
               error = function(e) {
                 cat("Error:", conditionMessage(e), "\n")
                 cat("Call:", deparse(conditionCall(e)), "\n")
                 NULL
               })

if (!is.null(es)) {
  cat("aggte succeeded!\n")
} else {
  # Manual aggregation as fallback
  cat("\n--- Manual aggregation ---\n")
  gt_dt <- data.table(group = gt$group, t = gt$t, att = gt$att, se = gt$se)
  gt_dt[, event_time := t - group]

  # Event study: average ATTs by event_time
  es_manual <- gt_dt[, .(att = weighted.mean(att, 1/se^2, na.rm=TRUE),
                          se = sqrt(1/sum(1/se^2, na.rm=TRUE)),
                          n = .N),
                      by = event_time]
  setorder(es_manual, event_time)
  es_manual <- es_manual[event_time >= -5 & event_time <= 5]

  cat("Manual event study:\n")
  for (i in 1:nrow(es_manual)) {
    cat("  e=", es_manual$event_time[i], ": ATT=", round(es_manual$att[i], 4),
        " SE=", round(es_manual$se[i], 4),
        " sig=", ifelse(abs(es_manual$att[i]/es_manual$se[i]) > 1.96, "*", ""), "\n")
  }

  # Simple pooled: average all post-treatment ATTs
  post <- gt_dt[event_time >= 0]
  pooled_att <- mean(post$att, na.rm=TRUE)
  pooled_se <- sqrt(mean(post$se^2, na.rm=TRUE) / nrow(post))
  cat("\nPooled ATT:", round(pooled_att, 4), " SE:", round(pooled_se, 4), "\n")
}
