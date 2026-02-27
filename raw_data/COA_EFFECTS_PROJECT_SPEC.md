# Civilian Oversight Agency (COA) Effects on Policing Outcomes

## Project Overview

This project estimates the causal effects of creating civilian oversight agencies (COAs) on policing outcomes using difference-in-differences (DiD) methods. The unit of analysis is the **municipal police department–year**. We restrict the sample to **municipal police departments only**, excluding county, state, and all other agency types.

---

## Actual Directory Structure

```
C:\Users\arvind\Desktop\coa_effects\
├── raw_data/
│   ├── arrests_csv_1974_2024_year/        # UCR arrest data (CSV files, annual)
│   ├── offenses_known_csv_1960_2024_month/ # UCR offenses known & clearances (CSV, monthly)
│   ├── coa_creation_data                   # COA creation dates & powers (treatment data)
│   ├── police_killings.xlsx                # Police killings data
│   ├── cities_historical_demographics.rds  # City-level historical demographics
│   ├── Austerity.dta                       # Austerity measures data (Stata format)
│   ├── countycouncils_comp.rds             # County councils composition data
│   ├── data_panel_post1990.rds             # Pre-built panel data (post-1990)
│   ├── ledb_candidatelevel                 # Law enforcement database, candidate level
│   └── police-residency-replication        # Police residency replication data
├── cleaned_data/                           # CREATE THIS — intermediate cleaned datasets
├── merged_data/                            # CREATE THIS — final analysis-ready panels
├── scripts/                                # CREATE THIS — all R scripts
├── output/
│   ├── tables/                             # CREATE THIS
│   └── figures/                            # CREATE THIS
└── COA_EFFECTS_PROJECT_SPEC.md             # This file
```

### Notes on Raw Data Files

- `arrests_csv_1974_2024_year/` — Folder of CSV files (likely one per year or concatenated). Explore contents first to understand structure.
- `offenses_known_csv_1960_2024_month/` — Folder of CSVs at the monthly level. Will need to aggregate to annual before analysis.
- `coa_creation_data` — Inspect to determine format (.csv, .dta, .rds, etc.) and contents.
- `police_killings.xlsx` — Excel file. Read with `readxl::read_excel()`.
- `cities_historical_demographics.rds` — R native format. Read with `readRDS()`. Likely contains city-level Census/ACS demographics over time.
- `Austerity.dta` — Stata file. Read with `haven::read_dta()`. May contain fiscal austerity measures — useful as a control or for heterogeneity.
- `data_panel_post1990.rds` — **This may be a pre-built analysis panel from prior work.** Inspect carefully — it may already contain merged UCR + demographics and save significant effort.
- `countycouncils_comp.rds` — County council composition. Potentially useful for heterogeneity or as a control.
- `ledb_candidatelevel` — Law enforcement candidate-level data. Inspect format and assess relevance.
- `police-residency-replication` — Police residency replication files. Inspect format and assess relevance.

**CRITICAL FIRST STEP:** Before building anything from scratch, inspect `data_panel_post1990.rds` thoroughly. If it already contains a merged panel of UCR data + demographics at the agency-year level, use it as the backbone and merge the COA treatment and police killings data onto it. This could save enormous effort.

---

## Step 0: Explore All Raw Data Files

**Script:** `00_explore_data.R`

Before doing anything else, systematically explore every file in `raw_data/`:

For each file:
1. Load it (detect format automatically: .csv, .dta, .rds, .xlsx, folder of CSVs)
2. Print: `dim()`, `names()`, `str()` or `glimpse()`, first 10 rows
3. Check for key identifiers: ORI, FIPS, city name, state, year
4. Check for key variables: arrest counts by offense, offenses known, clearances, race breakdowns, population, months reported
5. Summarize missingness by column
6. Save a text log of all exploration output to `output/data_exploration_log.txt`

**Pay special attention to `data_panel_post1990.rds`** — if this is already a merged panel, document exactly what variables it contains and whether it can serve as the analysis backbone.

