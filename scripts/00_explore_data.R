##############################################################################
# 00_explore_data.R — Step 0: Explore All Raw Data Files
# Systematically inspect every file in raw_data/
##############################################################################

library(data.table)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
raw_dir  <- file.path(base_dir, "raw_data")
out_dir  <- file.path(base_dir, "output")

log_file <- file.path(out_dir, "data_exploration_log.txt")
analysis_log <- file.path(out_dir, "analysis_log.txt")

# Helper: write to log
wlog <- function(..., file = log_file) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = file, append = TRUE)
}

# Initialize logs
cat("=== DATA EXPLORATION LOG ===\n", file = log_file)
cat(paste0("Generated: ", Sys.time(), "\n\n"), file = log_file, append = TRUE)

cat("=== ANALYSIS LOG ===\n", file = analysis_log)
cat(paste0("Generated: ", Sys.time(), "\n\n"), file = analysis_log, append = TRUE)
cat("Step 0: Exploring all raw data files\n\n", file = analysis_log, append = TRUE)

###############################################################################
# 1. COA Creation Data
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("1. COA CREATION DATA: coa_creation_data.csv")
wlog(paste(rep("=", 70), collapse=""))

coa <- fread(file.path(raw_dir, "coa_creation_data.csv"))
wlog("Dimensions: ", nrow(coa), " rows x ", ncol(coa), " cols")
wlog("Column names: ", paste(names(coa), collapse=", "))
wlog("\nColumn types:")
for (nm in names(coa)) {
  wlog("  ", nm, ": ", class(coa[[nm]])[1],
       " | NAs: ", sum(is.na(coa[[nm]])),
       " | unique: ", length(unique(coa[[nm]])))
}
wlog("\nFirst 5 rows:")
cap <- capture.output(print(head(coa, 5)))
for (line in cap) wlog(line)

