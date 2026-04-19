## Build a polished, structured coverage report (Markdown)
suppressPackageStartupMessages({ library(data.table); library(stringr) })
out_dir <- "C:/Users/arvind/Desktop/coa_effects/merged_data"
m  <- readRDS(file.path(out_dir, "coa_master_panel.rds")) |> as.data.table()
cw <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.rds") |> as.data.table()

N_COA <- uniqueN(m$coa_id)

# Quick stats
n_treated   <- uniqueN(m[treatment_year > 0, coa_id])
n_untreated <- N_COA - n_treated

# Variable groups
groups <- list(
  ucr_arrests   = c("drug_tot_arrests","drug_tot_black","drug_tot_white",
                    "index_tot_arrests","index_tot_black","index_tot_white",
                    "vio_tot_arrests","vio_tot_black","vio_tot_white",
                    "prop_tot_arrests","prop_tot_black","prop_tot_white",
                    "oth_tot_arrests","oth_tot_black","oth_tot_white",
                    "total_tot_arrests","total_tot_black","total_tot_white"),
  ucr_compliance = c("ucr_reporting_months"),
  pk_killings    = c("pk_killings_total","pk_killings_black","pk_killings_nonwhite"),
  leoka_employees= c("leoka_total_employees","leoka_total_officers","leoka_total_civilians"),
  lemas_officers = c("lemas_tot_mf","lemas_white_share","lemas_black_share","lemas_hisp_share","lemas_female_share"),
  cog_police_ftes= c("total_police_FTEs","total_police_FTEs_p100kc"),
  police_spend   = c("exp_pc_police","aust_rpolexplcpc","aust_polexpfiscpc"),
  total_spend    = c("exp_pc_total","aust_rtotexplcpc","aust_rtotrevpc"),
  city_demog     = c("dem_pct_women","dem_pct_white","dem_pct_black","dem_pct_hispanic","dem_pct_asian"),
  city_econ      = c("aust_ippov","aust_iunemprate","aust_ipnhblk","aust_iplat"),
  pres_vote      = c("pres_demshare","pres_total_votes"),
  city_dem_panel = c("demshare","dem_in_power","rep_in_power"),
  council_comp   = c("council_seats_total","council_total_dem","council_total_rep",
                     "council_total_white","council_total_black","council_total_hispanic","council_total_women"),
  police_chief   = c("chief_racefinal","chief_gender","chief_nonwhite","chief_female")
)
group_labels <- c(
  ucr_arrests    = "UCR arrests by race x offense",
  ucr_compliance = "UCR reporting completeness (months)",
  pk_killings    = "Police killings (Mapping Police Violence)",
  leoka_employees= "Police employees / officers (LEOKA, 2008-2019)",
  lemas_officers = "Police officers race/gender (LEMAS)",
  cog_police_ftes= "Police FTEs (Census of Governments)",
  police_spend   = "Police spending per capita",
  total_spend    = "Total municipal spending / revenue",
  city_demog     = "City racial/gender demographics",
  city_econ      = "City economic (poverty, unemp, race shares)",
  pres_vote      = "Presidential Dem vote share (county-level)",
  city_dem_panel = "City Dem/Rep in power (mayor/council from panel)",
  council_comp   = "County council composition (party/race/gender)",
  police_chief   = "Police chief identity (race/gender)"
)

cov_for <- function(cols, yrs) {
  sub <- m[year %in% yrs, .SD, .SDcols = c("coa_id", cols)]
  any_nonna <- sub[, .(present = any(!is.na(.SD))), by = coa_id, .SDcols = cols]
  cy <- m[year %in% yrs, .SD, .SDcols = c("coa_id","year", cols)]
  cy[, present := apply(.SD, 1, function(r) any(!is.na(r))), .SDcols = cols]
  list(cities  = sum(any_nonna$present),
       pct_c   = round(100 * mean(any_nonna$present), 1),
       pct_cy  = round(100 * mean(cy$present), 1))
}

