## Re-clean COA from raw with fixes for STATE_ABB typos / empties + city name fixes
suppressPackageStartupMessages({ library(data.table); library(stringr) })

raw <- "C:/Users/arvind/Desktop/coa_effects/raw_data"
coa <- fread(file.path(raw, "coa_creation_data.csv"))
setnames(coa, names(coa), c("ORI_raw","city_num","city_raw","state_raw","population",
                            "state_abb_raw","has_oversight_board","oversight_powers",
                            "charter_found","link","year_created_raw",
                            "can_investigate","can_discipline","created_via_election","selection_method"))

state_map <- c(
  "Alabama"="AL","Alaska"="AK","Arizona"="AZ","Arkansas"="AR","California"="CA",
  "Colorado"="CO","Connecticut"="CT","Delaware"="DE","District of Columbia"="DC",
  "Florida"="FL","Georgia"="GA","Hawaii"="HI","Idaho"="ID","Illinois"="IL",
  "Indiana"="IN","Iowa"="IA","Kansas"="KS","Kentucky"="KY","Louisiana"="LA",
  "Maine"="ME","Maryland"="MD","Massachusetts"="MA","Michigan"="MI","Minnesota"="MN",
  "Mississippi"="MS","Missouri"="MO","Montana"="MT","Nebraska"="NE","Nevada"="NV",
  "New Hampshire"="NH","New Jersey"="NJ","New Mexico"="NM","New York"="NY",
  "North Carolina"="NC","North Dakota"="ND","Ohio"="OH","Oklahoma"="OK","Oregon"="OR",
  "Pennsylvania"="PA","Rhode Island"="RI","South Carolina"="SC","South Dakota"="SD",
  "Tennessee"="TN","Texas"="TX","Utah"="UT","Vermont"="VT","Virginia"="VA",
  "Washington"="WA","West Virginia"="WV","Wisconsin"="WI","Wyoming"="WY")

# Resolve state from full state name first; STATE_ABB column is unreliable
coa[, state_full := str_trim(state_raw)]
coa[, state_abb := state_map[state_full]]
# Fall back to existing STATE_ABB only if it looks like a 2-letter US state
valid_abb <- unname(state_map)
coa[is.na(state_abb) & state_abb_raw %in% valid_abb, state_abb := state_abb_raw]
cat("Cities with no resolvable state:", sum(is.na(coa$state_abb)), "\n")
print(coa[is.na(state_abb), .(city_num, city_raw, state_raw, state_abb_raw)])

# City-name standardizer (more aggressive)
standardize_city <- function(x) {
  x <- tolower(trimws(x))
  x <- gsub("city$", " city", x)
  x <- gsub("\\s+(city|town|village|borough|municipality)$", "", x)
  x <- gsub("\\s+consolidated government \\(balance\\)$", "", x)
  x <- gsub("\\s+unified government \\(balance\\)$", "", x)
  x <- gsub("\\s+metropolitan government \\(balance\\)$", "", x)
  x <- gsub("/jefferson county metro government \\(balance\\)$", "", x)
  x <- gsub("^st\\.?\\s+", "saint ", x)
  x <- gsub("^ft\\.?\\s+", "fort ", x)
  x <- gsub("^mt\\.?\\s+", "mount ", x)
  x <- gsub("[[:punct:]]", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

coa[, city_clean := standardize_city(city_raw)]
coa[, state_clean := tolower(state_abb)]

# Manual fixes — map non-standard COA names to UCR panel city names
manual <- list(
  c("kansascity",                       "kansas city"),
  c("leaguecity",                       "league city"),
  c("dalycity",                         "daly city"),
  c("athens clarke",                    "athens-clarke county"),
  c("augusta richmond",                 "augusta-richmond county"),
  c("macon bibb county",                "macon"),
  c("nashville davidson",               "nashville-davidson county"),
  c("louisville",                       "louisville"),
  c("san buenaventura ventura",         "san buenaventura"),
  c("urban honolulu",                   "honolulu"),
  c("east los angeles",                 "east los angeles"),
  c("highlands ranch",                  "highlands ranch"),
  c("lehigh acres",                     "lehigh acres"),
  c("metairie",                         "metairie"),
  c("paradise",                         "paradise"),
  c("brandon",                          "brandon"),
  c("riverview",                        "riverview"),
  c("spring hill",                      "spring hill"),
  c("spring valley",                    "spring valley"),
  c("sunrise manor",                    "sunrise manor"),
  c("the woodlands",                    "the woodlands"),
  c("san tan valley",                   "san tan valley"),
  c("south fulton",                     "south fulton")
)
for (m in manual) coa[city_clean == m[1], city_clean := m[2]]
# Re-apply standardizer so manual mappings end up in same canonical form
coa[, city_clean := standardize_city(city_clean)]

# Cleaned year
coa[, year_created := suppressWarnings(as.integer(year_created_raw))]
coa[, treatment_year := fifelse(!is.na(year_created) & year_created > 0, year_created, 0L)]

bools <- function(x) fifelse(toupper(trimws(x)) == "Y", 1L, 0L)
coa[, has_board := bools(has_oversight_board)]
coa[, invest_power := bools(can_investigate)]
coa[, discipline_power := bools(can_discipline)]
coa[, election_created := bools(created_via_election)]

coa[, key := paste0(city_clean, "_", state_clean)]

# Dedup — keep earliest treatment year per (city,state)
coa <- coa[order(key, -treatment_year)][!duplicated(key)]

cat("Unique COA city-state pairs after re-clean:", nrow(coa), "\n")
saveRDS(coa, "C:/Users/arvind/Desktop/coa_effects/dev/coa_clean_v2.rds")
fwrite(coa, "C:/Users/arvind/Desktop/coa_effects/dev/coa_clean_v2.csv")
