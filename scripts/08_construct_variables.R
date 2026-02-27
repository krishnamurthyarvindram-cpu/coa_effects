##############################################################################
# 08_construct_variables.R — Step 8: Construct Analysis Variables
##############################################################################

library(data.table)
library(ggplot2)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 8: Construct Analysis Variables ==========")

panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/panel_merged.rds")))
wlog("Loaded panel: ", nrow(panel), " x ", ncol(panel))

# ---------------------------------------------------------------
# Treatment Variables
# ---------------------------------------------------------------
panel[, treated := as.integer(treatment_year > 0)]
panel[, post := as.integer(treated == 1 & year >= treatment_year)]
panel[, relative_time := fifelse(treated == 1, year - treatment_year, NA_integer_)]

wlog("Treatment variables constructed:")
wlog("  Treated units: ", sum(panel$treated == 1))
wlog("  Post-treatment obs: ", sum(panel$post == 1, na.rm=TRUE))
wlog("  Relative time range: ", min(panel$relative_time, na.rm=TRUE), " to ",
     max(panel$relative_time, na.rm=TRUE))

# For CSDID, gname = treatment_year (0 for never-treated)
panel[, gname := treatment_year]

# ---------------------------------------------------------------
# Population — use best available
# ---------------------------------------------------------------
panel[, population := fifelse(!is.na(population_est), population_est,
                               fifelse(!is.na(population_base), population_base,
                                       population_2020))]

wlog("Population: ", sum(is.na(panel$population)), " NAs out of ", nrow(panel))
# For per-capita rates, need positive population
panel[population <= 0 | is.na(population), population := NA_real_]

# ---------------------------------------------------------------
# Outcome Variables
# ---------------------------------------------------------------

# 1. Violent crime (offenses known) — from actual_index_violent
panel[, violent_crime := actual_index_violent]

# 2. Violent clearance rate
clr_viol <- grep("^tot_clr_.*violent", names(panel), value=TRUE)
if (length(clr_viol) > 0) {
  panel[, violent_cleared := get(clr_viol[1])]
  panel[, violent_clearance_rate := fifelse(violent_crime > 0,
                                             violent_cleared / violent_crime, NA_real_)]
  # Winsorize to [0, 1]
  panel[violent_clearance_rate > 1, violent_clearance_rate := 1]
  panel[violent_clearance_rate < 0, violent_clearance_rate := 0]
  wlog("Violent clearance rate: ", sum(!is.na(panel$violent_clearance_rate)), " non-NA values")
} else {
  wlog("WARNING: No violent clearance column found, creating NA placeholder")
  panel[, violent_clearance_rate := NA_real_]
}

# 3. Property clearance rate
clr_prop <- grep("^tot_clr_.*property", names(panel), value=TRUE)
if (length(clr_prop) > 0) {
  panel[, property_cleared := get(clr_prop[1])]
  panel[, property_clearance_rate := fifelse(actual_index_property > 0,
                                              property_cleared / actual_index_property, NA_real_)]
  panel[property_clearance_rate > 1, property_clearance_rate := 1]
  panel[property_clearance_rate < 0, property_clearance_rate := 0]
  wlog("Property clearance rate: ", sum(!is.na(panel$property_clearance_rate)), " non-NA values")
} else {
  wlog("WARNING: No property clearance column found, creating NA placeholder")
  panel[, property_clearance_rate := NA_real_]
}

# 4. Drug arrests (already in panel as drug_tot_arrests)
panel[, drug_arrests := drug_tot_arrests]

# 5. Discretionary arrests: oth_tot_arrests is "other" arrests which may approximate
# quality-of-life arrests. The panel has oth_tot_arrests which includes suspicion,
# vagrancy, vandalism, gambling, prostitution, drug, liquor, curfew, drunkenness.
# However, drug is separate. So discretionary = drug + other
panel[, discretionary_arrests := fifelse(!is.na(drug_tot_arrests) & !is.na(oth_tot_arrests),
                                          drug_tot_arrests + oth_tot_arrests, NA_real_)]

