suppressPackageStartupMessages(library(data.table))
d <- fread("C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year/arrests_yearly_2010.csv",
           select = c("ori9","year","fips_place_code","fips_state_code","state_abb","agency_name",
                      "population","number_of_months_reported","offense_code","total_arrests",
                      "total_white","total_black","total_hispanic","total_asian","total_american_indian"))
cat("rows:", nrow(d), "  cols:", ncol(d), "\n")
cat("unique offense_codes:\n"); print(sort(unique(d$offense_code)))
cat("unique ori9:", uniqueN(d$ori9), "\n")
print(head(d, 5))
