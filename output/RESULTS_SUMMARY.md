# Results Summary: Causal Effects of Civilian Oversight Agencies on Policing Outcomes

**Generated:** 2026-02-27 12:57:44.001236

---

## 1. Data Overview

### Merge Diagnostics

| Stage | N | Details |
|-------|---|---------|
| Panel base | 398 | 398 cities, 1990-2021 |
| COA Treatment | 112 | 112 treated, 9 unmatched |
| Police Killings | 4130 | 12187 total killings |
| Demographics | 8773 | 70.5% matched |

- **Panel backbone:** Pre-built city-year panel (`data_panel_post1990.rds`) with UCR arrest/offense data, demographics, and political variables.
- **Treatment:** Civilian Oversight Agency (COA) creation year from hand-collected data. 112 treated cities matched to panel, 284 never-treated control cities.
- **Police killings:** Mapped Encounters database, 2000-2021. 4,130 city-years with at least one killing.
- **Demographics:** Time-varying race/ethnicity from Census data, 70.5% of panel rows matched.

### Sample

- **Total observations:** 12,436 city-years
- **Unique agencies:** 398
- **Treated cities:** 114 (COA creation year known)
- **Control cities:** 284 (never-treated)
- **Year range:** 1990-2021
- **Estimation window:** 2000-2020 (for CSDID: treated cohorts 2002-2020)

### Summary Statistics (Means)

| Variable | Control Mean | Treated Mean | Control SD | Treated SD |
|----------|-------------|-------------|------------|------------|
| violent_crime_pc | 10289.0623 | 6890.4523 | 28716.0838 | 29106.7078 |
| violent_clearance_rate | 0.4709 | 0.4112 | 0.1781 | 0.163 |
| property_clearance_rate | 0.175 | 0.1484 | 0.0856 | 0.0736 |
| drug_arrests_pc | 10536.2864 | 5397.8675 | 25417.8754 | 19143.3171 |
| discretionary_arrests_pc | 43783.3988 | 19248.8308 | 102302.0388 | 64106.7332 |
| police_killings_pc | 3.1651 | 0.9158 | 22.0999 | 7.8786 |
| black_share_violent_arrests | 0.2926 | 0.4284 | 0.2231 | 0.2547 |
| black_share_drug_arrests | 0.2685 | 0.429 | 0.2369 | 0.2724 |

*Note: Per-capita rates are per 100,000 population. Clearance rates are proportions [0,1]. Black share variables are proportions.*

---

## 2. Main Results: Pooled ATT Estimates

### PanelMatch (Matching-Based DiD)

| Outcome | BW=3 (no cov) | BW=4 (no cov) | BW=5 (no cov) | BW=5 (with cov) |
|---------|---------------|---------------|---------------|-----------------|
| violent_crime_pc | 914.4033*** (312.6999) | 1132.6596*** (404.4785) | 1292.7292*** (432.1541) | 789.913 (860.6233) |
| violent_clearance_rate | -0.0132 (0.0131) | -0.0175 (0.0154) | -0.018 (0.0174) | -0.0083 (0.0187) |
| property_clearance_rate | -0.0064 (0.0074) | -0.0105 (0.0083) | -0.0146 (0.0098) | -0.0151 (0.0113) |
| drug_arrests_pc | 986.7727** (501.7462) | 1201.1493* (679.6721) | 1402.6817* (786.9004) | -135.511 (105.9788) |
| discretionary_arrests_pc | 3885.2255* (2000.3724) | 4789.5489** (2329.1674) | 5569.2128* (3093.4389) | -482.4004 (310.967) |
| police_killings_pc | 0.7519* (0.4218) | 0.8299 (0.5177) | 0.9806* (0.5235) | -0.1459 (0.1929) |
| black_share_violent_arrests | 9e-04 (0.0052) | 0 (0.0056) | -3e-04 (0.0069) | 5e-04 (0.0071) |
| black_share_drug_arrests | -0.0114 (0.0123) | -0.0081 (0.0125) | -0.0083 (0.0145) | -4e-04 (0.0153) |

*Stars: \*p<0.10, \*\*p<0.05, \*\*\*p<0.01. Standard errors in parentheses (bootstrap, 300 iterations).*