**Decision rule:** If `data_panel_post1990.rds` already contains agency-year level UCR arrest data, offenses known, clearances, demographics, and agency identifiers, then use it as the starting point and skip to merging on COA treatment + police killings. If it is incomplete, build from the individual UCR files.

---

## Step 1: Clean the Treatment Data

**Script:** `01_clean_coa.R`

1. Load `coa_creation_data` (detect format).
2. Identify key variables: city, state, COA creation year, COA powers/type.
3. Standardize city/state names: lowercase, trim whitespace, remove punctuation, standardize abbreviations (e.g., "St." → "saint", "Ft." → "fort").
4. Create `treatment_year`. Never-treated cities get `treatment_year = 0` (for CSDID) or `NA`.
5. **Report to log:** N treated cities, treatment year distribution, COA power breakdown, geographic distribution.

---

## Step 2: Clean UCR Arrest Data

**Script:** `02_clean_ucr_arrests.R`

**Source:** `arrests_csv_1974_2024_year/` folder

1. List all CSV files in the folder. Load and bind them (use `data.table::rbindlist()` or `purrr::map_dfr()` for speed).
2. **Filter to municipal police departments only.** Look for `agency_type`, `department_type`, or similar field. Keep only municipal/city police. Exclude county sheriffs, state police, campus police, tribal, special jurisdiction, etc.
3. Construct arrest outcome variables:
   - **Violent arrests** = aggravated assault + murder/non-negligent manslaughter + rape + robbery
   - **Quality-of-life / discretionary arrests** = suspicion + vagrancy + vandalism + gambling + prostitution + drug abuse violations + liquor law violations + curfew/loitering violations + drunkenness
   - **Drug arrests** = drug abuse violations
4. Extract **race-specific arrest counts** (Black, white, total) for each category above to compute shares later.
5. Retain: `ORI`, `agency_name`, `state`, `city`, `year`, `population`, `number_of_months_reported`.
6. **Report:** Raw N, N after municipal filter, year range, unique ORIs, months-reported distribution, variable missingness.

---

## Step 3: Clean UCR Offenses Known & Clearances

**Script:** `03_clean_ucr_offenses.R`

**Source:** `offenses_known_csv_1960_2024_month/` folder

1. Load all monthly CSVs. These are at the **month** level — aggregate to **annual** by summing offenses and clearances within each agency-year.
2. **Filter to municipal police departments only.**
3. Construct:
   - **Violent crime** (offenses known): murder + rape + robbery + aggravated assault
   - **Property crime** (offenses known): burglary + larceny-theft + motor vehicle theft
   - **Violent crimes cleared by arrest**
   - **Property crimes cleared by arrest**
   - `violent_clearance_rate = cleared / known` (NA if known = 0)
   - `property_clearance_rate = cleared / known` (NA if known = 0)
4. Track `months_reported` (count of months with data per agency-year, should be 0–12).
5. Retain: `ORI`, `agency_name`, `state`, `year`, `population`, `months_reported`.
6. **Report:** Same diagnostics.

---

## Step 4: Clean Police Killings

**Script:** `04_clean_police_killings.R`

**Source:** `police_killings.xlsx`

1. Load with `readxl::read_excel()`. Inspect all columns.
2. Key variables: date/year, city, state, victim race/ethnicity, agency name, circumstances.
3. Aggregate to **agency–year** level: total killings, Black killings, non-white killings.
4. Standardize city/state names (same function as Step 1).
5. **Report:** Total killings, year range, racial breakdown, geographic coverage.

---

## Step 5: Clean Demographics

**Script:** `05_clean_demographics.R`

**Source:** `cities_historical_demographics.rds`

1. Load with `readRDS()`. Inspect structure.
2. Key variables needed: total population, % Black, % Hispanic, % non-white, median household income, poverty rate, education levels, unemployment.
3. Identify geographic identifiers: FIPS place code, city name, state.
4. Check year coverage and whether this is annual, decennial, or ACS 5-year.
5. **Report:** N cities, year range, variable availability, missingness.

---

## Step 6: Inspect Pre-Built Panel

**Script:** `06_inspect_panel.R`

**Source:** `data_panel_post1990.rds`

