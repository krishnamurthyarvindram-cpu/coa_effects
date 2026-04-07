# Claude Code Instructions: COA Effects — Accountability Trap Analyses

## Project Context

This is the `coa_effects` repository. The core paper ("Handcuffed By Design") uses a staggered
difference-in-differences design across 243 large U.S. cities (1980–2020) to show that civilian
oversight agencies (COAs) do not change police behavior, and that politicians benefit electorally
from creating them. The goal of these new analyses is to transform that paper into a demonstration
of the **accountability trap**: a self-reinforcing equilibrium in which weak oversight reproduces
the political conditions that make weak oversight rational. 

The analyses below are organized in priority order. Complete each section fully before moving to
the next. All output should go in `output/`. All new or modified scripts go in `scripts/`.

---

## 0. Orientation — Understand the Data First

Before writing any new analysis code, do the following:

1. List all files in `cleaned_data/`, `merged_data/`, and `raw_data/` and print their names,
   dimensions, and column names. For CSV/RDS files use R. For any file you cannot immediately
   open, note the format and skip it.

2. For the main panel dataset (likely something like `panel_data`, `city_panel`, or `main_data`),
   print:
   - `head()` and `str()`
   - The full list of column names
   - The range of years covered
   - Number of unique cities
   - The name and coding of the COA adoption indicator (likely a dummy for whether a city has
     adopted a COA in year t)
   - The name and coding of any board authority/power variable (e.g., investigative authority,
     disciplinary authority, or a composite power score)
   - All outcome variables (clearance rate, police killings, discretionary arrests, racial
     disparities, vote share, etc.)

3. Check the `coa_charter_pdfs/` folder. Count how many PDFs are present and list their
   filenames. Note any naming convention (e.g., city name, year, or board name).

4. Look at all existing scripts in `scripts/`. For each script, print the filename and the
   first 30 lines so you understand what analyses already exist. Do not re-run existing analyses
   unless instructed.

5. Print a summary of your findings from steps 1–4 before proceeding. This is your orientation
   memo. It should answer: what data do I have, what outcomes are currently modeled, and what
   variables exist for board strength?

---

## 1. Sharpen the Board Power Measure

### 1a. Audit the existing authority coding

The paper codes boards into three tiers: review-only, investigative authority, and disciplinary
authority. Before building anything new, audit this coding:

```r
# Load the panel
# (use whatever the actual dataset name is — check step 0)

# Tabulate the authority variable(s)
table(panel$authority_level, useNA = "always")   # adjust column name as needed

# Cross-tab authority by decade of adoption
panel %>%
  filter(!is.na(coa_adopted_year)) %>%           # adjust column name as needed
  mutate(decade = floor(coa_adopted_year / 10) * 10) %>%
  group_by(decade, authority_level) %>%
  summarise(n = n_distinct(city)) %>%
  pivot_wider(names_from = authority_level, values_from = n, values_fill = 0)
```

Save this table to `output/authority_by_decade.csv`. Flag in a comment if the distribution
looks different from what the paper reports (96.1% cannot discipline).

### 1b. Extract additional features from charter PDFs (Python)

Create a new script `scripts/charter_text_extraction.py`. This script should:

1. Loop over every PDF in `coa_charter_pdfs/`.
2. Extract full text from each PDF using `pdfplumber` (install if needed: `pip install pdfplumber`).
3. For each charter, search for the following features and record TRUE/FALSE:

   **Sunset clause:** Search for any of: "sunset", "expires", "expiration", "shall terminate",
   "unless reauthorized", "subject to renewal". Flag TRUE if any found.

   **Voluntary cooperation language:** Search for: "shall cooperate", "may cooperate",
   "upon request", "voluntary", "if requested", "with the consent of". Flag TRUE if any found
   (this suggests police cooperation is discretionary rather than mandatory).

   **Mandatory cooperation language:** Search for: "shall provide", "must provide",
   "required to cooperate", "shall appear", "compelled", "subpoena". Flag TRUE if any found.

   **Budget language:** Search for: "appropriation", "budget", "funding", "fiscal year".
   Flag TRUE if any found.

   **Union exclusion:** Search for: "collective bargaining", "union contract", "MOU",
   "memorandum of understanding". Flag TRUE if any found (suggests union contract limits board).

