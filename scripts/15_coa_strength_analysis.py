##############################################################################
# 15_coa_strength_analysis.py
# COA Strength Analysis: Predictors, Electoral Effects, and Policing Outcomes
#
# Part A: What predicts STRONGER COAs (investigative/disciplinary powers)?
# Part B: Electoral rewards/punishment by COA strength
# Part C: Policing outcomes by COA strength
#
# COA strength classification:
#   - Strong: can independently investigate OR discipline (invest_power==1
#     or discipline_power==1)
#   - Weak: has oversight board but no independent investigative or
#     disciplinary power
##############################################################################

import os
import warnings
import numpy as np
import pandas as pd
import pyreadr
import statsmodels.api as sm
from statsmodels.discrete.discrete_model import Logit
from linearmodels.panel import PanelOLS

warnings.filterwarnings("ignore")

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")
os.makedirs(os.path.join(output_dir, "tables"), exist_ok=True)

print("=" * 70)
print("COA Strength Analysis")
print("=" * 70)

# ── 1. Load data ─────────────────────────────────────────────────────────────

panel_raw = pyreadr.read_r(os.path.join(base_dir, "merged_data/analysis_panel.rds"))[None]
ledb = pd.read_csv(os.path.join(base_dir, "raw_data/ledb_candidatelevel.csv"),
                    low_memory=False)
coa = pd.read_csv(os.path.join(base_dir, "raw_data/coa_creation_data.csv"))

print(f"Analysis panel: {panel_raw.shape[0]:,} city-year obs, {panel_raw['agency_id'].nunique()} cities")
print(f"LEDB: {ledb.shape[0]:,} candidate-election obs")

# ── 2. Construct COA strength measure ─────────────────────────────────────

# In the analysis panel, invest_power and discipline_power are already merged
panel_raw["strong_coa"] = (
    (panel_raw["invest_power"] == 1) | (panel_raw["discipline_power"] == 1)
).astype(int)
panel_raw["weak_coa"] = (
    (panel_raw["treated"] == 1) &
    (panel_raw["invest_power"] == 0) &
    (panel_raw["discipline_power"] == 0)
).astype(int)

# Summary
treated = panel_raw[panel_raw["treated"] == 1]
strong_cities = treated[treated["strong_coa"] == 1]["agency_id"].nunique()
weak_cities = treated[treated["weak_coa"] == 1]["agency_id"].nunique()
control_cities = panel_raw[panel_raw["treated"] == 0]["agency_id"].nunique()

print(f"\nCOA strength breakdown (city-level):")
print(f"  Strong COA (investigate or discipline): {strong_cities} cities")
print(f"  Weak COA (board only):                  {weak_cities} cities")
print(f"  No COA (control):                       {control_cities} cities")
print(f"  Of strong: investigate={treated[treated['invest_power']==1]['agency_id'].nunique()}, "
      f"discipline={treated[treated['discipline_power']==1]['agency_id'].nunique()}")

# ══════════════════════════════════════════════════════════════════════════
# PART A: What predicts STRONGER COAs?
# ══════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("PART A: What Predicts Stronger COAs?")
print("=" * 70)

# Cross-sectional: among cities that adopted a COA, what predicts
# getting a strong one (with investigate/discipline powers)?

# Build city council / mayor composition from LEDB
cc_win = ledb[(ledb["office_consolidated"] == "City Council") &
              (ledb["winner"] == "win")].copy()
cc_win["geo_clean"] = cc_win["geo_name"].str.lower().str.strip()
cc_win["state_clean"] = cc_win["state_abb"].str.lower().str.strip()

council_comp = cc_win.groupby(["geo_clean", "state_clean", "year"]).agg(
    council_pct_black=("prob_black", "mean"),
    council_pct_dem=("prob_democrat", "mean"),
    council_pct_female=("prob_female", "mean"),
).reset_index()

m_win = ledb[(ledb["office_consolidated"] == "Mayor") &
             (ledb["winner"] == "win")].copy()
