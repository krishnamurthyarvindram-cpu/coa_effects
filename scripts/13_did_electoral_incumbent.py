##############################################################################
# 13_did_electoral_incumbent.py
# DiD Analysis: Electoral Effects of COA Creation on Incumbent Politicians
#
# Research question: Do incumbent politicians (city councilors and mayors) who
# were in office when a COA was created see an electoral boost (higher vote
# share) compared to incumbents in cities where no COA status change occurred?
#
# Design:
#   - Unit of analysis: candidate (within-candidate panel via candidate FE)
#   - Treatment: indicator = 1 for elections in which the incumbent is running
#     for re-election AND a COA was created during their current term
#   - Control: incumbents running in cities with no change in COA status
#   - FEs: candidate fixed effects + year fixed effects
#   - Sample: city councilors and mayors only, incumbents only
#   - Outcome: vote_share
#   - Clustering: at the city (geo_name × state) level
##############################################################################

import os
import warnings
import numpy as np
import pandas as pd
import statsmodels.api as sm
from linearmodels.panel import PanelOLS

warnings.filterwarnings("ignore")

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")
os.makedirs(os.path.join(output_dir, "tables"), exist_ok=True)
os.makedirs(os.path.join(output_dir, "figures"), exist_ok=True)

print("=" * 70)
print("DiD Analysis: Electoral Effects of COA Creation on Incumbents")
print("=" * 70)

# ── 1. Load data ─────────────────────────────────────────────────────────────

ledb = pd.read_csv(os.path.join(base_dir, "raw_data/ledb_candidatelevel.csv"),
                    low_memory=False)
coa = pd.read_csv(os.path.join(base_dir, "raw_data/coa_creation_data.csv"))

print(f"\nRaw LEDB data: {ledb.shape[0]:,} rows, {ledb.shape[1]} cols")
print(f"Raw COA data:  {coa.shape[0]:,} rows, {coa.shape[1]} cols")

# ── 2. Clean COA data ────────────────────────────────────────────────────────

coa.columns = [
    "ORI", "city_num", "city_raw", "state_raw", "population", "state_abb",
    "has_oversight_board", "oversight_powers", "charter_found", "link",
    "year_created", "can_investigate", "can_discipline",
    "created_via_election", "selection_method"
]

# Clean year_created to numeric
coa["year_created_num"] = pd.to_numeric(
    coa["year_created"].astype(str).str.strip().str.replace(r"\(\?\)", "", regex=True),
    errors="coerce"
)

# Clean has_oversight_board
coa["has_board"] = coa["has_oversight_board"].str.strip().str.upper() == "Y"

# Standardize city names in COA
def clean_coa_city(name):
    s = str(name).lower().strip()
    # Remove common suffixes
    for suffix in [
        " metropolitan government (balance)",
        " consolidated government (balance)",
        " unified government (balance)",
        " (balance)", " municipality", " urban county",
        " city", " town", " village", " borough", " cdp"
    ]:
        s = s.replace(suffix, "")
    # Fix concatenated names
    replacements = {
        "kansascity": "kansas city",
        "oklahomacity": "oklahoma city",
        "jerseycity": "jersey city",
        "boisecity": "boise city",
        "salt lakecity": "salt lake city",
        "west valleycity": "west valley city",
    }
    for old, new in replacements.items():
        s = s.replace(old, new)
    # Fix hyphenated / combined names to match LEDB
    name_map = {
        "nashville-davidson": "nashville-davidson county",
        "louisville/jefferson county metro government": "louisville",
        "lexington-fayette": "lexington-fayette county",
        "augusta-richmond county": "augusta-richmond county",
        "macon-bibb county": "macon",
        "urban honolulu": "honolulu",
        "athens-clarke county unified government": "athens",
    }
    for old, new in name_map.items():
        if s == old:
            s = new
    s = s.strip()
    return s

coa["city_clean"] = coa["city_raw"].apply(clean_coa_city)

# Fix state abbreviations
state_fixes = {"NB": "NE", "OAKLAND": "CA", "LO": "LA"}
coa["state_clean"] = coa["state_abb"].str.strip().str.upper().replace(state_fixes)

# Fill missing states from state_raw
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
        state_full = row["state_raw"]
        if state_full in state_name_to_abb:
            coa.at[idx, "state_clean"] = state_name_to_abb[state_full]

