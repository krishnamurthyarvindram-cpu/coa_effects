## Quick panel inspection
panel <- readRDS("C:/Users/arvind/Desktop/coa_effects/raw_data/data_panel_post1990.rds")

# Only keep column names
nms <- names(panel)

# Clearance/offense columns
clear_cols <- grep("clear|offense|known|unfound", nms, ignore.case=TRUE, value=TRUE)
cat("Clearance/offense columns:", paste(clear_cols, collapse=", "), "\n")

# Year range
cat("Year range:", min(panel$year, na.rm=TRUE), "-", max(panel$year, na.rm=TRUE), "\n")
cat("Unique cities:", length(unique(panel$city)), "\n")
cat("Unique place_fips:", length(unique(panel$place_fips)), "\n")
cat("Rows:", nrow(panel), "Cols:", ncol(panel), "\n")

# Sample cities
cat("Sample cities:", paste(head(unique(panel$city), 15), collapse=", "), "\n")
cat("Sample abb:", paste(head(unique(panel$abb), 10), collapse=", "), "\n")

# COA columns
coa_cols <- grep("coa|oversight|treat|civilian", nms, ignore.case=TRUE, value=TRUE)
cat("COA columns:", paste(coa_cols, collapse=", "), "\n")

# Killings columns
kill_cols <- grep("kill|death|fatal|shoot", nms, ignore.case=TRUE, value=TRUE)
cat("Killings columns:", paste(kill_cols, collapse=", "), "\n")

# Population check
pop_cols <- grep("pop", nms, ignore.case=TRUE, value=TRUE)
cat("Population columns:", paste(pop_cols, collapse=", "), "\n")

# Free memory
rm(panel)
gc()
cat("Done.\n")
