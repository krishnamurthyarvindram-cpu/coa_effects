## Inspect every source dataset's structure (rows, cols, dtypes, year range)
suppressPackageStartupMessages({
  library(data.table); library(haven); library(readr); library(dplyr)
})

raw <- "C:/Users/arvind/Desktop/coa_effects/raw_data"
sink("C:/Users/arvind/Desktop/coa_effects/dev/00_inspect.txt", split = TRUE)

show <- function(name, df) {
  cat("\n\n======", name, "======\n")
  cat("rows:", nrow(df), " cols:", ncol(df), "\n")
  cat("columns:\n")
  print(sapply(df, class))
  cat("head:\n"); print(head(df, 3))
  yc <- intersect(c("year","Year","YEAR","yr"), names(df))
  if (length(yc)) cat("year range:", range(df[[yc[1]]], na.rm=TRUE), "\n")
}

cat("--- coa_creation_data.csv ---\n")
coa <- fread(file.path(raw, "coa_creation_data.csv"))
show("coa_creation_data", coa)

cat("\n--- data_panel_post1990.rds (UCR panel) ---\n")
panel <- readRDS(file.path(raw, "data_panel_post1990.rds"))
cat("class:", class(panel), "\n")
cat("rows:", nrow(panel), " cols:", ncol(panel), "\n")
cat("colnames (first 80):\n"); print(head(names(panel), 80))
cat("more cols:\n"); print(tail(names(panel), 60))
cat("year col candidates:", grep("year|Year|YEAR", names(panel), value=TRUE), "\n")

cat("\n--- ucrPoliceEmployeeData.csv ---\n")
emp <- fread(file.path(raw, "ucrPoliceEmployeeData.csv"))
show("emp", emp)

cat("\n--- Austerity.dta ---\n")
aust <- read_dta(file.path(raw, "Austerity.dta"))
cat("rows:", nrow(aust), " cols:", ncol(aust), "\n")
cat("colnames:\n"); print(names(aust))
cat("head:\n"); print(head(aust, 3))

cat("\n--- demVoteShareAllYearsFIPS.csv ---\n")
vs <- fread(file.path(raw, "demVoteShareAllYearsFIPS.csv"))
show("vote_share", vs)

cat("\n--- countycouncils_comp.rds ---\n")
cc <- readRDS(file.path(raw, "countycouncils_comp.rds"))
cat("class:", class(cc), "\n")
cat("rows:", nrow(cc), " cols:", ncol(cc), "\n")
print(names(cc)); print(head(cc, 3))

cat("\n--- cities_historical_demographics.rds ---\n")
dem <- readRDS(file.path(raw, "cities_historical_demographics.rds"))
cat("class:", class(dem), "\n")
cat("rows:", nrow(dem), " cols:", ncol(dem), "\n")
print(head(names(dem), 80)); print(head(dem, 3))

cat("\n--- police_killings.xlsx ---\n")
suppressPackageStartupMessages(library(readxl))
pk <- read_excel(file.path(raw, "police_killings.xlsx"))
cat("rows:", nrow(pk), " cols:", ncol(pk), "\n")
print(names(pk)); print(head(pk, 3))

cat("\n--- Police_Shootings_Dataset.csv ---\n")
ps <- fread(file.path(raw, "Police_Shootings_Dataset.csv"))
cat("rows:", nrow(ps), " cols:", ncol(ps), "\n")
print(head(ps, 3))

cat("\n--- arrests_csv_1974_2024_year ---\n")
arrests_dir <- file.path(raw, "arrests_csv_1974_2024_year")
print(list.files(arrests_dir)[1:20])

cat("\n--- offenses_known_csv_1960_2024_month ---\n")
off_dir <- file.path(raw, "offenses_known_csv_1960_2024_month")
print(list.files(off_dir)[1:20])

cat("\n--- city_data.tab ---\n")
cd <- tryCatch(fread(file.path(raw, "city_data.tab")), error=function(e) NULL)
if (!is.null(cd)) { cat("rows:", nrow(cd), " cols:", ncol(cd), "\n"); print(head(names(cd),60)) }

sink()
