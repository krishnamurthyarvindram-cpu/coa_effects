library(data.table)
panel <- as.data.table(readRDS("C:/Users/arvind/Desktop/coa_effects/merged_data/analysis_panel.rds"))

cat("Columns with invest/discipline/election/board:\n")
cols <- grep("invest|discipline|election|board|select|power|region|south", names(panel), value=TRUE, ignore.case=TRUE)
cat(paste(cols, collapse="\n"), "\n\n")

# Unique treated agencies
tr <- unique(panel[treated==1, .(agency_id, treatment_year, has_board, invest_power, discipline_power, election_created)])
cat("Treated agencies:", nrow(tr), "\n")

cat("\nHas board distribution:\n")
print(table(tr$has_board, useNA="ifany"))

cat("\nInvest power distribution:\n")
print(table(tr$invest_power, useNA="ifany"))

cat("\nDiscipline power distribution:\n")
print(table(tr$discipline_power, useNA="ifany"))

cat("\nElection created distribution:\n")
print(table(tr$election_created, useNA="ifany"))

cat("\nMedian population (all obs):\n")
cat(median(panel$population, na.rm=TRUE), "\n")

cat("\nMedian pct_black (all obs):\n")
cat(median(panel$pct_black, na.rm=TRUE), "\n")

cat("\nUnique states:\n")
st <- unique(panel[, .(agency_id, state_clean)])
print(sort(table(st$state_clean), decreasing=TRUE))

cat("\nSelection method:\n")
print(table(tr$election_created, useNA="ifany"))
