#!/usr/bin/env python3
"""
16_psm_did_analysis.py — Propensity Score Matching + DiD Estimation

Re-estimates all main models after matching treated and control cities
on pre-treatment characteristics:
  - City population (log)
  - Demographics (% Black, % White)
  - Pre-treatment violent crime rate
  - Pre-treatment property crime rate
  - Pre-treatment drug arrest rate

Uses nearest-neighbor propensity score matching (logit) with caliper,
then runs TWFE DiD on the matched sample.

Requires: pandas, numpy, statsmodels, scikit-learn, matplotlib
Data:     merged_data/analysis_panel.rds (via pyreadr)
"""

import os
import sys
import warnings
import numpy as np
import pandas as pd
import statsmodels.formula.api as smf
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from scipy.spatial.distance import cdist
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

warnings.filterwarnings("ignore")

# ── Paths ─────────────────────────────────────────────────────────────────────
base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
merged_dir = os.path.join(base_dir, "merged_data")
output_dir = os.path.join(base_dir, "output")
tables_dir = os.path.join(output_dir, "tables")
figures_dir = os.path.join(output_dir, "figures")
log_path = os.path.join(output_dir, "psm_analysis_log.txt")

os.makedirs(tables_dir, exist_ok=True)
os.makedirs(figures_dir, exist_ok=True)

log_fh = open(log_path, "w")

def wlog(msg):
    print(msg)
    log_fh.write(msg + "\n")
    log_fh.flush()

wlog("=" * 70)
wlog("STEP 16: Propensity Score Matching + DiD Analysis")
wlog("=" * 70)

# ── 1. Load Data ──────────────────────────────────────────────────────────────
try:
    import pyreadr
    panel_path = os.path.join(merged_dir, "analysis_panel.rds")
    wlog(f"\nLoading panel from {panel_path}")
    result = pyreadr.read_r(panel_path)
    panel = list(result.values())[0]
    wlog(f"Panel loaded: {panel.shape[0]:,} rows x {panel.shape[1]} cols")
except Exception as e:
    wlog(f"ERROR loading RDS: {e}")
    wlog("Trying CSV fallback...")
    # If RDS fails, try to see if a CSV version exists
    csv_path = os.path.join(merged_dir, "analysis_panel.csv")
    if os.path.exists(csv_path):
        panel = pd.read_csv(csv_path)
        wlog(f"Panel loaded from CSV: {panel.shape[0]:,} rows x {panel.shape[1]} cols")
    else:
        wlog("FATAL: No data file available. Ensure analysis_panel.rds is not a git-lfs pointer.")
        wlog("Run this script on a machine with the actual data files.")
        sys.exit(1)

# ── 2. Basic Setup ────────────────────────────────────────────────────────────
# Ensure key columns exist
required_cols = ["agency_id", "year", "treatment_year", "treated", "post"]
for c in required_cols:
    if c not in panel.columns:
        wlog(f"FATAL: Missing required column '{c}'")
        sys.exit(1)

panel["unit_id"] = panel["agency_id"].astype("category").cat.codes

wlog(f"\nUnique agencies: {panel['agency_id'].nunique()}")
wlog(f"Treated: {panel[panel['treated'] == 1]['agency_id'].nunique()}")
wlog(f"Control: {panel[panel['treated'] == 0]['agency_id'].nunique()}")
wlog(f"Year range: {panel['year'].min()} - {panel['year'].max()}")

# ── 3. Construct Pre-Treatment Covariates ─────────────────────────────────────
wlog("\n--- Constructing Pre-Treatment City-Level Covariates ---")

outcomes = [
    "violent_crime_pc", "violent_clearance_rate", "property_clearance_rate",
    "drug_arrests_pc", "discretionary_arrests_pc", "police_killings_pc",
    "black_share_violent_arrests", "black_share_drug_arrests"
]

