library(data.table)
base_dir <- "C:/Users/arvind/Desktop/coa_effects"
panel <- as.data.table(readRDS(file.path(base_dir, "raw_data/data_panel_post1990.rds")))

# Check what the problem cities look like in the panel
problem_cities <- c("arlington", "nashville", "kansas", "oklahoma", "jersey",
                     "salt lake", "lexington", "honolulu", "burbank", "cambridge",
                     "columbia", "athens", "south fulton", "spokane")

for (pc in problem_cities) {
  matches <- unique(panel[grepl(pc, city, ignore.case=TRUE), .(city, abb)])
  if (nrow(matches) > 0) {
    cat(pc, "-> found in panel:\n")
    print(matches)
  } else {
    cat(pc, "-> NOT found in panel\n")
  }
}

# Also check Springfield
cat("\nSpringfield in panel:\n")
print(unique(panel[grepl("springfield", city, ignore.case=TRUE), .(city, abb)]))

rm(panel); gc()
