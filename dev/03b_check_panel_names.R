## Check what city names exist in the UCR panel for the unmatched cases
suppressPackageStartupMessages({ library(data.table); library(stringr) })
raw <- "C:/Users/arvind/Desktop/coa_effects/raw_data"
panel <- readRDS(file.path(raw, "data_panel_post1990.rds")) |> as.data.table()
cities <- unique(panel[, .(city, abb, place_fips)])
cities[, city_l := tolower(city)]

probe <- c("nashville","louisville","metairie","brandon","columbia",
           "honolulu","temecula","menifee","centennial","jurupa",
           "athens","augusta","macon","paradise","spokane","spring",
           "highlands","lehigh","san tan","sunrise","south fulton",
           "the woodlands","urban honolulu","ventura","victorville",
           "east los angeles","riverview","enterprise")
for (p in probe) {
  hits <- cities[grepl(p, city_l), .(city, abb, place_fips)]
  if (nrow(hits)) cat("\n--", p, "--\n")
  if (nrow(hits)) print(hits)
}

# Same in Austerity
suppressPackageStartupMessages(library(haven))
aust <- read_dta(file.path(raw, "Austerity.dta")) |> as.data.table()
aust_c <- unique(aust[, .(name, state)])
aust_c[, n_l := tolower(name)]
cat("\n\n=== Austerity matches ===\n")
for (p in probe) {
  hits <- aust_c[grepl(p, n_l), .(name, state)]
  if (nrow(hits)) cat("\n--", p, "--\n")
  if (nrow(hits)) print(hits)
}
