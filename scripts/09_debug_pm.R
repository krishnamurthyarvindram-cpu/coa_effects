library(data.table)
library(PanelMatch)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/analysis_panel.rds")))

# Prepare
panel[, unit_id := as.integer(as.factor(agency_id))]
panel[, treat := as.integer(post)]
panel[treated == 0, treat := 0L]

# Small test subset
pm_dt <- panel[year >= 2000 & year <= 2021 & !is.na(violent_clearance_rate)]

# Check treatment pattern
cat("Treatment distribution:\n")
print(table(pm_dt$treat, useNA="ifany"))

# Check how many units switch from 0 to 1
pm_dt <- pm_dt[order(unit_id, year)]
pm_dt[, treat_change := treat - shift(treat), by = unit_id]
cat("\nTreatment transitions:\n")
print(table(pm_dt$treat_change, useNA="ifany"))

cat("\nUnits that switch to treatment:", length(unique(pm_dt[treat_change == 1]$unit_id)), "\n")

# Check for gaps in panel
pm_dt[, year_gap := year - shift(year), by = unit_id]
cat("Year gaps:\n")
print(table(pm_dt$year_gap, useNA="ifany"))

# Try PanelData with minimal data
test_df <- as.data.frame(pm_dt[, .(unit_id, year, treat, violent_clearance_rate)])
cat("\nTest data: ", nrow(test_df), "rows, ", length(unique(test_df$unit_id)), "units\n")
cat("Years:", range(test_df$year), "\n")

# Create PanelData
tryCatch({
  pd <- PanelData(
    panel.data = test_df,
    unit.id = "unit_id",
    time.id = "year",
    treatment = "treat",
    outcome = "violent_clearance_rate"
  )
  cat("PanelData created successfully\n")
  cat("Class:", class(pd), "\n")
  cat("Names:", names(pd), "\n")

  # Try simple PanelMatch
  pm <- PanelMatch(
    panel.data = pd,
    lag = 3,
    refinement.method = "none",
    qoi = "att",
    lead = 0:3,
    match.missing = TRUE,
    forbid.treatment.reversal = TRUE
  )
  cat("PanelMatch succeeded!\n")
  cat("Class:", class(pm), "\n")

  # Try PanelEstimate
  pe <- PanelEstimate(
    sets = pm,
    panel.data = pd,
    se.method = "bootstrap",
    number.iterations = 50,
    confidence.level = 0.95
  )
  cat("PanelEstimate succeeded!\n")
  print(summary(pe))

}, error = function(e) {
  cat("ERROR:", e$message, "\n")
  cat("Traceback:\n")
  traceback()
})
