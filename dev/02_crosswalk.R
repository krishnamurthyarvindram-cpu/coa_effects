## Build a crosswalk: 335 COA cities -> place_fips, county_fips, ori, GEOID
suppressPackageStartupMessages({
  library(data.table); library(haven); library(dplyr); library(stringr)
})
raw <- "C:/Users/arvind/Desktop/coa_effects/raw_data"

standardize_city <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("\\s+(city|town|village|borough|municipality)$", "", x)
  x <- gsub("^st\\.?\\s+", "saint ", x)
  x <- gsub("^ft\\.?\\s+", "fort ", x)
  x <- gsub("^mt\\.?\\s+", "mount ", x)
  x <- gsub("[[:punct:]]", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

coa <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/coa_clean_v2.rds") |>
  as.data.table()
cat("COA cities:", nrow(coa), "\n")

# UCR panel — already has place_fips per city
panel <- readRDS(file.path(raw, "data_panel_post1990.rds")) |> as.data.table()
panel_cw <- unique(panel[, .(place_fips, city, abb,
                              fips_state_code = fips_state_code.x,
                              fips_place_code = fips_place_code.x,
                              fips_county_code, fips_state_county_code,
                              ori, ori9_panel = ori9.x)])
panel_cw[, city_clean := standardize_city(city)]
panel_cw[, state_clean := tolower(abb)]
panel_cw[, key := paste0(city_clean, "_", state_clean)]
cat("panel unique cities:", nrow(panel_cw), "\n")

# Pad place_fips to 7 digits (string)
panel_cw[, place_fips_str := sprintf("%07d", place_fips)]
panel_cw[, county_fips_str := sprintf("%05d", as.integer(fips_state_county_code))]

# Austerity — place_fips already string
aust <- read_dta(file.path(raw, "Austerity.dta")) |> as.data.table()
aust_cw <- unique(aust[, .(place_fips_str = fips, name, state)])
aust_cw[, city_clean := standardize_city(name)]
aust_cw[, state_clean := tolower(state)]
aust_cw[, key := paste0(city_clean, "_", state_clean)]
cat("austerity unique cities:", nrow(aust_cw), "\n")

# city_data.tab — 309 cities with GEOID, ORI9, FIPS (county!)
cd <- fread(file.path(raw, "city_data.tab"), quote="")
cd[, NAME_clean := str_replace(toupper(NAME), "\\s*POLICE\\s*DEPARTMENT.*", "")]
cd[, NAME_clean := str_replace_all(NAME_clean, '"', "")]
cd[, NAME_clean := str_trim(NAME_clean)]
cd[, city_clean := standardize_city(NAME_clean)]
cd[, state_clean := tolower(str_replace_all(STATE, '"', ""))]
cd[, key := paste0(city_clean, "_", state_clean)]
cd[, ORI9 := str_replace_all(ORI9, '"', "")]
cd[, place_fips_str := str_remove(GEOID, "16000US")]
cd_cw <- unique(cd[, .(key, city_clean, state_clean, place_fips_str_cd = place_fips_str,
                        ori9_cd = ORI9, lear_id = LEAR_ID, county_fips_cd = sprintf("%05d", FIPS))])
cat("city_data.tab cities:", nrow(cd_cw), "\n")

# UCR Employee data — has GEOID + ORI
emp <- fread(file.path(raw, "ucrPoliceEmployeeData.csv"))
emp_cw <- unique(emp[, .(GEOID, ORI9, City, State.abb)])
emp_cw[, place_fips_str_emp := str_remove(GEOID, "16000US")]
emp_cw[, city_clean := standardize_city(City)]
emp_cw[, state_clean := tolower(State.abb)]
emp_cw[, key := paste0(city_clean, "_", state_clean)]
emp_cw <- unique(emp_cw[, .(key, place_fips_str_emp, ori9_emp = ORI9)])
cat("emp unique cities:", nrow(emp_cw), "\n")

# Demographics file may have city info
dem <- readRDS(file.path(raw, "cities_historical_demographics.rds")) |> as.data.table()
cat("demographics keys: place_fips only — uniqueN", uniqueN(dem$place_fips), "\n")

# ----- merge crosswalks onto COA -----
cw <- coa[, .(key, city_clean, state_clean, city_raw, state_raw = state_full, state_abb,
              treatment_year, has_board, invest_power, discipline_power,
              election_created, selection_method, population)]

cw <- merge(cw, panel_cw[, .(key, place_fips_str, county_fips_str, ori_panel = ori, ori9_panel)],
            by = "key", all.x = TRUE)
cw <- merge(cw, aust_cw[, .(key, place_fips_str_aust = place_fips_str)], by = "key", all.x = TRUE)
cw <- merge(cw, cd_cw[, .(key, place_fips_str_cd, ori9_cd, lear_id, county_fips_cd)],
            by = "key", all.x = TRUE)
cw <- merge(cw, emp_cw, by = "key", all.x = TRUE)

# Resolve a single canonical place_fips per COA city
cw[, place_fips := fcoalesce(place_fips_str, place_fips_str_aust,
                              place_fips_str_cd, place_fips_str_emp)]
cw[, county_fips := fcoalesce(county_fips_str, county_fips_cd)]
cw[, ori9 := fcoalesce(ori9_panel, ori9_cd, ori9_emp)]

cat("\n=== match diagnostics ===\n")
cat("COA cities with any place_fips:", sum(!is.na(cw$place_fips)), "/", nrow(cw), "\n")
cat("COA cities matched in UCR panel:", sum(!is.na(cw$place_fips_str)), "\n")
cat("COA cities matched in Austerity:", sum(!is.na(cw$place_fips_str_aust)), "\n")
cat("COA cities matched in city_data.tab:", sum(!is.na(cw$place_fips_str_cd)), "\n")
cat("COA cities matched in employee data:", sum(!is.na(cw$place_fips_str_emp)), "\n")
cat("COA cities with county_fips:", sum(!is.na(cw$county_fips)), "\n")
cat("COA cities with ori9:", sum(!is.na(cw$ori9)), "\n")

# Show un-matched to diagnose
unmatched <- cw[is.na(place_fips), .(city_clean, state_clean, city_raw)]
cat("\nUnmatched cities (sample):\n"); print(head(unmatched, 30))
cat("Total unmatched:", nrow(unmatched), "\n")

# DEDUPE — one row per COA city (key); some join cols expanded multiple ORIs
cw <- cw[order(key, -nchar(coalesce(ori9, "")))][, .SD[1], by = key]
cat("De-duped crosswalk rows:", nrow(cw), "\n")

saveRDS(cw, "C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.rds")
fwrite(cw, "C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.csv")
cat("\nSaved crosswalk.\n")