# Keep one row per city-state (earliest treatment year)
coa = coa.sort_values("year_created_num", na_position="last")
coa = coa.drop_duplicates(subset=["city_clean", "state_clean"], keep="first")

print(f"\nCleaned COA data: {len(coa)} unique cities")
print(f"  With COA (has_board=True): {coa['has_board'].sum()}")
print(f"  With valid creation year:  {coa['year_created_num'].notna().sum()}")

# ── 3. Clean LEDB data ───────────────────────────────────────────────────────

# Filter to city councilors and mayors only
ledb = ledb[ledb["office_consolidated"].isin(["City Council", "Mayor"])].copy()
print(f"\nLEDB after filtering to City Council + Mayor: {len(ledb):,} rows")
print(f"  City Council: {(ledb['office_consolidated'] == 'City Council').sum():,}")
print(f"  Mayor:        {(ledb['office_consolidated'] == 'Mayor').sum():,}")

# Clean geo_name and state
ledb["geo_clean"] = ledb["geo_name"].str.lower().str.strip()
ledb["state_clean"] = ledb["state_abb"].str.upper().str.strip()

# ── 4. Merge COA onto LEDB ───────────────────────────────────────────────────

merged = pd.merge(
    ledb,
    coa[["city_clean", "state_clean", "year_created_num", "has_board"]],
    left_on=["geo_clean", "state_clean"],
    right_on=["city_clean", "state_clean"],
    how="left",
    indicator=True
)

print(f"\nMerge results:")
print(merged["_merge"].value_counts().to_string())

# Cities that matched get their COA info; unmatched cities are not in the COA
# dataset at all — we treat them as never-treated (no COA).
merged["has_coa"] = (merged["_merge"] == "both") & (merged["has_board"] == True)
merged["coa_year"] = merged["year_created_num"]  # NaN for cities not in COA data

# Drop the merge indicator
merged.drop(columns=["_merge", "city_clean"], inplace=True)

n_in_coa = merged["has_coa"].sum()
print(f"\nMerged dataset: {len(merged):,} candidate-election observations")
print(f"  In COA city w/ board: {n_in_coa:,}")
print(f"  Other:                {len(merged) - n_in_coa:,}")

# ── 5. Build candidate panel and identify incumbents running again ────────────

# We need to identify incumbents: candidate appears in election t as incumbent,
# and we want to track their vote_share across elections.
# The 'incumbent' field flags whether a candidate is an incumbent in that race.

# Keep only rows with valid vote_share
merged = merged[merged["vote_share"].notna() & (merged["vote_share"] > 0)].copy()
print(f"\nAfter dropping missing/zero vote_share: {len(merged):,}")

# Create a candidate identifier
# Use bonica.cid where available (unique donor/candidate ID), else full_name + geo + state
merged["cand_id"] = merged["bonica.cid"].astype(str)
no_id_mask = (merged["bonica.cid"].isna())
merged.loc[no_id_mask, "cand_id"] = (
    merged.loc[no_id_mask, "full_name"].astype(str) + "_" +
    merged.loc[no_id_mask, "geo_clean"].astype(str) + "_" +
    merged.loc[no_id_mask, "state_clean"].astype(str)
)

# Keep only incumbents (incumbent == 1)
incumbents = merged[merged["incumbent"] == 1.0].copy()
print(f"\nIncumbent observations: {len(incumbents):,}")
print(f"  Unique candidates:   {incumbents['cand_id'].nunique():,}")
print(f"  City Council:        {(incumbents['office_consolidated'] == 'City Council').sum():,}")
print(f"  Mayor:               {(incumbents['office_consolidated'] == 'Mayor').sum():,}")

# ── 6. Construct treatment variable ──────────────────────────────────────────
# Treatment = 1 if a COA was created while this incumbent was in office
# i.e., the COA was created BETWEEN the previous election and the current one
# (which means: during the incumbent's current term).
#
# For an incumbent running in year t, their term started when they last won.
# We approximate term start as the previous election year for that candidate.
# If coa_year falls in (prev_election_year, current_election_year], treatment=1.

# Sort by candidate and year to get previous election year
incumbents = incumbents.sort_values(["cand_id", "year"])

# Get previous election year for each candidate
incumbents["prev_year"] = incumbents.groupby("cand_id")["year"].shift(1)

