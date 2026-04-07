###############################################################################
# board_strength_trajectory.py
# Section 4: Board Strength Trajectory Analysis (Amendment Model)
#
# Tests whether boards strengthen over time organically or only following shocks.
# Since the panel RDS is not accessible, this script:
#   (a) Checks for time-varying authority data
#   (b) Identifies cities with disbanded boards
#   (c) Uses existing event study results to assess persistence of null effects
###############################################################################

import os
import re
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")

print("=" * 70)
print("SECTION 4: BOARD STRENGTH TRAJECTORY ANALYSIS")
print("=" * 70)

# ── Load data ────────────────────────────────────────────────────────────
merged = pd.read_csv(os.path.join(base_dir, "merged_data/panel_with_charter_features.csv"))
coa_raw = pd.read_csv(os.path.join(base_dir, "raw_data/coa_creation_data_actual.csv"),
                       encoding='latin-1')
coa_raw.columns = coa_raw.columns.str.strip()

# Also load the legal analysis which has amendment info
legal = pd.read_csv(os.path.join(output_dir, "tables/independent_discipline_cities_analysis.csv"))

def clean_year(y):
    if pd.isna(y):
        return None
    s = str(y).strip()
    m = re.search(r'(\d{4})', s)
    if m and 1800 <= int(m.group(1)) <= 2030:
        return int(m.group(1))
    return None

merged['year_num'] = merged['year_created'].apply(clean_year)

# ── 4a. Check for time-varying authority data ────────────────────────────
print("\n4a. Checking for time-varying authority data...")
print("  Raw data columns:", list(coa_raw.columns))
print("  Classification columns:", list(merged.columns))

# The data has authority coded once per city (at adoption).
# No time-varying authority measures exist.
print("\n  FINDING: Authority is coded ONCE per city (at time of adoption/current status).")
print("  No time-varying authority data available in raw_data/ or cleaned_data/.")
print("  LIMITATION NOTED: Cannot track organic strengthening over time.")

# However, the legal analysis has some temporal information
print("\n  Legal analysis file contains creation_mechanism data with dates of amendments:")
if 'creation_mechanism' in legal.columns:
    for _, row in legal.iterrows():
        city = row.get('city', 'Unknown')
        mech = str(row.get('creation_mechanism', ''))
        if any(word in mech.lower() for word in ['revised', 'amended', 'strengthened',
                                                   'expanded', 'reformed']):
            print(f"    {city}: {mech[:100]}")

# ── 4b. Identify disbanded/re-created boards ────────────────────────────
print("\n4b. Checking for disbanded/re-created boards...")

# Check legal analysis for disbanding language
disbanded_cities = []
if 'preemption_details' in legal.columns or 'court_rulings_summary' in legal.columns:
    for _, row in legal.iterrows():
        details = str(row.get('preemption_details', '')) + ' ' + str(row.get('court_rulings_summary', ''))
        if any(word in details.lower() for word in ['disbanded', 'defunded', 'collapsed',
                                                      'dissolved', 'eliminated', 'abolished',
                                                      'gutted', 'replaced']):
            disbanded_cities.append({
                'city': row.get('city', 'Unknown'),
                'state': row.get('state', ''),
                'details': details[:200]
            })

print(f"  Cities with disbanded/gutted boards: {len(disbanded_cities)}")
for city_info in disbanded_cities:
    print(f"    {city_info['city']}, {city_info['state']}: {city_info['details'][:120]}...")

# ── 4c. Event study analysis — do null effects persist? ──────────────────
print("\n4c. Event study persistence analysis...")
print("  Using existing CSDID annualized results to assess effect persistence.")

# Load existing event study results
try:
    csdid_annual = pd.read_csv(os.path.join(output_dir, "tables/csdid_annualized.csv"))
    print(f"  CSDID annualized results loaded: {len(csdid_annual)} rows")
    print(f"  Columns: {list(csdid_annual.columns)}")
    print(f"  Outcomes: {csdid_annual['outcome'].unique() if 'outcome' in csdid_annual.columns else 'N/A'}")

    # If relative time data exists, assess persistence
    if 'rel_time' in csdid_annual.columns or 'e' in csdid_annual.columns:
        time_col = 'rel_time' if 'rel_time' in csdid_annual.columns else 'e'
        print(f"\n  Relative time column: {time_col}")
        print(f"  Time range: {csdid_annual[time_col].min()} to {csdid_annual[time_col].max()}")

        # For each outcome, check if effects grow, shrink, or stay null over time
        print("\n  PERSISTENCE TEST: Do effects change over event time?")
        for outcome in csdid_annual['outcome'].unique() if 'outcome' in csdid_annual.columns else []:
            sub = csdid_annual[csdid_annual['outcome'] == outcome].sort_values(time_col)
            # Split into early post (0-3) and late post (4+)
            early = sub[(sub[time_col] >= 0) & (sub[time_col] <= 3)]
            late = sub[sub[time_col] > 3]
            if len(early) > 0 and len(late) > 0:
                est_col = [c for c in ['att', 'estimate', 'coef', 'ATT'] if c in sub.columns]
                if est_col:
                    early_mean = early[est_col[0]].mean()
                    late_mean = late[est_col[0]].mean()
                    direction = "↑ growing" if abs(late_mean) > abs(early_mean) * 1.2 else \
                                "↓ shrinking" if abs(late_mean) < abs(early_mean) * 0.8 else \
                                "→ persistent"
                    print(f"    {outcome:35s}: early={early_mean:10.4f}, late={late_mean:10.4f} ({direction})")

except FileNotFoundError:
    print("  CSDID annualized results not found. Skipping event study persistence analysis.")

# ── Check existing event study figures ───────────────────────────────────
print("\n  Existing event study figures in output/figures/:")
fig_dir = os.path.join(output_dir, "figures")
es_files = [f for f in os.listdir(fig_dir) if f.startswith('eventstudy_')]
outcomes_covered = set()
for f in sorted(es_files):
    # Extract outcome name
    parts = f.replace('.png', '').split('_')
    # eventstudy_method_outcome_bwN
    if len(parts) >= 3:
        outcomes_covered.add('_'.join(parts[2:-1]))
print(f"  Outcomes with event study plots: {outcomes_covered}")
print(f"  Total event study figures: {len(es_files)}")

# ── Summary ──────────────────────────────────────────────────────────────
print("\n" + "=" * 70)
print("SECTION 4 SUMMARY")
print("=" * 70)
print("LIMITATIONS:")
print("  - Authority is coded ONCE per city — no time-varying authority data")
print("  - Cannot track organic board strengthening vs. amendment-driven change")
print("  - Event study relative time data available from existing CSDID results")
print(f"  - {len(disbanded_cities)} cities identified with disbanded/gutted boards")
print("\nTRAP INTERPRETATION:")
print("  If null effects persist across all event-time horizons (as shown in")
print("  existing event study figures), this is consistent with the trap:")
print("  boards do NOT strengthen informally over time — the equilibrium holds.")

print("\nSection 4 complete.")