# 6. Police killings (already merged: total_killings)
panel[, police_killings := total_killings]

# 7. Violent arrests (vio_tot_arrests)
panel[, violent_arrests := vio_tot_arrests]

# ---------------------------------------------------------------
# Racial Disparity Variables
# ---------------------------------------------------------------

# Black share of violent arrests
panel[, black_share_violent_arrests := fifelse(vio_tot_arrests >= 5,
                                                vio_tot_black / vio_tot_arrests, NA_real_)]

# Black share of drug arrests
panel[, black_share_drug_arrests := fifelse(drug_tot_arrests >= 5,
                                             drug_tot_black / drug_tot_arrests, NA_real_)]

# Black share of discretionary arrests
panel[, black_share_discretionary := fifelse(!is.na(drug_tot_black) & !is.na(oth_tot_black) &
                                               discretionary_arrests >= 5,
                                              (drug_tot_black + oth_tot_black) / discretionary_arrests,
                                              NA_real_)]

# Black share of police killings
panel[, black_share_killings := fifelse(total_killings >= 5,
                                         black_killings / total_killings, NA_real_)]

# Nonwhite share of killings
panel[, nonwhite_share_killings := fifelse(total_killings >= 5,
                                            nonwhite_killings / total_killings, NA_real_)]

# ---------------------------------------------------------------
# Per Capita Rates (per 100,000)
# ---------------------------------------------------------------
per100k <- function(count, pop) {
  fifelse(!is.na(count) & !is.na(pop) & pop > 0, count / pop * 100000, NA_real_)
}

panel[, violent_crime_pc := per100k(violent_crime, population)]
panel[, drug_arrests_pc := per100k(drug_arrests, population)]
panel[, discretionary_arrests_pc := per100k(discretionary_arrests, population)]
panel[, police_killings_pc := per100k(police_killings, population)]
panel[, violent_arrests_pc := per100k(violent_arrests, population)]

# ---------------------------------------------------------------
# Covariates
# ---------------------------------------------------------------
panel[, log_population := log(population + 1)]

# Median income — check if available
inc_cols <- grep("income|median", names(panel), ignore.case=TRUE, value=TRUE)
wlog("Income columns available: ", paste(inc_cols, collapse=", "))

# If no income column, we'll use what we have
if (length(inc_cols) == 0) {
  wlog("NOTE: No median income variable available. Will use demographics only.")
  panel[, median_income := NA_real_]
}

# ---------------------------------------------------------------
# Sample Restrictions
# ---------------------------------------------------------------
wlog("\n--- Sample Restrictions ---")
wlog("Before restrictions: ", nrow(panel), " rows")

# months_reported check
panel[, months_reported := number_of_months_reported]
wlog("months_reported distribution:")
print(table(panel$months_reported, useNA="ifany"))

# Drop agency-years with months_reported < 3 (but keep if NA — some panels don't have this)
panel[, sample_flag := 1L]
panel[!is.na(months_reported) & months_reported < 3, sample_flag := 0L]
wlog("Dropped for months_reported < 3: ", sum(panel$sample_flag == 0))

# Drop agencies with fewer than 5 years in panel
panel[, n_years := .N, by = agency_id]
panel[n_years < 5, sample_flag := 0L]
wlog("Dropped for < 5 years in panel: ",
     sum(panel$n_years < 5 & panel$sample_flag == 1))

# Flag large population jumps
panel[, pop_change := population / shift(population) - 1, by = agency_id]
panel[, large_pop_jump := as.integer(abs(pop_change) > 0.3)]
wlog("Flagged large population jumps (>30%): ", sum(panel$large_pop_jump == 1, na.rm=TRUE))

