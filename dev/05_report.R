## Coverage and missingness report for the master COA panel
suppressPackageStartupMessages({ library(data.table); library(stringr) })
out_dir <- "C:/Users/arvind/Desktop/coa_effects/merged_data"
m <- readRDS(file.path(out_dir, "coa_master_panel.rds")) |> as.data.table()

cat("Master panel:", nrow(m), "rows x", ncol(m), "cols\n")
cat("Unique COA cities:", uniqueN(m$coa_id), "\n")
cat("Year range:", range(m$year, na.rm=TRUE), "\n\n")

# -- variable groups -----------------------------------------------------
groups <- list(
  `Arrests x race x offense (UCR)` = c(
    "drug_tot_arrests","drug_tot_black","drug_tot_white",
    "index_tot_arrests","index_tot_black","index_tot_white",
    "vio_tot_arrests","vio_tot_black","vio_tot_white",
    "prop_tot_arrests","prop_tot_black","prop_tot_white",
    "oth_tot_arrests","oth_tot_black","oth_tot_white",
    "total_tot_arrests","total_tot_black","total_tot_white"),
  `UCR reporting compliance (months)` = c("ucr_reporting_months"),
  `Police killings (MPV)` = c("pk_killings_total","pk_killings_black","pk_killings_nonwhite"),
  `Police employees (LEOKA)` = c("leoka_total_employees","leoka_total_officers","leoka_total_civilians"),
  `Police officers (LEMAS)` = c("lemas_tot_mf","lemas_white_share","lemas_black_share",
                                 "lemas_hisp_share","lemas_female_share"),
  `Police FTEs (Census)` = c("total_police_FTEs","total_police_FTEs_p100kc"),
  `Police spending (per capita)` = c("exp_pc_police","aust_rpolexplcpc","aust_polexpfiscpc"),
  `Total municipal spending`= c("exp_pc_total","aust_rtotexplcpc","aust_rtotrevpc"),
  `City demographics (race/gender)` = c("dem_pct_women","dem_pct_white","dem_pct_black",
                                         "dem_pct_hispanic","dem_pct_asian"),
  `City economic (poverty/unemp)` = c("aust_ippov","aust_iunemprate","aust_ipnhblk","aust_iplat"),
  `Presidential vote share (county)` = c("pres_demshare","pres_total_votes"),
  `City Dem/Rep in power (panel)` = c("demshare","dem_in_power","rep_in_power"),
  `City council composition (county)` = c("council_seats_total","council_total_dem",
                                           "council_total_rep","council_total_white",
                                           "council_total_black","council_total_hispanic",
                                           "council_total_women"),
  `Police chief identity` = c("chief_racefinal","chief_gender","chief_nonwhite","chief_female")
)

# -- helper: how many COA cities have ANY non-NA value in this group, in 1990-2021 window
covered_cities <- function(cols, yrs = 1990:2021) {
  sub <- m[year %in% yrs, .SD, .SDcols = c("coa_id", cols)]
  any_nonna <- sub[, .(any_present = any(!is.na(.SD))), by = coa_id, .SDcols = cols]
  list(cities = sum(any_nonna$any_present),
       pct    = round(100 * sum(any_nonna$any_present) / uniqueN(m$coa_id), 1))
}
city_year_pct <- function(cols, yrs = 1990:2021) {
  sub <- m[year %in% yrs, .SD, .SDcols = c("coa_id","year", cols)]
  sub[, present := apply(.SD, 1, function(r) any(!is.na(r))), .SDcols = cols]
  round(100 * mean(sub$present), 1)
}

cat("\n========================================================\n")
cat("COVERAGE BY VARIABLE GROUP — share of 336 COA cities with any non-missing value 1990-2021\n")
cat("========================================================\n")
cat(sprintf("%-44s %14s %14s\n",
            "Variable group", "cities w/ data", "city-yr % filled"))