# For treated cities: average over pre-treatment years (year < treatment_year)
# For control cities: average over 2000-2015 to avoid late-period contamination
treated_panel = panel[panel["treated"] == 1].copy()
control_panel = panel[panel["treated"] == 0].copy()

# Pre-treatment data for treated
treated_pre = treated_panel[treated_panel["year"] < treated_panel["treatment_year"]]
# Restrict to 2000+ for comparability
treated_pre = treated_pre[treated_pre["year"] >= 2000]

# If some treated cities have no pre-2000 data, use their earliest years
cities_missing = set(treated_panel["agency_id"]) - set(treated_pre["agency_id"])
if cities_missing:
    wlog(f"  {len(cities_missing)} treated cities with no pre-treatment data after 2000; using earliest years")
    for aid in cities_missing:
        city_data = treated_panel[treated_panel["agency_id"] == aid].sort_values("year").head(5)
        treated_pre = pd.concat([treated_pre, city_data])

# Control: 2000-2015
control_pre = control_panel[(control_panel["year"] >= 2000) & (control_panel["year"] <= 2015)]

# PSM covariates: pre-treatment averages
psm_vars_raw = ["log_population", "pct_black", "violent_crime_pc",
                 "property_clearance_rate", "drug_arrests_pc"]

# Check which variables actually exist
psm_vars = [v for v in psm_vars_raw if v in panel.columns]
wlog(f"  PSM covariates available: {psm_vars}")

# Also check for additional demographics
for extra in ["pct_white", "pct_hispanic"]:
    if extra in panel.columns and panel[extra].notna().sum() > 1000:
        psm_vars.append(extra)
        wlog(f"  Added extra covariate: {extra}")

def compute_city_averages(df, vars_list):
    """Compute pre-treatment city-level averages."""
    agg = df.groupby("agency_id")[vars_list].mean().reset_index()
    return agg

treated_covs = compute_city_averages(treated_pre, psm_vars)
treated_covs["treated"] = 1

control_covs = compute_city_averages(control_pre, psm_vars)
control_covs["treated"] = 0

city_cross = pd.concat([treated_covs, control_covs], ignore_index=True)
wlog(f"\nCity-level cross-section: {len(city_cross)} cities")
wlog(f"  Treated: {city_cross['treated'].sum()}")
wlog(f"  Control: {(city_cross['treated'] == 0).sum()}")

# Drop cities with missing PSM covariates
n_before = len(city_cross)
city_cross = city_cross.dropna(subset=psm_vars)
n_after = len(city_cross)
wlog(f"  After dropping missing covariates: {n_after} cities ({n_before - n_after} dropped)")
wlog(f"    Treated: {city_cross['treated'].sum()}")
wlog(f"    Control: {(city_cross['treated'] == 0).sum()}")

# ── 4. Estimate Propensity Scores ────────────────────────────────────────────
wlog("\n--- Estimating Propensity Scores ---")

X = city_cross[psm_vars].values
y = city_cross["treated"].values

# Standardize for logistic regression
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)

# Logistic regression
logit = LogisticRegression(max_iter=5000, C=1.0, solver="lbfgs")
logit.fit(X_scaled, y)

city_cross = city_cross.copy()
city_cross["pscore"] = logit.predict_proba(X_scaled)[:, 1]

wlog(f"\nPropensity score distribution:")
wlog(f"  Treated:  mean={city_cross.loc[city_cross['treated']==1, 'pscore'].mean():.4f}  "
     f"sd={city_cross.loc[city_cross['treated']==1, 'pscore'].std():.4f}  "
     f"range=[{city_cross.loc[city_cross['treated']==1, 'pscore'].min():.4f}, "
     f"{city_cross.loc[city_cross['treated']==1, 'pscore'].max():.4f}]")
wlog(f"  Control:  mean={city_cross.loc[city_cross['treated']==0, 'pscore'].mean():.4f}  "
     f"sd={city_cross.loc[city_cross['treated']==0, 'pscore'].std():.4f}  "
     f"range=[{city_cross.loc[city_cross['treated']==0, 'pscore'].min():.4f}, "
     f"{city_cross.loc[city_cross['treated']==0, 'pscore'].max():.4f}]")

