##############################################################################
# 16_blm_protests_trends_analysis.py
#
# Analyzes BLM protest activity and Google Trends search interest as:
#   1. Predictors of COA adoption
#   2. Outcomes that shift around COA creation
#
# Data sources:
#   - Crowd Counting Consortium (CCC) protest data (Harvard Dataverse)
#     Phase 1 (2017-2020) and Phase 2 (2021-2024)
#   - Google Trends DMA-level search interest for policing terms
#   - COA analysis panel (analysis_panel.rds)
#   - Census CBSA delineation file (county -> MSA crosswalk)
#
# Models:
#   A. Protest activity -> COA adoption (cross-section + hazard)
#   B. Event study: protests and search interest around COA creation
#   C. Google Trends DMA-level analysis (if data available)
##############################################################################

import os
import warnings
import numpy as np
import pandas as pd
import pyreadr
import statsmodels.api as sm

warnings.filterwarnings("ignore")

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")
os.makedirs(os.path.join(output_dir, "tables"), exist_ok=True)

results = []  # collect all results rows


def add_result(section, model, outcome, variable, coef, se, pval, n, note=""):
    results.append({
        "section": section, "model": model, "outcome": outcome,
        "variable": variable, "coef": round(coef, 6), "se": round(se, 6),
        "pval": round(pval, 4), "n": n, "note": note
    })


def run_ols(y, X, cluster=None, label_section="", label_model="",
            label_outcome="", note=""):
    """Run OLS, optionally with clustered SEs. Store results."""
    mask = y.notna() & X.notna().all(axis=1)
    y_c, X_c = y[mask], X[mask]
    if len(y_c) < X_c.shape[1] + 5:
        return None
    try:
        if cluster is not None:
            cl = cluster[mask]
            model = sm.OLS(y_c, X_c).fit(
                cov_type="cluster", cov_kwds={"groups": cl})
        else:
            model = sm.OLS(y_c, X_c).fit(cov_type="HC1")
        for var in X_c.columns:
            if var == "const" or var.startswith("yr_"):
                continue
            add_result(label_section, label_model, label_outcome, var,
                       model.params[var], model.bse[var], model.pvalues[var],
                       int(model.nobs), note)
        return model
    except Exception as e:
        print(f"  OLS failed ({label_model}): {e}")
        return None


print("=" * 70)
print("BLM Protests & Google Trends: Predictors and Shifts around COA Adoption")
print("=" * 70)

###############################################################################
# 1. Load and process CCC protest data
###############################################################################
print("\n── 1. Loading CCC protest data ──")

ccc_cols_p1 = ["date", "locality", "state", "claims", "size_mean",
               "fips_code", "resolved_locality", "resolved_county",
               "resolved_state", "lat", "lon", "type", "arrests_any",
               "property_damage_any", "size_low", "size_high", "issues"]
ccc_cols_p2 = ["date", "locality", "state", "claims", "size_mean",
               "fips_code", "resolved_locality", "resolved_county",
               "resolved_state", "lat", "lon", "type", "arrests_any",
               "property_damage_any", "size_low", "size_high", "issue_tags"]

p1_path = os.path.join(base_dir, "raw_data/ccc_compiled_20172020.tsv")
p2_path = os.path.join(base_dir, "raw_data/ccc_compiled_20212024.tsv")

df1 = pd.read_csv(p1_path, sep="\t", low_memory=False, usecols=ccc_cols_p1)
df1.rename(columns={"issues": "issue_tags"}, inplace=True)
df2 = pd.read_csv(p2_path, sep="\t", low_memory=False, usecols=ccc_cols_p2)
ccc = pd.concat([df1, df2], ignore_index=True)
print(f"  Combined CCC: {len(ccc):,} protest events")

# Parse date
ccc["date_parsed"] = pd.to_datetime(ccc["date"], errors="coerce")
ccc["year"] = ccc["date_parsed"].dt.year
ccc["month"] = ccc["date_parsed"].dt.month

# Flag policing/racial justice protests
ccc["police_related"] = (
    ccc["issue_tags"].fillna("").str.contains(
        "polic|race|racial|justice|blm", case=False, regex=True) |
    ccc["claims"].fillna("").str.contains(
        "polic|BLM|Black Lives|Floyd|brutality|defund|accountab|racial justice",
        case=False, regex=True)
).astype(int)

print(f"  Police/BLM-related: {ccc['police_related'].sum():,} events")
print(f"  Year range: {ccc['year'].min()} - {ccc['year'].max()}")

# Clean FIPS codes
ccc["fips_code"] = pd.to_numeric(ccc["fips_code"], errors="coerce")
ccc = ccc.dropna(subset=["fips_code"])
ccc["fips_code"] = ccc["fips_code"].astype(int)

###############################################################################
# 2. Build county -> MSA crosswalk
###############################################################################
print("\n── 2. Building county-to-MSA crosswalk ──")

