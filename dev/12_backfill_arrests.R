## Backfill UCR arrests for the 41 merge-gap COA cities by streaming yearly CSVs
## and aggregating to the same race x offense schema as the master panel.
##
## Outputs:
##   dev/backfill_arrests.rds  (long: coa_id, year, all arrest columns)
##   merged_data/coa_master_panel_v2.{rds,csv}  (master with backfilled cells)
##   merged_data/coverage_report_v2.md
suppressPackageStartupMessages({
  library(data.table); library(stringr)
})

raw_dir <- "C:/Users/arvind/Desktop/coa_effects/raw_data/arrests_csv_1974_2024_year"
cls <- fread("C:/Users/arvind/Desktop/coa_effects/dev/ucr_missing_classification.csv")
mg  <- cls[classification == "MERGE_GAP_in_UCR_with_data" & !is.na(ori9_matched)]
cat("Merge-gap cities w/ resolved ORI:", nrow(mg), "\n")
target_oris <- mg$ori9_matched
ori_to_coa  <- setNames(mg$coa_id, mg$ori9_matched)
print(mg[, .(coa_id, ori9_matched, agency_found)])

# ---------- offense category mapping ----------
violent_codes  <- c("murder and nonnegligent manslaughter", "rape",
                    "robbery", "aggravated assault")
property_codes <- c("burglary", "theft", "motor vehicle theft", "arson")
drug_total     <- "drug - total drug"
# Excluded from `other`: drug subs (use drug_total instead) and gambling subs (use gambling - total)
drug_subs      <- c("drug possess - drug total","drug possess - marijuana",
                    "drug possess - opium and cocaine and derivatives including heroin",
                    "drug possess - other drug","drug possess - synthetic narcotics",
                    "drug sale - drug total","drug sale - marijuana",
                    "drug sale - opium and cocaine and derivatives including heroin",
                    "drug sale - other drug","drug sale - synthetic narcotics")
gambling_subs  <- c("gambling - bookmaking horse and sport book",
                    "gambling - number and lottery","gambling - other")

cat_of <- function(code) {
  fcase(
    code %in% violent_codes,  "violent",
    code %in% property_codes, "property",
    code == drug_total,       "drug",
    code %in% c(drug_subs, gambling_subs), "skip",
    default = "other"
  )
}

# ---------- stream yearly files ----------
files <- list.files(raw_dir, pattern = "arrests_yearly_\\d{4}\\.csv$", full.names = TRUE)
years_avail <- as.integer(gsub(".*_(\\d{4})\\.csv$", "\\1", basename(files)))
keep <- years_avail >= 1990 & years_avail <= 2024
files <- files[keep]; years_avail <- years_avail[keep]

needed <- c("ori9","year","offense_code","total_arrests","total_white","total_black",
            "total_hispanic","total_asian","total_american_indian",
            "number_of_months_reported","population","agency_name","state_abb")

agg_all <- vector("list", length(files))
for (i in seq_along(files)) {
  yr <- years_avail[i]; t0 <- Sys.time()
  d  <- fread(files[i], select = needed, showProgress = FALSE)
  d  <- d[ori9 %in% target_oris]
  if (nrow(d) == 0) { agg_all[[i]] <- NULL; next }
  d[, category := cat_of(offense_code)]
  d <- d[category != "skip"]
  agg <- d[, .(arrests   = sum(total_arrests, na.rm = TRUE),
               black     = sum(total_black,   na.rm = TRUE),
               white     = sum(total_white,   na.rm = TRUE),
               hispanic  = sum(total_hispanic,na.rm = TRUE),
               months_reported = max(number_of_months_reported, na.rm = TRUE),
               population_bf   = max(population, na.rm = TRUE),
               agency_name     = first(agency_name),
               state_abb       = first(state_abb)),
           by = .(ori9, year, category)]
  agg_all[[i]] <- agg
  cat(sprintf("  %d : %d agency-cat-rows for %d cities, %.1fs\n",
              yr, nrow(agg), uniqueN(agg$ori9),
              as.numeric(Sys.time() - t0, units = "secs")))
}
long <- rbindlist(agg_all)
cat("Total long rows:", nrow(long), "\n")

# ---------- pivot wide to match panel schema ----------
wide <- dcast(long, ori9 + year + months_reported + population_bf + agency_name + state_abb
              ~ category, value.var = c("arrests","black","white","hispanic"),
              fun.aggregate = sum, fill = NA_real_)

