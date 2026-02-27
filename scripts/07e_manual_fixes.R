##############################################################################
# 07e_manual_fixes.R — Apply manual treatment mappings for Nashville, Louisville etc.
##############################################################################

library(data.table)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 7e: Manual Fixes for Nashville/Louisville ==========")

panel <- as.data.table(readRDS(file.path(base_dir, "merged_data/panel_merged.rds")))

# Manual fixes based on known matches
# Nashville-Davidson County, TN -> COA created 2018 (from raw data: "Nashville-Davidson metropolitan government (balance)")
# Louisville, KY -> COA created (from raw data inspection)
coa_raw <- fread(file.path(base_dir, "raw_data/coa_creation_data.csv"))
setnames(coa_raw, c("ORI_raw", "city_num", "city_raw", "state_raw", "population",
                      "state_abb", "has_oversight_board", "oversight_powers",
                      "charter_found", "link", "year_created",
                      "can_investigate", "can_discipline",
                      "created_via_election", "selection_method"))

# Find Nashville
nash <- coa_raw[grepl("Nashville", city_raw, ignore.case=TRUE)]
cat("Nashville in COA data:\n")
print(nash[, .(city_raw, state_abb, year_created, can_investigate, can_discipline)])

# Find Louisville
lou <- coa_raw[grepl("Louisville", city_raw, ignore.case=TRUE)]
cat("\nLouisville in COA data:\n")
print(lou[, .(city_raw, state_abb, year_created, can_investigate, can_discipline)])

# Apply Nashville fix
if (nrow(nash) > 0) {
  yr <- as.integer(nash$year_created[1])
  inv <- ifelse(toupper(trimws(nash$can_investigate[1])) == "Y", 1L, 0L)
  disc <- ifelse(toupper(trimws(nash$can_discipline[1])) == "Y", 1L, 0L)
  elec <- ifelse(toupper(trimws(nash$created_via_election[1])) == "Y", 1L, 0L)
  hb <- ifelse(toupper(trimws(nash$has_oversight_board[1])) == "Y", 1L, 0L)

  panel[city_lower == "nashville davidson county" & state_clean == "tn",
        `:=`(treatment_year = yr, has_board = hb, invest_power = inv,
             discipline_power = disc, election_created = elec)]
  wlog("Fixed Nashville: treatment_year=", yr)
}

# Apply Louisville fix
if (nrow(lou) > 0) {
  yr <- as.integer(lou$year_created[1])
  if (!is.na(yr)) {
    inv <- ifelse(toupper(trimws(lou$can_investigate[1])) == "Y", 1L, 0L)
    disc <- ifelse(toupper(trimws(lou$can_discipline[1])) == "Y", 1L, 0L)
    elec <- ifelse(toupper(trimws(lou$created_via_election[1])) == "Y", 1L, 0L)
    hb <- ifelse(toupper(trimws(lou$has_oversight_board[1])) == "Y", 1L, 0L)

    # Check panel name
    lou_panel <- unique(panel[grepl("louisville", city_lower)]$city_lower)
    cat("Louisville in panel:", lou_panel, "\n")

    if (length(lou_panel) > 0) {
      panel[city_lower == lou_panel[1] & state_clean == "ky",
            `:=`(treatment_year = yr, has_board = hb, invest_power = inv,
                 discipline_power = disc, election_created = elec)]
      wlog("Fixed Louisville: treatment_year=", yr)
    }
  }
}

# Report
n_treated <- length(unique(panel[treatment_year > 0]$city_state))
n_control <- length(unique(panel[treatment_year == 0]$city_state))
wlog("After manual fixes:")
wlog("  Treated cities: ", n_treated)
wlog("  Control cities: ", n_control)

# Treatment timing histogram
library(ggplot2)
tr_years <- unique(panel[treatment_year > 0, .(city_state, treatment_year)])

p <- ggplot(tr_years, aes(x = treatment_year)) +
  geom_histogram(binwidth = 1, fill = "steelblue", color = "white") +
  labs(title = "Distribution of COA Creation Years",
       x = "Year COA Created", y = "Number of Cities") +
  theme_minimal() +
  theme(plot.title = element_text(hjust = 0.5))

ggsave(file.path(base_dir, "output/figures/treatment_timing_histogram.png"),
       p, width = 8, height = 5, dpi = 150)
wlog("Saved treatment timing histogram")

# Save final panel
saveRDS(panel, file.path(base_dir, "merged_data/panel_merged.rds"))
wlog("Saved updated panel")
wlog("Step 7e complete.\n")
