## Confirm full offense_code list from a yearly UCR CSV
suppressPackageStartupMessages(library(data.table))
d <- fread("C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year/arrests_yearly_2010.csv",
           select = "offense_code")
cat("Unique offense_code values:\n")
print(sort(unique(d$offense_code)))