# Logit coefficients
wlog("\nLogit coefficients (propensity score model):")
for var, coef in zip(psm_vars, logit.coef_[0]):
    wlog(f"  {var:35s}: {coef:+.4f}")

# ── 5. Nearest-Neighbor Matching ─────────────────────────────────────────────
wlog("\n--- Nearest-Neighbor Matching (with replacement, caliper=0.25 SD) ---")

treated_cities = city_cross[city_cross["treated"] == 1].copy()
control_cities = city_cross[city_cross["treated"] == 0].copy()

caliper = 0.25 * city_cross["pscore"].std()
wlog(f"  Caliper: {caliper:.4f}")

# For each treated city, find nearest control by propensity score
matches = []
unmatched_treated = []

for idx, trow in treated_cities.iterrows():
    t_pscore = trow["pscore"]
    # Find controls within caliper
    eligible = control_cities[abs(control_cities["pscore"] - t_pscore) <= caliper]
    if len(eligible) == 0:
        unmatched_treated.append(trow["agency_id"])
        continue
    # Nearest neighbor
    best_idx = (eligible["pscore"] - t_pscore).abs().idxmin()
    matches.append({
        "treated_agency": trow["agency_id"],
        "control_agency": control_cities.loc[best_idx, "agency_id"],
        "treated_pscore": t_pscore,
        "control_pscore": control_cities.loc[best_idx, "pscore"],
        "pscore_diff": abs(t_pscore - control_cities.loc[best_idx, "pscore"])
    })

matches_df = pd.DataFrame(matches)
wlog(f"\nMatching results:")
wlog(f"  Matched treated cities: {len(matches_df)}")
wlog(f"  Unmatched treated cities (outside caliper): {len(unmatched_treated)}")
wlog(f"  Unique control cities used: {matches_df['control_agency'].nunique()}")
wlog(f"  Mean pscore difference: {matches_df['pscore_diff'].mean():.4f}")
wlog(f"  Max pscore difference:  {matches_df['pscore_diff'].max():.4f}")

if unmatched_treated:
    wlog(f"\n  Unmatched treated cities: {unmatched_treated}")

# ── 6. Covariate Balance Check ───────────────────────────────────────────────
wlog("\n--- Covariate Balance: Before and After Matching ---")

matched_treated_ids = set(matches_df["treated_agency"])
matched_control_ids = set(matches_df["control_agency"])

balance_rows = []
for var in psm_vars:
    # Before matching: all cities
    t_before = city_cross.loc[city_cross["treated"] == 1, var]
    c_before = city_cross.loc[city_cross["treated"] == 0, var]
    pooled_sd = np.sqrt((t_before.var() + c_before.var()) / 2)
    smd_before = (t_before.mean() - c_before.mean()) / pooled_sd if pooled_sd > 0 else np.nan

    # After matching
    t_after = city_cross.loc[city_cross["agency_id"].isin(matched_treated_ids), var]
    c_after = city_cross.loc[city_cross["agency_id"].isin(matched_control_ids), var]
    pooled_sd_after = np.sqrt((t_after.var() + c_after.var()) / 2)
    smd_after = (t_after.mean() - c_after.mean()) / pooled_sd_after if pooled_sd_after > 0 else np.nan

    balance_rows.append({
        "variable": var,
        "treated_mean_before": t_before.mean(),
        "control_mean_before": c_before.mean(),
        "smd_before": smd_before,
        "treated_mean_after": t_after.mean(),
        "control_mean_after": c_after.mean(),
        "smd_after": smd_after,
        "pct_reduction": (1 - abs(smd_after) / abs(smd_before)) * 100 if smd_before != 0 else np.nan
    })

