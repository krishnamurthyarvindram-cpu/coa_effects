# Data Availability and Merge Missingness Report

**Project:** Causal Effects of Civilian Oversight Agencies (COAs) on Policing Outcomes
**Generated:** 2026-03-05

---

## 1. Source Data Universe

| Data Source | Raw Records | Unique Cities | Year Range | Key Join Field |
|-------------|------------|---------------|------------|----------------|
| COA/CRB Spreadsheet | 336 rows | 335 city-state pairs | Creation years: 1895-2025 | city + state (standardized) |
| Pre-built UCR Panel (`data_panel_post1990.rds`) | 12,436 city-years | 384 cities / 398 agencies | 1990-2021 | ORI, FIPS, city + state |
| Police Killings (`police_killings.xlsx`) | 31,498 individual incidents | 8,053 cities | 1999-2021 | city + state + year |
| Demographics (`cities_historical_demographics.rds`) | 1,609,203 rows | ~1,000+ FIPS codes | 1970-2020 | FIPS place code + year |
| UCR Arrests (raw CSVs, 51 files) | ~100-150 agencies/year | -- | 1974-2024 | ORI (pre-merged into panel) |
| UCR Offenses Known (raw CSVs, 65 files) | -- | -- | 1960-2024 | ORI (pre-merged into panel) |

### COA/CRB Spreadsheet Breakdown
- **Total cities in spreadsheet:** 336
- **Cities with valid COA creation year (treated):** 122
- **Cities without creation year (never-treated controls from spreadsheet):** 213
- **One duplicate dropped during cleaning:** final = 335 unique city-state pairs

---

## 2. Merge Results: COA Cities into UCR Panel

The UCR panel backbone contains **398 unique agencies across 384 cities**. The COA/CRB data was merged via standardized city+state name matching (exact + fuzzy Jaro-Winkler).

### Iterative Merge Progress

| Merge Stage | Treated Cities Matched | Control Cities Matched | Unmatched Treated |
|-------------|----------------------|----------------------|-------------------|
| Initial exact match | 103 | 295 | 21 |
| After fuzzy match + suffix fix (Step 7b) | 108 | 290 | 16 |
| After aggressive fuzzy + manual (Step 7d) | 112 | 286 | 9 |
| After manual Nashville/Louisville fix (Step 7e) | **114** | **284** | **8** |

### Match Rate Summary
- **122 treated COA cities** in the original spreadsheet
- **114 matched** to the UCR panel (93.4% match rate)
- **8 treated cities permanently unmatched** (6.6% lost):

| Unmatched Treated City | State | Likely Reason |
|------------------------|-------|---------------|
| Arlington | VA | Not in UCR panel (county-based jurisdiction?) |
| Burbank | CA | Small agency, not in panel |
| Cambridge | MA | Not in UCR panel |
| Columbia | MD | Unincorporated CDP (not a city police dept) |
| Louisville/Jefferson County | KY | Name mismatch partially resolved; 2 matched manually |
| Nashville-Davidson | TN | Name mismatch partially resolved; matched manually |
| South Fulton | GA | Very new city (incorporated 2017), not yet in panel |
| Springfield | MS | State abbreviation error? (no Springfield, MS exists) |
| Urban Honolulu | HI | Hawaii uses county-based policing; no city PD in UCR |

*Note: Nashville and Louisville were matched via manual fix in Step 7e, bringing the total to 114. The 8 listed above are the truly unresolvable cases.*

---

## 3. Merge Results: Police Killings into Panel

| Metric | Value |
|--------|-------|
| Raw police killing incidents | 31,498 |
| Aggregated to city-state-year level | 19,478 unique observations |
| Unique cities in killings data | 8,053 |
| Panel city-years matched with killings > 0 | 4,130 (33.2% of 12,436 panel rows) |
| Panel city-years with zero killings | 8,306 (66.8%) |
| Total killings captured in final panel | ~13,054 |
| Match rate (panel rows with any killing data) | 34.8% of left join |

**Interpretation:** Most panel city-years have zero police killings, which is expected -- these are relatively rare events distributed across 384 cities over 22 years. The 34.8% rate reflects city-years where at least one killing occurred, not missing data per se.