1. Load and thoroughly inspect.
2. Document: What unit is it at (agency-year? city-year?)? What variables does it contain? What years does it cover? Does it already have UCR arrest/offense data? Demographics? ORI codes?
3. **Decision:** Can this serve as the analysis backbone? If yes, use it and merge COA treatment + police killings onto it. If no, build from Steps 2–5.

---

## Step 7: Merge All Datasets

**Script:** `07_merge_all.R`

### Merge Key Hierarchy (most to least reliable)
1. `ORI` + `year` (best — both UCR datasets share this)
2. `FIPS place code` + `state FIPS` + `year`
3. Standardized `city_name` + `state` + `year` (fallback — use fuzzy matching if needed)

### Merge Procedure

At **every single merge step**, print and log:
```r
merge_report <- function(left, right, merged, stage_name) {
  cat("\n===", stage_name, "===\n")
  cat("Left rows:", nrow(left), "| Right rows:", nrow(right), "\n")
  cat("Merged rows:", nrow(merged), "\n")
  cat("Match rate (of left):", round(nrow(merged)/nrow(left)*100, 1), "%\n")
  cat("Unmatched left:", nrow(left) - nrow(merged), "\n")
  cat("Unmatched right:", nrow(right) - nrow(merged), "\n")
}
```

#### 7a. UCR Arrests ↔ UCR Offenses/Clearances
- Merge on `ORI` + `year`
- Both are UCR — match rate should be high

#### 7b. Merged UCR ↔ COA Treatment Data
- Try `ORI` first if COA data has it
- Then `city` + `state` (standardized) + `year`
- Use `stringdist_left_join()` with Jaro-Winkler distance (threshold ≤ 0.1) for fuzzy city matching
- **CRITICAL:** Print the full list of treated cities and whether each one matched. Any unmatched treated city needs manual attention — print it as a warning.

#### 7c. Add Police Killings
- Merge on `city` + `state` + `year` (or ORI if available)
- After merge, fill unmatched city-years with 0 killings (for cities that ARE in the panel but had no killings that year)

#### 7d. Add Demographics
- Merge on `FIPS` or `city` + `state` + `year`
- Use ORI-FIPS crosswalk if available in any of the existing datasets

### Master Merge Diagnostics

Save a table to `output/tables/merge_diagnostics.csv`:

| Stage | Left N | Right N | Matched N | Match Rate | Lost Treated Cities |
|-------|--------|---------|-----------|------------|---------------------|
| UCR Arrests ↔ Offenses | ... | ... | ... | ...% | ... |
| UCR ↔ COA Treatment | ... | ... | ... | ...% | LIST THEM |
| + Police Killings | ... | ... | ... | ...% | ... |
| + Demographics | ... | ... | ... | ...% | ... |

Final panel report:
- Dimensions: N agencies × T years
- N treated vs. control agencies
- Treatment year distribution in final sample
- Year range

---

## Step 8: Construct Analysis Variables

**Script:** `08_construct_variables.R`

### Outcome Variables

| # | Variable Name | Definition |
|---|--------------|-----------|
| 1 | `violent_crime` | Offenses known: murder + rape + robbery + aggravated assault |
| 2 | `violent_clearance_rate` | Violent cleared / violent known (NA if denom = 0; winsorize at [0,1]) |
| 3 | `property_clearance_rate` | Property cleared / property known (same handling) |
| 4 | `drug_arrests` | Drug abuse violation arrests |
| 5 | `discretionary_arrests` | suspicion + vagrancy + vandalism + gambling + prostitution + drugs + liquor + curfew/loitering + drunkenness |
| 6 | `police_killings` | Count killed by police per agency-year (0 if none) |
| 7a–h | `black_share_*` and `nonwhite_share_*` | Black (or non-white) count / total count for: violent arrests, drug arrests, discretionary arrests, police killings. Set NA if denominator < 5 |
| 8 | `months_reported` | Months agency reported to UCR (0–12) |

### Treatment Variables
- `treated`: 1 if city ever created COA
- `treatment_year`: year created (0 for never-treated, for CSDID `gname`)
- `post`: 1 if `year >= treatment_year`
- `relative_time`: `year - treatment_year`