cbsa_path = os.path.join(base_dir, "raw_data/cbsa_delineation_2020.xls")
cbsa = pd.read_excel(cbsa_path, header=2)
metro = cbsa[
    cbsa["Metropolitan/Micropolitan Statistical Area"] ==
    "Metropolitan Statistical Area"
].copy()
metro["county_fips"] = (
    metro["FIPS State Code"].astype(int).astype(str).str.zfill(2) +
    metro["FIPS County Code"].astype(int).astype(str).str.zfill(3)
).astype(int)

county_to_msa = metro[["county_fips", "CBSA Code", "CBSA Title"]].copy()
county_to_msa.columns = ["county_fips", "cbsa_code", "msa_name"]
county_to_msa = county_to_msa.drop_duplicates()
print(f"  MSAs: {county_to_msa['cbsa_code'].nunique()}")

# Map CCC events to MSAs
ccc = ccc.merge(county_to_msa, left_on="fips_code", right_on="county_fips",
                how="left")
print(f"  CCC events mapped to MSA: {ccc['cbsa_code'].notna().sum():,} "
      f"of {len(ccc):,}")

###############################################################################
# 3. Aggregate protests to MSA-year level
###############################################################################
print("\n── 3. Aggregating protests to MSA-year ──")

# All protests by MSA-year
msa_year_all = ccc.dropna(subset=["cbsa_code"]).groupby(
    ["cbsa_code", "msa_name", "year"]
).agg(
    n_protests=("date", "size"),
    n_police_protests=("police_related", "sum"),
    total_size_est=("size_mean", lambda x: x.sum(skipna=True)),
    police_size_est=("size_mean", lambda x: x[ccc.loc[x.index, "police_related"] == 1].sum(skipna=True)),
    any_arrests=("arrests_any", "sum"),
    any_property_damage=("property_damage_any", "sum"),
).reset_index()

# Also compute mean size
msa_year_all["avg_protest_size"] = (
    msa_year_all["total_size_est"] / msa_year_all["n_protests"]
).replace([np.inf, -np.inf], np.nan)

print(f"  MSA-year observations: {len(msa_year_all):,}")
print(f"  Unique MSAs: {msa_year_all['cbsa_code'].nunique()}")
print(f"  Years: {msa_year_all['year'].min()} - {msa_year_all['year'].max()}")
print(f"  Police protests per MSA-year (mean): "
      f"{msa_year_all['n_police_protests'].mean():.1f}")

# Also city-level aggregation for direct city matching
city_year = ccc.dropna(subset=["resolved_state"]).copy()
city_year["city_clean"] = city_year["resolved_locality"].str.lower().str.strip()
city_year["state_clean"] = city_year["resolved_state"].str.lower().str.strip()

city_year_agg = city_year.groupby(
    ["city_clean", "state_clean", "year"]
).agg(
    n_protests=("date", "size"),
    n_police_protests=("police_related", "sum"),
    total_size_est=("size_mean", lambda x: x.sum(skipna=True)),
).reset_index()
print(f"  City-year observations: {len(city_year_agg):,}")

###############################################################################
# 4. Load COA panel and merge
###############################################################################
print("\n── 4. Loading COA analysis panel ──")

panel_path = os.path.join(base_dir, "merged_data/analysis_panel.rds")
try:
    panel = pyreadr.read_r(panel_path)[None]
except:
    # Fallback: try from /tmp if raw data was downloaded there
    panel = pyreadr.read_r("/tmp/analysis_panel.rds")[None]

print(f"  Panel: {panel.shape[0]:,} city-year obs, "
      f"{panel['agency_id'].nunique()} cities")

# Restrict to CCC coverage years (2017-2024)
panel_ccc = panel[panel["year"].between(2017, 2024)].copy()
print(f"  Panel (2017-2024): {len(panel_ccc):,} obs")

# Match panel cities to CCC city-year data
# Panel has city_lower and state_clean
panel_ccc["city_clean_merge"] = panel_ccc["city_lower"].str.lower().str.strip()
panel_ccc["state_clean_merge"] = panel_ccc["state_clean"].str.lower().str.strip()

# State abbreviation mapping for CCC (which uses state abbreviations)
state_abbr_to_full = {
    "al": "al", "ak": "ak", "az": "az", "ar": "ar", "ca": "ca",
    "co": "co", "ct": "ct", "de": "de", "dc": "dc", "fl": "fl",
    "ga": "ga", "hi": "hi", "id": "id", "il": "il", "in": "in",
    "ia": "ia", "ks": "ks", "ky": "ky", "la": "la", "me": "me",
    "md": "md", "ma": "ma", "mi": "mi", "mn": "mn", "ms": "ms",
    "mo": "mo", "mt": "mt", "ne": "ne", "nv": "nv", "nh": "nh",
    "nj": "nj", "nm": "nm", "ny": "ny", "nc": "nc", "nd": "nd",
    "oh": "oh", "ok": "ok", "or": "or", "pa": "pa", "ri": "ri",
    "sc": "sc", "sd": "sd", "tn": "tn", "tx": "tx", "ut": "ut",
    "vt": "vt", "va": "va", "wa": "wa", "wv": "wv", "wi": "wi",
    "wy": "wy"
}