balance_df = pd.DataFrame(balance_rows)
balance_df.to_csv(os.path.join(tables_dir, "psm_balance_table.csv"), index=False)

wlog(f"\n{'Variable':35s} | {'SMD Before':>10s} | {'SMD After':>10s} | {'% Reduction':>12s}")
wlog("-" * 75)
for _, row in balance_df.iterrows():
    wlog(f"{row['variable']:35s} | {row['smd_before']:>10.4f} | {row['smd_after']:>10.4f} | "
         f"{row['pct_reduction']:>10.1f}%")

# ── 7. Build Matched Panel ───────────────────────────────────────────────────
wlog("\n--- Building Matched Panel ---")

matched_agencies = matched_treated_ids | matched_control_ids
matched_panel = panel[panel["agency_id"].isin(matched_agencies)].copy()
matched_panel = matched_panel[(matched_panel["year"] >= 2000) & (matched_panel["year"] <= 2020)]

wlog(f"Matched panel: {len(matched_panel):,} city-years")
wlog(f"  Agencies: {matched_panel['agency_id'].nunique()}")
wlog(f"  Treated: {matched_panel[matched_panel['treated'] == 1]['agency_id'].nunique()}")
wlog(f"  Control: {matched_panel[matched_panel['treated'] == 0]['agency_id'].nunique()}")
wlog(f"  Years: {matched_panel['year'].min()}-{matched_panel['year'].max()}")

# ── 8. PSM Propensity Score Plot ──────────────────────────────────────────────
wlog("\n--- Generating Propensity Score Plots ---")

fig, axes = plt.subplots(1, 2, figsize=(14, 5))

# Before matching
ax = axes[0]
ax.hist(city_cross.loc[city_cross["treated"] == 1, "pscore"], bins=30, alpha=0.6,
        label="Treated", color="steelblue", density=True)
ax.hist(city_cross.loc[city_cross["treated"] == 0, "pscore"], bins=30, alpha=0.6,
        label="Control", color="coral", density=True)
ax.set_xlabel("Propensity Score")
ax.set_ylabel("Density")
ax.set_title("Before Matching")
ax.legend()

# After matching
ax = axes[1]
ax.hist(city_cross.loc[city_cross["agency_id"].isin(matched_treated_ids), "pscore"],
        bins=30, alpha=0.6, label="Treated (matched)", color="steelblue", density=True)
ax.hist(city_cross.loc[city_cross["agency_id"].isin(matched_control_ids), "pscore"],
        bins=30, alpha=0.6, label="Control (matched)", color="coral", density=True)
ax.set_xlabel("Propensity Score")
ax.set_ylabel("Density")
ax.set_title("After Matching")
ax.legend()

plt.tight_layout()
plt.savefig(os.path.join(figures_dir, "psm_propensity_scores.png"), dpi=150)
plt.close()

# ── 9. TWFE DiD on Matched Sample ────────────────────────────────────────────
wlog("\n" + "=" * 70)
wlog("TWFE DiD Estimation on PSM-Matched Sample")
wlog("=" * 70)

did_results = []

