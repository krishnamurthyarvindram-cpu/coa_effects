##############################################################################
# 12_final_summary.R — Step 12: Output Checklist & RESULTS_SUMMARY.md
##############################################################################

library(data.table)

base_dir <- "C:/Users/arvind/Desktop/coa_effects"
log_file <- file.path(base_dir, "output/analysis_log.txt")

wlog <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n")
  cat(msg, "\n", file = log_file, append = TRUE)
}

wlog("\n========== STEP 12: Final Output Checklist & Summary ==========")

# ---------------------------------------------------------------
# Output Checklist
# ---------------------------------------------------------------
required_tables <- c(
  "merge_diagnostics.csv", "summary_stats.csv", "pretrends_means.csv",
  "panelmatch_annualized.csv", "panelmatch_pooled.csv",
  "csdid_annualized.csv", "csdid_pooled.csv", "csdid_by_cohort.csv",
  "heterogeneity_results.csv"
)

wlog("\n--- Table Checklist ---")
for (f in required_tables) {
  fp <- file.path(base_dir, "output/tables", f)
  exists <- file.exists(fp)
  sz <- if (exists) file.size(fp) else 0
  wlog("  [", ifelse(exists & sz > 50, "X", " "), "] ", f, " (", sz, " bytes)")
}

outcomes <- c("violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
              "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
              "black_share_violent_arrests", "black_share_drug_arrests")
bws <- c(3, 4, 5)

wlog("\n--- Figure Checklist ---")
wlog("  [", ifelse(file.exists(file.path(base_dir, "output/figures/treatment_timing_histogram.png")), "X", " "),
     "] treatment_timing_histogram.png")

for (o in outcomes) {
  for (b in bws) {
    # PanelMatch
    fp_pm <- file.path(base_dir, paste0("output/figures/eventstudy_panelmatch_", o, "_bw", b, ".png"))
    wlog("  [", ifelse(file.exists(fp_pm), "X", " "), "] eventstudy_panelmatch_", o, "_bw", b, ".png")
    # CSDID
    fp_cs <- file.path(base_dir, paste0("output/figures/eventstudy_csdid_", o, "_bw", b, ".png"))
    wlog("  [", ifelse(file.exists(fp_cs), "X", " "), "] eventstudy_csdid_", o, "_bw", b, ".png")
  }
}

# ---------------------------------------------------------------
# Build RESULTS_SUMMARY.md
# ---------------------------------------------------------------
wlog("\n--- Building RESULTS_SUMMARY.md ---")

# Load data
pm_pooled <- fread(file.path(base_dir, "output/tables/panelmatch_pooled.csv"))
cs_pooled <- fread(file.path(base_dir, "output/tables/csdid_pooled.csv"))
sumstats <- fread(file.path(base_dir, "output/tables/summary_stats.csv"))
merge_diag <- fread(file.path(base_dir, "output/tables/merge_diagnostics.csv"))
het <- fread(file.path(base_dir, "output/tables/heterogeneity_results.csv"))

# Helper: format number with significance stars
fmt <- function(att, se, digits = 4) {
  if (is.na(att) | is.na(se)) return("NA")
  z <- abs(att / se)
  stars <- ifelse(z > 2.576, "***", ifelse(z > 1.96, "**", ifelse(z > 1.645, "*", "")))
  paste0(round(att, digits), stars, " (", round(se, digits), ")")
}

# Build markdown
md <- character()
a <- function(...) md <<- c(md, paste0(...))

