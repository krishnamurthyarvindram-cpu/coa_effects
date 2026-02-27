library(data.table)
library(did)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

cs_dt <- panel[year >= 2000 & year <= 2020]
# gname as NUMERIC (not integer)
cs_dt[, gname := as.numeric(treatment_year)]
cs_dt[treatment_year == 0, gname := 0]
cs_dt <- cs_dt[gname == 0 | (gname >= 2002 & gname <= 2018)]

cs_sub <- cs_dt[!is.na(violent_clearance_rate)]
cs_df <- as.data.frame(cs_sub)

cat("Never-treated (gname==0):", sum(cs_df$gname == 0), "\n")
cat("Treated:", sum(cs_df$gname > 0), "\n")
cat("gname type:", class(cs_df$gname), "\n")

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

cat("att_gt succeeded. Trying aggte...\n")

es <- tryCatch({
  aggte(gt, type = "dynamic", min_e = -5, max_e = 5)
}, error = function(e) {
  cat("aggte dynamic error:", e$message, "\n")
  NULL
})

if (!is.null(es)) {
  cat("aggte dynamic succeeded!\n")
  cat("ATTs:\n")
  for (i in seq_along(es$egt)) {
    cat("  t=", es$egt[i], ": ATT=", round(es$att.egt[i], 4),
        " SE=", round(es$se.egt[i], 4), "\n")
  }
}

simple <- tryCatch(aggte(gt, type = "simple"), error = function(e) {
  cat("simple error:", e$message, "\n"); NULL
})

if (!is.null(simple)) {
  cat("Simple ATT:", round(simple$overall.att, 4),
      " SE:", round(simple$overall.se, 4), "\n")
}