### Rate Normalization
- Create per-capita versions (per 100,000) for all count outcomes using agency population

### Sample Restrictions
- Drop agency-years with `months_reported < 3` (robustness: test at 6, 12)
- Drop agencies with fewer than 5 years in panel
- Flag but do not drop agencies with large population jumps (possible reporting errors)

### Output
- Save final analysis dataset to `merged_data/analysis_panel.rds`
- Save summary statistics table to `output/tables/summary_stats.csv` (treated vs. control)
- Save pre-treatment trend means by relative time to `output/tables/pretrends_means.csv`

---

## Step 9: Estimation — PanelMatch

**Script:** `09_analysis_panelmatch.R`

**Package:** `PanelMatch`

### Estimation Framework: Bandwidths, Annualized, and Pooled

All estimation in this project should be run across **multiple post-treatment bandwidths** and reported in **two forms**:

- **Bandwidths:** Restrict the post-treatment window to +3 years, +4 years, and +5 years after COA creation. This means:
  - For bandwidth +3: only use data from `relative_time` in [-L, +3] (where L is the pre-treatment lag)
  - For bandwidth +4: `relative_time` in [-L, +4]
  - For bandwidth +5: `relative_time` in [-L, +5]
  - Trim the sample to these windows before estimation. This ensures results are not driven by very long-run dynamics or compositional changes in the treated sample at longer horizons.

- **Annualized estimates:** Year-by-year (dynamic/event study) treatment effects. These show the ATT at each relative time period (e.g., t+0, t+1, t+2, ..., t+K). These are the standard event study coefficients.

- **Pooled estimates:** A single average ATT across all post-treatment years within the bandwidth. For bandwidth +3, this is the average effect across years 0, 1, 2, 3 after treatment. This gives a single headline number per bandwidth.

### Implementation for PanelMatch

For **each outcome variable × each bandwidth (3, 4, 5)**:

```r
library(PanelMatch)

bandwidths <- c(3, 4, 5)

for (bw in bandwidths) {

  # Trim sample to bandwidth window
  panel_bw <- panel %>%
    filter(is.na(relative_time) | (relative_time >= -4 & relative_time <= bw))
  # Note: never-treated units (relative_time = NA) are always kept

  # --- ANNUALIZED (event study) ---
  PM_annual <- PanelMatch(
    lag = 4,
    time.id = "year",
    unit.id = "agency_id",
    treatment = "post",
    refinement.method = "mahalanobis",
    covs.formula = ~ log(population) + pct_black + median_income,
    size.match = 5,
    data = panel_bw,
    match.missing = TRUE,
    qoi = "att",
    outcome.var = "OUTCOME_NAME",
    lead = 0:bw,
    forbid.treatment.reversal = TRUE
  )

  PE_annual <- PanelEstimate(
    sets = PM_annual,
    data = panel_bw,
    se.method = "bootstrap",
    number.iterations = 1000,
    confidence.level = 0.95
  )

  # Save annualized event study plot
  png(paste0("output/figures/eventstudy_panelmatch_OUTCOME_bw", bw, ".png"),
      width = 800, height = 500)
  plot(PE_annual)
  dev.off()

  # Extract annualized coefficients
  # ... save to table with columns: outcome, bandwidth, lead, estimate, se, ci_lower, ci_upper

  # --- POOLED (single ATT across post-treatment) ---
  # PanelMatch doesn't have a built-in pooled aggregator, so compute manually:
  # Average the lead-specific ATTs (leads 0 through bw) and bootstrap the average

  # Method: Extract the per-lead ATTs from PE_annual, then take their mean.
  # For SEs: use the bootstrap iterations — for each bootstrap draw, average across leads,
  # then take the SD of those averaged draws as the pooled SE.

  coefs <- summary(PE_annual)$summary  # or however the package stores lead-specific ATTs
  pooled_att <- mean(coefs$estimate[1:(bw+1)])
  # For proper pooled SEs, average across leads within each bootstrap iteration:
  # boot_draws is iterations × leads matrix
  # pooled_boot <- rowMeans(boot_draws)
  # pooled_se <- sd(pooled_boot)

  # Save pooled result to table with columns: outcome, bandwidth, pooled_att, pooled_se, ci_lower, ci_upper
}
```