### CSDID (Callaway & Sant'Anna)

| Outcome | BW=3 (no cov) | BW=4 (no cov) | BW=5 (no cov) | BW=5 (with cov) |
|---------|---------------|---------------|---------------|-----------------|
| violent_crime_pc | 978.1972*** (147.6059) | 1163.1535*** (133.6866) | 1359.1501*** (123.3641) | -518.7006** (226.4869) |
| violent_clearance_rate | 0.0019 (0.0098) | 9e-04 (0.009) | 0.0018 (0.0085) | -0.0038 (0.0089) |
| property_clearance_rate | -0.0062 (0.0049) | -0.0082* (0.0045) | -0.0104** (0.0042) | -0.0107** (0.0043) |
| drug_arrests_pc | 1084.2244*** (233.506) | 1350.682*** (212.4339) | 1607.5926*** (195.9475) | -181.8454 (414.6702) |
| discretionary_arrests_pc | 4574.5791*** (748.5463) | 5658.4131*** (676.845) | 6678.1196*** (621.6474) | -5064.8378*** (794.355) |
| police_killings_pc | 0.5944** (0.2816) | 0.7324*** (0.2564) | 0.8683*** (0.2391) | 0.5016 (0.7436) |
| black_share_violent_arrests | 0.0197 (0.0224) | 0.0139 (0.0207) | 0.0185 (0.0202) | 0.0205 (0.0199) |
| black_share_drug_arrests | 0.0213 (0.0234) | 0.0175 (0.0215) | 0.0224 (0.0202) | 0.0253 (0.0208) |

*Stars: \*p<0.10, \*\*p<0.05, \*\*\*p<0.01. Standard errors from manual aggregation of group-time ATTs (bootstrap, 200 iterations). Note: aggte() in did v2.3.0 has a bug; manual aggregation used instead.*

---

## 3. Event Study Figures

All event study plots show ATT estimates by years relative to COA creation, with 95% confidence intervals.

### violent_crime_pc

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_violent_crime_pc_bw3.png` | `eventstudy_csdid_violent_crime_pc_bw3.png` |
| BW=4 | `eventstudy_panelmatch_violent_crime_pc_bw4.png` | `eventstudy_csdid_violent_crime_pc_bw4.png` |
| BW=5 | `eventstudy_panelmatch_violent_crime_pc_bw5.png` | `eventstudy_csdid_violent_crime_pc_bw5.png` |

### violent_clearance_rate

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_violent_clearance_rate_bw3.png` | `eventstudy_csdid_violent_clearance_rate_bw3.png` |
| BW=4 | `eventstudy_panelmatch_violent_clearance_rate_bw4.png` | `eventstudy_csdid_violent_clearance_rate_bw4.png` |
| BW=5 | `eventstudy_panelmatch_violent_clearance_rate_bw5.png` | `eventstudy_csdid_violent_clearance_rate_bw5.png` |

### property_clearance_rate

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_property_clearance_rate_bw3.png` | `eventstudy_csdid_property_clearance_rate_bw3.png` |
| BW=4 | `eventstudy_panelmatch_property_clearance_rate_bw4.png` | `eventstudy_csdid_property_clearance_rate_bw4.png` |
| BW=5 | `eventstudy_panelmatch_property_clearance_rate_bw5.png` | `eventstudy_csdid_property_clearance_rate_bw5.png` |

### drug_arrests_pc

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_drug_arrests_pc_bw3.png` | `eventstudy_csdid_drug_arrests_pc_bw3.png` |
| BW=4 | `eventstudy_panelmatch_drug_arrests_pc_bw4.png` | `eventstudy_csdid_drug_arrests_pc_bw4.png` |
| BW=5 | `eventstudy_panelmatch_drug_arrests_pc_bw5.png` | `eventstudy_csdid_drug_arrests_pc_bw5.png` |

