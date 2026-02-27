library(data.table)
library(did)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

cs_dt <- panel[year >= 2000 & year <= 2020]
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
# Only keep cohorts with enough units (at least 2)
gname_counts <- cs_dt[gname > 0, .(n = length(unique(unit_id))), by = gname]
big_cohorts <- gname_counts[n >= 2]$gname
cs_dt <- cs_dt[gname == 0 | gname %in% big_cohorts]

cs_sub <- cs_dt[!is.na(violent_clearance_rate)]
cs_df <- as.data.frame(cs_sub)

cat("Cohort sizes:\n")
print(gname_counts[order(gname)])
cat("\nUsing cohorts with n>=2:", paste(big_cohorts, collapse=", "), "\n")
cat("Data:", nrow(cs_df), "rows,", length(unique(cs_df$unit_id)), "units\n")

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

cat("\natt_gt result:\n")
cat("  class:", class(gt), "\n")
cat("  groups:", head(gt$group), "\n")
cat("  t:", head(gt$t), "\n")
cat("  att:", head(gt$att), "\n")
cat("  se:", head(gt$se), "\n")
cat("  n att values:", length(gt$att), "\n")
cat("  V_analytical:", class(gt$V_analytical), "\n")
cat("  V_analytical is NULL:", is.null(gt$V_analytical), "\n")

# Try with allow_unbalanced_panel
gt2 <- tryCatch({
  att_gt(
    yname = "violent_clearance_rate",
    tname = "year",
    idname = "unit_id",
    gname = "gname",
    data = cs_df,
    est_method = "reg",
    control_group = "nevertreated",
    panel = FALSE,
    allow_unbalanced_panel = TRUE,
    print_details = FALSE
  )
}, error = function(e) {
  cat("att_gt2 error:", e$message, "\n")
  NULL
})

if (!is.null(gt2)) {
  cat("\ngt2 V_analytical is NULL:", is.null(gt2$V_analytical), "\n")

  es2 <- tryCatch(aggte(gt2, type = "dynamic"), error = function(e) {
    cat("aggte error:", e$message, "\n"); NULL
  })
  if (!is.null(es2)) cat("aggte succeeded with gt2!\n")
}

# Try the example from did documentation
cat("\n--- Testing with did package example ---\n")
data(mpdta)
cat("mpdta:", nrow(mpdta), "rows\n")
gt_ex <- att_gt(yname = "lemp", tname = "year", idname = "countyreal",
                gname = "first.treat", data = mpdta, panel = FALSE)
es_ex <- aggte(gt_ex, type = "dynamic")
cat("Example aggte succeeded!\n")
cat("Example ATTs:", round(es_ex$att.egt[1:3], 4), "\n")