# Check for key identifiers
wlog("\nKey identifier check:")
for (id_col in c("ORI", "ori", "FIPS", "fips", "city", "City", "state", "State",
                  "year", "Year", "treatment_year", "creation_year", "coa_year")) {
  matches <- grep(id_col, names(coa), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  Found: ", paste(matches, collapse=", "))
}

###############################################################################
# 2. Pre-Built Panel (data_panel_post1990.rds) — CRITICAL
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("2. PRE-BUILT PANEL: data_panel_post1990.rds  *** CRITICAL ***")
wlog(paste(rep("=", 70), collapse=""))

panel <- readRDS(file.path(raw_dir, "data_panel_post1990.rds"))
wlog("Dimensions: ", nrow(panel), " rows x ", ncol(panel), " cols")
wlog("Column names: ", paste(names(panel), collapse=", "))
wlog("\nColumn types and missingness:")
for (nm in names(panel)) {
  wlog("  ", nm, ": ", class(panel[[nm]])[1],
       " | NAs: ", sum(is.na(panel[[nm]])),
       " (", round(100*mean(is.na(panel[[nm]])), 1), "%)",
       " | unique: ", min(length(unique(panel[[nm]])), 100))
}

# Check what this panel contains
wlog("\nKey identifier check:")
for (id_col in c("ORI", "ori", "FIPS", "fips", "city", "state", "year",
                  "agency", "dept", "population", "pop")) {
  matches <- grep(id_col, names(panel), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  Found: ", paste(matches, collapse=", "))
}

# Year range
year_cols <- grep("year", names(panel), ignore.case = TRUE, value = TRUE)
if (length(year_cols) > 0) {
  for (yc in year_cols) {
    if (is.numeric(panel[[yc]])) {
      wlog("  ", yc, " range: ", min(panel[[yc]], na.rm=TRUE), " - ",
           max(panel[[yc]], na.rm=TRUE))
    }
  }
}

# Check for UCR-type variables
wlog("\nChecking for UCR arrest/offense variables:")
ucr_patterns <- c("arrest", "offense", "crime", "murder", "rape", "robbery",
                   "assault", "burglary", "larceny", "vehicle", "drug",
                   "clearance", "clear", "violent", "property")
for (pat in ucr_patterns) {
  matches <- grep(pat, names(panel), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  ", pat, ": ", paste(matches, collapse=", "))
}

# Check for demographic variables
wlog("\nChecking for demographic variables:")
demo_patterns <- c("pop", "black", "white", "hisp", "income", "poverty",
                    "unemploy", "educ", "race")
for (pat in demo_patterns) {
  matches <- grep(pat, names(panel), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  ", pat, ": ", paste(matches, collapse=", "))
}

# Check for treatment/COA variables
wlog("\nChecking for COA/treatment variables:")
treat_patterns <- c("coa", "oversight", "treat", "civilian", "review")
for (pat in treat_patterns) {
  matches <- grep(pat, names(panel), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  ", pat, ": ", paste(matches, collapse=", "))
}

wlog("\nFirst 3 rows (transposed):")
cap <- capture.output(str(head(panel, 3)))
for (line in cap[1:min(80, length(cap))]) wlog(line)

# Unique agencies/years
if ("ori" %in% tolower(names(panel))) {
  ori_col <- grep("^ori$", names(panel), ignore.case = TRUE, value = TRUE)[1]
  wlog("\nUnique agencies (", ori_col, "): ", length(unique(panel[[ori_col]])))
}

###############################################################################
# 3. Arrests Data (sample one file)
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("3. UCR ARRESTS DATA: arrests_csv_1974_2024_year/")
wlog(paste(rep("=", 70), collapse=""))

arrest_dir <- file.path(raw_dir, "arrests_csv_1974_2024_year")
arrest_files <- list.files(arrest_dir, pattern = "\\.csv$", full.names = TRUE)
wlog("Number of CSV files: ", length(arrest_files))
wlog("Files: ", paste(basename(arrest_files)[1:5], collapse=", "), ", ...")

# Read one sample file to understand structure
sample_arrest <- fread(arrest_files[length(arrest_files)], nrows = 100)
wlog("\nSample file: ", basename(arrest_files[length(arrest_files)]))
wlog("Dimensions: ", nrow(sample_arrest), " rows x ", ncol(sample_arrest), " cols")
wlog("Column names: ", paste(names(sample_arrest), collapse=", "))

wlog("\nColumn types:")
for (nm in names(sample_arrest)) {
  wlog("  ", nm, ": ", class(sample_arrest[[nm]])[1])
}

wlog("\nKey identifier check:")
for (id_col in c("ORI", "ori", "agency_type", "department_type", "city", "state",
                  "year", "population", "months_reported")) {
  matches <- grep(id_col, names(sample_arrest), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  Found: ", paste(matches, collapse=", "))
}

# Check for agency type filter
type_cols <- grep("type|agency_type|dept_type", names(sample_arrest), ignore.case = TRUE, value = TRUE)
if (length(type_cols) > 0) {
  for (tc in type_cols) {
    wlog("\n  Values of ", tc, ": ", paste(unique(sample_arrest[[tc]])[1:20], collapse=", "))
  }
}

# Check arrest categories
wlog("\nArrest-related columns:")
arrest_patterns <- c("murder", "manslaughter", "rape", "robbery", "assault",
                      "drug", "narcotic", "suspicion", "vagran", "vandal",
                      "gambl", "prostitut", "liquor", "curfew", "loiter",
                      "drunken", "violent", "property", "total")
for (pat in arrest_patterns) {
  matches <- grep(pat, names(sample_arrest), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  ", pat, ": ", paste(matches, collapse=", "))
}

# Race columns
wlog("\nRace-related columns:")
race_patterns <- c("white", "black", "asian", "native", "race", "hispanic")
for (pat in race_patterns) {
  matches <- grep(pat, names(sample_arrest), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  ", pat, ": ", paste(matches[1:min(10, length(matches))], collapse=", "))
}

wlog("\nFirst 3 rows:")
cap <- capture.output(print(head(sample_arrest, 3)))
for (line in cap[1:min(50, length(cap))]) wlog(line)

###############################################################################
# 4. Offenses Known Data (sample one file)
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("4. UCR OFFENSES KNOWN: offenses_known_csv_1960_2024_month/")
wlog(paste(rep("=", 70), collapse=""))

offense_dir <- file.path(raw_dir, "offenses_known_csv_1960_2024_month")
offense_files <- list.files(offense_dir, pattern = "\\.csv$", full.names = TRUE)
wlog("Number of CSV files: ", length(offense_files))

# Read a recent sample file
sample_offense <- fread(offense_files[length(offense_files)], nrows = 100)
wlog("\nSample file: ", basename(offense_files[length(offense_files)]))
wlog("Dimensions: ", nrow(sample_offense), " rows x ", ncol(sample_offense), " cols")
wlog("Column names: ", paste(names(sample_offense), collapse=", "))

wlog("\nColumn types:")
for (nm in names(sample_offense)) {
  wlog("  ", nm, ": ", class(sample_offense[[nm]])[1])
}

wlog("\nKey identifier check:")
for (id_col in c("ORI", "ori", "agency_type", "city", "state", "year", "month",
                  "population", "months_reported")) {
  matches <- grep(id_col, names(sample_offense), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  Found: ", paste(matches, collapse=", "))
}

# Check offense/clearance columns
wlog("\nOffense/clearance columns:")
off_patterns <- c("murder", "rape", "robbery", "assault", "burglary",
                   "larceny", "theft", "vehicle", "arson", "clear", "actual",
                   "unfounded", "offense")
for (pat in off_patterns) {
  matches <- grep(pat, names(sample_offense), ignore.case = TRUE, value = TRUE)
  if (length(matches) > 0) wlog("  ", pat, ": ", paste(matches[1:min(10, length(matches))], collapse=", "))
}

# Agency type
type_cols <- grep("type|agency_type", names(sample_offense), ignore.case = TRUE, value = TRUE)
if (length(type_cols) > 0) {
  for (tc in type_cols) {
    wlog("\n  Values of ", tc, ": ", paste(unique(sample_offense[[tc]])[1:20], collapse=", "))
  }
}

wlog("\nFirst 3 rows (selected columns):")
cap <- capture.output(print(head(sample_offense[, 1:min(20, ncol(sample_offense))], 3)))
for (line in cap[1:min(30, length(cap))]) wlog(line)

###############################################################################
# 5. Police Killings
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("5. POLICE KILLINGS: police_killings.xlsx")
wlog(paste(rep("=", 70), collapse=""))

if (requireNamespace("readxl", quietly = TRUE)) {
  pk <- readxl::read_excel(file.path(raw_dir, "police_killings.xlsx"), n_max = 200)
  wlog("Dimensions: ", nrow(pk), " rows x ", ncol(pk), " cols")
  wlog("(reading full file for total count...)")
  pk_full <- readxl::read_excel(file.path(raw_dir, "police_killings.xlsx"))
  wlog("FULL Dimensions: ", nrow(pk_full), " rows x ", ncol(pk_full), " cols")
  wlog("Column names: ", paste(names(pk_full), collapse=", "))

  wlog("\nColumn types and missingness:")
  for (nm in names(pk_full)) {
    wlog("  ", nm, ": ", class(pk_full[[nm]])[1],
         " | NAs: ", sum(is.na(pk_full[[nm]])),
         " (", round(100*mean(is.na(pk_full[[nm]])), 1), "%)")
  }

  wlog("\nKey identifier check:")
  for (id_col in c("city", "state", "county", "agency", "ORI", "year", "date",
                    "race", "name", "armed", "cause")) {
    matches <- grep(id_col, names(pk_full), ignore.case = TRUE, value = TRUE)
    if (length(matches) > 0) wlog("  Found: ", paste(matches, collapse=", "))
  }

  # Year range
  date_cols <- grep("date|year", names(pk_full), ignore.case = TRUE, value = TRUE)
  for (dc in date_cols) {
    if (is.numeric(pk_full[[dc]])) {
      wlog("  ", dc, " range: ", min(pk_full[[dc]], na.rm=TRUE), " - ",
           max(pk_full[[dc]], na.rm=TRUE))
    } else if (inherits(pk_full[[dc]], "Date") || inherits(pk_full[[dc]], "POSIXct")) {
      wlog("  ", dc, " range: ", as.character(min(pk_full[[dc]], na.rm=TRUE)), " - ",
           as.character(max(pk_full[[dc]], na.rm=TRUE)))
    } else {
      wlog("  ", dc, " sample: ", paste(head(pk_full[[dc]], 5), collapse=", "))
    }
  }

  # Race breakdown
  race_cols <- grep("race|ethnic", names(pk_full), ignore.case = TRUE, value = TRUE)
  for (rc in race_cols) {
    wlog("\n  Race/ethnicity values (", rc, "):")
    tab <- table(pk_full[[rc]], useNA = "ifany")
    for (i in seq_along(tab)) {
      wlog("    ", names(tab)[i], ": ", tab[i])
    }
  }

  wlog("\nFirst 5 rows:")
  cap <- capture.output(print(head(pk_full, 5)))
  for (line in cap[1:min(30, length(cap))]) wlog(line)

  rm(pk, pk_full)
} else {
  wlog("WARNING: readxl package not available. Install with install.packages('readxl')")
}

###############################################################################
# 6. Demographics
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("6. DEMOGRAPHICS: cities_historical_demographics.rds")
wlog(paste(rep("=", 70), collapse=""))

demo <- readRDS(file.path(raw_dir, "cities_historical_demographics.rds"))
wlog("Dimensions: ", nrow(demo), " rows x ", ncol(demo), " cols")
wlog("Column names: ", paste(names(demo), collapse=", "))

wlog("\nColumn types and missingness:")
for (nm in names(demo)) {
  wlog("  ", nm, ": ", class(demo[[nm]])[1],
       " | NAs: ", sum(is.na(demo[[nm]])),
       " (", round(100*mean(is.na(demo[[nm]])), 1), "%)",
       " | unique: ", min(length(unique(demo[[nm]])), 100))
}

# Year range
year_cols <- grep("year", names(demo), ignore.case = TRUE, value = TRUE)
for (yc in year_cols) {
  if (is.numeric(demo[[yc]])) {
    wlog("  ", yc, " range: ", min(demo[[yc]], na.rm=TRUE), " - ",
         max(demo[[yc]], na.rm=TRUE))
  }
}

wlog("\nFirst 5 rows:")
cap <- capture.output(print(head(demo, 5)))
for (line in cap[1:min(30, length(cap))]) wlog(line)

###############################################################################
# 7. Austerity Data
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("7. AUSTERITY: Austerity.dta")
wlog(paste(rep("=", 70), collapse=""))

if (requireNamespace("haven", quietly = TRUE)) {
  aust <- haven::read_dta(file.path(raw_dir, "Austerity.dta"))
  wlog("Dimensions: ", nrow(aust), " rows x ", ncol(aust), " cols")
  wlog("Column names: ", paste(names(aust), collapse=", "))

  wlog("\nColumn types and missingness:")
  for (nm in names(aust)[1:min(30, ncol(aust))]) {
    wlog("  ", nm, ": ", class(aust[[nm]])[1],
         " | NAs: ", sum(is.na(aust[[nm]])),
         " (", round(100*mean(is.na(aust[[nm]])), 1), "%)")
  }

  wlog("\nFirst 3 rows:")
  cap <- capture.output(print(head(aust, 3)))
  for (line in cap[1:min(30, length(cap))]) wlog(line)

  rm(aust)
} else {
  wlog("WARNING: haven package not available")
}

###############################################################################
# 8. County Councils Composition
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("8. COUNTY COUNCILS: countycouncils_comp.rds")
wlog(paste(rep("=", 70), collapse=""))

cc <- readRDS(file.path(raw_dir, "countycouncils_comp.rds"))
wlog("Dimensions: ", nrow(cc), " rows x ", ncol(cc), " cols")
wlog("Column names: ", paste(names(cc), collapse=", "))

wlog("\nColumn types:")
for (nm in names(cc)[1:min(20, ncol(cc))]) {
  wlog("  ", nm, ": ", class(cc[[nm]])[1],
       " | NAs: ", sum(is.na(cc[[nm]])))
}

wlog("\nFirst 3 rows:")
cap <- capture.output(print(head(cc, 3)))
for (line in cap[1:min(20, length(cap))]) wlog(line)

rm(cc)

###############################################################################
# 9. LEDB Candidate Level
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("9. LEDB CANDIDATE LEVEL: ledb_candidatelevel.csv")
wlog(paste(rep("=", 70), collapse=""))

ledb <- fread(file.path(raw_dir, "ledb_candidatelevel.csv"), nrows = 100)
wlog("Sample dimensions: ", nrow(ledb), " rows x ", ncol(ledb), " cols")
wlog("Column names: ", paste(names(ledb), collapse=", "))

wlog("\nColumn types:")
for (nm in names(ledb)[1:min(20, ncol(ledb))]) {
  wlog("  ", nm, ": ", class(ledb[[nm]])[1])
}

wlog("\nFirst 3 rows:")
cap <- capture.output(print(head(ledb, 3)))
for (line in cap[1:min(20, length(cap))]) wlog(line)

rm(ledb)

###############################################################################
# SUMMARY DECISION
###############################################################################
wlog("\n", paste(rep("=", 70), collapse=""))
wlog("SUMMARY AND KEY DECISIONS")
wlog(paste(rep("=", 70), collapse=""))
wlog("Step 0 exploration complete.")
wlog("Check the log above to determine:")
wlog("1. Can data_panel_post1990.rds serve as the analysis backbone?")
wlog("2. What identifiers are available for merging?")
wlog("3. What variables need to be constructed from raw UCR files?")
wlog("4. What is the format of each file?")

cat("\n\nStep 0 exploration complete. See", log_file, "\n")