res <- list()
for (g in names(groups)) {
  cv <- covered_cities(groups[[g]])
  pc <- city_year_pct(groups[[g]])
  res[[g]] <- list(group = g, cities = cv$cities, pct_cities = cv$pct, cyfill = pc)
  cat(sprintf("%-44s   %4d (%5.1f%%)   %5.1f%%\n",
              g, cv$cities, cv$pct, pc))
}

# -- which COA cities are missing a given group entirely (during 1990-2021) ---
report_missing_cities <- function(label, cols) {
  sub <- m[year %in% 1990:2021, .SD, .SDcols = c("coa_id", cols)]
  any_nonna <- sub[, .(present = any(!is.na(.SD))), by = coa_id, .SDcols = cols]
  miss <- any_nonna[present == FALSE, coa_id]
  cat(sprintf("\n--- Missing all %s data: %d cities ---\n", label, length(miss)))
  if (length(miss) <= 60) cat(paste(miss, collapse = "\n"), "\n")
  else cat(paste(head(miss, 50), collapse = "\n"), "\n  ... and", length(miss) - 50, "more\n")
}

report_missing_cities("UCR arrest", groups$`Arrests x race x offense (UCR)`)
report_missing_cities("UCR reporting", groups$`UCR reporting compliance (months)`)
report_missing_cities("police killings", groups$`Police killings (MPV)`)
report_missing_cities("LEOKA employee", groups$`Police employees (LEOKA)`)
report_missing_cities("LEMAS officer", groups$`Police officers (LEMAS)`)
report_missing_cities("Census-of-Govts police spending", groups$`Police spending (per capita)`[1])
report_missing_cities("Austerity fiscal", groups$`Total municipal spending`[2:3])
report_missing_cities("city demographics", groups$`City demographics (race/gender)`)
report_missing_cities("presidential vote share", groups$`Presidential vote share (county)`)
report_missing_cities("county council comp", groups$`City council composition (county)`)
report_missing_cities("police chief", groups$`Police chief identity`)

# -- year-by-year coverage for a few key vars (% city-years filled) ---
cat("\n\n========================================================\n")
cat("YEAR-BY-YEAR COVERAGE (% of 336 COA cities with non-missing) for key variables\n")
cat("========================================================\n")
key_vars <- c(
  "total_tot_arrests" = "UCR arrests (any)",
  "ucr_reporting_months" = "UCR months reported",
  "lemas_tot_mf" = "LEMAS officers",
  "leoka_total_officers" = "LEOKA officers",
  "exp_pc_police" = "Police spend/capita (CoG)",
  "aust_rpolexplcpc" = "Police spend/capita (Austerity)",
  "dem_pct_white" = "City pct white",
  "pres_demshare" = "Pres Dem vote share (county)",
  "council_seats_total" = "Council size (county)",
  "pk_killings_total" = "Police killings (MPV)"
)
hdr <- paste(c(sprintf("%-32s","Variable"),
               sprintf("%5d", seq(1990, 2024, by = 2))), collapse = " ")
cat(hdr, "\n")
for (v in names(key_vars)) {
  yrly <- m[, .(pct = round(100 * mean(!is.na(get(v))), 0)), by = year][order(year)]
  vals <- yrly[year %in% seq(1990,2024,by=2), pct]
  cat(sprintf("%-32s %s\n", key_vars[v], paste(sprintf("%5d", vals), collapse = " ")))
}

# -- write CSV summary
summary_df <- data.table(
  group = sapply(res, `[[`, "group"),
  cities_with_data = sapply(res, `[[`, "cities"),
  pct_of_336 = sapply(res, `[[`, "pct_cities"),
  city_year_pct_filled = sapply(res, `[[`, "cyfill")
)
fwrite(summary_df, file.path(out_dir, "coverage_summary.csv"))
cat("\nWrote summary to", file.path(out_dir, "coverage_summary.csv"), "\n")
