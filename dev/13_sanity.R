## Sanity-check backfill numbers vs. agencies known to exist
suppressPackageStartupMessages({ library(data.table) })
m <- readRDS("C:/Users/arvind/Desktop/coa_effects/merged_data/coa_master_panel.rds") |> as.data.table()

cat("--- Charlotte NC arrests by year (post-backfill) ---\n")
print(m[coa_id == "charlotte_nc", .(year, total_tot_arrests, vio_tot_arrests,
                                    drug_tot_arrests, ucr_reporting_months)] |>
        head(15))

cat("\n--- Indianapolis IN arrests by year ---\n")
print(m[coa_id == "indianapolis_in", .(year, total_tot_arrests, vio_tot_arrests,
                                       drug_tot_arrests, ucr_reporting_months)] |>
        head(15))

cat("\n--- Honolulu HI arrests by year ---\n")
print(m[coa_id == "honolulu_hi", .(year, total_tot_arrests, vio_tot_arrests,
                                   drug_tot_arrests, ucr_reporting_months)] |>
        head(15))

cat("\n--- Detroit (already in panel — not backfilled) — should be unchanged ---\n")
print(m[coa_id == "detroit_mi", .(year, total_tot_arrests, vio_tot_arrests,
                                  drug_tot_arrests, ucr_reporting_months)] |>
        head(5))

cat("\n--- Cities now with arrests data (count by year) ---\n")
print(m[, .(N = sum(!is.na(total_tot_arrests))), by = year][order(year)])