m_win["geo_clean"] = m_win["geo_name"].str.lower().str.strip()
m_win["state_clean"] = m_win["state_abb"].str.lower().str.strip()

mayor_comp = m_win.groupby(["geo_clean", "state_clean", "year"]).agg(
    mayor_black=("prob_black", "mean"),
    mayor_dem=("prob_democrat", "mean"),
).reset_index()

# Merge onto panel
panel_raw["geo_clean"] = panel_raw["city_lower"].str.lower().str.strip()
panel_raw["st_clean"] = panel_raw["state_clean"].str.lower().str.strip()
panel_raw = panel_raw.sort_values(["agency_id", "year"])

panel_raw = pd.merge(
    panel_raw, council_comp,
    left_on=["geo_clean", "st_clean", "year"],
    right_on=["geo_clean", "state_clean", "year"],
    how="left", suffixes=("", "_cc")
)
if "state_clean_cc" in panel_raw.columns:
    panel_raw.drop(columns=["state_clean_cc"], inplace=True)

panel_raw = pd.merge(
    panel_raw, mayor_comp,
    left_on=["geo_clean", "st_clean", "year"],
    right_on=["geo_clean", "state_clean", "year"],
    how="left", suffixes=("", "_m")
)
if "state_clean_m" in panel_raw.columns:
    panel_raw.drop(columns=["state_clean_m"], inplace=True)

# Forward fill council/mayor composition
for col in ["council_pct_black", "council_pct_dem", "council_pct_female",
            "mayor_black", "mayor_dem"]:
    panel_raw[col] = panel_raw.groupby("agency_id")[col].ffill()

panel_raw["log_pop"] = np.log(panel_raw["population"].clip(lower=1))

south_states = ["al", "ar", "fl", "ga", "ky", "la", "ms", "nc", "sc", "tn", "tx", "va", "wv"]
panel_raw["south"] = panel_raw["st_clean"].isin(south_states).astype(int)
panel_raw["dem_power"] = panel_raw["dem_in_power"].astype(float)

# Build cross-section of COA cities (pre-treatment averages)
coa_cities = panel_raw[panel_raw["treated"] == 1].copy()
coa_pre = coa_cities[coa_cities["year"] < coa_cities["treatment_year"]].copy()

# For cities treated before panel start, use earliest years
if len(coa_pre) == 0:
    coa_pre = coa_cities.copy()

pred_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
             "violent_crime_pc", "drug_arrests_pc", "police_killings_pc",
             "black_share_violent_arrests",
             "dem_power", "council_pct_dem", "council_pct_black",
             "mayor_dem", "mayor_black"]

agg_dict = {v: "mean" for v in pred_vars if v in coa_pre.columns}
agg_dict["strong_coa"] = "first"
agg_dict["invest_power"] = "first"
agg_dict["discipline_power"] = "first"
agg_dict["treatment_year"] = "first"

coa_cross = coa_pre.groupby("agency_id").agg(agg_dict).reset_index()

print(f"\nCross-section of COA cities: {len(coa_cross)}")
print(f"  Strong COA: {coa_cross['strong_coa'].sum()}")
print(f"  Weak COA:   {(coa_cross['strong_coa'] == 0).sum()}")

results_all = []