for outcome in outcomes:
    if outcome not in matched_panel.columns:
        wlog(f"\nSKIP {outcome}: not in panel")
        continue

    df = matched_panel[["agency_id", "unit_id", "year", "treated", "post", outcome]].dropna()
    n_valid = len(df)
    n_treated_post = df["post"].sum()

    if n_valid < 100 or n_treated_post < 10:
        wlog(f"\nSKIP {outcome}: too few obs (n={n_valid}, treated_post={n_treated_post})")
        continue

    wlog(f"\n--- Outcome: {outcome} ---")
    wlog(f"  N obs: {n_valid:,}  |  N agencies: {df['agency_id'].nunique()}  |  "
         f"Treated post obs: {int(n_treated_post)}")

    # TWFE: Y_it = alpha_i + gamma_t + beta * post_it + epsilon_it
    try:
        model = smf.ols(f"{outcome} ~ post + C(agency_id) + C(year)", data=df).fit(
            cov_type="cluster", cov_kwds={"groups": df["agency_id"]}
        )

        beta = model.params.get("post", np.nan)
        se = model.bse.get("post", np.nan)
        pval = model.pvalues.get("post", np.nan)
        ci_lower = model.conf_int().loc["post", 0] if "post" in model.conf_int().index else np.nan
        ci_upper = model.conf_int().loc["post", 1] if "post" in model.conf_int().index else np.nan

        stars = ""
        if pval < 0.01:
            stars = "***"
        elif pval < 0.05:
            stars = "**"
        elif pval < 0.10:
            stars = "*"

        wlog(f"  TWFE ATT = {beta:.4f}{stars} (SE={se:.4f}, p={pval:.4f})")
        wlog(f"  95% CI: [{ci_lower:.4f}, {ci_upper:.4f}]")

        did_results.append({
            "model": "PSM + TWFE",
            "outcome": outcome,
            "att": beta,
            "se": se,
            "p_value": pval,
            "ci_lower": ci_lower,
            "ci_upper": ci_upper,
            "significance": stars,
            "n_obs": n_valid,
            "n_agencies": df["agency_id"].nunique(),
            "n_treated_agencies": df[df["treated"] == 1]["agency_id"].nunique(),
            "n_control_agencies": df[df["treated"] == 0]["agency_id"].nunique(),
        })
    except Exception as e:
        wlog(f"  ERROR: {e}")

# ── 10. TWFE with covariates on matched sample ───────────────────────────────
wlog("\n" + "=" * 70)
wlog("TWFE DiD with Covariates on PSM-Matched Sample")
wlog("=" * 70)

cov_formula_vars = []
for v in ["log_population", "pct_black"]:
    if v in matched_panel.columns:
        cov_formula_vars.append(v)

if cov_formula_vars:
    cov_str = " + ".join(cov_formula_vars)
    wlog(f"Covariates: {cov_str}")

    for outcome in outcomes:
        if outcome not in matched_panel.columns:
            continue

        keep_cols = ["agency_id", "unit_id", "year", "treated", "post", outcome] + cov_formula_vars
        df = matched_panel[keep_cols].dropna()
        n_valid = len(df)
        n_treated_post = df["post"].sum()

        if n_valid < 100 or n_treated_post < 10:
            continue

        wlog(f"\n--- Outcome: {outcome} (with covariates) ---")
        wlog(f"  N obs: {n_valid:,}")

        try:
            formula = f"{outcome} ~ post + {cov_str} + C(agency_id) + C(year)"
            model = smf.ols(formula, data=df).fit(
                cov_type="cluster", cov_kwds={"groups": df["agency_id"]}
            )

            beta = model.params.get("post", np.nan)
            se = model.bse.get("post", np.nan)
            pval = model.pvalues.get("post", np.nan)
            ci_lower = model.conf_int().loc["post", 0] if "post" in model.conf_int().index else np.nan
            ci_upper = model.conf_int().loc["post", 1] if "post" in model.conf_int().index else np.nan

            stars = ""
            if pval < 0.01:
                stars = "***"
            elif pval < 0.05:
                stars = "**"
            elif pval < 0.10:
                stars = "*"

            wlog(f"  TWFE ATT = {beta:.4f}{stars} (SE={se:.4f}, p={pval:.4f})")

            did_results.append({
                "model": "PSM + TWFE + Covariates",
                "outcome": outcome,
                "att": beta,
                "se": se,
                "p_value": pval,
                "ci_lower": ci_lower,
                "ci_upper": ci_upper,
                "significance": stars,
                "n_obs": n_valid,
                "n_agencies": df["agency_id"].nunique(),
                "n_treated_agencies": df[df["treated"] == 1]["agency_id"].nunique(),
                "n_control_agencies": df[df["treated"] == 0]["agency_id"].nunique(),
            })
        except Exception as e:
            wlog(f"  ERROR: {e}")