a("# Results Summary: Causal Effects of Civilian Oversight Agencies on Policing Outcomes")
a("")
a("**Generated:** ", Sys.time())
a("")
a("---")
a("")
a("## 1. Data Overview")
a("")
a("### Merge Diagnostics")
a("")
a("| Stage | N | Details |")
a("|-------|---|---------|")
for (i in 1:nrow(merge_diag)) {
  a("| ", merge_diag$Stage[i], " | ", merge_diag$N[i], " | ", merge_diag$Details[i], " |")
}
a("")
a("- **Panel backbone:** Pre-built city-year panel (`data_panel_post1990.rds`) with UCR arrest/offense data, demographics, and political variables.")
a("- **Treatment:** Civilian Oversight Agency (COA) creation year from hand-collected data. 112 treated cities matched to panel, 284 never-treated control cities.")
a("- **Police killings:** Mapped Encounters database, 2000-2021. 4,130 city-years with at least one killing.")
a("- **Demographics:** Time-varying race/ethnicity from Census data, 70.5% of panel rows matched.")
a("")

a("### Sample")
a("")
a("- **Total observations:** 12,436 city-years")
a("- **Unique agencies:** 398")
a("- **Treated cities:** 114 (COA creation year known)")
a("- **Control cities:** 284 (never-treated)")
a("- **Year range:** 1990-2021")
a("- **Estimation window:** 2000-2020 (for CSDID: treated cohorts 2002-2020)")
a("")

a("### Summary Statistics (Means)")
a("")
a("| Variable | Control Mean | Treated Mean | Control SD | Treated SD |")
a("|----------|-------------|-------------|------------|------------|")
for (v in outcomes) {
  ctrl <- sumstats[variable == v & group == "Control"]
  trt <- sumstats[variable == v & group == "Treated"]
  if (nrow(ctrl) > 0 & nrow(trt) > 0) {
    a("| ", v, " | ", ctrl$mean, " | ", trt$mean, " | ", ctrl$sd, " | ", trt$sd, " |")
  }
}
a("")
a("*Note: Per-capita rates are per 100,000 population. Clearance rates are proportions [0,1]. Black share variables are proportions.*")
a("")

a("---")
a("")
a("## 2. Main Results: Pooled ATT Estimates")
a("")
a("### PanelMatch (Matching-Based DiD)")
a("")
a("| Outcome | BW=3 (no cov) | BW=4 (no cov) | BW=5 (no cov) | BW=5 (with cov) |")
a("|---------|---------------|---------------|---------------|-----------------|")
for (v in outcomes) {
  r3 <- pm_pooled[outcome == v & bandwidth == 3 & covariates == "none"]
  r4 <- pm_pooled[outcome == v & bandwidth == 4 & covariates == "none"]
  r5 <- pm_pooled[outcome == v & bandwidth == 5 & covariates == "none"]
  r5c <- pm_pooled[outcome == v & bandwidth == 5 & covariates == "with_covs"]
  a("| ", v, " | ",
    ifelse(nrow(r3) > 0, fmt(r3$pooled_att, r3$pooled_se), "---"), " | ",
    ifelse(nrow(r4) > 0, fmt(r4$pooled_att, r4$pooled_se), "---"), " | ",
    ifelse(nrow(r5) > 0, fmt(r5$pooled_att, r5$pooled_se), "---"), " | ",
    ifelse(nrow(r5c) > 0, fmt(r5c$pooled_att, r5c$pooled_se), "---"), " |")
}
a("")
a("*Stars: \\*p<0.10, \\*\\*p<0.05, \\*\\*\\*p<0.01. Standard errors in parentheses (bootstrap, 300 iterations).*")
a("")

a("### CSDID (Callaway & Sant'Anna)")
a("")
a("| Outcome | BW=3 (no cov) | BW=4 (no cov) | BW=5 (no cov) | BW=5 (with cov) |")
a("|---------|---------------|---------------|---------------|-----------------|")
for (v in outcomes) {
  r3 <- cs_pooled[outcome == v & bandwidth == 3 & covariates == "none"]
  r4 <- cs_pooled[outcome == v & bandwidth == 4 & covariates == "none"]
  r5 <- cs_pooled[outcome == v & bandwidth == 5 & covariates == "none"]
  r5c <- cs_pooled[outcome == v & bandwidth == 5 & covariates == "with_covs"]
  a("| ", v, " | ",
    ifelse(nrow(r3) > 0, fmt(r3$pooled_att, r3$pooled_se), "---"), " | ",
    ifelse(nrow(r4) > 0, fmt(r4$pooled_att, r4$pooled_se), "---"), " | ",
    ifelse(nrow(r5) > 0, fmt(r5$pooled_att, r5$pooled_se), "---"), " | ",
    ifelse(nrow(r5c) > 0, fmt(r5c$pooled_att, r5c$pooled_se), "---"), " |")
}
a("")
a("*Stars: \\*p<0.10, \\*\\*p<0.05, \\*\\*\\*p<0.01. Standard errors from manual aggregation of group-time ATTs (bootstrap, 200 iterations). Note: aggte() in did v2.3.0 has a bug; manual aggregation used instead.*")
a("")