---

## 4. Merge Results: Demographics into Panel

| Metric | Value |
|--------|-------|
| Demographic rows available | 1,609,203 |
| Panel rows with demographics matched | 8,773 (70.5%) |
| Panel rows missing demographics | 3,663 (29.5%) |

**Key gap:** No median income variable was available in any data source. Models rely on `log_population` and `pct_black` as covariates only.

---

## 5. Data Availability by Model/Estimator

### A. PanelMatch (Matching-Based DiD)

- **Estimation window:** 2000-2020
- **Panel fed to PanelMatch:** 8,358 city-years (after restricting to 2000-2020), 398 units
- **Treated units with treatment transition in range:** 97

| Outcome Variable | Non-NA City-Years | Treated Post-Treatment Obs | % Available |
|------------------|-------------------|---------------------------|-------------|
| violent_crime_pc | 9,869 | 1,227 | 94.5% |
| violent_clearance_rate | 9,866 | 1,227 | 94.5% |
| property_clearance_rate | 9,871 | 1,228 | 94.5% |
| drug_arrests_pc | 8,025 | 995 | 76.8% |
| discretionary_arrests_pc | 8,025 | 995 | 76.8% |
| police_killings_pc | 10,446 | 1,343 | 100.0% |
| black_share_violent_arrests | 8,022 | 994 | 76.8% |
| black_share_drug_arrests | 7,997 | 991 | 76.5% |

**Notes:**
- Drug/discretionary arrest and racial share variables have ~23% missing, likely from agencies with incomplete UCR reporting in some years.
- Police killings coded as 0 when no incident recorded, so 100% "available" but highly zero-inflated.
- PanelMatch ran with bandwidths BW=3, 4, 5 and lags=4, match=5.

### B. CSDID (Callaway & Sant'Anna)

- **Estimation window:** 2000-2020
- **Panel fed to CSDID:** 7,602 city-years (after dropping incomplete units), 362 units
- **Treated cohorts used:** 21 distinct treatment years (2000-2020)
- **Treated units:** 53
- **Never-treated (control) units:** 309
- **Group-time ATTs estimated:** 340 (for outcomes with all years); 320 (for arrest-based outcomes with more missing data)

| Outcome | Group-Time ATTs | Notes |
|---------|-----------------|-------|
| violent_crime_pc | 340 | Full coverage |
| violent_clearance_rate | 340 | Full coverage |
| property_clearance_rate | 340 | Full coverage |
| drug_arrests_pc | 320 | Fewer due to missing arrest data |
| discretionary_arrests_pc | 320 | Fewer due to missing arrest data |
| police_killings_pc | 340 | Full coverage |
| black_share_violent_arrests | 320 | Fewer due to missing data |
| black_share_drug_arrests | 320 | Fewer due to missing data |

**Key difference from PanelMatch:** CSDID uses `panel=FALSE` (repeated cross-section mode) because of unbalanced panel. It also restricts to units with sufficient pre/post data, reducing from 398 to 362 units and from 114 to 53 treated cities.

### C. Heterogeneity Analysis (CSDID subgroups)

- **Base panel:** 7,602 city-years, 362 units
- **Median population cutoff:** 107,730
- **Median % Black cutoff:** 9.92%

| Subgroup | Treated Units | Notes |
|----------|--------------|-------|
| Investigative power: Yes | 14 | Many outcomes failed (singular matrix) |
| Investigative power: No | 39 | Most outcomes failed (singular matrix) |
| Disciplinary power: Yes | 5 | All outcomes succeeded |
| Disciplinary power: No | 48 | Some outcomes failed |
| Large city (above median pop) | 48 | All outcomes succeeded |
| Small city (below median pop) | 5 | All outcomes succeeded |
| High % Black (above median) | 34 | Several outcomes failed |
| Low % Black (below median) | 19 | Most outcomes succeeded |
| South | 15 | Some outcomes failed |
| Non-South | 38 | Most outcomes succeeded |

### D. Electoral Incumbent DiD (Script 13)