# ── 11. Event Study on Matched Sample ────────────────────────────────────────
wlog("\n" + "=" * 70)
wlog("Event Study (Dynamic TWFE) on PSM-Matched Sample")
wlog("=" * 70)

# Construct relative_time
matched_panel["relative_time"] = np.where(
    matched_panel["treated"] == 1,
    matched_panel["year"] - matched_panel["treatment_year"],
    np.nan
)

# For control units, we need to assign a pseudo-treatment year for event study
# Use the average treatment year of their matched treated city
control_pseudo_year = {}
for _, m in matches_df.iterrows():
    t_year = panel.loc[panel["agency_id"] == m["treated_agency"], "treatment_year"].iloc[0]
    if m["control_agency"] not in control_pseudo_year:
        control_pseudo_year[m["control_agency"]] = []
    control_pseudo_year[m["control_agency"]].append(t_year)

for cid, years in control_pseudo_year.items():
    pseudo_year = int(np.median(years))
    mask = matched_panel["agency_id"] == cid
    matched_panel.loc[mask, "relative_time"] = matched_panel.loc[mask, "year"] - pseudo_year

es_results = []

for outcome in outcomes:
    if outcome not in matched_panel.columns:
        continue

    df = matched_panel[["agency_id", "year", "relative_time", outcome]].dropna()
    df = df[(df["relative_time"] >= -5) & (df["relative_time"] <= 5)]
    df["relative_time"] = df["relative_time"].astype(int)

    if len(df) < 100:
        continue

    wlog(f"\n--- Event Study: {outcome} ---")

    # Create dummies for relative_time, omitting -1 as reference
    time_dummies = pd.get_dummies(df["relative_time"], prefix="rt", dtype=float)
    # Drop reference period (rt_-1)
    ref_col = "rt_-1"
    if ref_col in time_dummies.columns:
        time_dummies = time_dummies.drop(columns=[ref_col])

    df_es = pd.concat([df.reset_index(drop=True), time_dummies.reset_index(drop=True)], axis=1)

    try:
        rt_cols = [c for c in time_dummies.columns]
        formula = f"{outcome} ~ {' + '.join(rt_cols)} + C(agency_id) + C(year)"
        model = smf.ols(formula, data=df_es).fit(
            cov_type="cluster", cov_kwds={"groups": df_es["agency_id"]}
        )

        for rt_col in rt_cols:
            t_val = int(rt_col.replace("rt_", ""))
            beta = model.params.get(rt_col, np.nan)
            se = model.bse.get(rt_col, np.nan)
            pval = model.pvalues.get(rt_col, np.nan)

            es_results.append({
                "outcome": outcome,
                "event_time": t_val,
                "att": beta,
                "se": se,
                "p_value": pval,
                "ci_lower": beta - 1.96 * se,
                "ci_upper": beta + 1.96 * se,
            })

        wlog(f"  Event study estimated for t=-5..+5 (ref=-1)")

    except Exception as e:
        wlog(f"  ERROR: {e}")

# ── 12. Event Study Plots ────────────────────────────────────────────────────
if es_results:
    es_df = pd.DataFrame(es_results)
    es_df.to_csv(os.path.join(tables_dir, "psm_event_study.csv"), index=False)

    for outcome in es_df["outcome"].unique():
        sub = es_df[es_df["outcome"] == outcome].sort_values("event_time")
        # Add reference period (0 at t=-1)
        ref_row = pd.DataFrame([{
            "outcome": outcome, "event_time": -1, "att": 0, "se": 0,
            "p_value": 1, "ci_lower": 0, "ci_upper": 0
        }])
        sub = pd.concat([sub, ref_row]).sort_values("event_time")

        fig, ax = plt.subplots(figsize=(8, 5))
        ax.axhline(y=0, color="gray", linewidth=0.8)
        ax.axvline(x=-0.5, color="red", linestyle="--", alpha=0.5)
        ax.fill_between(sub["event_time"], sub["ci_lower"], sub["ci_upper"],
                        alpha=0.2, color="steelblue")
        ax.plot(sub["event_time"], sub["att"], "o-", color="steelblue", markersize=5)
        ax.set_xlabel("Years Relative to COA Creation")
        ax.set_ylabel("ATT")
        ax.set_title(f"PSM Event Study: {outcome}")
        plt.tight_layout()
        plt.savefig(os.path.join(figures_dir, f"eventstudy_psm_{outcome}.png"), dpi=150)
        plt.close()

    wlog(f"\nSaved event study plots for {es_df['outcome'].nunique()} outcomes")