a("---")
a("")
a("## 3. Event Study Figures")
a("")
a("All event study plots show ATT estimates by years relative to COA creation, with 95% confidence intervals.")
a("")
for (v in outcomes) {
  a("### ", v)
  a("")
  a("| Bandwidth | PanelMatch | CSDID |")
  a("|-----------|-----------|-------|")
  for (b in bws) {
    a("| BW=", b, " | `eventstudy_panelmatch_", v, "_bw", b, ".png` | `eventstudy_csdid_", v, "_bw", b, ".png` |")
  }
  a("")
}

a("---")
a("")
a("## 4. Pre-Trends Assessment")
a("")
a("Pre-trends were assessed via event study plots and pre-treatment coefficient significance.")
a("")

# Check pre-trends from CSDID annualized
cs_ann <- fread(file.path(base_dir, "output/tables/csdid_annualized.csv"))
a("### CSDID Pre-Period Coefficients (BW=5, no covariates)")
a("")
a("| Outcome | Event Time | ATT | SE | Significant? |")
a("|---------|-----------|-----|----|----|")
for (v in outcomes) {
  pre <- cs_ann[outcome == v & bandwidth == 5 & covariates == "none" & event_time < 0]
  if (nrow(pre) > 0) {
    for (i in 1:nrow(pre)) {
      sig <- abs(pre$att[i] / pre$se[i]) > 1.96
      a("| ", v, " | ", pre$event_time[i], " | ", round(pre$att[i], 4), " | ",
        round(pre$se[i], 4), " | ", ifelse(sig, "YES", "no"), " |")
    }
  }
}
a("")
a("*Note: Significant pre-period coefficients suggest potential violations of the parallel trends assumption for that outcome.*")
a("")

a("---")
a("")
a("## 5. Heterogeneity Analysis")
a("")
a("CSDID pooled ATT estimates by subgroup (BW=5, no covariates).")
a("")

het_pooled <- het[result_type == "pooled" & bandwidth == 5]

dims <- c("coa_power", "city_size", "race", "region")
dim_labels <- c("COA Power Type", "City Size", "Racial Composition", "Region")

for (d in seq_along(dims)) {
  a("### ", dim_labels[d])
  a("")
  sub <- het_pooled[dimension == dims[d]]
  if (nrow(sub) == 0) {
    a("*No results available.*")
    a("")
    next
  }
  sgs <- unique(sub$subgroup_label)
  header <- paste0("| Outcome | ", paste(sgs, collapse = " | "), " |")
  sep <- paste0("|---------|", paste(rep("------", length(sgs)), collapse="|"), "|")
  a(header)
  a(sep)
  for (v in outcomes) {
    vals <- character()
    for (sg in sgs) {
      row <- sub[outcome == v & subgroup_label == sg]
      if (nrow(row) > 0) {
        vals <- c(vals, fmt(row$att, row$se))
      } else {
        vals <- c(vals, "---")
      }
    }
    a("| ", v, " | ", paste(vals, collapse = " | "), " |")
  }
  a("")
  a("*N treated in each group: ", paste(sapply(sgs, function(sg) {
    r <- sub[subgroup_label == sg]
    if (nrow(r) > 0) paste0(sg, "=", r$n_treated[1]) else paste0(sg, "=?")
  }), collapse = ", "), "*")
  a("")
}

