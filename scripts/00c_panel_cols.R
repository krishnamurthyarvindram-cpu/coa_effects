## Check all column names for offense/crime data patterns
panel <- readRDS("C:/Users/arvind/Desktop/coa_effects/raw_data/data_panel_post1990.rds")
nms <- names(panel)

# Search for offense/crime/clearance patterns more broadly
patterns <- c("actual", "clear", "unfound", "murder", "rape", "robbery",
              "assault", "burglary", "larceny", "vehicle", "arson",
              "crime", "violent_crime", "property_crime", "homicide",
              "manslaughter")
for (p in patterns) {
  m <- grep(p, nms, ignore.case=TRUE, value=TRUE)
  if (length(m) > 0) cat(p, ":", paste(m[1:min(5, length(m))], collapse=", "),
                          ifelse(length(m) > 5, paste0("... (", length(m), " total)"), ""), "\n")
}

# Also check: what does "vio" mean? Is it arrests or offenses?
# And what's in unfound columns?
cat("\n--- Unfound columns sample values ---\n")
cat("unfound_all_crimes:", paste(head(panel$unfound_all_crimes, 10), collapse=", "), "\n")
cat("unfound_index_violent:", paste(head(panel$unfound_index_violent, 10), collapse=", "), "\n")

# Check if there's an actual_* prefix (offenses known)
actual_cols <- grep("^actual", nms, ignore.case=TRUE, value=TRUE)
cat("\nActual columns:", paste(actual_cols, collapse=", "), "\n")

# Check for tot_offenses or similar
off_cols <- grep("tot_off|offense|known|reported_crime|ucr_crime", nms, ignore.case=TRUE, value=TRUE)
cat("Offense columns:", paste(off_cols, collapse=", "), "\n")

# What about police-specific variables like use of force?
force_cols <- grep("force|shoot|complaint|misconduct|excessive", nms, ignore.case=TRUE, value=TRUE)
cat("Force/misconduct columns:", paste(force_cols, collapse=", "), "\n")

# Check distinct values of key treatment-related columns
# Check for any column with < 5 unique values that might be treatment indicators
binary_cols <- character(0)
for (nm in nms[1:100]) {
  if (length(unique(panel[[nm]])) <= 5 && is.numeric(panel[[nm]])) {
    binary_cols <- c(binary_cols, nm)
  }
}
cat("\nBinary/few-value numeric cols (first 100):", paste(binary_cols, collapse=", "), "\n")

rm(panel); gc()