# ── 13. Comparison Table: PSM vs Original ─────────────────────────────────────
wlog("\n" + "=" * 70)
wlog("Comparison: PSM-Matched vs Unmatched (Full Sample) TWFE")
wlog("=" * 70)

# Also run on full (unmatched) sample for direct comparison
full_panel = panel[(panel["year"] >= 2000) & (panel["year"] <= 2020)].copy()

for outcome in outcomes:
    if outcome not in full_panel.columns:
        continue

    df = full_panel[["agency_id", "unit_id", "year", "treated", "post", outcome]].dropna()
    if len(df) < 100:
        continue

    try:
        model = smf.ols(f"{outcome} ~ post + C(agency_id) + C(year)", data=df).fit(
            cov_type="cluster", cov_kwds={"groups": df["agency_id"]}
        )

        beta = model.params.get("post", np.nan)
        se = model.bse.get("post", np.nan)
        pval = model.pvalues.get("post", np.nan)
        ci_lower = model.conf_int().loc["post", 0] if "post" in model.conf_int().index else np.nan
        ci_upper = model.conf_int().loc["post", 1] if "post" in model.conf_int().index else np.nan

        stars = ""
        if pval < 0.01:
            stars = "***"
        elif pval < 0.05:
            stars = "**"
        elif pval < 0.10:
            stars = "*"

        did_results.append({
            "model": "Full Sample TWFE (no PSM)",
            "outcome": outcome,
            "att": beta,
            "se": se,
            "p_value": pval,
            "ci_lower": ci_lower,
            "ci_upper": ci_upper,
            "significance": stars,
            "n_obs": len(df),
            "n_agencies": df["agency_id"].nunique(),
            "n_treated_agencies": df[df["treated"] == 1]["agency_id"].nunique(),
            "n_control_agencies": df[df["treated"] == 0]["agency_id"].nunique(),
        })
    except Exception as e:
        wlog(f"  Full sample TWFE error for {outcome}: {e}")

# ── 14. Save All Results ──────────────────────────────────────────────────────
wlog("\n--- Saving Results ---")

results_df = pd.DataFrame(did_results)
results_df.to_csv(os.path.join(tables_dir, "psm_did_results.csv"), index=False)
wlog(f"Saved {len(results_df)} result rows to psm_did_results.csv")

# Pretty-print comparison table
wlog("\n" + "=" * 70)
wlog("RESULTS COMPARISON TABLE")
wlog("=" * 70)

for outcome in outcomes:
    sub = results_df[results_df["outcome"] == outcome]
    if len(sub) == 0:
        continue
    wlog(f"\n  {outcome}:")
    for _, row in sub.iterrows():
        wlog(f"    {row['model']:35s}  ATT={row['att']:>10.4f}{row['significance']:3s}  "
             f"(SE={row['se']:.4f})  N={int(row['n_obs']):,}  "
             f"[{int(row['n_treated_agencies'])} treated / {int(row['n_control_agencies'])} control]")

# Save match details
matches_df.to_csv(os.path.join(tables_dir, "psm_match_pairs.csv"), index=False)
wlog(f"\nSaved match pairs to psm_match_pairs.csv")