# Build the report
md <- character()
md <- c(md,
  "# COA Master Dataset — Coverage & Missingness Report",
  "",
  sprintf("**Master dataset:** `merged_data/coa_master_panel.csv` (also `.rds`)  "),
  sprintf("**Rows:** %d (city-years)  ", nrow(m)),
  sprintf("**Cities:** %d unique COA cities  ", N_COA),
  sprintf("**Years:** %d to %d  ", min(m$year), max(m$year)),
  sprintf("**Treated (has COA):** %d  ·  Never-treated: %d  ", n_treated, n_untreated),
  "",
  "## What's in it",
  "",
  "| Block | Source file | Key | Year span |",
  "|---|---|---|---|",
  "| COA treatment + powers | `coa_creation_data.csv` | city + state | static |",
  "| Arrests by race x offense, LEMAS officers, demshare, chief identity, CoG spending, demographics | `data_panel_post1990.rds` | place_fips x year | 1990-2021 |",
  "| Fiscal: police/total/social spending, poverty, unemployment, race shares | `Austerity.dta` | place_fips x year | 1990-2019 |",
  "| Demographics (race/gender %) | `cities_historical_demographics.rds` | place_fips x year | 1970-2020 |",
  "| Police employees (officers, civilians, total) | `ucrPoliceEmployeeData.csv` | place_fips x year | 2008-2019 |",
  "| Police killings | `cleaned_data/police_killings.rds` (from MPV xlsx) | city + state x year | 1999-2021 |",
  "| Presidential Dem vote share | `demVoteShareAllYearsFIPS.csv` | county_fips x year | 2000-2020 |",
  "| County council composition | `countycouncils_comp.rds` | county_fips x year | 1989-2021 |",
  "",
  "## Crosswalk match rates (336 COA cities -> external IDs)",
  "")

cw_panel  <- sum(!is.na(cw$place_fips_str))
cw_aust   <- sum(!is.na(cw$place_fips_str_aust))
cw_emp    <- sum(!is.na(cw$place_fips_str_emp))
cw_cd     <- sum(!is.na(cw$place_fips_str_cd))
cw_anyfips<- sum(!is.na(cw$place_fips))
cw_county <- sum(!is.na(cw$county_fips))
cw_ori    <- sum(!is.na(cw$ori9))

md <- c(md,
  "| Crosswalk source | COA cities matched (of 336) |",
  "|---|---|",
  sprintf("| UCR panel (place_fips)             | %d (%.1f%%) |", cw_panel,  100*cw_panel/N_COA),
  sprintf("| Austerity (place_fips)             | %d (%.1f%%) |", cw_aust,   100*cw_aust/N_COA),
  sprintf("| city_data.tab (place_fips)         | %d (%.1f%%) |", cw_cd,     100*cw_cd/N_COA),
  sprintf("| LEOKA employee data (place_fips)   | %d (%.1f%%) |", cw_emp,    100*cw_emp/N_COA),
  sprintf("| **ANY place_fips resolved**        | **%d (%.1f%%)** |", cw_anyfips, 100*cw_anyfips/N_COA),
  sprintf("| County FIPS resolved               | %d (%.1f%%) |", cw_county, 100*cw_county/N_COA),
  sprintf("| ORI9 (police agency ID) resolved   | %d (%.1f%%) |", cw_ori,    100*cw_ori/N_COA),
  "",
  "## Coverage by variable block",
  "",
  "Two windows shown:",
  "- **1990-2021** (the dense panel period)",
  "- **2000-2021** (when MPV/vote share/most council data starts)",
  "",
  "*Cities w/ data* = COA cities with at least one non-missing observation in any year of the window.  ",
  "*City-yr % filled* = share of (city × year) cells in the window with at least one non-missing variable in the block.",
  "",
  "| Variable block | Cities w/ data 1990-21 (% of 336) | City-yr % filled 1990-21 | Cities w/ data 2000-21 (%) | City-yr % filled 2000-21 |",
  "|---|---|---|---|---|")

for (g in names(groups)) {
  c1 <- cov_for(groups[[g]], 1990:2021)
  c2 <- cov_for(groups[[g]], 2000:2021)
  md <- c(md, sprintf("| %s | %d (%.1f%%) | %.1f%% | %d (%.1f%%) | %.1f%% |",
                      group_labels[g], c1$cities, c1$pct_c, c1$pct_cy,
                      c2$cities, c2$pct_c, c2$pct_cy))
}

# Year-by-year coverage table for key variables
md <- c(md, "",
  "## Year-by-year coverage (% of 336 COA cities with non-missing) — selected variables",
  "")