4. Output a dataframe with one row per charter PDF, columns:
   `filename, has_sunset, voluntary_cooperation, mandatory_cooperation, 
    has_budget_language, has_union_exclusion, text_length`

5. Save to `output/charter_features.csv`.

6. Print the frequency of each feature across all charters.

### 1c. Merge charter features back to the panel

Create `scripts/merge_charter_features.R`:

1. Load `output/charter_features.csv`.
2. Parse city names from the PDF filenames (use whatever naming convention exists — inspect
   filenames first and write a regex or manual lookup as needed).
3. Merge to the panel on city (and year if multiple charters per city exist).
4. Create a composite `board_weakness_index` that sums: `has_sunset` +
   `voluntary_cooperation` + `has_union_exclusion`. Higher = weaker board design.
5. Save the augmented panel to `merged_data/panel_with_charter_features.rds`.
6. Print crosstabs of `board_weakness_index` by `authority_level` to verify they correlate
   as expected.

---

## 2. The Core Trap Analysis: Board Strength Interaction in the DiD

This is the most important new analysis. Create `scripts/did_by_board_strength.R`.

### 2a. Split-sample DiD by authority level

Using the main panel and your DiD specification (replicate whatever estimator is in the
existing scripts — likely `fixest::feols` or `estimatr::lm_robust` with city and year FEs):

Run the main DiD separately for three subsamples:
- Cities with review-only boards
- Cities with investigative authority boards  
- Cities with disciplinary authority boards (the ~4% group)

For each subsample, estimate effects on ALL of the paper's main outcomes
(clearance rate, police killings per 100k, discretionary arrest rate, racial disparity
measures, and any others in the panel).

```r
library(fixest)
library(modelsummary)

outcomes <- c("clearance_rate", "police_killings_per100k", 
              "discretionary_arrests", "black_arrest_share")  
# Adjust these to actual column names found in step 0

authority_levels <- c("review_only", "investigative", "disciplinary")

results <- list()

for (auth in authority_levels) {
  sub <- panel %>% filter(authority_level == auth | !ever_adopted_coa)
  # ^ Include never-adopters as control group in each subsample
  
  for (outcome in outcomes) {
    formula <- as.formula(paste(outcome, "~ coa_active | city + year"))
    # Adjust treatment indicator name to match actual data
    
    mod <- feols(formula, data = sub, cluster = ~city)
    results[[paste(auth, outcome, sep = "_")]] <- mod
  }
}

# Export a coefficient plot comparing the three groups
# Use modelsummary or broom to tidy results into a single dataframe
coef_df <- map_dfr(names(results), function(nm) {
  parts <- str_split(nm, "_", n = 2)[[1]]
  tidy(results[[nm]]) %>%
    filter(term == "coa_active") %>%
    mutate(authority = parts[1], outcome = parts[2])
})

# Save
write_csv(coef_df, "output/did_by_authority_level.csv")

# Plot
ggplot(coef_df, aes(x = authority, y = estimate, ymin = estimate - 1.96*std.error,
                     ymax = estimate + 1.96*std.error, color = authority)) +
  geom_pointrange() +
  geom_hline(yintercept = 0, linetype = "dashed") +
  facet_wrap(~outcome, scales = "free_y") +
  labs(title = "DiD Effects by Board Authority Level",
       subtitle = "Null average masks heterogeneity by board strength",
       x = "Board Authority Level", y = "ATT (95% CI)") +
  theme_minimal() +
  theme(legend.position = "none")

ggsave("output/did_by_authority_level.png", width = 10, height = 7, dpi = 300)
```

### 2b. Continuous interaction

If a continuous power score exists or can be constructed (e.g., 0 = review only,
1 = investigative, 2 = disciplinary; or use the `board_weakness_index` from step 1c),
run an interaction model:

```r
mod_interaction <- feols(
  clearance_rate ~ coa_active * authority_score | city + year,
  # Replace clearance_rate and authority_score with actual names
  data = panel,
  cluster = ~city
)

# Marginal effects plot: predicted effect of COA at each level of authority_score
library(marginaleffects)
plot_predictions(mod_interaction, condition = c("authority_score", "coa_active"))
ggsave("output/interaction_marginal_effects.png", width = 8, height = 5, dpi = 300)
```

Save all model objects to `output/models_by_strength.rds`.

---

## 3. The Post-Floyd Equilibrium Robustness Test

This is the most theoretically decisive test. Create `scripts/post_floyd_analysis.R`.

### 3a. Extend the sample if post-2020 charter data exists

Check whether any data in the repo covers board adoptions or authority changes after 2020.
If it does, use it. If not, note this as a limitation and work with what is available.

### 3b. Identify Floyd-era board creations

In the existing panel (or extended if available), flag boards created in 2020–2021:

```r
panel <- panel %>%
  mutate(floyd_era = case_when(
    coa_adopted_year == 2020 ~ "Floyd-era (2020)",
    coa_adopted_year == 2021 ~ "Floyd-era (2021)",
    coa_adopted_year >= 2015 & coa_adopted_year < 2020 ~ "Pre-Floyd (2015-2019)",
    coa_adopted_year < 2015 ~ "Early adoption (pre-2015)",
    TRUE ~ NA_character_
  ))
```

### 3c. Compare authority levels across adoption eras

```r
era_authority <- panel %>%
  filter(!is.na(coa_adopted_year)) %>%
  distinct(city, floyd_era, authority_level) %>%
  group_by(floyd_era, authority_level) %>%
  summarise(n = n()) %>%
  group_by(floyd_era) %>%
  mutate(pct = n / sum(n) * 100)

write_csv(era_authority, "output/authority_by_floyd_era.csv")
print(era_authority)

# Bar chart
ggplot(era_authority, aes(x = floyd_era, y = pct, fill = authority_level)) +
  geom_col(position = "stack") +
  geom_text(aes(label = paste0(round(pct, 1), "%")),
            position = position_stack(vjust = 0.5), size = 3, color = "white") +
  labs(title = "Board Authority Level by Adoption Era",
       subtitle = "If the accountability trap holds, Floyd-era boards should be no stronger",
       x = "Adoption Era", y = "Share of Boards (%)", fill = "Authority Level") +
  theme_minimal() +
  scale_fill_manual(values = c("review_only" = "#d62728",
                                "investigative" = "#ff7f0e",
                                "disciplinary" = "#2ca02c"))

ggsave("output/authority_by_floyd_era.png", width = 9, height = 6, dpi = 300)
```

### 3d. Chi-square test: is Floyd-era authority distribution different?

```r
contingency <- panel %>%
  filter(!is.na(coa_adopted_year)) %>%
  distinct(city, floyd_era, authority_level) %>%
  mutate(floyd_binary = ifelse(grepl("Floyd", floyd_era), "Floyd-era", "Pre-Floyd")) %>%
  count(floyd_binary, authority_level) %>%
  pivot_wider(names_from = authority_level, values_from = n, values_fill = 0) %>%
  column_to_rownames("floyd_binary")

chisq_result <- chisq.test(contingency)
print(chisq_result)
# Trap prediction: p > 0.05 (no significant difference — equilibrium absorbed the shock)
```

Save results and interpretation to `output/floyd_era_test.txt`. Print a one-paragraph
interpretation: does the data support the trap prediction?

---

## 4. Board Strength Trajectory Analysis (Amendment Model)

This analysis tests whether boards strengthen over time organically or only following shocks.

### 4a. Check for time-varying authority data

Look in `raw_data/` and `cleaned_data/` for any dataset that has authority scores measured
at multiple points for the same city (e.g., original adoption authority + any subsequent
amendment records). If such data exists, use it. If authority is only coded once per city
(at adoption), note this limitation and skip to step 4b.

### 4b. Construct amendment outcome from adoption records

If the data includes both `adoption_year` and `authority_level` but also has records of
cities that disbanded and re-created boards (which the paper mentions), use this to infer
strengthening or weakening:

```r
# Cities that created, disbanded, and re-created a board potentially signal
# equilibrium instability — flag and examine these cases
disbanded_cities <- panel %>%
  group_by(city) %>%
  filter(any(coa_disbanded == 1)) %>%  # adjust variable name
  distinct(city) %>%
  pull(city)

cat("Cities with disbanded boards:", length(disbanded_cities), "\n")
cat(disbanded_cities, sep = "\n")
```

### 4c. Event study: does authority predict outcomes differently by years-since-creation

Even without amendment data, you can run an event study relative to adoption year to see
whether the null effects persist or attenuate over time (if they attenuate, the board
might be strengthening informally; if they persist, consistent with the trap):

```r
# Relative time indicators
panel <- panel %>%
  group_by(city) %>%
  mutate(rel_time = year - coa_adopted_year) %>%  # adjust variable name
  ungroup()

# Sun-Baker or Callaway-Sant'Anna event study (if already in existing scripts, adapt)
# If using fixest:
library(fixest)

es_mod <- feols(
  clearance_rate ~                               # adjust outcome
    i(rel_time, ref = -1) |                      # event study relative to adoption
    city + year,
  data = panel %>% filter(rel_time >= -5 & rel_time <= 10),
  cluster = ~city
)

iplot(es_mod, main = "Event Study: Effect of COA Adoption on Clearance Rate",
      xlab = "Years Relative to COA Adoption")

# Do this for each outcome
for (outcome in outcomes) {
  es <- feols(as.formula(paste(outcome, "~ i(rel_time, ref = -1) | city + year")),
              data = panel %>% filter(rel_time >= -5 & rel_time <= 10),
              cluster = ~city)
  png(paste0("output/event_study_", outcome, ".png"), width = 800, height = 500)
  iplot(es, main = paste("Event Study:", outcome))
  dev.off()
}
```

---

## 5. Police Political Capacity as a Predictor of Board Weakness

This analysis tests whether police political capacity at the state level predicts board
weakness at the city level — the Node 1 → Node 2 mechanism of the accountability trap.

### 5a. Merge state collective bargaining law data

The key external dataset is Dhammapala, McAdams, and Rappaport's coding of state police
collective bargaining laws. Check whether this is already in `raw_data/`. If it is, load it.
If not, create a placeholder dataset with the following structure and note it needs to be
filled in with the published coding:

```r
# Placeholder — fill with actual Dhammapala et al. coding
# Variables needed:
#   state: state abbreviation
#   cb_year: year the variable is coded (use earliest available)
#   mandatory_bargaining: 1 if state requires collective bargaining with police unions
#   leobr: 1 if state has a Law Enforcement Officers' Bill of Rights
#   grievance_arbitration: 1 if state requires binding arbitration of officer grievances

# If the data is already in raw_data, load it here and merge on state + year
# panel <- panel %>%
#   left_join(cb_laws, by = c("state", "year"))
```

If the CB law data is available and merged, run:

```r
# Does mandatory bargaining predict weaker boards?
# Unit of analysis: city-level, one row per city, at time of adoption

adoption_level <- panel %>%
  filter(!is.na(coa_adopted_year)) %>%
  distinct(city, state, coa_adopted_year, authority_level, .keep_all = TRUE) %>%
  left_join(cb_laws %>% filter(cb_year <= 2000),  # pre-period CB law
            by = "state")

# Authority as ordered outcome
adoption_level <- adoption_level %>%
  mutate(authority_num = case_when(
    authority_level == "review_only" ~ 0,
    authority_level == "investigative" ~ 1,
    authority_level == "disciplinary" ~ 2,
    TRUE ~ NA_real_
  ))

mod_cb <- lm(authority_num ~ mandatory_bargaining + leobr + 
               log(population) + pct_black + median_income + 
               factor(decade_adopted),  # adjust variable names
             data = adoption_level)

summary(mod_cb)
# Trap prediction: mandatory_bargaining and leobr have negative coefficients
# (stronger CB protections → weaker boards)
```

Save output to `output/cb_law_board_strength.txt`.

### 5b. Use CB law as moderator in main DiD