### discretionary_arrests_pc

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_discretionary_arrests_pc_bw3.png` | `eventstudy_csdid_discretionary_arrests_pc_bw3.png` |
| BW=4 | `eventstudy_panelmatch_discretionary_arrests_pc_bw4.png` | `eventstudy_csdid_discretionary_arrests_pc_bw4.png` |
| BW=5 | `eventstudy_panelmatch_discretionary_arrests_pc_bw5.png` | `eventstudy_csdid_discretionary_arrests_pc_bw5.png` |

### police_killings_pc

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_police_killings_pc_bw3.png` | `eventstudy_csdid_police_killings_pc_bw3.png` |
| BW=4 | `eventstudy_panelmatch_police_killings_pc_bw4.png` | `eventstudy_csdid_police_killings_pc_bw4.png` |
| BW=5 | `eventstudy_panelmatch_police_killings_pc_bw5.png` | `eventstudy_csdid_police_killings_pc_bw5.png` |

### black_share_violent_arrests

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_black_share_violent_arrests_bw3.png` | `eventstudy_csdid_black_share_violent_arrests_bw3.png` |
| BW=4 | `eventstudy_panelmatch_black_share_violent_arrests_bw4.png` | `eventstudy_csdid_black_share_violent_arrests_bw4.png` |
| BW=5 | `eventstudy_panelmatch_black_share_violent_arrests_bw5.png` | `eventstudy_csdid_black_share_violent_arrests_bw5.png` |

### black_share_drug_arrests

| Bandwidth | PanelMatch | CSDID |
|-----------|-----------|-------|
| BW=3 | `eventstudy_panelmatch_black_share_drug_arrests_bw3.png` | `eventstudy_csdid_black_share_drug_arrests_bw3.png` |
| BW=4 | `eventstudy_panelmatch_black_share_drug_arrests_bw4.png` | `eventstudy_csdid_black_share_drug_arrests_bw4.png` |
| BW=5 | `eventstudy_panelmatch_black_share_drug_arrests_bw5.png` | `eventstudy_csdid_black_share_drug_arrests_bw5.png` |

---

## 4. Pre-Trends Assessment

Pre-trends were assessed via event study plots and pre-treatment coefficient significance.

### CSDID Pre-Period Coefficients (BW=5, no covariates)

| Outcome | Event Time | ATT | SE | Significant? |
|---------|-----------|-----|----|----|
| violent_crime_pc | -5 | 339.0299 | 1063.627 | no |
| violent_crime_pc | -4 | -517.8407 | 940.4233 | no |
| violent_crime_pc | -3 | 444.1556 | 318.9691 | no |
| violent_crime_pc | -2 | 387.0386 | 309.722 | no |
| violent_crime_pc | -1 | 361.8068 | 292.8794 | no |
| violent_clearance_rate | -5 | 0.007 | 0.0178 | no |
| violent_clearance_rate | -4 | 2e-04 | 0.0203 | no |
| violent_clearance_rate | -3 | -0.0101 | 0.0195 | no |
| violent_clearance_rate | -2 | 9e-04 | 0.027 | no |
| violent_clearance_rate | -1 | 0.0109 | 0.0221 | no |
| property_clearance_rate | -5 | 0.0018 | 0.0102 | no |
| property_clearance_rate | -4 | -0.006 | 0.0098 | no |
| property_clearance_rate | -3 | -0.0056 | 0.009 | no |
| property_clearance_rate | -2 | -0.0025 | 0.0094 | no |
| property_clearance_rate | -1 | -5e-04 | 0.0083 | no |
| drug_arrests_pc | -5 | 353.8454 | 1308.4721 | no |
| drug_arrests_pc | -4 | -468.8803 | 1100.2256 | no |
| drug_arrests_pc | -3 | 562.8196 | 461.559 | no |
| drug_arrests_pc | -2 | 434.2896 | 442.9709 | no |
| drug_arrests_pc | -1 | 379.8665 | 455.7561 | no |
| discretionary_arrests_pc | -5 | 1557.0037 | 6187.6819 | no |
| discretionary_arrests_pc | -4 | -2718.488 | 5305.0067 | no |
| discretionary_arrests_pc | -3 | 2483.5655 | 1499.8949 | no |
| discretionary_arrests_pc | -2 | 2208.8608 | 1504.6383 | no |
| discretionary_arrests_pc | -1 | 1817.1502 | 1469.166 | no |
| police_killings_pc | -5 | -0.2588 | 0.9018 | no |
| police_killings_pc | -4 | 0.4158 | 0.62 | no |
| police_killings_pc | -3 | 0.2747 | 0.607 | no |
| police_killings_pc | -2 | 0.3788 | 0.5945 | no |
| police_killings_pc | -1 | 0.3582 | 0.5436 | no |
| black_share_violent_arrests | -5 | 0.0057 | 0.0473 | no |
| black_share_violent_arrests | -4 | 0.0068 | 0.0461 | no |
| black_share_violent_arrests | -3 | -0.002 | 0.0426 | no |
| black_share_violent_arrests | -2 | 5e-04 | 0.0511 | no |
| black_share_violent_arrests | -1 | -0.0344 | 0.0451 | no |
| black_share_drug_arrests | -5 | 0.0015 | 0.0487 | no |
| black_share_drug_arrests | -4 | 0.0159 | 0.0442 | no |
| black_share_drug_arrests | -3 | 0.0065 | 0.0417 | no |
| black_share_drug_arrests | -2 | -0.0128 | 0.0534 | no |
| black_share_drug_arrests | -1 | -0.0453 | 0.0456 | no |

*Note: Significant pre-period coefficients suggest potential violations of the parallel trends assumption for that outcome.*

---

## 5. Heterogeneity Analysis

CSDID pooled ATT estimates by subgroup (BW=5, no covariates).

### COA Power Type

| Outcome | Investigative Power: Yes | Investigative Power: No | Disciplinary Power: Yes | Disciplinary Power: No |
|---------|------|------|------|------|
| violent_crime_pc | 1128.789*** (139.7248) | --- | 1633.5888*** (280.823) | --- |
| violent_clearance_rate | -0.0121*** (0.004) | --- | 0.004 (0.0032) | --- |
| property_clearance_rate | -0.007*** (0.0012) | --- | 0.0026* (0.0015) | --- |
| drug_arrests_pc | --- | --- | 2910.9293*** (539.0584) | 1394.1557*** (199.2984) |
| discretionary_arrests_pc | --- | --- | 10861.9552*** (1528.5593) | 6005.5485*** (610.0388) |
| police_killings_pc | 1.5025*** (0.2807) | 0.9024*** (0.2481) | 1.0223** (0.509) | 0.8201*** (0.2318) |
| black_share_violent_arrests | --- | --- | 0.0099* (0.0053) | 0.0215 (0.0215) |
| black_share_drug_arrests | --- | --- | 0.0407*** (0.0058) | 0.0202 (0.0219) |

*N treated in each group: Investigative Power: Yes=14, Investigative Power: No=39, Disciplinary Power: Yes=5, Disciplinary Power: No=48*

### City Size

| Outcome | Large City (above median pop) | Small City (below median pop) |
|---------|------|------|
| violent_crime_pc | 1379.4982*** (131.6262) | 1289.7426*** (253.0551) |
| violent_clearance_rate | 0.0057 (0.0094) | -0.0137* (0.0073) |
| property_clearance_rate | -0.0045 (0.0046) | -0.0478*** (0.0034) |
| drug_arrests_pc | 1671.4208*** (212.5502) | 1473.2749*** (383.4309) |
| discretionary_arrests_pc | 6884.717*** (660.8454) | 6087.9304*** (1107.1182) |
| police_killings_pc | 0.8093*** (0.2344) | 0.9947* (0.5095) |
| black_share_violent_arrests | 0.0238 (0.0265) | 0.0013 (0.0045) |
| black_share_drug_arrests | 0.0286 (0.0243) | -0.0084* (0.0051) |

*N treated in each group: Large City (above median pop)=48, Small City (below median pop)=5*

### Racial Composition

| Outcome | High % Black (above median) | Low % Black (below median) |
|---------|------|------|
| violent_crime_pc | --- | 1283.9965*** (161.1735) |
| violent_clearance_rate | --- | 0.021** (0.0092) |
| property_clearance_rate | --- | -0.0086** (0.0041) |
| drug_arrests_pc | --- | 1481.9655*** (240.5074) |
| discretionary_arrests_pc | --- | 6357.8384*** (736.2056) |
| police_killings_pc | 0.7179*** (0.2304) | 0.9*** (0.2862) |
| black_share_violent_arrests | --- | -0.0112 (0.0103) |
| black_share_drug_arrests | --- | 0.002 (0.0149) |

*N treated in each group: High % Black (above median)=34, Low % Black (below median)=19*

### Region

| Outcome | South | Non-South |
|---------|------|------|
| violent_crime_pc | 1510.2661*** (199.9232) | 1401.6832*** (131.8443) |
| violent_clearance_rate | 0.0088 (0.008) | 0.0084 (0.0097) |
| property_clearance_rate | 0.0015 (0.0046) | -0.0139*** (0.0047) |
| drug_arrests_pc | --- | --- |
| discretionary_arrests_pc | --- | --- |
| police_killings_pc | -4e-04 (0.3424) | 1.0198*** (0.2372) |
| black_share_violent_arrests | --- | --- |
| black_share_drug_arrests | --- | --- |

*N treated in each group: South=15, Non-South=38*

---

## 6. Key Takeaways

### Consistent Findings Across Estimators

- **violent_crime_pc:** PanelMatch ATT=1292.73(sig); CSDID ATT=1359.15(sig). Signs consistent.
- **violent_clearance_rate:** PanelMatch ATT=-0.02(n.s.); CSDID ATT=0(n.s.). Signs INCONSISTENT.
- **property_clearance_rate:** PanelMatch ATT=-0.01(n.s.); CSDID ATT=-0.01(sig). Signs consistent.
- **drug_arrests_pc:** PanelMatch ATT=1402.68(n.s.); CSDID ATT=1607.59(sig). Signs consistent.
- **discretionary_arrests_pc:** PanelMatch ATT=5569.21(n.s.); CSDID ATT=6678.12(sig). Signs consistent.
- **police_killings_pc:** PanelMatch ATT=0.98(n.s.); CSDID ATT=0.87(sig). Signs consistent.
- **black_share_violent_arrests:** PanelMatch ATT=0(n.s.); CSDID ATT=0.02(n.s.). Signs INCONSISTENT.
- **black_share_drug_arrests:** PanelMatch ATT=-0.01(n.s.); CSDID ATT=0.02(n.s.). Signs INCONSISTENT.

### Sensitivity to Covariates

Several outcomes show sign reversals when covariates (log_population, pct_black) are added in CSDID,
suggesting that unobserved city characteristics correlated with both COA adoption and policing outcomes
may confound the unconditional estimates. This is a key concern for causal interpretation.

### Data Limitations

1. **UCR reporting:** Per-capita rates show extreme outliers (max violent_crime_pc ~290,000 per 100K),
   suggesting data quality issues in some city-years (population mismatches or reporting errors).
2. **Missing data:** No median income variable available. Demographics matched for only 70.5% of panel rows.
3. **Treatment heterogeneity:** Only 10 cities have COAs with disciplinary power; 6 created via election.
   Subgroup estimates for these dimensions are imprecise.
4. **Panel balance:** Using `panel=FALSE` in CSDID due to unbalanced panel. Manual aggregation of
   group-time ATTs used instead of aggte() due to a bug in did v2.3.0.
5. **Police killings data:** Available only 2000-2021; many city-years have zero killings, creating
   sparse outcome distributions.
6. **Unmatched treated cities:** 9 COA cities in raw data could not be matched to the UCR panel
   (Arlington VA, Burbank CA, Cambridge MA, Columbia MD, South Fulton GA, Springfield MS, Honolulu HI, etc.).

---

## 7. Scripts and Reproducibility

| Step | Script | Description |
|------|--------|-------------|
| 0 | `00_explore_data.R` | Data exploration |
| 1 | `01_clean_coa.R` | Clean COA treatment data |
| 4 | `04_clean_police_killings.R` | Clean police killings data |
| 7 | `07_merge_all.R`, `07d_final_merge.R`, `07e_manual_fixes.R` | Merge all datasets |
| 8 | `08_construct_variables.R` | Construct outcome/treatment variables |
| 9 | `09_analysis_panelmatch.R` | PanelMatch estimation |
| 10 | `10_analysis_csdid.R` | CSDID estimation |
| 11 | `11_heterogeneity.R` | Heterogeneity analysis |
| 12 | `12_final_summary.R` | This script |

All scripts are in `scripts/`. Output tables in `output/tables/`, figures in `output/figures/`.
