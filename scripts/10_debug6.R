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
cs_dt[, n_obs := .N, by = unit_id]
cs_dt <- cs_dt[n_obs >= 10]

cs_sub <- cs_dt[!is.na(violent_clearance_rate)]
cs_df <- as.data.frame(cs_sub)

cat("Data:", nrow(cs_df), "rows,", length(unique(cs_df$unit_id)), "units\n")

# Try with bstrap instead of analytical
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

cat("att_gt class:", class(gt), "\n")
cat("V_analytical class:", class(gt$V_analytical), "\n")
cat("n att values:", length(gt$att), "\n")

# Check if V_analytical needs conversion
# The aggte error might be from Matrix package version issue
# Try to manually convert V to regular matrix
gt$V_analytical <- as.matrix(gt$V_analytical)
cat("V_analytical class after conversion:", class(gt$V_analytical), "\n")

es <- tryCatch(aggte(gt, type = "dynamic", min_e = -5, max_e = 5),
               error = function(e) { cat("Error:", e$message, "\n"); NULL })

if (!is.null(es)) {
  cat("SUCCESS!\n")
  for (i in seq_along(es$egt)) {
    cat("  e=", es$egt[i], ": ATT=", round(es$att.egt[i], 4), "\n")
  }
}

# Also try simple
simple <- tryCatch(aggte(gt, type = "simple"),
                    error = function(e) { cat("Simple error:", e$message, "\n"); NULL })
if (!is.null(simple)) {
  cat("Simple ATT:", round(simple$overall.att, 4), "\n")
}
