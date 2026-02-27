library(data.table)
library(did)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))
panel[, unit_id := as.integer(as.factor(agency_id))]

# Use small sample
cs_dt <- panel[year >= 2000 & year <= 2020]
cs_dt[, gname := treatment_year]
cs_dt[treatment_year == 0, gname := 0L]
cs_dt <- cs_dt[gname == 0 | (gname >= 2002 & gname <= 2018)]
cs_dt[gname > 2020, gname := 0L]

cs_sub <- cs_dt[!is.na(violent_clearance_rate)]
cs_df <- as.data.frame(cs_sub)

cat("Data: ", nrow(cs_df), " rows, ", length(unique(cs_df$unit_id)), " units\n")
cat("Treated units: ", length(unique(cs_df[cs_df$gname > 0, "unit_id"])), "\n")
cat("Cohorts: ", paste(sort(unique(cs_df$gname[cs_df$gname > 0])), collapse=", "), "\n")

# Try att_gt
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

cat("att_gt class:", class(gt), "\n")
cat("att_gt names:", names(gt), "\n")

# Try aggte
es <- tryCatch({
  aggte(gt, type = "dynamic", min_e = -5, max_e = 5)
}, error = function(e) {
  cat("aggte error:", e$message, "\n")
  # Try without min/max
  tryCatch({
    aggte(gt, type = "dynamic")
  }, error = function(e2) {
    cat("aggte error2:", e2$message, "\n")
    NULL
  })
})

if (!is.null(es)) {
  cat("aggte succeeded!\n")
  cat("Event times:", es$egt, "\n")
  cat("ATTs:", round(es$att.egt, 4), "\n")
} else {
  cat("aggte failed\n")
}

# Try simple
simple <- tryCatch({
  aggte(gt, type = "simple")
}, error = function(e) {
  cat("simple error:", e$message, "\n")
  NULL
})

if (!is.null(simple)) {
  cat("Simple ATT:", round(simple$overall.att, 4), " SE:", round(simple$overall.se, 4), "\n")
}