# Rename columns to match the master panel (drug_tot_arrests, drug_tot_black, etc.)
rn <- function(name) {
  parts <- strsplit(name, "_")[[1]]
  if (length(parts) < 2) return(name)
  metric <- parts[1]      # arrests / black / white / hispanic
  cat_   <- parts[2]      # drug / property / violent / other
  prefix <- switch(cat_,
                   drug     = "drug",
                   property = "prop",
                   violent  = "vio",
                   other    = "oth",
                   cat_)
  suffix <- switch(metric,
                   arrests  = "tot_arrests",
                   black    = "tot_black",
                   white    = "tot_white",
                   hispanic = "tot_hispanic",
                   metric)
  paste0(prefix, "_", suffix)
}
new_names <- names(wide)
for (i in seq_along(new_names)) {
  if (grepl("^(arrests|black|white|hispanic)_", new_names[i])) {
    new_names[i] <- rn(new_names[i])
  }
}
setnames(wide, names(wide), new_names)

# Compute index = vio + prop, and total = vio+prop+drug+oth
for (race in c("tot_arrests","tot_black","tot_white","tot_hispanic")) {
  vio <- wide[[paste0("vio_", race)]]; prop <- wide[[paste0("prop_", race)]]
  drug<- wide[[paste0("drug_", race)]]; oth <- wide[[paste0("oth_", race)]]
  vio[is.na(vio)] <- 0; prop[is.na(prop)] <- 0
  drug[is.na(drug)] <- 0; oth[is.na(oth)] <- 0
  wide[, paste0("index_", race) := vio + prop]
  wide[, paste0("total_", race) := vio + prop + drug + oth]
}

# Add coa_id
wide[, coa_id := ori_to_coa[ori9]]
wide[, ucr_reporting_months := months_reported]

# Save backfill long form
saveRDS(wide, "C:/Users/arvind/Desktop/coa_effects/dev/backfill_arrests.rds")
fwrite(wide, "C:/Users/arvind/Desktop/coa_effects/dev/backfill_arrests.csv")
cat("Backfill rows:", nrow(wide), "  unique cities:", uniqueN(wide$coa_id), "\n")

# ---------- merge into master ----------
m <- readRDS("C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.rds") |> as.data.table()
cat("Master before backfill rows:", nrow(m), " cities w/ arrests:",
    uniqueN(m[!is.na(total_tot_arrests), coa_id]), "\n")

# Cols to backfill
arr_cols <- c(
  "drug_tot_arrests","drug_tot_black","drug_tot_white","drug_tot_hispanic",
  "vio_tot_arrests","vio_tot_black","vio_tot_white","vio_tot_hispanic",
  "prop_tot_arrests","prop_tot_black","prop_tot_white","prop_tot_hispanic",
  "oth_tot_arrests","oth_tot_black","oth_tot_white","oth_tot_hispanic",
  "index_tot_arrests","index_tot_black","index_tot_white","index_tot_hispanic",
  "total_tot_arrests","total_tot_black","total_tot_white","total_tot_hispanic",
  "ucr_reporting_months","number_of_months_reported"
)
# panel didn't have *_tot_hispanic variants; we'll add new columns
for (c in arr_cols) if (!c %in% names(m)) m[, (c) := NA_real_]

# Build a key for joining
bf <- wide[, c("coa_id","year", intersect(arr_cols, names(wide))), with = FALSE]
setnames(bf, intersect(arr_cols, names(wide)), paste0(intersect(arr_cols, names(wide)), "_bf"))
m2 <- merge(m, bf, by = c("coa_id","year"), all.x = TRUE)

# For each backfilled column, fill in NAs from the _bf version
for (c in intersect(arr_cols, names(wide))) {
  bfc <- paste0(c, "_bf")
  if (bfc %in% names(m2)) {
    m2[is.na(get(c)) & !is.na(get(bfc)), (c) := get(bfc)]
    m2[, (bfc) := NULL]
  }
}

cat("Master after backfill rows:", nrow(m2), " cities w/ arrests:",
    uniqueN(m2[!is.na(total_tot_arrests), coa_id]), "\n")

saveRDS(m2, "C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.rds")
fwrite(m2, "C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.csv")
# Also keep a v2 stamp
saveRDS(m2, "C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel_v2.rds")
cat("Wrote updated master to merged_data/coa_master_panel.{rds,csv} (also _v2)\n")