# Direct city-year merge
merged = panel_ccc.merge(
    city_year_agg,
    left_on=["city_clean_merge", "state_clean_merge", "year"],
    right_on=["city_clean", "state_clean", "year"],
    how="left"
)
# Fill NAs with 0 for protest counts (cities with no protests)
for col in ["n_protests", "n_police_protests", "total_size_est"]:
    merged[col] = merged[col].fillna(0)

matched_cities = merged[merged["n_protests"] > 0]["agency_id"].nunique()
print(f"  Matched cities (at least 1 protest): {matched_cities} "
      f"of {merged['agency_id'].nunique()}")
print(f"  City-year obs with protests: "
      f"{(merged['n_protests'] > 0).sum()}")
print(f"  City-year obs with police protests: "
      f"{(merged['n_police_protests'] > 0).sum()}")

###############################################################################
# 5. Also merge MSA-level protest data
###############################################################################
print("\n── 5. MSA-level protest merge ──")

# We need to map panel cities to MSAs via their county FIPS
# Panel has fips_state_code.x but we need county FIPS
# Best approach: use city name + state to find the CCC county FIPS, then MSA

# Build a city-state -> MSA lookup from CCC data
city_msa_lookup = ccc.dropna(subset=["cbsa_code", "resolved_locality", "resolved_state"]).copy()
city_msa_lookup["city_lc"] = city_msa_lookup["resolved_locality"].str.lower().str.strip()
city_msa_lookup["state_lc"] = city_msa_lookup["resolved_state"].str.lower().str.strip()
city_msa_lookup = city_msa_lookup.groupby(["city_lc", "state_lc"]).agg(
    cbsa_code=("cbsa_code", "first"),
    msa_name=("msa_name", "first"),
).reset_index()

# Merge MSA info to panel
merged = merged.merge(
    city_msa_lookup,
    left_on=["city_clean_merge", "state_clean_merge"],
    right_on=["city_lc", "state_lc"],
    how="left", suffixes=("", "_msa_lookup")
)

# If we got MSA codes, also merge MSA-level protest aggregates
if merged["cbsa_code"].notna().any():
    merged = merged.merge(
        msa_year_all[["cbsa_code", "year", "n_protests", "n_police_protests",
                       "total_size_est"]].rename(columns={
            "n_protests": "msa_n_protests",
            "n_police_protests": "msa_n_police_protests",
            "total_size_est": "msa_total_size",
        }),
        on=["cbsa_code", "year"],
        how="left"
    )
    for col in ["msa_n_protests", "msa_n_police_protests", "msa_total_size"]:
        merged[col] = merged[col].fillna(0)
    print(f"  Cities mapped to MSA: {merged['cbsa_code'].notna().sum()}")
else:
    merged["msa_n_protests"] = 0
    merged["msa_n_police_protests"] = 0
    merged["msa_total_size"] = 0
    print("  No MSA matches found; using city-level data only")

###############################################################################
# 6. Log transforms and standardized variables
###############################################################################
print("\n── 6. Constructing analysis variables ──")

merged["log_police_protests"] = np.log1p(merged["n_police_protests"])
merged["log_all_protests"] = np.log1p(merged["n_protests"])
merged["log_msa_police_protests"] = np.log1p(merged["msa_n_police_protests"])
merged["log_msa_all_protests"] = np.log1p(merged["msa_n_protests"])

# Per capita (per 100k) protest rates
merged["police_protests_pc"] = np.where(
    merged["population"] > 0,
    merged["n_police_protests"] / merged["population"] * 100000,
    np.nan
)
merged["msa_police_protests_pc"] = np.where(
    merged["population"] > 0,
    merged["msa_n_police_protests"] / merged["population"] * 100000,
    np.nan
)

# Relative time
merged["treated"] = merged["treated"].astype(int)
merged["treatment_year"] = pd.to_numeric(merged["treatment_year"], errors="coerce")
merged["relative_time"] = np.where(
    merged["treated"] == 1,
    merged["year"] - merged["treatment_year"],
    np.nan
)

# Pre-2020 vs post-2020 indicator
merged["post_2020"] = (merged["year"] >= 2020).astype(int)

# Year fixed effects
for yr in sorted(merged["year"].unique()):
    merged[f"yr_{int(yr)}"] = (merged["year"] == yr).astype(int)

yr_cols = [c for c in merged.columns if c.startswith("yr_") and c != "yr_2017"]

print(f"  Final merged dataset: {len(merged):,} obs, "
      f"{merged['agency_id'].nunique()} cities")

###############################################################################
# PART A: Do protests predict COA adoption?
###############################################################################
print("\n" + "=" * 70)
print("PART A: Do BLM Protests Predict COA Adoption?")
print("=" * 70)

# A1: Cross-sectional: among non-COA cities as of 2017,
# does 2017-2019 protest intensity predict subsequent COA creation?

