##############################################################################
# 14_coa_adoption_predictors.py
# What predicts COA adoption?
#
# Cross-sectional and panel models examining city-level predictors of
# civilian oversight agency (COA) creation. Predictors include:
#   1. City demographics (population, racial composition)
#   2. Political context (Dem vote share, party in power, council/mayor
#      composition by race and party)
#   3. Crime statistics (violent crime rate, drug arrest rate, clearance rates)
#   4. Police violence (police killings per capita, racial disparities)
#
# Models:
#   A. Cross-sectional logit/LPM: Ever-adopt COA by 2025 (city-level)
#   B. Panel hazard/LPM: Year of COA adoption (city-year panel with
#      year FEs), conditional on not yet having adopted
##############################################################################

import os
import warnings
import numpy as np
import pandas as pd
import pyreadr
import statsmodels.api as sm
from statsmodels.discrete.discrete_model import Logit

warnings.filterwarnings("ignore")

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")
os.makedirs(os.path.join(output_dir, "tables"), exist_ok=True)

print("=" * 70)
print("What Predicts COA Adoption?")
print("=" * 70)

# ── 1. Load data ─────────────────────────────────────────────────────────────

panel = pyreadr.read_r(os.path.join(base_dir, "merged_data/analysis_panel.rds"))[None]
ledb = pd.read_csv(os.path.join(base_dir, "raw_data/ledb_candidatelevel.csv"),
                    low_memory=False)

print(f"\nAnalysis panel: {panel.shape[0]:,} city-year obs, {panel['agency_id'].nunique()} cities")

# ── 2. Build city council and mayor composition from LEDB ─────────────────

# City council winners → city-year council composition
cc_win = ledb[(ledb["office_consolidated"] == "City Council") &
              (ledb["winner"] == "win")].copy()
cc_win["geo_clean"] = cc_win["geo_name"].str.lower().str.strip()
cc_win["state_clean"] = cc_win["state_abb"].str.lower().str.strip()

council_comp = cc_win.groupby(["geo_clean", "state_clean", "year"]).agg(
    council_n_members=("full_name", "size"),
    council_pct_black=("prob_black", "mean"),
    council_pct_hispanic=("prob_hispanic", "mean"),
    council_pct_white=("prob_white", "mean"),
    council_pct_female=("prob_female", "mean"),
    council_pct_dem=("prob_democrat", "mean"),
).reset_index()

print(f"Council composition: {len(council_comp):,} city-year obs from {council_comp['geo_clean'].nunique()} cities")

# Mayor winners → city-year mayor characteristics
m_win = ledb[(ledb["office_consolidated"] == "Mayor") &
             (ledb["winner"] == "win")].copy()
m_win["geo_clean"] = m_win["geo_name"].str.lower().str.strip()
m_win["state_clean"] = m_win["state_abb"].str.lower().str.strip()

mayor_comp = m_win.groupby(["geo_clean", "state_clean", "year"]).agg(
    mayor_black=("prob_black", "mean"),
    mayor_hispanic=("prob_hispanic", "mean"),
    mayor_female=("prob_female", "mean"),
    mayor_dem=("prob_democrat", "mean"),
).reset_index()

print(f"Mayor composition:   {len(mayor_comp):,} city-year obs from {mayor_comp['geo_clean'].nunique()} cities")

# ── 3. Merge council/mayor composition onto main panel ────────────────────

# Panel has city_lower and state_clean
panel["geo_clean"] = panel["city_lower"].str.lower().str.strip()
panel["st_clean"] = panel["state_clean"].str.lower().str.strip()

# Forward-fill council/mayor composition: election results carry forward
# until the next election. First merge on exact year, then forward fill.
panel = panel.sort_values(["agency_id", "year"])

# Merge council composition
panel = pd.merge(
    panel,
    council_comp,
    left_on=["geo_clean", "st_clean", "year"],
    right_on=["geo_clean", "state_clean", "year"],
    how="left",
    suffixes=("", "_cc")
)
if "state_clean_cc" in panel.columns:
    panel.drop(columns=["state_clean_cc"], inplace=True)