# ── 15. IPW (Inverse Propensity Weighting) as Robustness ─────────────────────
wlog("\n" + "=" * 70)
wlog("Robustness: Inverse Propensity Weighting (IPW) on Full Sample")
wlog("=" * 70)

# Merge propensity scores back to full panel
pscore_map = city_cross[["agency_id", "pscore"]].copy()
ipw_panel = full_panel.merge(pscore_map, on="agency_id", how="inner")

# Trim extreme propensity scores (common support)
trim_lo, trim_hi = 0.05, 0.95
ipw_panel = ipw_panel[(ipw_panel["pscore"] >= trim_lo) & (ipw_panel["pscore"] <= trim_hi)]
wlog(f"IPW panel after trimming [{trim_lo}, {trim_hi}]: {len(ipw_panel):,} city-years, "
     f"{ipw_panel['agency_id'].nunique()} agencies")

# IPW weights: treated get w=1, control get w = p/(1-p)
ipw_panel["ipw_weight"] = np.where(
    ipw_panel["treated"] == 1,
    1.0,
    ipw_panel["pscore"] / (1 - ipw_panel["pscore"])
)

ipw_results = []
for outcome in outcomes:
    if outcome not in ipw_panel.columns:
        continue

    df = ipw_panel[["agency_id", "unit_id", "year", "treated", "post",
                     outcome, "ipw_weight"]].dropna()
    if len(df) < 100:
        continue

    wlog(f"\n--- IPW: {outcome} ---")
    try:
        model = smf.wls(f"{outcome} ~ post + C(agency_id) + C(year)",
                        data=df, weights=df["ipw_weight"]).fit(
            cov_type="cluster", cov_kwds={"groups": df["agency_id"]}
        )

        beta = model.params.get("post", np.nan)
        se = model.bse.get("post", np.nan)
        pval = model.pvalues.get("post", np.nan)

        stars = ""
        if pval < 0.01:
            stars = "***"
        elif pval < 0.05:
            stars = "**"
        elif pval < 0.10:
            stars = "*"

        wlog(f"  IPW ATT = {beta:.4f}{stars} (SE={se:.4f}, p={pval:.4f})")

        ipw_results.append({
            "model": "IPW + TWFE",
            "outcome": outcome,
            "att": beta,
            "se": se,
            "p_value": pval,
            "ci_lower": beta - 1.96 * se,
            "ci_upper": beta + 1.96 * se,
            "significance": stars,
            "n_obs": len(df),
            "n_agencies": df["agency_id"].nunique(),
            "n_treated_agencies": df[df["treated"] == 1]["agency_id"].nunique(),
            "n_control_agencies": df[df["treated"] == 0]["agency_id"].nunique(),
        })
    except Exception as e:
        wlog(f"  ERROR: {e}")

if ipw_results:
    ipw_df = pd.DataFrame(ipw_results)
    # Append to main results
    all_results = pd.concat([results_df, ipw_df], ignore_index=True)
    all_results.to_csv(os.path.join(tables_dir, "psm_did_results.csv"), index=False)
    wlog(f"\nUpdated results file with {len(ipw_df)} IPW estimates")

# ── Final Summary ─────────────────────────────────────────────────────────────
wlog("\n" + "=" * 70)
wlog("ANALYSIS COMPLETE")
wlog("=" * 70)
wlog(f"\nOutput files:")
wlog(f"  - {os.path.join(tables_dir, 'psm_did_results.csv')}")
wlog(f"  - {os.path.join(tables_dir, 'psm_balance_table.csv')}")
wlog(f"  - {os.path.join(tables_dir, 'psm_match_pairs.csv')}")
wlog(f"  - {os.path.join(tables_dir, 'psm_event_study.csv')}")
wlog(f"  - {os.path.join(figures_dir, 'psm_propensity_scores.png')}")
wlog(f"  - {os.path.join(figures_dir, 'eventstudy_psm_*.png')}")
wlog(f"  - {log_path}")

log_fh.close()
print("\nDone. See output/psm_analysis_log.txt for full log.")