# For incumbents' first appearance, approximate term start as election year - 4
# (common term length for mayors/councils). This is conservative.
incumbents["term_start"] = incumbents["prev_year"]
first_mask = incumbents["term_start"].isna()
incumbents.loc[first_mask, "term_start"] = incumbents.loc[first_mask, "year"] - 4

# Treatment: COA created during the incumbent's current term
# coa_year in (term_start, year]
incumbents["coa_created_during_term"] = (
    incumbents["coa_year"].notna() &
    (incumbents["coa_year"] > incumbents["term_start"]) &
    (incumbents["coa_year"] <= incumbents["year"])
).astype(int)

# Broader treatment: COA exists at time of election (created on or before election year)
incumbents["coa_exists"] = (
    incumbents["coa_year"].notna() &
    (incumbents["coa_year"] <= incumbents["year"])
).astype(int)

# Post-treatment: election is AFTER COA creation (for cities that eventually get one)
incumbents["post_coa"] = (
    incumbents["coa_year"].notna() &
    (incumbents["year"] >= incumbents["coa_year"])
).astype(int)

print(f"\n--- Treatment variable summary ---")
print(f"COA created during incumbent's term (main treatment):")
print(incumbents["coa_created_during_term"].value_counts().to_string())
print(f"\nCOA exists at election time:")
print(incumbents["coa_exists"].value_counts().to_string())

# ── 7. Define analysis samples ───────────────────────────────────────────────

# For the DiD we need within-candidate variation. Keep candidates with 2+ obs.
cand_counts = incumbents.groupby("cand_id").size()
multi_obs = cand_counts[cand_counts >= 2].index
panel = incumbents[incumbents["cand_id"].isin(multi_obs)].copy()

print(f"\nPanel (candidates with 2+ observations): {len(panel):,} obs")
print(f"  Unique candidates: {panel['cand_id'].nunique():,}")

# Create city identifier for clustering
panel["city_id"] = panel["geo_clean"].astype(str) + "_" + panel["state_clean"].astype(str)

# Encode candidate and year for fixed effects
panel["cand_fe"] = pd.Categorical(panel["cand_id"]).codes
panel["year_fe"] = pd.Categorical(panel["year"]).codes

print(f"  Year range: {panel['year'].min()} – {panel['year'].max()}")
print(f"  Unique cities: {panel['city_id'].nunique()}")

# ── 8. Estimate DiD models ───────────────────────────────────────────────────

results_list = []


def run_ols_fe(data, treatment_var, label, sample_label="All"):
    """
    Estimate within-candidate DiD with year FEs using PanelOLS.
    vote_share_it = alpha_i + gamma_t + beta * Treatment_it + epsilon_it
    """
    df = data[["vote_share", treatment_var, "cand_id", "year", "city_id"]].dropna().copy()

    if df[treatment_var].nunique() < 2:
        print(f"  [{label}] Skipping: no variation in treatment")
        return None

    # Set panel index
    df = df.reset_index(drop=True)
    df["obs_id"] = range(len(df))
    df = df.set_index(["cand_id", "year"])

    # PanelOLS: entity (candidate) + time (year) FEs
    mod = PanelOLS(
        dependent=df["vote_share"],
        exog=df[[treatment_var]],
        entity_effects=True,
        time_effects=True,
        check_rank=False
    )

    # Cluster SEs at city level
    try:
        res = mod.fit(cov_type="clustered", cluster_entity=False,
                      clusters=df["city_id"])
    except Exception:
        # Fallback: cluster at entity level
        res = mod.fit(cov_type="clustered", cluster_entity=True)

    beta = res.params[treatment_var]
    se = res.std_errors[treatment_var]
    t_stat = res.tstats[treatment_var]
    p_val = res.pvalues[treatment_var]
    ci_low, ci_high = beta - 1.96 * se, beta + 1.96 * se
    n_obs = int(res.nobs)
    n_cand = df.index.get_level_values(0).nunique()
    n_treated = int(df[treatment_var].sum())

    print(f"\n  [{label} | {sample_label}]")
    print(f"    beta  = {beta:.5f}  (SE = {se:.5f})")
    print(f"    t     = {t_stat:.3f},  p = {p_val:.4f}")
    print(f"    95% CI: [{ci_low:.5f}, {ci_high:.5f}]")
    print(f"    N obs = {n_obs:,}, N candidates = {n_cand:,}, N treated = {n_treated:,}")

    stars = ""
    if p_val < 0.01:
        stars = "***"
    elif p_val < 0.05:
        stars = "**"
    elif p_val < 0.10:
        stars = "*"

    result = {
        "model": label,
        "sample": sample_label,
        "treatment_var": treatment_var,
        "beta": round(beta, 6),
        "se": round(se, 6),
        "t_stat": round(t_stat, 3),
        "p_value": round(p_val, 4),
        "ci_lower": round(ci_low, 6),
        "ci_upper": round(ci_high, 6),
        "significance": stars,
        "n_obs": n_obs,
        "n_candidates": n_cand,
        "n_treated_obs": n_treated,
        "candidate_fe": "Yes",
        "year_fe": "Yes",
    }
    results_list.append(result)
    return res