# Merge mayor composition
panel = pd.merge(
    panel,
    mayor_comp,
    left_on=["geo_clean", "st_clean", "year"],
    right_on=["geo_clean", "state_clean", "year"],
    how="left",
    suffixes=("", "_m")
)
if "state_clean_m" in panel.columns:
    panel.drop(columns=["state_clean_m"], inplace=True)

# Forward-fill within city (election results persist until next election)
council_cols = ["council_n_members", "council_pct_black", "council_pct_hispanic",
                "council_pct_white", "council_pct_female", "council_pct_dem"]
mayor_cols = ["mayor_black", "mayor_hispanic", "mayor_female", "mayor_dem"]

for col in council_cols + mayor_cols:
    panel[col] = panel.groupby("agency_id")[col].ffill()

cc_matched = panel[council_cols[0]].notna().sum()
m_matched = panel[mayor_cols[0]].notna().sum()
print(f"\nCouncil comp matched: {cc_matched:,} / {len(panel):,} panel rows ({cc_matched/len(panel)*100:.1f}%)")
print(f"Mayor comp matched:   {m_matched:,} / {len(panel):,} panel rows ({m_matched/len(panel)*100:.1f}%)")

# ── 4. Construct key predictor variables ──────────────────────────────────

# Log population (already exists but recompute to ensure)
panel["log_pop"] = np.log(panel["population"].clip(lower=1))

# Police killings per 100k
panel["killings_pc"] = panel["police_killings_pc"]

# Racial disparity in policing
panel["black_arrest_disparity"] = panel["black_share_violent_arrests"]

# Dem share (very sparse — use dem_in_power instead as main political var)
panel["dem_power"] = panel["dem_in_power"].astype(float)

# South indicator
south_states = ["al", "ar", "fl", "ga", "ky", "la", "ms", "nc", "sc", "tn", "tx", "va", "wv"]
panel["south"] = panel["st_clean"].isin(south_states).astype(int)

# ── 5. Build cross-sectional dataset (city-level) ────────────────────────
# For each city, take the average of pre-treatment characteristics.
# For never-treated cities, average over 2000-2015.
# For treated cities, average over years before treatment.

print("\n" + "=" * 70)
print("PART A: Cross-Sectional Analysis — What predicts ever adopting a COA?")
print("=" * 70)

# Restrict to reasonable panel window
panel_window = panel[(panel["year"] >= 2000) & (panel["year"] <= 2020)].copy()

# For treated cities: pre-treatment years only
# For control cities: all years 2000-2015 (to avoid contamination from
# late adoptions and to use a comparable time window)
def get_pre_period(row):
    if row["treatment_year"] > 0 and row["treatment_year"] >= 2000:
        return row["year"] < row["treatment_year"]
    elif row["treatment_year"] > 0:
        # Treated before 2000 — always treated in our window
        return False
    else:
        return row["year"] <= 2015

panel_window["pre_period"] = panel_window.apply(get_pre_period, axis=1)
pre_data = panel_window[panel_window["pre_period"]].copy()

# Collapse to city-level averages
predictor_vars = [
    "log_pop", "pct_black", "pct_white", "pct_hispanic",
    "violent_crime_pc", "drug_arrests_pc", "discretionary_arrests_pc",
    "violent_clearance_rate", "property_clearance_rate",
    "killings_pc", "black_arrest_disparity",
    "dem_power",
    "council_pct_black", "council_pct_dem", "council_pct_female",
    "mayor_black", "mayor_dem", "mayor_female",
    "south"
]

# Aggregate
agg_dict = {v: "mean" for v in predictor_vars if v in pre_data.columns}
agg_dict["treatment_year"] = "first"
agg_dict["year"] = "count"  # number of pre-period years

city_cross = pre_data.groupby("agency_id").agg(agg_dict).reset_index()
city_cross.rename(columns={"year": "n_pre_years"}, inplace=True)

# Outcome: ever adopted COA (treatment_year > 0, with treatment after 2000
# so we have pre-period data)
city_cross["ever_adopt"] = (city_cross["treatment_year"] >= 2000).astype(int)

