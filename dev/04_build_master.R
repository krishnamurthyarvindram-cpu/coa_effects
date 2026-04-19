## Build the master COA city x year panel (1990-2024) merging all sources
suppressPackageStartupMessages({
  library(data.table); library(haven); library(dplyr); library(stringr)
})

raw     <- "C:/Users/arvind/Desktop/coa_effects/raw_data"
out_dir <- "C:/Users/arvind/Desktop/coa_effects/merged_data"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
log_path <- "C:/Users/arvind/Desktop/coa_effects/dev/04_build_master.log"
sink(log_path, split = TRUE)
cat("===== BUILD MASTER =====\n")
t0 <- Sys.time()

# -------------------------------------------------------------------- #
# 1. COA crosswalk (built in 02_crosswalk.R)
# -------------------------------------------------------------------- #
cw <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.rds") |> as.data.table()
cat("COA cities:", nrow(cw), "\n")

# Standardise place_fips both as int and 7-char str
cw[, place_fips_str := str_pad(place_fips, 7, "left", "0")]
cw[, place_fips_int := suppressWarnings(as.integer(place_fips))]
cw[, county_fips_str := str_pad(county_fips, 5, "left", "0")]

# -------------------------------------------------------------------- #
# 2. Base panel: 336 cities x 1990-2024
# -------------------------------------------------------------------- #
years <- 1990:2024
base <- CJ(coa_id = cw$key, year = years)
base <- merge(base, cw[, .(key, city_clean, state_clean, city_raw, state_abb,
                            place_fips_str, place_fips_int, county_fips_str, ori9,
                            treatment_year, has_board, invest_power, discipline_power,
                            election_created, selection_method,
                            coa_population_2017 = population)],
              by.x = "coa_id", by.y = "key", all.x = TRUE)
setorder(base, coa_id, year)
cat("Base panel rows:", nrow(base), "  cities:", uniqueN(base$coa_id), "\n")

# -------------------------------------------------------------------- #
# 3. UCR panel — arrests, LEMAS officers, spending, demographics, demshare
#    Keyed by place_fips (int) x year, 1990-2021
# -------------------------------------------------------------------- #
panel <- readRDS(file.path(raw, "data_panel_post1990.rds")) |> as.data.table()
panel_keep <- c(
  "place_fips","year",
  "population_est","population_2010","population_2020",
  # vote share / dem in power (where available)
  "demshare","votes_total","pid_final_win","dem_elected","rep_elected",
  "dem_in_power","rep_in_power",
  # arrests by race x offense (counts)
  "drug_tot_arrests","drug_tot_black","drug_tot_white",
  "index_tot_arrests","index_tot_black","index_tot_white",
  "vio_tot_arrests","vio_tot_black","vio_tot_white",
  "prop_tot_arrests","prop_tot_black","prop_tot_white",
  "oth_tot_arrests","oth_tot_black","oth_tot_white",
  "total_tot_arrests","total_tot_black","total_tot_white",
  # arrest rates per 100k
  "drug_tot_arrests_p100c","prop_tot_arrests_p100c","oth_tot_arrests_p100c",
  "vio_tot_arrests_p100c","total_tot_arrests_p100c","index_tot_arrests_p100c",
  # UCR reporting completeness
  "number_of_months_reported",
  # LEMAS officer counts / shares
  "lemas_tot_mf","lemas_white_share","lemas_black_share","lemas_hisp_share",
  "lemas_api_share","lemas_female_share","lemas_year","use_lemas_data",
  "female_officer_share",
  # demographics (panel-merged)
  "percent_women","percent_white.y","percent_black.y","percent_hispanic","percent_asian_american",
  # police chief
  "chief_firstname","chief_lastname","chief_racefinal","chief_gender",
  "chief_nonwhite","chief_white","chief_black","chief_hispanic","chief_female",
  # spending per capita (deflated)
  "expenditure.PC","fire.PC","police.PC","corrections.PC",
  # police FTEs and pay (Census of Govts)
  "total_police_FTEs","avg_ft_pay_police_FTEs","tot_pay_police_FPT",
  "total_police_FTEs_p100kc"
)
panel_sub <- unique(panel[, ..panel_keep], by = c("place_fips","year"))
setnames(panel_sub,
         old = c("percent_white.y","percent_black.y","expenditure.PC","fire.PC","police.PC","corrections.PC"),
         new = c("pct_white","pct_black","exp_pc_total","exp_pc_fire","exp_pc_police","exp_pc_corrections"))