# Get cities that didn't have a COA as of 2017
pre_period = merged[merged["year"].between(2017, 2019)].copy()
city_protests_pre = pre_period.groupby("agency_id").agg(
    total_police_protests=("n_police_protests", "sum"),
    total_protests=("n_protests", "sum"),
    avg_police_protests=("n_police_protests", "mean"),
    msa_avg_police_protests=("msa_n_police_protests", "mean"),
    treated=("treated", "first"),
    treatment_year=("treatment_year", "first"),
    log_pop=("log_population", "mean"),
    pct_black=("pct_black", "mean"),
    pct_hispanic=("pct_hispanic", "mean"),
    violent_crime_pc=("violent_crime_pc", "mean"),
    drug_arrests_pc=("drug_arrests_pc", "mean"),
).reset_index()

# Outcome: adopted COA in 2020 or later
city_protests_pre["adopted_post2019"] = (
    (city_protests_pre["treated"] == 1) &
    (city_protests_pre["treatment_year"] >= 2020)
).astype(int)

# Also: adopted COA ever
city_protests_pre["ever_adopted"] = city_protests_pre["treated"].astype(int)

# Log transform
city_protests_pre["log_police_protests_pre"] = np.log1p(
    city_protests_pre["total_police_protests"])
city_protests_pre["log_all_protests_pre"] = np.log1p(
    city_protests_pre["total_protests"])
city_protests_pre["log_msa_police_pre"] = np.log1p(
    city_protests_pre["msa_avg_police_protests"])

print(f"\n  Cross-sectional sample: {len(city_protests_pre)} cities")
print(f"  Adopted COA post-2019: {city_protests_pre['adopted_post2019'].sum()}")
print(f"  Ever adopted: {city_protests_pre['ever_adopted'].sum()}")
print(f"  Mean police protests 2017-19: "
      f"{city_protests_pre['total_police_protests'].mean():.1f}")

# A1a: LPM — ever adopted ~ protest intensity + controls
print("\n  A1: Cross-sectional LPM — Ever adopted COA")
for outcome_name, outcome_var in [("ever_adopted", "ever_adopted"),
                                   ("adopted_post2019", "adopted_post2019")]:
    for protest_var, pname in [
        ("log_police_protests_pre", "log(police protests 2017-19)"),
        ("log_all_protests_pre", "log(all protests 2017-19)"),
        ("log_msa_police_pre", "log(MSA police protests 2017-19)"),
    ]:
        y = city_protests_pre[outcome_var]
        X = city_protests_pre[[protest_var, "log_pop", "pct_black",
                                "pct_hispanic"]].copy()
        X = sm.add_constant(X)
        X = X.dropna(axis=0, how="any")
        y = y.loc[X.index]
        run_ols(y, X, label_section="A_cross_section",
                label_model=f"LPM_{outcome_name}", label_outcome=outcome_name,
                note=pname)

# A1b: Logit
print("  A1b: Logit — Ever adopted COA")
for outcome_name, outcome_var in [("ever_adopted", "ever_adopted")]:
    y = city_protests_pre[outcome_var]
    X = city_protests_pre[["log_police_protests_pre", "log_pop", "pct_black",
                            "pct_hispanic"]].copy()
    mask = y.notna() & X.notna().all(axis=1) & (y.var() > 0)
    y_c, X_c = y[mask], X[mask]
    X_c = sm.add_constant(X_c)
    if len(y_c) > 10:
        try:
            logit_mod = sm.Logit(y_c, X_c).fit(disp=0)
            for var in ["log_police_protests_pre", "log_pop", "pct_black",
                        "pct_hispanic"]:
                # Marginal effects at means
                mfx = logit_mod.get_margeff(at="mean")
                idx = list(X_c.columns).index(var) - 1  # minus const
                add_result("A_cross_section", "Logit_margeff",
                           outcome_name, var,
                           mfx.margeff[idx], mfx.margeff_se[idx],
                           mfx.pvalues[idx], int(logit_mod.nobs),
                           "marginal effect at mean")
            print(f"    Logit pseudo-R2: {logit_mod.prsquared:.4f}")
        except Exception as e:
            print(f"    Logit failed: {e}")

# A2: Panel hazard model — discrete-time LPM
print("\n  A2: Panel discrete-time hazard — year of COA adoption")

# Keep only city-years where city hasn't yet adopted
hazard_panel = merged.copy()
hazard_panel["not_yet_adopted"] = (
    (hazard_panel["treated"] == 0) |
    (hazard_panel["year"] < hazard_panel["treatment_year"])
).astype(int)
hazard_panel = hazard_panel[hazard_panel["not_yet_adopted"] == 1].copy()

# Outcome: adopted this year
hazard_panel["adopted_this_year"] = 0
mask_adopt = (
    (hazard_panel["treated"] == 1) &
    (hazard_panel["year"] == hazard_panel["treatment_year"])
)
# Actually, once not_yet_adopted filters post-treatment, we can't have
# year == treatment_year in the filtered set. Re-approach:
hazard_panel2 = merged.copy()
hazard_panel2["adopted_this_year"] = (
    (hazard_panel2["treated"] == 1) &
    (hazard_panel2["year"] == hazard_panel2["treatment_year"])
).astype(int)
# Keep obs up to and including the adoption year
hazard_panel2 = hazard_panel2[
    (hazard_panel2["treated"] == 0) |
    (hazard_panel2["year"] <= hazard_panel2["treatment_year"])
].copy()