def run_logit_lpm(data, y_var, x_vars, label, part="A"):
    """Run logit and LPM, return results."""
    cols = [y_var] + x_vars
    df = data[cols].dropna().copy()

    if df[y_var].nunique() < 2 or len(df) < 20:
        print(f"  [{label}] Skipping: insufficient data (N={len(df)}, "
              f"Y variation={df[y_var].nunique()})")
        return None

    y = df[y_var]
    X = sm.add_constant(df[x_vars])

    # Try logit first
    model_type = "Logit"
    try:
        mod = Logit(y, X)
        res = mod.fit(disp=0, maxiter=200)
        r2 = res.prsquared
    except Exception:
        model_type = "LPM"
        mod = sm.OLS(y, X)
        res = mod.fit(cov_type="HC1")
        r2 = res.rsquared

    print(f"\n  [{label}] ({model_type}, N={len(df)}, Y=1: {int(y.sum())})")
    print(f"  {'Variable':35s} {'Coef':>10s} {'SE':>10s} {'p':>8s}")
    print(f"  {'-'*65}")

    for var in x_vars:
        coef = res.params[var]
        se = res.bse[var]
        p = res.pvalues[var]
        stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))
        print(f"  {var:35s} {coef:10.5f} {se:10.5f} {p:8.4f} {stars}")
        results_all.append({
            "part": part, "model": label, "model_type": model_type,
            "variable": var, "coef": round(coef, 6), "se": round(se, 6),
            "p_value": round(p, 4), "significance": stars,
            "n_obs": len(df), "n_y1": int(y.sum()),
        })

    print(f"  {'Pseudo ' if model_type == 'Logit' else ''}R²: {r2:.4f}")
    return res


# A1: Demographics + crime → strong COA
print("\n── A1: Demographics + Crime ──")
a1_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
           "violent_crime_pc", "drug_arrests_pc", "police_killings_pc",
           "black_share_violent_arrests"]
run_logit_lpm(coa_cross, "strong_coa", a1_vars, "Demographics + Crime", "A")

# A2: Demographics + politics → strong COA
print("\n── A2: Demographics + Politics ──")
a2_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
           "dem_power", "council_pct_dem", "council_pct_black",
           "mayor_dem", "mayor_black"]
run_logit_lpm(coa_cross, "strong_coa", a2_vars, "Demographics + Politics", "A")

# A3: Full model
print("\n── A3: Full Model ──")
a3_vars = ["log_pop", "pct_black", "pct_hispanic", "south",
           "violent_crime_pc", "police_killings_pc",
           "black_share_violent_arrests",
           "dem_power", "council_pct_dem", "council_pct_black",
           "mayor_dem", "mayor_black"]
run_logit_lpm(coa_cross, "strong_coa", a3_vars, "Full Model", "A")

# A4: LPM for robustness
print("\n── A4: Full Model (LPM) ──")
a3_df = coa_cross[["strong_coa"] + a3_vars].dropna()
if len(a3_df) >= 20 and a3_df["strong_coa"].nunique() == 2:
    y = a3_df["strong_coa"]
    X = sm.add_constant(a3_df[a3_vars])
    res_lpm = sm.OLS(y, X).fit(cov_type="HC1")
    print(f"\n  [Full Model LPM] (N={len(a3_df)}, Y=1: {int(y.sum())})")
    print(f"  {'Variable':35s} {'Coef':>10s} {'SE':>10s} {'p':>8s}")
    print(f"  {'-'*65}")
    for var in a3_vars:
        coef = res_lpm.params[var]
        se = res_lpm.bse[var]
        p = res_lpm.pvalues[var]
        stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))
        print(f"  {var:35s} {coef:10.5f} {se:10.5f} {p:8.4f} {stars}")
        results_all.append({
            "part": "A", "model": "Full Model (LPM)", "model_type": "LPM",
            "variable": var, "coef": round(coef, 6), "se": round(se, 6),
            "p_value": round(p, 4), "significance": stars,
            "n_obs": len(a3_df), "n_y1": int(y.sum()),
        })
    print(f"  R²: {res_lpm.rsquared:.4f}")

# Balance table: strong vs weak COA cities
print("\n── Balance: Strong vs Weak COA Cities ──")
print(f"\n{'Variable':35s} {'Strong':>10s} {'Weak':>10s} {'Diff':>10s} {'p':>8s}")
print("-" * 75)
from scipy import stats
for var in pred_vars:
    s = coa_cross[coa_cross["strong_coa"] == 1][var].dropna()
    w = coa_cross[coa_cross["strong_coa"] == 0][var].dropna()
    if len(s) > 3 and len(w) > 3:
        t, p = stats.ttest_ind(s, w)
        diff = s.mean() - w.mean()
        stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))
        print(f"{var:35s} {s.mean():10.4f} {w.mean():10.4f} {diff:10.4f} {p:8.4f} {stars}")