```r
# Does the DiD null attenuate in weak-CB-law states?
mod_cb_did <- feols(
  clearance_rate ~ coa_active * mandatory_bargaining | city + year,
  data = panel,
  cluster = ~city
)
summary(mod_cb_did)
# Trap prediction: coa_active:mandatory_bargaining < 0
# (COAs are less effective in mandatory-bargaining states because
#  collective bargaining law strengthens police resistance)
```

---

## 6. Electoral Mechanism: Does Strong vs. Weak Board Creation Differ in Political Consequences?

The paper currently shows politicians gain ~2.4pp from creating any board. The trap argument
requires showing the gain is specifically tied to creating *weak* boards. Create
`scripts/electoral_by_strength.R`.

```r
# The electoral analysis dataset likely has city-election observations
# with vote share for incumbents and a post-COA-creation indicator.
# Load it (check what exists in merged_data or cleaned_data).

# Identify the electoral dataset — likely used for the vote share analysis in the paper

# Merge authority level to electoral data
electoral <- electoral %>%
  left_join(panel %>% 
              distinct(city, authority_level, coa_adopted_year),
            by = "city")

# Split electoral gains by board strength
# Compare: (a) review-only board creators vs. (b) disciplinary board creators

mod_weak <- lm(vote_share ~ post_coa + controls,   # adjust to actual specification
               data = electoral %>% filter(authority_level == "review_only"))

mod_strong <- lm(vote_share ~ post_coa + controls,
                 data = electoral %>% filter(authority_level == "disciplinary"))

# Compare coefficients
# Trap prediction: post_coa coefficient is larger (more positive) for weak-board creators
# because strong-board creators face police retaliation that offsets the reform credit

modelsummary(list("Review-Only Boards" = mod_weak,
                  "Disciplinary Boards" = mod_strong),
             output = "output/electoral_by_strength.txt",
             coef_map = c("post_coa" = "Post-COA Creation"),
             stars = TRUE,
             title = "Electoral Benefits of COA Creation by Board Strength")
```

Note: if the disciplinary subsample is too small for regression (expected given ~4% base rate),
report descriptive statistics only and note the limitation explicitly.

---

## 7. Complaint Volume as a Mediator

This tests the Node 2 → Node 3 mechanism: weak boards generate low complaint volumes.

### 7a. Check for complaint data

Look in all data folders for any variable measuring:
- Annual complaint counts (per city, per year, or per 100k residents)
- Sustain rates (share of complaints resulting in officer discipline)
- Truncation rates (share of complaints not completed — as in the CCRB paper)

If complaint data exists, report its coverage (which cities, which years).

### 7b. Complaint volume ~ board strength

If complaint data covers enough cities and years:

```r
# Unit: city-year, post-COA-creation observations only
post_adoption <- panel %>%
  filter(coa_active == 1) %>%   # adjust
  filter(!is.na(complaint_rate))  # adjust to actual variable name

mod_complaints <- feols(
  complaint_rate ~ authority_score |   # continuous authority measure
    city + year,
  data = post_adoption,
  cluster = ~city
)
summary(mod_complaints)
# Trap prediction: positive coefficient — stronger boards attract more complaints
# (consistent with COPA experimental findings applied observationally)

# Sustain rate ~ board strength
mod_sustain <- feols(
  sustain_rate ~ authority_score | city + year,
  data = post_adoption,
  cluster = ~city
)
summary(mod_sustain)
```

Save output to `output/complaints_by_strength.txt`.

---

## 8. Produce Summary Output for Paper Integration

Once all analyses above are complete, create `scripts/summary_tables.R` that consolidates
results into paper-ready tables and figures.

### 8a. Master coefficient table

Use `modelsummary` to produce a single table with:
- Column 1: Main DiD (full sample) — current paper result
- Column 2: DiD, review-only boards only
- Column 3: DiD, investigative authority boards only  
- Column 4: DiD, disciplinary authority boards only
- Column 5: Interaction model (treatment × authority score)

For the clearance rate outcome first, then replicate for police killings.