print(f"  Hazard panel: {len(hazard_panel2):,} obs, "
      f"{hazard_panel2['adopted_this_year'].sum()} adoption events")

# Lagged protests
hazard_panel2 = hazard_panel2.sort_values(["agency_id", "year"])
hazard_panel2["lag_police_protests"] = hazard_panel2.groupby("agency_id")[
    "n_police_protests"].shift(1)
hazard_panel2["lag_log_police_protests"] = np.log1p(
    hazard_panel2["lag_police_protests"])
hazard_panel2["lag_msa_police_protests"] = hazard_panel2.groupby("agency_id")[
    "msa_n_police_protests"].shift(1)
hazard_panel2["lag_log_msa_police"] = np.log1p(
    hazard_panel2["lag_msa_police_protests"])

# A2a: Hazard with city-level protests
for pvar, pname in [
    ("lag_log_police_protests", "lag log(city police protests)"),
    ("lag_log_msa_police", "lag log(MSA police protests)"),
]:
    y = hazard_panel2["adopted_this_year"]
    X = hazard_panel2[[pvar, "log_population", "pct_black",
                        "pct_hispanic"] + yr_cols].copy()
    X = sm.add_constant(X)
    run_ols(y, X, cluster=hazard_panel2["agency_id"],
            label_section="A_hazard", label_model=f"hazard_LPM",
            label_outcome="adopted_this_year", note=pname)

# A2b: Post-2020 interaction (George Floyd effect)
hazard_panel2["lag_police_x_post2020"] = (
    hazard_panel2["lag_log_police_protests"] * hazard_panel2["post_2020"])

y = hazard_panel2["adopted_this_year"]
X = hazard_panel2[["lag_log_police_protests", "post_2020",
                    "lag_police_x_post2020", "log_population",
                    "pct_black", "pct_hispanic"] + yr_cols].copy()
X = sm.add_constant(X)
run_ols(y, X, cluster=hazard_panel2["agency_id"],
        label_section="A_hazard", label_model="hazard_interaction",
        label_outcome="adopted_this_year",
        note="protests × post-2020")

###############################################################################
# PART B: Event study — do protests and trends shift around COA creation?
###############################################################################
print("\n" + "=" * 70)
print("PART B: Event Study — Protests and Search Interest around COA Creation")
print("=" * 70)

# Restrict to treated cities with relative_time
treated_data = merged[merged["treated"] == 1].copy()
treated_data["rt"] = treated_data["relative_time"]
treated_data = treated_data.dropna(subset=["rt"])
treated_data["rt"] = treated_data["rt"].astype(int)

# Restrict to window [-4, +4]
window = treated_data[(treated_data["rt"] >= -4) & (treated_data["rt"] <= 4)]
print(f"  Event-study window: {len(window):,} obs, "
      f"{window['agency_id'].nunique()} treated cities")

# B1: Raw event-study means
print("\n  B1: Raw means by relative time")
es_means = window.groupby("rt").agg(
    n_obs=("agency_id", "size"),
    mean_police_protests=("n_police_protests", "mean"),
    mean_all_protests=("n_protests", "mean"),
    mean_msa_police_protests=("msa_n_police_protests", "mean"),
    median_police_protests=("n_police_protests", "median"),
).reset_index()
print(es_means.to_string(index=False))

for _, row in es_means.iterrows():
    for col in ["mean_police_protests", "mean_all_protests",
                "mean_msa_police_protests"]:
        add_result("B_event_study", "raw_means", col, f"rt={int(row['rt'])}",
                   row[col], 0, 0, int(row["n_obs"]),
                   "descriptive mean by relative time")

# B2: DiD event-study regression
# Create relative time dummies (omit rt=-1 as reference)
print("\n  B2: Event-study regression (city FE + year FE)")

# Need control group too
es_data = merged.copy()
es_data["rt"] = es_data["relative_time"]
# For control cities, rt is NaN — they serve as comparison in all years

# Create rt dummies for treated
for t in range(-4, 5):
    if t == -1:
        continue
    es_data[f"rt_{t}"] = ((es_data["rt"] == t)).astype(int)

rt_dummies = [f"rt_{t}" for t in range(-4, 5) if t != -1]