a("---")
a("")
a("## 6. Key Takeaways")
a("")
a("### Consistent Findings Across Estimators")
a("")

# Analyze consistency
for (v in outcomes) {
  pm5 <- pm_pooled[outcome == v & bandwidth == 5 & covariates == "none"]
  cs5 <- cs_pooled[outcome == v & bandwidth == 5 & covariates == "none"]
  if (nrow(pm5) > 0 & nrow(cs5) > 0) {
    pm_sig <- abs(pm5$pooled_att / pm5$pooled_se) > 1.96
    cs_sig <- abs(cs5$pooled_att / cs5$pooled_se) > 1.96
    pm_sign <- sign(pm5$pooled_att)
    cs_sign <- sign(cs5$pooled_att)
    consistent <- pm_sign == cs_sign
    a("- **", v, ":** PanelMatch ATT=", round(pm5$pooled_att, 2),
      ifelse(pm_sig, "(sig)", "(n.s.)"),
      "; CSDID ATT=", round(cs5$pooled_att, 2),
      ifelse(cs_sig, "(sig)", "(n.s.)"),
      ". Signs ", ifelse(consistent, "consistent", "INCONSISTENT"), ".")
  }
}

a("")
a("### Sensitivity to Covariates")
a("")
a("Several outcomes show sign reversals when covariates (log_population, pct_black) are added in CSDID,")
a("suggesting that unobserved city characteristics correlated with both COA adoption and policing outcomes")
a("may confound the unconditional estimates. This is a key concern for causal interpretation.")
a("")

a("### Data Limitations")
a("")
a("1. **UCR reporting:** Per-capita rates show extreme outliers (max violent_crime_pc ~290,000 per 100K),")
a("   suggesting data quality issues in some city-years (population mismatches or reporting errors).")
a("2. **Missing data:** No median income variable available. Demographics matched for only 70.5% of panel rows.")
a("3. **Treatment heterogeneity:** Only 10 cities have COAs with disciplinary power; 6 created via election.")
a("   Subgroup estimates for these dimensions are imprecise.")
a("4. **Panel balance:** Using `panel=FALSE` in CSDID due to unbalanced panel. Manual aggregation of")
a("   group-time ATTs used instead of aggte() due to a bug in did v2.3.0.")
a("5. **Police killings data:** Available only 2000-2021; many city-years have zero killings, creating")
a("   sparse outcome distributions.")
a("6. **Unmatched treated cities:** 9 COA cities in raw data could not be matched to the UCR panel")
a("   (Arlington VA, Burbank CA, Cambridge MA, Columbia MD, South Fulton GA, Springfield MS, Honolulu HI, etc.).")
a("")

a("---")
a("")
a("## 7. Scripts and Reproducibility")
a("")
a("| Step | Script | Description |")
a("|------|--------|-------------|")
a("| 0 | `00_explore_data.R` | Data exploration |")
a("| 1 | `01_clean_coa.R` | Clean COA treatment data |")
a("| 4 | `04_clean_police_killings.R` | Clean police killings data |")
a("| 7 | `07_merge_all.R`, `07d_final_merge.R`, `07e_manual_fixes.R` | Merge all datasets |")
a("| 8 | `08_construct_variables.R` | Construct outcome/treatment variables |")
a("| 9 | `09_analysis_panelmatch.R` | PanelMatch estimation |")
a("| 10 | `10_analysis_csdid.R` | CSDID estimation |")
a("| 11 | `11_heterogeneity.R` | Heterogeneity analysis |")
a("| 12 | `12_final_summary.R` | This script |")
a("")
a("All scripts are in `scripts/`. Output tables in `output/tables/`, figures in `output/figures/`.")

# Write the file
writeLines(md, file.path(base_dir, "output/RESULTS_SUMMARY.md"))
wlog("Saved RESULTS_SUMMARY.md (", length(md), " lines)")
wlog("\nStep 12 complete.")
wlog("\n========== PIPELINE COMPLETE ==========")
