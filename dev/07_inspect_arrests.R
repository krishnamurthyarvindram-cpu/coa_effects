## Inspect a yearly arrests CSV to plan extraction
suppressPackageStartupMessages({ library(data.table) })
f <- "C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year/arrests_yearly_2010.csv"
d <- fread(f, nrow = 5)
cat("rows:", nrow(d), " cols:", ncol(d), "\n")
cat("colnames (first 80):\n"); print(head(names(d), 80))
cat("ORI/agency cols:\n"); print(grep("ori|agency|state|fips|place|city", names(d), ignore.case=TRUE, value=TRUE))
cat("race cols:\n"); print(grep("white|black|hispanic|asian|amer|native|race", names(d), ignore.case=TRUE, value=TRUE)[1:50])
cat("offense cols:\n"); print(grep("drug|robbery|murder|rape|assault|larceny|burglary|arson|index|violent|property", names(d), ignore.case=TRUE, value=TRUE)[1:30])
cat("\nSample rows:\n"); print(head(d, 2))
cat("\nFile size:\n"); print(file.info(f)$size)