- **Data:** LEDB candidate-level electoral data merged with COA treatment
- **Join:** city+state fuzzy match between LEDB and COA spreadsheet
- **Panel structure:** Candidate-election observations (incumbents with 2+ appearances)
- **Treatment:** `coa_created_during_term` (binary, COA created between consecutive elections)

### E. COA Adoption Predictors (Script 14)

- **Cross-sectional sample:** Pre-treatment city averages for cities in the analysis panel
- **Panel hazard model:** City-years up to (and including) adoption year for treated cities; all years for controls
- **Cities in cross-section:** Derived from the 398-city analysis panel
- **Covariates:** Population, demographics, political variables, crime rates (pre-treatment averages)

### F. COA Strength Analysis (Script 15)

- **Base:** Analysis panel (12,436 city-years, 398 cities)
- **Strong COA:** Cities with investigative or disciplinary power
- **Weak COA:** Cities with board only (no investigative/disciplinary power)
- **Policing panel:** Subset with sufficient data for TWFE regressions
- **Comparisons:** Strong vs. control, weak vs. control, and joint models

---

## 6. Summary: City Counts Across the Pipeline

```
COA/CRB Spreadsheet
  336 total rows (335 unique city-state pairs)
  ├── 122 treated (valid creation year)
  └── 213 never-treated
         │
         ▼  Merge with UCR Panel (398 agencies / 384 cities)
         │
  ┌──────┴──────────────────────────────────┐
  │  114 treated matched (93.4%)            │
  │  284 never-treated in panel             │
  │    8 treated cities LOST                │
  │  Total: 398 cities in analysis panel    │
  └──────┬──────────────────────────────────┘
         │
         ▼  Restrict to 2000-2020 + data completeness
         │
  ┌──────┴──────────────────────────────────┐
  │  PanelMatch: 398 units, 97 treated      │
  │  CSDID:      362 units, 53 treated      │
  │  (CSDID drops units w/ gaps)            │
  └─────────────────────────────────────────┘
```

---

## 7. Variable-Level Missingness in Final Analysis Panel (12,436 rows)

| Variable | Non-NA | Missing | % Missing |
|----------|--------|---------|-----------|
| Population | 12,436 | 0 | 0.0% |
| violent_crime_pc | 12,436 | 0 | 0.0% |
| violent_clearance_rate | 11,750 | 686 | 5.5% |
| property_clearance_rate | 11,755 | 681 | 5.5% |
| drug_arrests_pc | 12,436 | 0 | 0.0% |
| discretionary_arrests_pc | 12,436 | 0 | 0.0% |
| police_killings_pc | 12,436 | 0 | 0.0%* |
| black_share_violent_arrests | varies | varies | ~23% |
| black_share_drug_arrests | varies | varies | ~23% |
| pct_black (demographics) | 8,773 | 3,663 | 29.5% |
| pct_white (demographics) | 8,773 | 3,663 | 29.5% |
| median_income | 0 | 12,436 | 100.0% |

*Police killings coded as 0 when no incident; true missingness is 0% but data is highly zero-inflated (66.8% of city-years = 0).

---

## 8. Key Concerns and Caveats

1. **8 treated COA cities could not be matched** to the UCR panel, including major cities like Honolulu and Arlington, VA. These are disproportionately non-standard jurisdictions (county-based, CDPs, or very new cities).

2. **CSDID uses only 53 of 114 treated cities** due to panel balance requirements and the 2000-2020 window restriction. This is a substantial reduction that may affect external validity.

3. **Drug/arrest racial share variables are ~23% missing**, creating differential sample sizes across outcome models. Results for these outcomes are based on a smaller, potentially non-random subset.

4. **Demographics are 29.5% missing**, limiting covariate-adjusted specifications. Models with covariates use only `log_population` and `pct_black`.

5. **No median income data** was available from any source, which is a meaningful omission for selection-on-observables strategies.

6. **Police killings are zero-inflated:** 66.8% of city-years have zero killings. The per-capita rate is dominated by zeros, potentially biasing linear DiD estimates.

7. **UCR data quality:** Some city-years show implausible per-capita crime rates (max ~290,000 per 100K for violent crime), suggesting population denominator errors or reporting anomalies.