### Specification Grid

For each outcome, run the full grid:

| Dimension | Values |
|-----------|--------|
| Bandwidth | +3, +4, +5 years post-treatment |
| Estimate type | Annualized (event study) and Pooled (single ATT) |
| Covariates | None (match on outcome lags only) vs. with covariates (population, % Black, income) |
| Pre-treatment lags | 3, 4, 5 |
| Match size | 5 (baseline), 10 (robustness) |

### Output Tables

Save to `output/tables/panelmatch_annualized.csv`:
| outcome | bandwidth | lag | match_size | covariates | lead | att | se | ci_lower | ci_upper |

Save to `output/tables/panelmatch_pooled.csv`:
| outcome | bandwidth | lag | match_size | covariates | pooled_att | pooled_se | ci_lower | ci_upper |

---

## Step 10: Estimation — Callaway & Sant'Anna (CSDID)

**Script:** `10_analysis_csdid.R`

**Package:** `did`

### Implementation: Bandwidths, Annualized, and Pooled

For **each outcome variable × each bandwidth (3, 4, 5)**:

```r
library(did)

bandwidths <- c(3, 4, 5)

for (bw in bandwidths) {

  # Trim sample to bandwidth window
  # For CSDID, trimming works slightly differently because it estimates group-time ATTs.
  # Approach: restrict the panel so that for each treated unit, we only keep observations
  # within [-max_pre, +bw] of their treatment_year. Keep all years for never-treated.
  panel_bw <- panel %>%
    filter(
      treatment_year == 0 |  # never-treated: keep all years
      (relative_time >= -5 & relative_time <= bw)  # treated: trim to bandwidth
    )

  # --- GROUP-TIME ATTs ---
  gt_result <- att_gt(
    yname = "OUTCOME_NAME",
    tname = "year",
    idname = "agency_id",
    gname = "treatment_year",   # 0 for never-treated
    xformla = ~ log(population) + pct_black + median_income,
    data = panel_bw,
    est_method = "dr",
    control_group = "nevertreated",
    base_period = "varying",
    clustervars = "agency_id"
  )

  # --- ANNUALIZED (dynamic event study) ---
  es_result <- aggte(gt_result, type = "dynamic",
                     min_e = -5, max_e = bw)

  # Save event study plot
  p <- ggdid(es_result)
  ggsave(paste0("output/figures/eventstudy_csdid_OUTCOME_bw", bw, ".png"),
         p, width = 8, height = 5)

  # Extract annualized coefficients from es_result
  es_table <- data.frame(
    outcome = "OUTCOME_NAME",
    bandwidth = bw,
    event_time = es_result$egt,
    att = es_result$att.egt,
    se = es_result$se.egt
  )
  es_table$ci_lower <- es_table$att - 1.96 * es_table$se
  es_table$ci_upper <- es_table$att + 1.96 * es_table$se
  # ... append to annualized results table

  # --- POOLED (single ATT across post-treatment within bandwidth) ---
  # Use aggte with type = "simple" on the bandwidth-restricted sample.
  # This averages all post-treatment group-time ATTs into one number.
  simple_result <- aggte(gt_result, type = "simple")

  pooled_table <- data.frame(
    outcome = "OUTCOME_NAME",
    bandwidth = bw,
    pooled_att = simple_result$overall.att,
    pooled_se = simple_result$overall.se
  )
  pooled_table$ci_lower <- pooled_table$pooled_att - 1.96 * pooled_table$pooled_se
  pooled_table$ci_upper <- pooled_table$pooled_att + 1.96 * pooled_table$pooled_se
  # ... append to pooled results table

  # --- BY COHORT ---
  group_result <- aggte(gt_result, type = "group")
  # ... save cohort-specific ATTs

  # --- PRE-TRENDS TEST ---
  # From the dynamic aggregation, check that pre-treatment event-time coefficients
  # (negative event times) are jointly insignificant
  pre_coefs <- es_table %>% filter(event_time < 0)
  # Log: are pre-treatment ATTs close to zero? Any significant?
}
```