key_vars <- c(
  total_tot_arrests       = "UCR arrests (any race/offense)",
  ucr_reporting_months    = "UCR months reported",
  pk_killings_total       = "Police killings (MPV)",
  leoka_total_officers    = "Total officers (LEOKA)",
  lemas_tot_mf            = "Sworn officers (LEMAS)",
  total_police_FTEs       = "Police FTEs (Census)",
  exp_pc_police           = "Police $ per capita (CoG)",
  aust_rpolexplcpc        = "Police $ per capita (Austerity)",
  aust_rtotexplcpc        = "Total municipal $ per capita",
  dem_pct_white           = "City % white",
  pres_demshare           = "Pres Dem vote share (county)",
  council_seats_total     = "County council size",
  chief_racefinal         = "Police chief race"
)
yrs <- seq(1990, 2024, by = 2)
md <- c(md, paste0("| Variable | ", paste(yrs, collapse = " | "), " |"),
        paste0("|", paste(rep("---", length(yrs)+1), collapse = "|"), "|"))
for (v in names(key_vars)) {
  yr_pct <- m[, .(pct = round(100 * mean(!is.na(get(v))), 0)), by = year][order(year)]
  vals <- yr_pct[year %in% yrs, pct]
  md <- c(md, paste0("| ", key_vars[v], " | ", paste(sprintf("%d", vals), collapse = " | "), " |"))
}

# Cities with NO data in critical blocks
miss_for <- function(cols, yrs = 1990:2021) {
  sub <- m[year %in% yrs, .SD, .SDcols = c("coa_id", cols)]
  any_nonna <- sub[, .(present = any(!is.na(.SD))), by = coa_id, .SDcols = cols]
  any_nonna[present == FALSE, coa_id]
}

md <- c(md, "",
  "## COA cities with NO data in a given block (1990-2021)",
  "",
  "These are typically (a) census-designated places without their own police agency or (b) cities not in the source panel.",
  "")

for (g in names(groups)) {
  miss <- miss_for(groups[[g]], 1990:2021)
  if (length(miss) == 0) next
  md <- c(md, sprintf("### %s — %d cities missing entirely", group_labels[g], length(miss)))
  md <- c(md, "", paste("- ", paste(miss, collapse = "\n- ")), "")
}

# Header + tail notes
md <- c(md, "",
  "## Notes & caveats",
  "",
  "- **Year span**: dense panel is 1990-2021. Years 2022-2024 are nearly empty because the upstream panel ends in 2021. The dataset includes those rows for forward-extension when newer data is appended.",
  "- **UCR coverage gap**: the source panel `data_panel_post1990.rds` covers 398 cities; for COA cities not in that panel (typically smaller or non-reporting agencies), arrest/LEMAS data is NA. Raw yearly UCR arrest CSVs in `raw_data/arrests_csv_1974_2024_year/` could be used to extract additional cities at the cost of substantial processing (each file ~400 MB).",
  "- **Vote share is presidential** at the county level (the only city-level political-control variable in the panel itself is `dem_in_power`/`demshare` from local elections, with thinner coverage). The presidential vote share is a useful proxy for local political lean.",
  "- **Council composition is county-level** (from `countycouncils_comp.rds`). True city council composition is not in the supplied data sources.",
  "- **Police killings (MPV)** start in 1999 and have a known undercount before 2013.",
  "- **LEOKA employee data** is only available 2008-2019 in the supplied file.",
  "- **CDP cities** (Highlands Ranch, Metairie, Paradise, etc.) have no incorporated-place fiscal/UCR data at all; they appear in the panel for COA-treatment context but most variables will be NA.",
  ""
)

writeLines(md, file.path(out_dir, "coverage_report.md"))
cat("Wrote", file.path(out_dir, "coverage_report.md"), "\n")

# Per-city coverage CSV (for the user to inspect)
city_cov <- data.table(coa_id = sort(unique(m$coa_id)))
for (g in names(groups)) {
  city_cov[, (paste0("has_", g)) := as.integer(coa_id %in% miss_for(groups[[g]], 1990:2021))]
  city_cov[, (paste0("has_", g)) := 1L - city_cov[[paste0("has_", g)]]]
}
fwrite(city_cov, file.path(out_dir, "per_city_coverage.csv"))
cat("Wrote", file.path(out_dir, "per_city_coverage.csv"), "\n")