```r
modelsummary(
  list("Full Sample" = mod_full,
       "Review Only" = mod_review,
       "Investigative" = mod_investigative,
       "Disciplinary" = mod_disciplinary,
       "Interaction" = mod_interaction),
  output = "output/main_table_by_strength.tex",
  coef_map = c("coa_active" = "COA Active",
               "coa_active:authority_score" = "COA × Authority Score"),
  stars = TRUE,
  gof_map = c("nobs", "r.squared", "FE: city", "FE: year"),
  title = "Effects of Civilian Oversight on Police Behavior, by Board Authority Level"
)
```

### 8b. Floyd-era figure for paper

The figure from step 3c (`authority_by_floyd_era.png`) should be publication-ready.
If it is not, clean it up: use a white background, remove gridlines on axes that don't need
them, make font sizes legible at journal print size (title 14pt, axis labels 12pt,
legend 10pt), and use a colorblind-accessible palette.

```r
# Colorblind-safe palette (Okabe-Ito)
colors <- c("review_only" = "#E69F00",
            "investigative" = "#56B4E9",
            "disciplinary" = "#009E73")
```

### 8c. Write a findings memo

At the end of `scripts/summary_tables.R`, print to console (or save to 
`output/findings_memo.txt`) a structured summary in this format:

```
ACCOUNTABILITY TRAP — EMPIRICAL FINDINGS MEMO
==============================================

1. BOARD STRENGTH HETEROGENEITY
   - DiD effect on [outcome], review-only boards: [coef] ([p-value])
   - DiD effect on [outcome], investigative boards: [coef] ([p-value])
   - DiD effect on [outcome], disciplinary boards: [coef] ([p-value])
   - Interpretation: [does the data show stronger boards perform better?]

2. POST-FLOYD EQUILIBRIUM TEST
   - Share of Floyd-era boards with disciplinary authority: [%]
   - Share of pre-Floyd boards with disciplinary authority: [%]
   - Chi-square test p-value: [p]
   - Interpretation: [does the trap prediction hold?]

3. POLICE POLITICAL CAPACITY → BOARD WEAKNESS
   - Effect of mandatory bargaining on authority score: [coef] ([p-value])
   - Interpretation: [does CB law predict weaker boards?]

4. ELECTORAL MECHANISM
   - Post-COA vote share gain, weak boards: [coef] ([p-value])
   - Post-COA vote share gain, strong boards: [coef] ([p-value])
   - Interpretation: [is the electoral benefit concentrated in weak board creation?]

5. COMPLAINT MEDIATION (if data available)
   - Effect of authority score on complaint rate: [coef] ([p-value])
   - Interpretation: [do weaker boards generate fewer complaints?]
```

---

## Notes on R Conventions

- Use `fixest::feols` for all panel models with fixed effects; do not use `plm` or `lfe`.
- Cluster standard errors at the city level throughout (`cluster = ~city`).
- Use `modelsummary` for all output tables; save both `.tex` (for LaTeX) and `.txt` versions.
- Use `ggplot2` for all figures. Set `theme_minimal()` as default.
- Label all figures with `labs(caption = "Note: ...")` explaining the sample and specification.
- Save all figures at `dpi = 300` minimum.
- Comment your code. Each major block should have a one-line comment explaining what it does
  and what the predicted direction of results is under the accountability trap hypothesis.
- If a dataset or variable is missing that an analysis requires, print a clear error message
  explaining what is needed and skip that analysis block rather than crashing.

---

## Deliverables Checklist

When all analyses are complete, confirm the following files exist in `output/`:

- [ ] `authority_by_decade.csv`
- [ ] `charter_features.csv`
- [ ] `did_by_authority_level.csv`
- [ ] `did_by_authority_level.png`
- [ ] `interaction_marginal_effects.png`
- [ ] `authority_by_floyd_era.csv`
- [ ] `authority_by_floyd_era.png`
- [ ] `floyd_era_test.txt`
- [ ] Event study PNGs for each outcome (`event_study_[outcome].png`)
- [ ] `cb_law_board_strength.txt` (or note if data unavailable)
- [ ] `electoral_by_strength.txt`
- [ ] `complaints_by_strength.txt` (or note if data unavailable)
- [ ] `main_table_by_strength.tex` and `.txt`
- [ ] `findings_memo.txt`

Print the checklist with checkmarks or X marks at the end of the session.