### Specification Grid

For each outcome, run the full grid:

| Dimension | Values |
|-----------|--------|
| Bandwidth | +3, +4, +5 years post-treatment |
| Estimate type | Annualized (event study) and Pooled (single ATT) |
| Covariates | None vs. `~ log(population) + pct_black + pct_hispanic + median_income + poverty_rate` |
| Control group | `"nevertreated"` (baseline) vs. `"notyettreated"` (robustness) |
| Estimation method | `"dr"` (doubly robust, baseline), `"reg"`, `"ipw"` |

### Output Tables

Save to `output/tables/csdid_annualized.csv`:
| outcome | bandwidth | covariates | control_group | est_method | event_time | att | se | ci_lower | ci_upper |

Save to `output/tables/csdid_pooled.csv`:
| outcome | bandwidth | covariates | control_group | est_method | pooled_att | pooled_se | ci_lower | ci_upper |

Save to `output/tables/csdid_by_cohort.csv`:
| outcome | bandwidth | group | att | se | ci_lower | ci_upper |

---

## Step 11: Heterogeneity Analysis

After main results:

1. **By COA power type:** Split treatment by subpoena power, investigative authority, disciplinary authority. Run CSDID separately for each subgroup. Report both annualized and pooled across all three bandwidths.
2. **By city size:** Above/below median population. Same bandwidth × annualized/pooled grid.
3. **By racial composition:** Above/below median % Black. Same grid.
4. **By region:** South vs. non-South. Same grid.

---

## Step 12: Output Checklist

### Tables
- [ ] `output/tables/merge_diagnostics.csv`
- [ ] `output/tables/summary_stats.csv`
- [ ] `output/tables/pretrends_means.csv`
- [ ] `output/tables/panelmatch_annualized.csv` — all outcomes × bandwidths × specs, year-by-year ATTs
- [ ] `output/tables/panelmatch_pooled.csv` — all outcomes × bandwidths × specs, single pooled ATTs
- [ ] `output/tables/csdid_annualized.csv` — all outcomes × bandwidths × specs, event study ATTs
- [ ] `output/tables/csdid_pooled.csv` — all outcomes × bandwidths × specs, single pooled ATTs
- [ ] `output/tables/csdid_by_cohort.csv` — cohort-specific ATTs
- [ ] `output/tables/heterogeneity_results.csv`

### Figures
- [ ] `output/figures/treatment_timing_histogram.png`
- [ ] `output/figures/pretrends_raw_*.png` (one per outcome)
- [ ] `output/figures/eventstudy_panelmatch_*_bw3.png` (one per outcome)
- [ ] `output/figures/eventstudy_panelmatch_*_bw4.png` (one per outcome)
- [ ] `output/figures/eventstudy_panelmatch_*_bw5.png` (one per outcome)
- [ ] `output/figures/eventstudy_csdid_*_bw3.png` (one per outcome)
- [ ] `output/figures/eventstudy_csdid_*_bw4.png` (one per outcome)
- [ ] `output/figures/eventstudy_csdid_*_bw5.png` (one per outcome)

### Summary Document
- [ ] `output/RESULTS_SUMMARY.md` — includes for each outcome:
  - Pooled ATT table across bandwidths (3, 4, 5) for both PanelMatch and CSDID
  - Event study figure references
  - Pre-trends assessment
  - Key takeaways

---

## R Package Dependencies

```r
install.packages(c(
  "tidyverse", "data.table", "haven", "readr", "readxl",
  "stringdist", "fuzzyjoin",
  "PanelMatch", "did", "fixest",
  "modelsummary", "kableExtra",
  "ggplot2", "patchwork", "scales"
))
```

---

## INSTRUCTIONS FOR CLAUDE CODE

### How to Launch This Project