for outcome, oname in [
    ("n_police_protests", "police_protests"),
    ("log_police_protests", "log_police_protests"),
    ("msa_n_police_protests", "msa_police_protests"),
    ("n_protests", "all_protests"),
]:
    y = es_data[outcome]
    X = es_data[rt_dummies + yr_cols].copy()

    # Add city fixed effects via demeaning
    # Use within-transformation
    city_means = es_data.groupby("agency_id")[outcome].transform("mean")
    y_dm = y - city_means

    year_means = es_data.groupby("year")[outcome].transform("mean")
    overall_mean = y.mean()

    # Simple approach: FE via dummies would be too many.
    # Use city-demeaned outcome with year FEs
    X = sm.add_constant(es_data[rt_dummies + yr_cols])

    mask = y_dm.notna() & X.notna().all(axis=1)
    if mask.sum() < 20:
        continue

    try:
        model = sm.OLS(y_dm[mask], X[mask]).fit(
            cov_type="cluster",
            cov_kwds={"groups": es_data.loc[mask, "agency_id"]})
        for t in range(-4, 5):
            if t == -1:
                continue
            var = f"rt_{t}"
            add_result("B_event_study", "FE_regression", oname, var,
                       model.params[var], model.bse[var],
                       model.pvalues[var], int(model.nobs),
                       "city-demeaned, year FE, cluster city")
    except Exception as e:
        print(f"  Event study regression failed for {oname}: {e}")

# B3: Simple DiD — pre vs post COA creation
print("\n  B3: Simple DiD — pre vs post COA creation on protests")

merged["post_coa"] = (
    (merged["treated"] == 1) &
    (merged["year"] >= merged["treatment_year"])
).astype(int)

for outcome, oname in [
    ("n_police_protests", "police_protests"),
    ("log_police_protests", "log_police_protests"),
    ("msa_n_police_protests", "msa_police_protests"),
    ("police_protests_pc", "police_protests_pc"),
]:
    y = merged[outcome]
    X = merged[["post_coa", "log_population", "pct_black",
                 "pct_hispanic"] + yr_cols].copy()
    X = sm.add_constant(X)

    # City-demean
    city_mean = merged.groupby("agency_id")[outcome].transform("mean")
    y_dm = y - city_mean

    mask = y_dm.notna() & X.notna().all(axis=1)
    if mask.sum() < 20:
        continue

    try:
        model = sm.OLS(y_dm[mask], X[mask]).fit(
            cov_type="cluster",
            cov_kwds={"groups": merged.loc[mask, "agency_id"]})
        add_result("B_did", "FE_post_coa", oname, "post_coa",
                   model.params["post_coa"], model.bse["post_coa"],
                   model.pvalues["post_coa"], int(model.nobs),
                   "city FE + year FE + controls")
    except Exception as e:
        print(f"  DiD failed for {oname}: {e}")

###############################################################################
# PART C: Google Trends Analysis (if data available)
###############################################################################
print("\n" + "=" * 70)
print("PART C: Google Trends DMA-Level Analysis")
print("=" * 70)

ts_path = os.path.join(base_dir, "raw_data/google_trends_national_timeseries.tsv")
dma_path = os.path.join(base_dir, "raw_data/google_trends_dma_crosssection.tsv")

trends_available = False

# C1: National time series
if os.path.exists(ts_path):
    trends_ts = pd.read_csv(ts_path, sep="\t")
    print(f"\n  National time series: {len(trends_ts):,} rows, "
          f"{trends_ts['term'].nunique()} terms")
    print(f"  Date range: {trends_ts['date'].min()} to {trends_ts['date'].max()}")

    # Create national yearly averages
    trends_ts["date_parsed"] = pd.to_datetime(trends_ts["date"])
    trends_ts["year"] = trends_ts["date_parsed"].dt.year

    yearly_trends = trends_ts.groupby(["term", "year"]).agg(
        mean_interest=("interest", "mean"),
        max_interest=("interest", "max"),
    ).reset_index()

    # Pivot to wide for merging
    trends_wide = yearly_trends.pivot_table(
        index="year", columns="term", values="mean_interest"
    ).reset_index()
    trends_wide.columns = ["year"] + [
        f"gtrend_{c.replace(' ', '_')}" for c in trends_wide.columns[1:]
    ]

    # Merge with panel
    merged = merged.merge(trends_wide, on="year", how="left")
    trends_available = True

    # Summary stats
    print("\n  National yearly search interest:")
    for term in yearly_trends["term"].unique():
        t_data = yearly_trends[yearly_trends["term"] == term]
        print(f"    {term}: {t_data['mean_interest'].mean():.1f} mean, "
              f"peak {t_data['max_interest'].max():.0f} in "
              f"{t_data.loc[t_data['max_interest'].idxmax(), 'year']}")

    for col in [c for c in merged.columns if c.startswith("gtrend_")]:
        add_result("C_trends_national", "descriptive", col, "mean",
                   merged[col].mean(), merged[col].std(), 0,
                   int(merged[col].notna().sum()), "national yearly average")
else:
    print("  National time series not found — skipping")

