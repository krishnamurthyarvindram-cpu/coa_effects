library(data.table)
library(did)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

# Start from 2000, only keep units that are either:
# 1. Never treated (treatment_year == 0)
# 2. Treated WITHIN the panel period (treatment_year >= 2002 to allow pre-periods)
cs_dt <- panel[year >= 2000 & year <= 2020]
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]

# EXCLUDE units treated before panel start
cs_dt <- cs_dt[gname == 0 | gname >= 2002]
# Also exclude units treated too late (no post data)
cs_dt[gname > 2020, gname := 0]

# Only keep units with at least 10 years of data
cs_dt[, n_obs := .N, by = unit_id]
cs_dt <- cs_dt[n_obs >= 10]

cs_sub <- cs_dt[!is.na(violent_clearance_rate)]
cs_df <- as.data.frame(cs_sub)

cat("Data:", nrow(cs_df), "rows,", length(unique(cs_df$unit_id)), "units\n")
cat("Treated:", length(unique(cs_df[cs_df$gname > 0, "unit_id"])), "units\n")
cat("Never-treated:", length(unique(cs_df[cs_df$gname == 0, "unit_id"])), "units\n")
cat("Cohorts:", paste(sort(unique(cs_df$gname[cs_df$gname > 0])), collapse=", "), "\n")

gt <- att_gt(
  yname = "violent_clearance_rate",
  tname = "year",
  idname = "unit_id",
  gname = "gname",
  data = cs_df,
  est_method = "reg",
  control_group = "nevertreated",
  panel = FALSE,
  print_details = FALSE
)

cat("\natt_gt succeeded. Groups:", length(unique(gt$group)), "\n")
cat("Trying aggte...\n")

es <- tryCatch(aggte(gt, type = "dynamic", min_e = -5, max_e = 5),
               error = function(e) { cat("Error:", e$message, "\n"); NULL })

if (!is.null(es)) {
  cat("SUCCESS! Dynamic aggregation:\n")
  for (i in seq_along(es$egt)) {
    cat("  e=", es$egt[i], ": ATT=", round(es$att.egt[i], 4),
        " SE=", round(es$se.egt[i], 4), "\n")
  }
}

simple <- tryCatch(aggte(gt, type = "simple"),
                    error = function(e) { cat("Simple error:", e$message, "\n"); NULL })
if (!is.null(simple)) {
  cat("Simple ATT:", round(simple$overall.att, 4), " SE:", round(simple$overall.se, 4), "\n")
}