print(f"\nCross-sectional dataset: {len(city_cross)} cities")
print(f"  Adopted COA (2000+): {city_cross['ever_adopt'].sum()}")
print(f"  Never adopted:       {(city_cross['ever_adopt'] == 0).sum()}")

# ── 6. Cross-sectional models ────────────────────────────────────────────

results_list = []


def run_cross_model(data, predictors, label, model_type="logit"):
    """Estimate cross-sectional model predicting COA adoption."""
    cols = ["ever_adopt"] + predictors
    df = data[cols].dropna().copy()

    if df["ever_adopt"].nunique() < 2:
        print(f"  [{label}] Skipping: no variation in outcome")
        return None

    y = df["ever_adopt"]
    X = sm.add_constant(df[predictors])

    if model_type == "logit":
        try:
            mod = Logit(y, X)
            res = mod.fit(disp=0, maxiter=100)
        except Exception as e:
            print(f"  [{label}] Logit failed ({e}), falling back to LPM")
            model_type = "lpm"

    if model_type == "lpm":
        mod = sm.OLS(y, X)
        res = mod.fit(cov_type="HC1")

    print(f"\n  [{label}] ({model_type.upper()}, N={len(df)})")
    print(f"  {'Variable':35s} {'Coef':>10s} {'SE':>10s} {'p':>8s}")
    print(f"  {'-'*65}")

    for var in predictors:
        coef = res.params[var]
        se = res.bse[var]
        p = res.pvalues[var]
        stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))
        print(f"  {var:35s} {coef:10.5f} {se:10.5f} {p:8.4f} {stars}")

        results_list.append({
            "panel": "A. Cross-Section",
            "model": label,
            "model_type": model_type.upper(),
            "variable": var,
            "coef": round(coef, 6),
            "se": round(se, 6),
            "p_value": round(p, 4),
            "significance": stars,
            "n_obs": len(df),
            "n_adopt": int(y.sum()),
        })

    if model_type == "logit":
        print(f"  Pseudo R²: {res.prsquared:.4f}")
    else:
        print(f"  R²: {res.rsquared:.4f}")

    return res


# Model A1: City demographics only
print("\n── A1: City Demographics ──")
demo_vars = ["log_pop", "pct_black", "pct_hispanic", "south"]
run_cross_model(city_cross, demo_vars, "Demographics Only")

# Model A2: Demographics + crime/policing
print("\n── A2: Demographics + Crime/Policing ──")
crime_vars = demo_vars + ["violent_crime_pc", "drug_arrests_pc",
                          "killings_pc", "black_arrest_disparity"]
run_cross_model(city_cross, crime_vars, "Demographics + Crime")

# Model A3: Demographics + political context
print("\n── A3: Demographics + Political Context ──")
pol_vars = demo_vars + ["dem_power", "council_pct_dem", "council_pct_black",
                        "mayor_dem", "mayor_black"]
run_cross_model(city_cross, pol_vars, "Demographics + Politics")

# Model A4: Kitchen sink
print("\n── A4: Full Model ──")
full_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
             "violent_crime_pc", "drug_arrests_pc",
             "killings_pc", "black_arrest_disparity",
             "dem_power", "council_pct_dem", "council_pct_black",
             "mayor_dem", "mayor_black"]
run_cross_model(city_cross, full_vars, "Full Model")

# Model A5: LPM versions for robustness
print("\n── A5: LPM — Full Model ──")
run_cross_model(city_cross, full_vars, "Full Model (LPM)", model_type="lpm")


# ══════════════════════════════════════════════════════════════════════════
# PART B: Panel Hazard Model — When do cities adopt?
# ══════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("PART B: Panel Hazard Model — Year of COA Adoption")
print("=" * 70)

# Build panel where each city-year is an observation UNTIL adoption.
# Once a city adopts, it drops out. Outcome: adopt_this_year = 1.
# This is a discrete-time hazard model estimated as a LPM with year FEs.

hazard_panel = panel_window.copy()
hazard_panel["adopt_this_year"] = (
    (hazard_panel["treatment_year"] > 0) &
    (hazard_panel["year"] == hazard_panel["treatment_year"])
).astype(int)

