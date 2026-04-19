## Probe specific missing cities in the UCR panel
suppressPackageStartupMessages({ library(data.table); library(stringr) })
panel <- readRDS("C:/Users/arvind/Desktop/coa_effects/raw_data/data_panel_post1990.rds") |> as.data.table()
cities <- unique(panel[, .(city, abb)])

probes <- list(
  c("indianapolis","IN"), c("charlotte","NC"), c("savannah","GA"),
  c("cambridge","MA"), c("lowell","MA"), c("burbank","CA"),
  c("glendale","CA"), c("clovis","CA"), c("concord","CA"),
  c("daly","CA"), c("downey","CA"), c("west covina","CA"),
  c("fullerton","CA"), c("huntington beach","CA"), c("roseville","CA"),
  c("corona","CA"), c("murrieta","CA"), c("san mateo","CA"),
  c("santa rosa","CA"), c("santa clarita","CA"),
  c("indianapolis","IN"), c("macon","GA"), c("norwalk","CA"),
  c("thousand oaks","CA"), c("visalia","CA"), c("miami gardens","FL"),
  c("sandy springs","GA"), c("honolulu","HI"),
  c("broken arrow","OK"), c("sugar land","TX"), c("wichita falls","TX")
)
for (p in probes) {
  hits <- cities[abb == p[2] & grepl(p[1], city, ignore.case = TRUE), .(city)]
  cat(sprintf("%-22s %s -> ", p[1], p[2]),
      if (nrow(hits)) paste(head(hits$city, 5), collapse=" | ") else "NOT FOUND", "\n")
}
