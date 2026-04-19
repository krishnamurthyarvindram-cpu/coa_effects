library(data.table)
ucr <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/ucr_agency_year_report.rds") |> as.data.table()
cat("--- Charlotte NC agencies (last 5 yrs) ---\n")
print(ucr[state_abb=="NC" & grepl("charlotte|mecklenburg", tolower(agency_name)) & year >= 2017,
          .(ori9, agency_name, year, months_reported, sum_arrests_all, population)])
cat("\n--- Augusta-Richmond GA (last 5 yrs) ---\n")
print(ucr[state_abb=="GA" & grepl("augusta|richmond", tolower(agency_name)) & year >= 2017,
          .(ori9, agency_name, year, months_reported, sum_arrests_all, population)])
cat("\n--- Indianapolis IN (last 5 yrs) ---\n")
print(ucr[state_abb=="IN" & grepl("indianapolis", tolower(agency_name)) & year >= 2017,
          .(ori9, agency_name, year, months_reported, sum_arrests_all, population)])
cat("\n--- Macon GA agencies (last 5 yrs) ---\n")
print(ucr[state_abb=="GA" & grepl("macon|bibb", tolower(agency_name)) & year >= 2015,
          .(ori9, agency_name, year, months_reported, sum_arrests_all, population)])