Open a terminal in `C:\Users\arvind\Desktop\coa_effects\` and run:

```
claude
```

Then paste the following prompt (see below). Claude Code will read this spec file and execute autonomously.

### The Prompt to Give Claude Code

```
Read the file `COA_EFFECTS_PROJECT_SPEC.md` in this directory. This is a complete specification
for a research project on the causal effects of civilian oversight agencies on policing outcomes.

Execute the entire project from start to finish, following the spec step by step.

OPERATING RULES:

1. AUTONOMOUS EXECUTION: Do not ask me questions or pause for confirmation at any point.
   Make reasonable decisions and document them in log files. If something is ambiguous,
   pick the best option, note what you chose and why in a log, and keep going.

2. DECISION-MAKING PROTOCOL:
   - If a merge fails or has low match rates: try alternative identifiers (ORI, city+state,
     fuzzy match), log the results, and proceed with the best available match.
   - If a variable is missing from a dataset: skip that variable, note it in the log,
     and continue with available variables.
   - If a model fails to converge or errors out: log the error, try a simpler specification,
     and move on to the next outcome.
   - If a file format is ambiguous: try the most likely format first, fall back to alternatives.
   - If column names don't match expected names: inspect the data, identify the closest match,
     and rename accordingly. Log the mapping.

3. LOGGING: Create a running log file at `output/analysis_log.txt`. Append to it at every
   major step: what you did, what you found, what decisions you made, match rates, sample
   sizes, any warnings or issues.

4. ORDER OF OPERATIONS: Follow the spec's step numbering (0 through 12). Do not skip steps.
   The exploration step (Step 0) is critical — the contents of the data files determine
   everything downstream.

5. ERROR RECOVERY: If a script errors out, diagnose the issue, fix it, and re-run. Do not
   stop the entire pipeline for one failed step. Wrap model estimation in tryCatch() so one
   failed model doesn't kill the batch.

6. CREATE ALL DIRECTORIES that don't exist yet (cleaned_data/, merged_data/, scripts/,
   output/tables/, output/figures/).

7. WRITE ALL SCRIPTS as .R files in the scripts/ folder, then source them. This creates
   a reproducible record.

8. ESTIMATION STRUCTURE: For every outcome, run estimation across bandwidths (+3, +4, +5
   years post-treatment). For each bandwidth, produce BOTH annualized (year-by-year event
   study) estimates AND pooled (single average post-treatment ATT) estimates. This applies
   to both PanelMatch and CSDID. The results tables must clearly label bandwidth, estimate
   type (annualized vs pooled), and specification.

9. FINAL DELIVERABLE: When done, produce a summary document (output/RESULTS_SUMMARY.md)
   containing:
   - Data overview and merge success rates
   - Summary statistics
   - Main DiD results (PanelMatch and CSDID) for all outcomes, all bandwidths, annualized and pooled
   - Key event study figures (embed or reference file paths)
   - Any issues, caveats, or data limitations encountered

Start now. Begin with Step 0: explore all raw data files.
```

### Tips for Best Results with Claude Code

- **Give it the full spec up front.** Claude Code works best when it can see the entire plan and execute sequentially rather than getting instructions piecemeal.
- **Don't interrupt mid-pipeline.** Let it run through the full sequence. Check the log file afterward.
- **If it hits a wall:** Re-prompt with "Continue from where you left off. Read the log at output/analysis_log.txt to see what's been completed."
- **For very long pipelines:** You may need to break into 2–3 sessions:
  - Session 1: "Execute Steps 0–8 from the spec" (data cleaning + merging)
  - Session 2: "Execute Steps 9–10 from the spec" (estimation)
  - Session 3: "Execute Steps 11–12 from the spec" (heterogeneity + output)
- **If you need to adjust after seeing results:** Edit the spec, then tell Claude Code "Re-read the spec. I've updated [section]. Re-run from Step [X]."

---

## References

- Callaway, B., & Sant'Anna, P. H. (2021). Difference-in-differences with multiple time periods. *Journal of Econometrics*, 225(2), 200–230.
- Imai, K., Kim, I. S., & Wang, E. H. (2021). Matching methods for causal inference with time-series cross-sectional data. *American Journal of Political Science*.