# Analysis sample
analysis <- panel[sample_flag == 1]
wlog("\nAnalysis sample: ", nrow(analysis), " rows")
wlog("  Unique agencies: ", length(unique(analysis$agency_id)))
wlog("  Treated: ", length(unique(analysis[treated == 1]$agency_id)))
wlog("  Control: ", length(unique(analysis[treated == 0]$agency_id)))
wlog("  Year range: ", min(analysis$year), " - ", max(analysis$year))

# ---------------------------------------------------------------
# Further restrict: drop treated units with treatment_year > 2021
# (panel only goes to 2021, so treatments in 2022+ have no post data)
# ---------------------------------------------------------------
# For estimation, we need treatment_year within the panel years
# Keep them but note for CSDID they won't contribute post-treatment info
treatment_in_range <- analysis[treated == 1 & treatment_year <= max(analysis$year)]
wlog("Treated units with treatment in panel range: ",
     length(unique(treatment_in_range$agency_id)))

# ---------------------------------------------------------------
# Save Analysis Dataset
# ---------------------------------------------------------------
saveRDS(analysis, file.path(base_dir, "merged_data/analysis_panel.rds"))
wlog("Saved analysis panel to merged_data/analysis_panel.rds")

# ---------------------------------------------------------------
# Summary Statistics
# ---------------------------------------------------------------
wlog("\n--- Summary Statistics ---")

outcome_vars <- c("violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
                   "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
                   "violent_arrests_pc",
                   "black_share_violent_arrests", "black_share_drug_arrests",
                   "black_share_discretionary")

# Summary by treated/control
summary_list <- list()
for (v in outcome_vars) {
  if (v %in% names(analysis)) {
    for (grp in c(0, 1)) {
      vals <- analysis[treated == grp][[v]]
      vals <- vals[!is.na(vals)]
      summary_list[[length(summary_list) + 1]] <- data.table(
        variable = v,
        group = ifelse(grp == 1, "Treated", "Control"),
        n = length(vals),
        mean = round(mean(vals), 4),
        sd = round(sd(vals), 4),
        median = round(median(vals), 4),
        min = round(min(vals), 4),
        max = round(max(vals), 4)
      )
    }
  }
}
summary_dt <- rbindlist(summary_list)
fwrite(summary_dt, file.path(base_dir, "output/tables/summary_stats.csv"))
wlog("Saved summary statistics to output/tables/summary_stats.csv")
cat("\nSummary Statistics:\n")
print(summary_dt)

# ---------------------------------------------------------------
# Pre-treatment Trend Means
# ---------------------------------------------------------------
pretrend_data <- analysis[treated == 1 & !is.na(relative_time) & relative_time >= -5 & relative_time <= 5]
if (nrow(pretrend_data) > 0) {
  pretrend_means <- pretrend_data[, lapply(.SD, function(x) mean(x, na.rm=TRUE)),
                                   by = relative_time,
                                   .SDcols = intersect(outcome_vars, names(pretrend_data))]
  setorder(pretrend_means, relative_time)
  fwrite(pretrend_means, file.path(base_dir, "output/tables/pretrends_means.csv"))
  wlog("Saved pre-trend means to output/tables/pretrends_means.csv")

  # Plot raw pre-trends
  for (v in intersect(outcome_vars[1:7], names(pretrend_means))) {
    if (all(is.na(pretrend_means[[v]]))) next
    p <- ggplot(pretrend_means, aes(x = relative_time, y = get(v))) +
      geom_line() + geom_point() +
      geom_vline(xintercept = -0.5, linetype = "dashed", color = "red") +
      labs(title = paste("Raw Pre/Post Trends:", v),
           x = "Years Relative to COA Creation", y = v) +
      theme_minimal()
    ggsave(file.path(base_dir, paste0("output/figures/pretrends_raw_", v, ".png")),
           p, width = 8, height = 5, dpi = 150)
  }
  wlog("Saved pre-trend plots")
}

wlog("Step 8 complete.\n")