# Drop post-adoption years for treated cities
hazard_panel = hazard_panel[
    (hazard_panel["treatment_year"] == 0) |  # never-treated: keep all
    (hazard_panel["year"] <= hazard_panel["treatment_year"])  # treated: keep up to adoption
].copy()

print(f"\nHazard panel: {len(hazard_panel):,} city-year obs")
print(f"  Adoption events: {hazard_panel['adopt_this_year'].sum()}")
print(f"  Cities:          {hazard_panel['agency_id'].nunique()}")


def run_hazard_model(data, predictors, label):
    """Estimate discrete-time hazard (LPM with year FEs)."""
    # Create year dummies
    year_dummies = pd.get_dummies(data["year"], prefix="yr", drop_first=True, dtype=float)

    cols_needed = ["adopt_this_year", "agency_id"] + predictors
    df = data[cols_needed].dropna().copy()
    df = df.join(year_dummies.loc[df.index])

    if df["adopt_this_year"].nunique() < 2:
        print(f"  [{label}] Skipping: no variation in outcome")
        return None

    y = df["adopt_this_year"]
    yr_cols = [c for c in df.columns if c.startswith("yr_")]
    X_cols = predictors + yr_cols
    X = sm.add_constant(df[X_cols])

    mod = sm.OLS(y, X)
    # Cluster SEs at city level
    res = mod.fit(cov_type="cluster", cov_kwds={"groups": df["agency_id"]})

    print(f"\n  [{label}] (LPM + Year FEs, N={len(df)}, Clusters={df['agency_id'].nunique()})")
    print(f"  {'Variable':35s} {'Coef':>10s} {'SE':>10s} {'p':>8s}")
    print(f"  {'-'*65}")

    for var in predictors:
        coef = res.params[var]
        se = res.bse[var]
        p = res.pvalues[var]
        stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))
        print(f"  {var:35s} {coef:10.5f} {se:10.5f} {p:8.4f} {stars}")

        results_list.append({
            "panel": "B. Panel Hazard",
            "model": label,
            "model_type": "LPM+YearFE",
            "variable": var,
            "coef": round(coef, 6),
            "se": round(se, 6),
            "p_value": round(p, 4),
            "significance": stars,
            "n_obs": len(df),
            "n_adopt": int(y.sum()),
        })

    print(f"  R²: {res.rsquared:.4f}")
    return res


# Model B1: City demographics
print("\n── B1: City Demographics ──")
run_hazard_model(hazard_panel, demo_vars, "Demographics Only")

# Model B2: Demographics + crime/policing
print("\n── B2: Demographics + Crime/Policing ──")
hazard_crime_vars = demo_vars + ["violent_crime_pc", "drug_arrests_pc",
                                  "killings_pc", "black_arrest_disparity"]
run_hazard_model(hazard_panel, hazard_crime_vars, "Demographics + Crime")

# Model B3: Demographics + political context
print("\n── B3: Demographics + Political Context ──")
hazard_pol_vars = demo_vars + ["dem_power", "council_pct_dem",
                                "council_pct_black", "mayor_dem", "mayor_black"]
run_hazard_model(hazard_panel, hazard_pol_vars, "Demographics + Politics")

# Model B4: Full model
print("\n── B4: Full Model ──")
hazard_full_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
                    "violent_crime_pc", "drug_arrests_pc",
                    "killings_pc", "black_arrest_disparity",
                    "dem_power", "council_pct_dem", "council_pct_black",
                    "mayor_dem", "mayor_black"]
run_hazard_model(hazard_panel, hazard_full_vars, "Full Model")

# ── 7. Lagged predictors (t-1) for panel models ──────────────────────────
# Avoid simultaneity: use lagged values of time-varying predictors

print("\n── B5: Full Model with Lagged Predictors ──")

lag_vars = ["violent_crime_pc", "drug_arrests_pc", "killings_pc",
            "black_arrest_disparity", "council_pct_dem", "council_pct_black",
            "mayor_dem", "mayor_black"]