# ══════════════════════════════════════════════════════════════════════════
# PART B: Electoral Effects by COA Strength
# ══════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("PART B: Electoral Rewards/Punishment by COA Strength")
print("=" * 70)

# Clean COA data for LEDB merge
coa.columns = [
    "ORI", "city_num", "city_raw", "state_raw", "population", "state_abb",
    "has_oversight_board", "oversight_powers", "charter_found", "link",
    "year_created", "can_investigate", "can_discipline",
    "created_via_election", "selection_method"
]

coa["year_created_num"] = pd.to_numeric(
    coa["year_created"].astype(str).str.strip().str.replace(r"\(\?\)", "", regex=True),
    errors="coerce"
)
coa["has_board"] = coa["has_oversight_board"].str.strip().str.upper() == "Y"
coa["invest"] = coa["can_investigate"].str.strip().str.upper().str.startswith("Y").fillna(False)
coa["discip"] = coa["can_discipline"].str.strip().str.upper().str.startswith("Y").fillna(False)
coa["strong"] = (coa["invest"] | coa["discip"]).astype(int)


def clean_coa_city(name):
    s = str(name).lower().strip()
    for suffix in [" metropolitan government (balance)",
                   " consolidated government (balance)",
                   " unified government (balance)",
                   " (balance)", " municipality", " urban county",
                   " city", " town", " village", " borough", " cdp"]:
        s = s.replace(suffix, "")
    for old, new in {"kansascity": "kansas city", "oklahomacity": "oklahoma city",
                     "jerseycity": "jersey city", "boisecity": "boise city",
                     "salt lakecity": "salt lake city",
                     "west valleycity": "west valley city"}.items():
        s = s.replace(old, new)
    for old, new in {"nashville-davidson": "nashville-davidson county",
                     "louisville/jefferson county metro government": "louisville",
                     "lexington-fayette": "lexington-fayette county",
                     "macon-bibb county": "macon",
                     "urban honolulu": "honolulu",
                     "athens-clarke county unified government": "athens"}.items():
        if s == old:
            s = new
    return s.strip()


coa["city_clean"] = coa["city_raw"].apply(clean_coa_city)
state_fixes = {"NB": "NE", "OAKLAND": "CA", "LO": "LA"}
coa["state_clean"] = coa["state_abb"].str.strip().str.upper().replace(state_fixes)

state_name_to_abb = {
    "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR",
    "California": "CA", "Colorado": "CO", "Connecticut": "CT",
    "Delaware": "DE", "Florida": "FL", "Georgia": "GA", "Hawaii": "HI",
    "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
    "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME",
    "Maryland": "MD", "Massachusetts": "MA", "Michigan": "MI",
    "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO",
    "Montana": "MT", "Nebraska": "NE", "Nevada": "NV",
    "New Hampshire": "NH", "New Jersey": "NJ", "New Mexico": "NM",
    "New York": "NY", "North Carolina": "NC", "North Dakota": "ND",
    "Ohio": "OH", "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA",
    "Rhode Island": "RI", "South Carolina": "SC", "South Dakota": "SD",
    "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT",
    "Virginia": "VA", "Washington": "WA", "West Virginia": "WV",
    "Wisconsin": "WI", "Wyoming": "WY", "District of Columbia": "DC",
}
for idx, row in coa.iterrows():
    if pd.isna(row["state_clean"]) or row["state_clean"] in ("NAN", ""):
        if row["state_raw"] in state_name_to_abb:
            coa.at[idx, "state_clean"] = state_name_to_abb[row["state_raw"]]

coa = coa.sort_values("year_created_num", na_position="last")
coa = coa.drop_duplicates(subset=["city_clean", "state_clean"], keep="first")

# Prepare LEDB
ledb_cm = ledb[ledb["office_consolidated"].isin(["City Council", "Mayor"])].copy()
ledb_cm["geo_clean"] = ledb_cm["geo_name"].str.lower().str.strip()
ledb_cm["state_clean"] = ledb_cm["state_abb"].str.upper().str.strip()