print("\n" + "=" * 70)
print("MODEL ESTIMATES")
print("=" * 70)

# ── Model 1: Main treatment – COA created during incumbent's term ─────────
print("\n── Model 1: COA Created During Term ──")
run_ols_fe(panel, "coa_created_during_term",
           "COA Created During Term", "All Incumbents")

# ── Model 2: Post-COA indicator (broader) ─────────────────────────────────
print("\n── Model 2: Post-COA (COA Exists at Election) ──")
run_ols_fe(panel, "post_coa",
           "Post-COA", "All Incumbents")

# ── Model 3: By office type ──────────────────────────────────────────────
print("\n── Model 3: By Office Type ──")
for office in ["City Council", "Mayor"]:
    sub = panel[panel["office_consolidated"] == office]
    if len(sub) > 50:
        run_ols_fe(sub, "coa_created_during_term",
                   "COA Created During Term", office)

# ── Model 4: COA created during term, by office (post-COA) ───────────────
print("\n── Model 4: Post-COA by Office Type ──")
for office in ["City Council", "Mayor"]:
    sub = panel[panel["office_consolidated"] == office]
    if len(sub) > 50:
        run_ols_fe(sub, "post_coa",
                   "Post-COA", office)

# ── Model 5: Winners vs. all (did creating COA help win?) ────────────────
print("\n── Model 5: Win indicator as outcome ──")
panel["win"] = (panel["winner"] == "win").astype(int)


def run_ols_fe_outcome(data, treatment_var, outcome_var, label, sample_label="All"):
    """Run PanelOLS with a flexible outcome."""
    df = data[[outcome_var, treatment_var, "cand_id", "year", "city_id"]].dropna().copy()

    if df[treatment_var].nunique() < 2:
        print(f"  [{label}] Skipping: no variation in treatment")
        return None

    df = df.reset_index(drop=True)
    df = df.set_index(["cand_id", "year"])

    mod = PanelOLS(
        dependent=df[outcome_var],
        exog=df[[treatment_var]],
        entity_effects=True,
        time_effects=True,
        check_rank=False
    )

    try:
        res = mod.fit(cov_type="clustered", cluster_entity=False,
                      clusters=df["city_id"])
    except Exception:
        res = mod.fit(cov_type="clustered", cluster_entity=True)

    beta = res.params[treatment_var]
    se = res.std_errors[treatment_var]
    t_stat = res.tstats[treatment_var]
    p_val = res.pvalues[treatment_var]
    ci_low, ci_high = beta - 1.96 * se, beta + 1.96 * se
    n_obs = int(res.nobs)
    n_cand = df.index.get_level_values(0).nunique()
    n_treated = int(df[treatment_var].sum())

    print(f"\n  [{label} | {sample_label}]")
    print(f"    beta  = {beta:.5f}  (SE = {se:.5f})")
    print(f"    t     = {t_stat:.3f},  p = {p_val:.4f}")
    print(f"    95% CI: [{ci_low:.5f}, {ci_high:.5f}]")
    print(f"    N obs = {n_obs:,}, N candidates = {n_cand:,}, N treated = {n_treated:,}")

    stars = ""
    if p_val < 0.01:
        stars = "***"
    elif p_val < 0.05:
        stars = "**"
    elif p_val < 0.10:
        stars = "*"

    result = {
        "model": label,
        "sample": sample_label,
        "treatment_var": treatment_var,
        "outcome": outcome_var,
        "beta": round(beta, 6),
        "se": round(se, 6),
        "t_stat": round(t_stat, 3),
        "p_value": round(p_val, 4),
        "ci_lower": round(ci_low, 6),
        "ci_upper": round(ci_high, 6),
        "significance": stars,
        "n_obs": n_obs,
        "n_candidates": n_cand,
        "n_treated_obs": n_treated,
        "candidate_fe": "Yes",
        "year_fe": "Yes",
    }
    results_list.append(result)
    return res