base[, place_fips_int := suppressWarnings(as.integer(place_fips_str))]
base <- merge(base, panel_sub,
              by.x = c("place_fips_int","year"), by.y = c("place_fips","year"),
              all.x = TRUE)
cat("After UCR panel merge: rows=", nrow(base), " any panel hit: ",
    sum(!is.na(base$total_tot_arrests)), "\n")

# -------------------------------------------------------------------- #
# 4. Austerity — fiscal & police spending (1990-2021), key place_fips str
# -------------------------------------------------------------------- #
aust <- read_dta(file.path(raw, "Austerity.dta")) |> as.data.table()
aust_keep <- c(
  "fips","year",
  "ipop","rtotrevpc","rtotexplcpc","rpolexplcpc","rpolexplcpt","rpolexplcpn",
  "polexpfiscpc","ratpolsoc","ratpolsocedufisc","soceduexpfiscpc",
  "rsocexplcpc","rhealexplcpc","rhospexplcpc","rparksexplcpc",
  "rlibexplcpc","rpubassexplcpc","rhouscommexplcpc",
  "ipnhblk","iplat","ippov","iunemprate","iviocrimertucr","lipropcrimertucr",
  "ipmen15to34","ipvhu"
)
aust_sub <- unique(aust[, intersect(aust_keep, names(aust)), with = FALSE], by = c("fips","year"))
setnames(aust_sub, "fips", "place_fips_str")
# Add aust_ prefix to all but keys
nm <- setdiff(names(aust_sub), c("place_fips_str","year"))
setnames(aust_sub, nm, paste0("aust_", nm))

base <- merge(base, aust_sub, by = c("place_fips_str","year"), all.x = TRUE)
cat("After Austerity merge: any aust hit: ", sum(!is.na(base$aust_rpolexplcpc)), "\n")

# -------------------------------------------------------------------- #
# 5. Demographics — cities_historical_demographics (1970-2020)
#    interpolated to year-level
# -------------------------------------------------------------------- #
dem <- readRDS(file.path(raw, "cities_historical_demographics.rds")) |> as.data.table()
dem[, place_fips := str_pad(place_fips, 7, "left", "0")]
dem_keep <- c("place_fips","year","percent_women","percent_white",
              "percent_black","percent_hispanic","percent_asian_american")
dem_sub <- unique(dem[, ..dem_keep], by = c("place_fips","year"))
setnames(dem_sub, c("percent_women","percent_white","percent_black","percent_hispanic","percent_asian_american"),
                    c("dem_pct_women","dem_pct_white","dem_pct_black","dem_pct_hispanic","dem_pct_asian"))

base <- merge(base, dem_sub, by.x = c("place_fips_str","year"),
              by.y = c("place_fips","year"), all.x = TRUE)
cat("After demographics merge: any dem hit: ", sum(!is.na(base$dem_pct_white)), "\n")

# -------------------------------------------------------------------- #
# 6. UCR Police Employee data (LEOKA, 2008-2019)
# -------------------------------------------------------------------- #
emp <- fread(file.path(raw, "ucrPoliceEmployeeData.csv"))
emp[, place_fips_str := str_remove(GEOID, "16000US")]
emp_sub <- unique(emp[, .(place_fips_str, year,
                          leoka_total_employees = total.employees,
                          leoka_total_officers  = total.officers,
                          leoka_total_civilians = total.civilians,
                          leoka_population      = Population)])
base <- merge(base, emp_sub, by = c("place_fips_str","year"), all.x = TRUE)
cat("After LEOKA employee merge: any hit: ", sum(!is.na(base$leoka_total_officers)), "\n")