# Merge
merged = pd.merge(
    ledb_cm,
    coa[["city_clean", "state_clean", "year_created_num", "has_board", "strong",
         "invest", "discip"]],
    left_on=["geo_clean", "state_clean"],
    right_on=["city_clean", "state_clean"],
    how="left"
)
merged.drop(columns=["city_clean"], inplace=True, errors="ignore")
merged = merged[merged["vote_share"].notna() & (merged["vote_share"] > 0)].copy()

# Candidate ID
merged["cand_id"] = merged["bonica.cid"].astype(str)
no_id = merged["bonica.cid"].isna()
merged.loc[no_id, "cand_id"] = (
    merged.loc[no_id, "full_name"].astype(str) + "_" +
    merged.loc[no_id, "geo_clean"].astype(str) + "_" +
    merged.loc[no_id, "state_clean"].astype(str)
)

# Incumbents only
inc = merged[merged["incumbent"] == 1.0].copy()
inc = inc.sort_values(["cand_id", "year"])
inc["prev_year"] = inc.groupby("cand_id")["year"].shift(1)
inc["term_start"] = inc["prev_year"].fillna(inc["year"] - 4)

# Strong COA created during term
inc["strong_coa_during_term"] = (
    inc["year_created_num"].notna() &
    (inc["strong"] == 1) &
    (inc["year_created_num"] > inc["term_start"]) &
    (inc["year_created_num"] <= inc["year"])
).astype(int)

# Weak COA created during term
inc["weak_coa_during_term"] = (
    inc["year_created_num"].notna() &
    (inc["strong"] == 0) &
    (inc["has_board"] == True) &
    (inc["year_created_num"] > inc["term_start"]) &
    (inc["year_created_num"] <= inc["year"])
).astype(int)

# Any COA during term
inc["any_coa_during_term"] = (
    inc["strong_coa_during_term"] | inc["weak_coa_during_term"]
).astype(int)

# Post strong/weak COA
inc["post_strong_coa"] = (
    inc["year_created_num"].notna() &
    (inc["strong"] == 1) &
    (inc["year"] >= inc["year_created_num"])
).astype(int)

inc["post_weak_coa"] = (
    inc["year_created_num"].notna() &
    (inc["strong"] == 0) &
    (inc["has_board"] == True) &
    (inc["year"] >= inc["year_created_num"])
).astype(int)

# Panel: 2+ obs per candidate
cand_counts = inc.groupby("cand_id").size()
multi = cand_counts[cand_counts >= 2].index
elec_panel = inc[inc["cand_id"].isin(multi)].copy()
elec_panel["city_id"] = elec_panel["geo_clean"].astype(str) + "_" + elec_panel["state_clean"].astype(str)
elec_panel["win"] = (elec_panel["winner"] == "win").astype(int)

print(f"\nElectoral panel: {len(elec_panel):,} obs, {elec_panel['cand_id'].nunique():,} candidates")
print(f"  Strong COA during term: {elec_panel['strong_coa_during_term'].sum()}")
print(f"  Weak COA during term:   {elec_panel['weak_coa_during_term'].sum()}")
print(f"  Post strong COA:        {elec_panel['post_strong_coa'].sum()}")
print(f"  Post weak COA:          {elec_panel['post_weak_coa'].sum()}")