run_ols_fe_outcome(panel, "coa_created_during_term", "win",
                   "COA Created During Term → Win", "All Incumbents")

run_ols_fe_outcome(panel, "post_coa", "win",
                   "Post-COA → Win", "All Incumbents")

# ── 9. Summary statistics ────────────────────────────────────────────────────

print("\n" + "=" * 70)
print("SUMMARY STATISTICS")
print("=" * 70)

# Cities in the panel
print(f"\nPanel overview:")
print(f"  Total observations:   {len(panel):,}")
print(f"  Unique candidates:    {panel['cand_id'].nunique():,}")
print(f"  Unique cities:        {panel['city_id'].nunique():,}")
print(f"  Year range:           {panel['year'].min()} – {panel['year'].max()}")
print(f"\n  Office breakdown:")
print(panel["office_consolidated"].value_counts().to_string())

# Treatment summary
print(f"\n  Treatment (COA created during term):")
treated_panel = panel[panel["coa_created_during_term"] == 1]
control_panel = panel[panel["coa_created_during_term"] == 0]
print(f"    Treated obs:  {len(treated_panel):,}")
print(f"    Control obs:  {len(control_panel):,}")
print(f"    Treated candidates: {treated_panel['cand_id'].nunique():,}")
print(f"    Control candidates: {control_panel['cand_id'].nunique():,}")

# Vote share by treatment
print(f"\n  Mean vote share:")
print(f"    Treated:  {treated_panel['vote_share'].mean():.4f}")
print(f"    Control:  {control_panel['vote_share'].mean():.4f}")
print(f"    Diff:     {treated_panel['vote_share'].mean() - control_panel['vote_share'].mean():.4f}")

# Win rate by treatment
print(f"\n  Win rate:")
t_win = (treated_panel["winner"] == "win").mean()
c_win = (control_panel["winner"] == "win").mean()
print(f"    Treated:  {t_win:.4f}")
print(f"    Control:  {c_win:.4f}")
print(f"    Diff:     {t_win - c_win:.4f}")

# ── 10. Save results ─────────────────────────────────────────────────────────

results_df = pd.DataFrame(results_list)
results_path = os.path.join(output_dir, "tables", "did_electoral_incumbent.tsv")
results_df.to_csv(results_path, index=False, sep="\t")
print(f"\nResults saved to: {results_path}")

# Print final results table
print("\n" + "=" * 70)
print("RESULTS TABLE")
print("=" * 70)
display_cols = ["model", "sample", "beta", "se", "p_value", "significance",
                "n_obs", "n_candidates", "n_treated_obs"]
existing_cols = [c for c in display_cols if c in results_df.columns]
print(results_df[existing_cols].to_string(index=False))

# ── 11. Save summary stats table ─────────────────────────────────────────────

summary_rows = []
for grp_name, grp_data in [("All", panel),
                            ("City Council", panel[panel["office_consolidated"] == "City Council"]),
                            ("Mayor", panel[panel["office_consolidated"] == "Mayor"])]:
    for trt_name, trt_val in [("Control", 0), ("Treated", 1)]:
        sub = grp_data[grp_data["coa_created_during_term"] == trt_val]
        if len(sub) == 0:
            continue
        summary_rows.append({
            "sample": grp_name,
            "group": trt_name,
            "n_obs": len(sub),
            "n_candidates": sub["cand_id"].nunique(),
            "n_cities": sub["city_id"].nunique(),
            "mean_vote_share": round(sub["vote_share"].mean(), 4),
            "sd_vote_share": round(sub["vote_share"].std(), 4),
            "win_rate": round((sub["winner"] == "win").mean(), 4),
            "mean_year": round(sub["year"].mean(), 1),
        })

summary_df = pd.DataFrame(summary_rows)
summary_path = os.path.join(output_dir, "tables", "did_electoral_summary_stats.tsv")
summary_df.to_csv(summary_path, index=False, sep="\t")
print(f"\nSummary stats saved to: {summary_path}")
print(summary_df.to_string(index=False))

print("\n" + "=" * 70)
print("Analysis complete.")
print("=" * 70)