# -------------------------------------------------------------------- #
# 7. Police killings — pre-cleaned MPV city/state/year aggregates
# -------------------------------------------------------------------- #
pk_agg <- readRDS("C:/Users/arvind/Desktop/coa_effects/cleaned_data/police_killings.rds") |>
  as.data.table()
setnames(pk_agg, c("total_killings","black_killings","nonwhite_killings"),
         c("pk_killings_total","pk_killings_black","pk_killings_nonwhite"))
pk_agg <- unique(pk_agg, by = c("city_clean","state_clean","year"))

base[, mk := paste0(city_clean, "_", state_clean)]
pk_agg[, mk := paste0(city_clean, "_", state_clean)]
base <- merge(base,
              pk_agg[, .(mk, year, pk_killings_total, pk_killings_black, pk_killings_nonwhite)],
              by = c("mk","year"), all.x = TRUE)
base[, mk := NULL]
cat("After police-killings merge: cities with any killings: ",
    uniqueN(base[!is.na(pk_killings_total), coa_id]), "\n")

# -------------------------------------------------------------------- #
# 8. County-level: presidential vote share (Dem) — 2000-2021
# -------------------------------------------------------------------- #
vs <- fread(file.path(raw, "demVoteShareAllYearsFIPS.csv"))
vs[, county_fips_str := str_pad(county_fips, 5, "left", "0")]
# only DEM party rows give demshare directly
vs_d <- unique(vs[party == "DEMOCRAT", .(county_fips_str, year,
                                          pres_demshare = demshare,
                                          pres_total_votes = totalvotes)],
               by = c("county_fips_str","year"))
base <- merge(base, vs_d, by = c("county_fips_str","year"), all.x = TRUE)
cat("After vote-share merge: any hit: ", sum(!is.na(base$pres_demshare)), "\n")

# -------------------------------------------------------------------- #
# 9. County council composition (race/party/gender) — 1989-2021
# -------------------------------------------------------------------- #
cc <- readRDS(file.path(raw, "countycouncils_comp.rds")) |> as.data.table()
cc[, county_fips_str := str_pad(fips, 5, "left", "0")]
cc_keep <- c("county_fips_str","year",
             "seats_total","total_dem","total_rep","total_oth",
             "total_women","total_men",
             "total_white","total_black","total_hispanic","total_asian",
             "total_prob_whi","total_prob_bla","total_prob_his","total_prob_asi")
cc_sub <- unique(cc[, ..cc_keep], by = c("county_fips_str","year"))
setnames(cc_sub, setdiff(names(cc_sub), c("county_fips_str","year")),
         paste0("council_", setdiff(names(cc_sub), c("county_fips_str","year"))))
base <- merge(base, cc_sub, by = c("county_fips_str","year"), all.x = TRUE)
cat("After council merge: any hit: ", sum(!is.na(base$council_seats_total)), "\n")

# -------------------------------------------------------------------- #
# Final: derived flags
# -------------------------------------------------------------------- #
base[, post_treatment := fifelse(treatment_year > 0 & year >= treatment_year, 1L, 0L)]
base[, has_coa := as.integer(treatment_year > 0)]
base[, ucr_reporting_months := number_of_months_reported]

setcolorder(base, c("coa_id","city_clean","state_clean","city_raw","state_abb",
                    "place_fips_str","place_fips_int","county_fips_str","ori9",
                    "year","treatment_year","has_coa","post_treatment",
                    "has_board","invest_power","discipline_power","election_created"))

cat("\n=== FINAL master rows:", nrow(base), "  cols:", ncol(base), " ===\n")
saveRDS(base, file.path(out_dir, "coa_master_panel.rds"))
fwrite(base, file.path(out_dir, "coa_master_panel.csv"))
cat("Wrote:", file.path(out_dir, "coa_master_panel.csv"), "\n")
cat("Elapsed:", round(as.numeric(Sys.time() - t0, units = "secs"), 1), "s\n")
sink()