def run_panel_did(data, treatment_var, outcome_var, label, sample_label, part="B"):
    """PanelOLS with candidate FE + year FE, clustered at city."""
    df = data[[outcome_var, treatment_var, "cand_id", "year", "city_id"]].dropna().copy()

    if df[treatment_var].nunique() < 2 or len(df) < 30:
        print(f"  [{label} | {sample_label} | Y={outcome_var}] Skipping")
        return None

    df = df.reset_index(drop=True).set_index(["cand_id", "year"])
    mod = PanelOLS(dependent=df[outcome_var], exog=df[[treatment_var]],
                   entity_effects=True, time_effects=True, check_rank=False)
    try:
        res = mod.fit(cov_type="clustered", cluster_entity=False, clusters=df["city_id"])
    except Exception:
        res = mod.fit(cov_type="clustered", cluster_entity=True)

    beta = res.params[treatment_var]
    se = res.std_errors[treatment_var]
    p = res.pvalues[treatment_var]
    n = int(res.nobs)
    n_t = int(df[treatment_var].sum())
    stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))

    print(f"  [{label} | {sample_label} | Y={outcome_var}] "
          f"beta={beta:.5f} SE={se:.5f} p={p:.4f}{' '+stars if stars else ''} "
          f"N={n:,} Nt={n_t}")

    results_all.append({
        "part": part, "model": label, "sample": sample_label,
        "outcome": outcome_var, "treatment_var": treatment_var,
        "model_type": "PanelOLS",
        "variable": treatment_var, "coef": round(beta, 6), "se": round(se, 6),
        "p_value": round(p, 4), "significance": stars,
        "n_obs": n, "n_y1": n_t,
    })
    return res


# Electoral models: strong vs weak COA
print("\n── B1: Strong vs Weak COA During Term ──")
for outcome in ["vote_share", "win"]:
    for trt in ["strong_coa_during_term", "weak_coa_during_term"]:
        trt_label = "Strong COA During Term" if "strong" in trt else "Weak COA During Term"
        run_panel_did(elec_panel, trt, outcome, trt_label, "All Incumbents")

print("\n── B2: Post Strong vs Post Weak COA ──")
for outcome in ["vote_share", "win"]:
    for trt in ["post_strong_coa", "post_weak_coa"]:
        trt_label = "Post Strong COA" if "strong" in trt else "Post Weak COA"
        run_panel_did(elec_panel, trt, outcome, trt_label, "All Incumbents")

# By office
print("\n── B3: By Office Type ──")
for office in ["City Council", "Mayor"]:
    sub = elec_panel[elec_panel["office_consolidated"] == office]
    for outcome in ["vote_share", "win"]:
        for trt in ["strong_coa_during_term", "weak_coa_during_term"]:
            trt_label = "Strong COA During Term" if "strong" in trt else "Weak COA During Term"
            run_panel_did(sub, trt, outcome, trt_label, office)

# By race
print("\n── B4: By Candidate Race ──")
for race, race_label in [("black", "Black"), ("caucasian", "White")]:
    race_sub = elec_panel[elec_panel["race_est"] == race]
    rc = race_sub.groupby("cand_id").size()
    race_panel = race_sub[race_sub["cand_id"].isin(rc[rc >= 2].index)]
    for outcome in ["vote_share", "win"]:
        for trt in ["strong_coa_during_term", "weak_coa_during_term",
                     "post_strong_coa", "post_weak_coa"]:
            trt_label = trt.replace("_", " ").replace("coa", "COA").title()
            run_panel_did(race_panel, trt, outcome, trt_label, f"Race: {race_label}")

# By party
print("\n── B5: By Party ──")
for party, party_label in [("D", "Democrat"), ("R", "Republican")]:
    party_sub = elec_panel[elec_panel["pid_est"] == party]
    pc = party_sub.groupby("cand_id").size()
    party_panel = party_sub[party_sub["cand_id"].isin(pc[pc >= 2].index)]
    for outcome in ["vote_share", "win"]:
        for trt in ["strong_coa_during_term", "weak_coa_during_term"]:
            trt_label = "Strong COA During Term" if "strong" in trt else "Weak COA During Term"
            run_panel_did(party_panel, trt, outcome, trt_label, f"Party: {party_label}")


# ══════════════════════════════════════════════════════════════════════════
# PART C: Policing Outcomes by COA Strength
# ══════════════════════════════════════════════════════════════════════════

print("\n" + "=" * 70)
print("PART C: Policing Outcomes by COA Strength")
print("=" * 70)

