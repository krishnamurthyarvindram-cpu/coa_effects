library(data.table)
ucr <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/ucr_agency_year_report.rds") |> as.data.table()
cat("--- Ventura/San Buenaventura CA agencies ---\n")
print(ucr[state_abb=="CA" & grepl("ventura|buenaventura", tolower(agency_name)) & year >= 2018,
          .(ori9, agency_name, year, sum_arrests_all, population)])
cat("\n--- South Fulton GA ---\n")
print(ucr[state_abb=="GA" & grepl("fulton|south fulton", tolower(agency_name)) & year >= 2018,
          .(ori9, agency_name, year, sum_arrests_all, population)] |> head(20))
