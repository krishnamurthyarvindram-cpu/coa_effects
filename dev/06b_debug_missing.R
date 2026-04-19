## Why are some matched cities (Charlotte, Savannah) flagged as no-arrests?
suppressPackageStartupMessages({ library(data.table); library(stringr) })
m  <- readRDS("C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.rds") |> as.data.table()
cw <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/02_crosswalk.rds") |> as.data.table()

probe <- c("charlotte_nc","savannah_ga","cambridge_ma","indianapolis_in",
           "honolulu_hi","macon_ga","austin_tx","detroit_mi")
for (p in probe) {
  row <- cw[key == p]
  cat("\n",p,"-- place_fips_str:", row$place_fips_str, "  ori9:", row$ori9, "\n")
  arr <- m[coa_id == p, .(year, total_tot_arrests, ucr_reporting_months)]
  cat("  rows w/ arrests data:", sum(!is.na(arr$total_tot_arrests)), "/", nrow(arr), "\n")
  cat("  rows w/ months data:", sum(!is.na(arr$ucr_reporting_months)), "/", nrow(arr), "\n")
  if (any(!is.na(arr$total_tot_arrests))) print(head(arr[!is.na(total_tot_arrests)], 3))
}

panel <- readRDS("C:/Users/arvind/Desktop/coa_effects/raw_data/data_panel_post1990.rds") |> as.data.table()
cat("\n--- panel rows for charlotte ---\n")
print(panel[city == "charlotte" & abb == "NC", .(year, place_fips, total_tot_arrests, number_of_months_reported)] |> head(10))
cat("\n--- panel rows for savannah ---\n")
print(panel[city == "savannah" & abb == "GA", .(year, place_fips, total_tot_arrests, number_of_months_reported)] |> head(10))