# Use the analysis panel with city-year data
# Create separate post indicators for strong vs weak COA
pol_panel = panel_raw.copy()
pol_panel["post_strong"] = (
    (pol_panel["strong_coa"] == 1) & (pol_panel["post"] == 1)
).astype(int)
pol_panel["post_weak"] = (
    (pol_panel["weak_coa"] == 1) & (pol_panel["post"] == 1)
).astype(int)

# Restrict to 2000-2020 and reasonable treatment timing
pol_panel = pol_panel[(pol_panel["year"] >= 2000) & (pol_panel["year"] <= 2020)].copy()

# Unit ID for panel
pol_panel["unit_id"] = pd.Categorical(pol_panel["agency_id"]).codes

# Only keep cities with enough data
city_counts = pol_panel.groupby("agency_id").size()
pol_panel = pol_panel[pol_panel["agency_id"].isin(city_counts[city_counts >= 5].index)]

print(f"\nPolicing panel: {len(pol_panel):,} city-year obs, {pol_panel['agency_id'].nunique()} cities")
print(f"  Post strong COA obs: {pol_panel['post_strong'].sum()}")
print(f"  Post weak COA obs:   {pol_panel['post_weak'].sum()}")

# Outcome variables
policing_outcomes = [
    ("violent_crime_pc", "Violent Crime Rate"),
    ("violent_clearance_rate", "Violent Clearance Rate"),
    ("property_clearance_rate", "Property Clearance Rate"),
    ("drug_arrests_pc", "Drug Arrest Rate"),
    ("discretionary_arrests_pc", "Discretionary Arrest Rate"),
    ("police_killings_pc", "Police Killings Rate"),
    ("violent_arrests_pc", "Violent Arrest Rate"),
    ("black_share_violent_arrests", "Black Share Violent Arrests"),
    ("black_share_drug_arrests", "Black Share Drug Arrests"),
]


def run_policing_did(data, treatment_var, outcome_var, label, trt_label):
    """City-year PanelOLS with city FE + year FE."""
    df = data[[outcome_var, treatment_var, "agency_id", "year"]].dropna().copy()

    if df[treatment_var].nunique() < 2 or len(df) < 50:
        print(f"  [{trt_label} → {label}] Skipping (N={len(df)})")
        return None

    df = df.reset_index(drop=True).set_index(["agency_id", "year"])
    mod = PanelOLS(dependent=df[outcome_var], exog=df[[treatment_var]],
                   entity_effects=True, time_effects=True, check_rank=False)
    res = mod.fit(cov_type="clustered", cluster_entity=True)

    beta = res.params[treatment_var]
    se = res.std_errors[treatment_var]
    p = res.pvalues[treatment_var]
    n = int(res.nobs)
    n_t = int(df[treatment_var].sum())
    stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))

    print(f"  [{trt_label:20s} → {label:30s}] beta={beta:11.5f} SE={se:10.5f} "
          f"p={p:.4f}{' '+stars if stars else ''} N={n:,}")

    results_all.append({
        "part": "C", "model": trt_label, "sample": "All Cities",
        "outcome": outcome_var, "treatment_var": treatment_var,
        "model_type": "PanelOLS",
        "variable": treatment_var, "coef": round(beta, 6), "se": round(se, 6),
        "p_value": round(p, 4), "significance": stars,
        "n_obs": n, "n_y1": n_t,
    })
    return res


# C1: Any COA (baseline for comparison)
print("\n── C1: Any COA (baseline) ──")
for outcome_var, outcome_label in policing_outcomes:
    run_policing_did(pol_panel, "post", outcome_var, outcome_label, "Any COA (post)")

# C2: Strong COA
print("\n── C2: Strong COA ──")
# Compare strong COA cities to never-treated (drop weak COA cities)
strong_vs_control = pol_panel[(pol_panel["strong_coa"] == 1) | (pol_panel["treated"] == 0)]
for outcome_var, outcome_label in policing_outcomes:
    run_policing_did(strong_vs_control, "post_strong", outcome_var, outcome_label,
                     "Strong COA (post)")