hazard_panel = hazard_panel.sort_values(["agency_id", "year"])
for var in lag_vars:
    hazard_panel[f"L_{var}"] = hazard_panel.groupby("agency_id")[var].shift(1)

lagged_full_vars = (["log_pop", "pct_black", "pct_hispanic", "south"] +
                    [f"L_{v}" for v in lag_vars])
run_hazard_model(hazard_panel, lagged_full_vars, "Full Model (Lagged)")

# ══════════════════════════════════════════════════════════════════════════
# PART C: Summary Statistics by Adoption Status
# ══════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("PART C: Summary Statistics by Adoption Status")
print("=" * 70)

summary_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
                "violent_crime_pc", "drug_arrests_pc",
                "killings_pc", "black_arrest_disparity",
                "dem_power", "council_pct_dem", "council_pct_black",
                "mayor_dem", "mayor_black"]

summary_rows = []
for var in summary_vars:
    for adopt_val, adopt_label in [(1, "Adopted COA"), (0, "Never Adopted")]:
        sub = city_cross[city_cross["ever_adopt"] == adopt_val]
        vals = sub[var].dropna()
        if len(vals) == 0:
            continue
        summary_rows.append({
            "variable": var,
            "group": adopt_label,
            "n": len(vals),
            "mean": round(vals.mean(), 4),
            "sd": round(vals.std(), 4),
            "median": round(vals.median(), 4),
        })

# Add difference in means test
from scipy import stats
for var in summary_vars:
    adopt = city_cross[city_cross["ever_adopt"] == 1][var].dropna()
    control = city_cross[city_cross["ever_adopt"] == 0][var].dropna()
    if len(adopt) > 5 and len(control) > 5:
        t_stat, p_val = stats.ttest_ind(adopt, control)
        diff = adopt.mean() - control.mean()
        stars = "***" if p_val < 0.01 else ("**" if p_val < 0.05 else ("*" if p_val < 0.10 else ""))
        summary_rows.append({
            "variable": var,
            "group": "Difference",
            "n": len(adopt) + len(control),
            "mean": round(diff, 4),
            "sd": round(p_val, 4),
            "median": stars,
        })

summary_df = pd.DataFrame(summary_rows)

# Print balance table
print(f"\n{'Variable':35s} {'Adopted':>12s} {'Never':>12s} {'Diff':>10s} {'p-val':>8s}")
print("-" * 80)
for var in summary_vars:
    rows = summary_df[summary_df["variable"] == var]
    adopt_row = rows[rows["group"] == "Adopted COA"]
    never_row = rows[rows["group"] == "Never Adopted"]
    diff_row = rows[rows["group"] == "Difference"]
    if len(adopt_row) > 0 and len(never_row) > 0:
        a_mean = adopt_row["mean"].values[0]
        n_mean = never_row["mean"].values[0]
        if len(diff_row) > 0:
            d_mean = diff_row["mean"].values[0]
            d_p = diff_row["sd"].values[0]
            d_stars = diff_row["median"].values[0]
            print(f"{var:35s} {a_mean:12.4f} {n_mean:12.4f} {d_mean:10.4f} {d_p:8.4f} {d_stars}")
        else:
            print(f"{var:35s} {a_mean:12.4f} {n_mean:12.4f}")

# ── 8. Save results ──────────────────────────────────────────────────────

results_df = pd.DataFrame(results_list)
results_path = os.path.join(output_dir, "tables", "coa_adoption_predictors.tsv")
results_df.to_csv(results_path, index=False, sep="\t")
print(f"\nRegression results saved to: {results_path}")

summary_path = os.path.join(output_dir, "tables", "coa_adoption_balance_table.tsv")
summary_df.to_csv(summary_path, index=False, sep="\t")
print(f"Balance table saved to: {summary_path}")

# Final results table
print("\n" + "=" * 70)
print("ALL REGRESSION RESULTS")
print("=" * 70)
display_cols = ["panel", "model", "variable", "coef", "se", "p_value",
                "significance", "n_obs"]
print(results_df[display_cols].to_string(index=False))

print("\n" + "=" * 70)
print("Analysis complete.")
print("=" * 70)
