suppressPackageStartupMessages(library(data.table))
d <- fread("C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year/arrests_yearly_2010.csv", nrow=5)
cat("Total cols:", ncol(d), "\n")
cat("First 40 cols:\n"); print(head(names(d), 40))
cat("\nRace cols:\n"); print(grep("white|black|hispanic|asian|amer|race|ethnic", names(d), ignore.case=TRUE, value=TRUE))
cat("\nOffense col:\n"); print(grep("offense", names(d), ignore.case=TRUE, value=TRUE))

unique_off <- fread("C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year/arrests_yearly_2010.csv", select="offense_name")
cat("\nUnique offense_name values:\n"); print(unique(unique_off$offense_name))
