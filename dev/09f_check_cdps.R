library(data.table); library(stringr)
ucr <- readRDS("C:/Users/arvind/Desktop/coa_effects/dev/ucr_agency_year_report.rds") |> as.data.table()

# Try direct match on the 16 NOT_IN_UCR list
cdps <- list(
  c("brandon",          "FL"),
  c("columbia",         "MD"),  # Columbia MD (Howard county, CDP)
  c("east los angeles", "CA"),
  c("enterprise",       "NV"),
  c("highlands ranch",  "CO"),
  c("lehigh acres",     "FL"),
  c("metairie",         "LA"),
  c("paradise",         "NV"),
  c("riverview",        "FL"),
  c("san buenaventura", "CA"),  # = Ventura
  c("san tan valley",   "AZ"),
  c("south fulton",     "GA"),
  c("spring hill",      "FL"),
  c("spring valley",    "NV"),
  c("sunrise manor",    "NV"),
  c("the woodlands",    "TX"),
  c("ventura",          "CA")   # alias for san buenaventura
)
for (cd in cdps) {
  city <- cd[1]; st <- cd[2]
  hits <- ucr[state_abb == st & grepl(city, tolower(agency_name), fixed = TRUE) &
              year >= 2015,
              .(.N, max_arrests = max(sum_arrests_all, na.rm=TRUE),
                max_pop = max(population, na.rm=TRUE)), by = .(ori9, agency_name)]
  cat(sprintf("\n%s, %s ->\n", city, st))
  if (nrow(hits)) print(hits[order(-max_pop)][1:min(5, .N)]) else cat("  (none)\n")
}
