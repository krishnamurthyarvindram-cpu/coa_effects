library(data.table)
ucr <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/ucr_agency_year_report.rds") |> as.data.table()
ucr[, place_fips_built := sprintf("%02d%05d", as.integer(fips_state_code), as.integer(fips_place_code))]

cat("--- All UCR agencies in place_fips 3712000 (Charlotte place_fips) ---\n")
print(ucr[place_fips_built == "3712000" & year >= 2017,
          .(ori9, agency_name, fips_state_code, fips_place_code, year, sum_arrests_all, population)])
cat("\n--- Charlotte-Mecklenburg PD's recorded fips_place_code over years ---\n")
print(ucr[ori9 == "NC0600100" & year >= 2017,
          .(ori9, agency_name, fips_state_code, fips_place_code, place_fips_built, sum_arrests_all)])

cat("\n--- Augusta-Richmond GA1210000 fips ---\n")
print(ucr[ori9 == "GA1210000" & year >= 2017,
          .(ori9, agency_name, fips_state_code, fips_place_code, place_fips_built, sum_arrests_all)])