# C2: DMA cross-section
if os.path.exists(dma_path):
    trends_dma = pd.read_csv(dma_path, sep="\t")
    print(f"\n  DMA cross-section: {len(trends_dma):,} rows")

    # Try to match DMAs to MSAs by name
    if "geoName" in trends_dma.columns:
        # DMA names look like "New York NY", "Los Angeles CA"
        # MSA names look like "New York-Newark-Jersey City, NY-NJ-PA"
        # Simple approach: extract primary city from DMA name
        trends_dma["dma_city"] = trends_dma["geoName"].str.extract(
            r"^(.+?)\s+[A-Z]{2}$")[0].str.lower().str.strip()
        trends_dma["dma_state"] = trends_dma["geoName"].str.extract(
            r"\s+([A-Z]{2})$")[0].str.lower().str.strip()

        # Pivot to wide: one row per DMA with all terms as columns
        dma_wide = trends_dma.pivot_table(
            index=["geoName", "dma_city", "dma_state"],
            columns="term",
            values="interest",
            aggfunc="first"
        ).reset_index()
        dma_wide.columns = [
            c if not isinstance(c, str) or c in ["geoName", "dma_city", "dma_state"]
            else f"dma_{c.replace(' ', '_')}"
            for c in dma_wide.columns
        ]

        # Match to panel cities
        merged = merged.merge(
            dma_wide,
            left_on=["city_clean_merge", "state_clean_merge"],
            right_on=["dma_city", "dma_state"],
            how="left"
        )

        dma_matched = merged.filter(like="dma_").notna().any(axis=1).sum()
        print(f"  DMA-matched observations: {dma_matched}")

        # Models: DMA search interest predicting COA adoption
        dma_interest_cols = [c for c in merged.columns
                             if c.startswith("dma_") and c not in
                             ["dma_city", "dma_state"]]
        if dma_interest_cols:
            for col in dma_interest_cols:
                if merged[col].notna().sum() > 20:
                    # Cross-sectional: does DMA-level search predict COA?
                    y = merged.groupby("agency_id")["treated"].first()
                    x = merged.groupby("agency_id")[col].first()
                    df_cs = pd.DataFrame({"treated": y, col: x}).dropna()
                    if len(df_cs) > 10:
                        X_cs = sm.add_constant(df_cs[[col]])
                        mod = sm.OLS(df_cs["treated"], X_cs).fit(cov_type="HC1")
                        add_result("C_trends_dma", "cross_section_LPM",
                                   "ever_adopted", col,
                                   mod.params[col], mod.bse[col],
                                   mod.pvalues[col], int(mod.nobs),
                                   "DMA search interest -> COA adoption")
    trends_available = True
else:
    print("  DMA cross-section not found — skipping")

# C3: Trends as predictors of COA adoption (if available)
if trends_available:
    print("\n  C3: National Google Trends predicting COA adoption")

    gtrend_cols = [c for c in merged.columns if c.startswith("gtrend_")]
    if gtrend_cols:
        # Lagged trends
        merged = merged.sort_values(["agency_id", "year"])
        for col in gtrend_cols:
            merged[f"lag_{col}"] = merged.groupby("agency_id")[col].shift(1)

        lag_trend_cols = [f"lag_{c}" for c in gtrend_cols]

        # Use first available trend as predictor in hazard model
        for tcol in lag_trend_cols[:2]:
            y = hazard_panel2["adopted_this_year"]
            # Re-merge trends into hazard panel
            hazard_with_trends = hazard_panel2.merge(
                merged[["agency_id", "year", tcol]].drop_duplicates(),
                on=["agency_id", "year"], how="left"
            )
            X = hazard_with_trends[[tcol, "log_population", "pct_black",
                                     "pct_hispanic"] + yr_cols].copy()
            X = sm.add_constant(X)
            y = hazard_with_trends["adopted_this_year"]
            run_ols(y, X, cluster=hazard_with_trends["agency_id"],
                    label_section="C_trends_hazard",
                    label_model="hazard_trends",
                    label_outcome="adopted_this_year",
                    note=f"lagged national {tcol}")

###############################################################################
# PART D: Combined models — protests + trends + demographics
###############################################################################
print("\n" + "=" * 70)
print("PART D: Combined Prediction Models")
print("=" * 70)

# D1: Full cross-sectional model with protests + demographics
print("\n  D1: Full cross-sectional model — COA adoption predictors")

# Re-construct cross-sectional dataset with protest data
cs_data = city_protests_pre.copy()

# Add 2020 protest intensity (the George Floyd spike year)
protests_2020 = merged[merged["year"] == 2020].groupby("agency_id").agg(
    police_protests_2020=("n_police_protests", "sum"),
    msa_police_protests_2020=("msa_n_police_protests", "sum"),
).reset_index()
cs_data = cs_data.merge(protests_2020, on="agency_id", how="left")
cs_data["police_protests_2020"] = cs_data["police_protests_2020"].fillna(0)
cs_data["log_police_protests_2020"] = np.log1p(cs_data["police_protests_2020"])