# C3: Weak COA
print("\n── C3: Weak COA ──")
weak_vs_control = pol_panel[(pol_panel["weak_coa"] == 1) | (pol_panel["treated"] == 0)]
for outcome_var, outcome_label in policing_outcomes:
    run_policing_did(weak_vs_control, "post_weak", outcome_var, outcome_label,
                     "Weak COA (post)")

# C4: Strong vs Weak (both in same model)
print("\n── C4: Strong vs Weak in Same Model ──")
for outcome_var, outcome_label in policing_outcomes:
    df = pol_panel[[outcome_var, "post_strong", "post_weak", "agency_id", "year"]].dropna().copy()
    if len(df) < 50:
        continue
    df = df.reset_index(drop=True).set_index(["agency_id", "year"])
    mod = PanelOLS(dependent=df[outcome_var], exog=df[["post_strong", "post_weak"]],
                   entity_effects=True, time_effects=True, check_rank=False)
    res = mod.fit(cov_type="clustered", cluster_entity=True)

    for trt in ["post_strong", "post_weak"]:
        beta = res.params[trt]
        se = res.std_errors[trt]
        p = res.pvalues[trt]
        n = int(res.nobs)
        n_t = int(df[trt].sum())
        stars = "***" if p < 0.01 else ("**" if p < 0.05 else ("*" if p < 0.10 else ""))
        trt_nice = "Strong COA" if "strong" in trt else "Weak COA"
        print(f"  [{trt_nice:20s} → {outcome_label:30s}] beta={beta:11.5f} SE={se:10.5f} "
              f"p={p:.4f}{' '+stars if stars else ''} N={n:,}")
        results_all.append({
            "part": "C", "model": f"Joint: {trt_nice}", "sample": "All Cities",
            "outcome": outcome_var, "treatment_var": trt,
            "model_type": "PanelOLS (joint)",
            "variable": trt, "coef": round(beta, 6), "se": round(se, 6),
            "p_value": round(p, 4), "significance": stars,
            "n_obs": n, "n_y1": n_t,
        })

# C5: Investigate power specifically
print("\n── C5: Investigative Power Specifically ──")
pol_panel["post_investigate"] = (
    (pol_panel["invest_power"] == 1) & (pol_panel["post"] == 1)
).astype(int)
invest_vs_control = pol_panel[(pol_panel["invest_power"] == 1) | (pol_panel["treated"] == 0)]
for outcome_var, outcome_label in policing_outcomes:
    run_policing_did(invest_vs_control, "post_investigate", outcome_var, outcome_label,
                     "Investigate Power")

# C6: Discipline power specifically
print("\n── C6: Disciplinary Power Specifically ──")
pol_panel["post_discipline"] = (
    (pol_panel["discipline_power"] == 1) & (pol_panel["post"] == 1)
).astype(int)
discip_vs_control = pol_panel[(pol_panel["discipline_power"] == 1) | (pol_panel["treated"] == 0)]
for outcome_var, outcome_label in policing_outcomes:
    run_policing_did(discip_vs_control, "post_discipline", outcome_var, outcome_label,
                     "Discipline Power")


# ── Save all results ──────────────────────────────────────────────────────

results_df = pd.DataFrame(results_all)
results_path = os.path.join(output_dir, "tables", "coa_strength_analysis.tsv")
results_df.to_csv(results_path, index=False, sep="\t")
print(f"\nAll results saved to: {results_path}")

# ── Print summary tables ─────────────────────────────────────────────────

for part_label, part_code in [("PART A: Predictors of Strong COA", "A"),
                               ("PART B: Electoral Effects by Strength", "B"),
                               ("PART C: Policing Outcomes by Strength", "C")]:
    sub = results_df[results_df["part"] == part_code]
    if len(sub) == 0:
        continue
    print(f"\n{'='*70}")
    print(part_label)
    print("=" * 70)
    cols = ["model", "outcome", "variable", "coef", "se", "p_value",
            "significance", "n_obs", "n_y1"]
    cols = [c for c in cols if c in sub.columns]
    print(sub[cols].to_string(index=False))

print("\n" + "=" * 70)
print("Analysis complete.")
print("=" * 70)