# Full model
for outcome_name, outcome_var in [("adopted_post2019", "adopted_post2019"),
                                   ("ever_adopted", "ever_adopted")]:
    y = cs_data[outcome_var]
    X_vars = ["log_police_protests_pre", "log_pop", "pct_black",
              "pct_hispanic"]
    if "violent_crime_pc" in cs_data.columns:
        X_vars.append("violent_crime_pc")
    if "drug_arrests_pc" in cs_data.columns:
        X_vars.append("drug_arrests_pc")

    X = cs_data[X_vars].copy()
    mask = y.notna() & X.notna().all(axis=1)
    X_c = sm.add_constant(X[mask])
    y_c = y[mask]

    if len(y_c) > 10:
        mod = sm.OLS(y_c, X_c).fit(cov_type="HC1")
        for var in X_vars:
            add_result("D_combined", f"full_LPM_{outcome_name}",
                       outcome_name, var,
                       mod.params[var], mod.bse[var],
                       mod.pvalues[var], int(mod.nobs),
                       "full cross-section model")
        print(f"    {outcome_name}: R²={mod.rsquared:.4f}, n={int(mod.nobs)}")

# D2: 2020 protest intensity and post-2020 adoption
print("\n  D2: 2020 protest spike → post-2020 COA adoption")
y = cs_data["adopted_post2019"]
X = cs_data[["log_police_protests_2020", "log_police_protests_pre",
             "log_pop", "pct_black", "pct_hispanic"]].copy()
mask = y.notna() & X.notna().all(axis=1)
X_c = sm.add_constant(X[mask])
y_c = y[mask]
if len(y_c) > 10:
    mod = sm.OLS(y_c, X_c).fit(cov_type="HC1")
    for var in ["log_police_protests_2020", "log_police_protests_pre"]:
        add_result("D_combined", "protest_2020_effect",
                   "adopted_post2019", var,
                   mod.params[var], mod.bse[var],
                   mod.pvalues[var], int(mod.nobs),
                   "2020 protest spike + pre-period protests")
    print(f"    R²={mod.rsquared:.4f}, n={int(mod.nobs)}")
    print(f"    2020 protests coef: {mod.params['log_police_protests_2020']:.4f} "
          f"(p={mod.pvalues['log_police_protests_2020']:.4f})")
    print(f"    Pre protests coef: {mod.params['log_police_protests_pre']:.4f} "
          f"(p={mod.pvalues['log_police_protests_pre']:.4f})")

###############################################################################
# PART E: Summary statistics and protest descriptives
###############################################################################
print("\n" + "=" * 70)
print("PART E: Descriptive Statistics")
print("=" * 70)

# E1: Protest activity by treated vs control
print("\n  E1: Protest activity — treated vs control cities")
for grp_name, grp_val in [("Treated", 1), ("Control", 0)]:
    grp = merged[merged["treated"] == grp_val]
    for var in ["n_police_protests", "n_protests", "msa_n_police_protests"]:
        vals = grp[var].dropna()
        add_result("E_descriptives", f"mean_{grp_name}", var, "mean",
                   vals.mean(), vals.std(), 0, len(vals))
    print(f"  {grp_name}: "
          f"mean police protests = {grp['n_police_protests'].mean():.2f}, "
          f"all protests = {grp['n_protests'].mean():.2f}")

# E2: National protest time series by year
print("\n  E2: National protest counts by year")
yearly = ccc.groupby("year").agg(
    total_events=("date", "size"),
    police_events=("police_related", "sum"),
).reset_index()
for _, row in yearly.iterrows():
    add_result("E_national_trends", "yearly_counts",
               "total_protests", str(int(row["year"])),
               row["total_events"], 0, 0, int(row["total_events"]))
    add_result("E_national_trends", "yearly_counts",
               "police_protests", str(int(row["year"])),
               row["police_events"], 0, 0, int(row["police_events"]))
print(yearly.to_string(index=False))

###############################################################################
# Save results
###############################################################################
print("\n" + "=" * 70)
print("Saving Results")
print("=" * 70)

results_df = pd.DataFrame(results)
out_path = os.path.join(output_dir, "tables/blm_protests_trends_analysis.tsv")
results_df.to_csv(out_path, sep="\t", index=False)
print(f"\nSaved {len(results_df)} result rows to {out_path}")

# Also save the MSA-year protest aggregation
msa_out = os.path.join(output_dir, "tables/msa_year_protests.tsv")
msa_year_all.to_csv(msa_out, sep="\t", index=False)
print(f"Saved MSA-year protests to {msa_out}")

# Save event study means
es_out = os.path.join(output_dir, "tables/protest_event_study_means.tsv")
es_means.to_csv(es_out, sep="\t", index=False)
print(f"Saved event study means to {es_out}")

# Print key findings
print("\n" + "=" * 70)
print("KEY FINDINGS")
print("=" * 70)

key_results = results_df[
    (results_df["section"].isin(["A_cross_section", "A_hazard",
                                  "B_did", "D_combined"])) &
    (~results_df["variable"].str.startswith("yr_")) &
    (results_df["variable"] != "const")
].copy()

key_results["sig"] = key_results["pval"].apply(
    lambda p: "***" if p < 0.01 else ("**" if p < 0.05 else
              ("*" if p < 0.1 else ""))
)

if len(key_results) > 0:
    print(key_results[["section", "model", "outcome", "variable",
                        "coef", "se", "pval", "sig", "n"]
                       ].to_string(index=False))

print("\nDone!")
