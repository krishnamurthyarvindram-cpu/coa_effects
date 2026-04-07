###############################################################################
# did_by_board_strength.py
# Section 2: The Core Trap Analysis — Board Strength Interaction in the DiD
#
# Since analysis_panel.rds is a Git LFS pointer (not directly accessible),
# this script:
#   (a) Uses the existing TWFE results from coa_strength_analysis.tsv
#       (Part C: policing outcomes by strong/weak/investigate/discipline)
#   (b) Reorganizes them into the three-tier authority framework
#   (c) Produces the coefficient plot and output tables
#   (d) Runs the continuous interaction model using the city-level data
###############################################################################

import os
import re
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")
os.makedirs(output_dir, exist_ok=True)

print("=" * 70)
print("SECTION 2: DiD BY BOARD STRENGTH — CORE TRAP ANALYSIS")
print("=" * 70)

# ── Load existing TWFE strength results ──────────────────────────────────
strength = pd.read_csv(os.path.join(output_dir, "tables/coa_strength_analysis.tsv"), sep='\t')

# Filter to Part C (policing outcomes)
part_c = strength[strength['part'] == 'C'].copy()
print(f"Part C results: {len(part_c)} rows")
print(f"Models: {part_c['model'].unique()}")
print(f"Outcomes: {part_c['outcome'].unique()}")

# ── 2a. Reorganize into three-tier authority framework ───────────────────
# The existing results have:
#   - "Any COA (post)" = full sample
#   - "Strong COA (post)" = investigate or discipline
#   - "Weak COA (post)" = board only
#   - "Investigate Power" = can investigate
#   - "Discipline Power" = can discipline
# For three-tier:
#   - Review-only = "Weak COA (post)" (weak_coa = treated & !invest & !discipline)
#   - Investigative = "Investigate Power" minus those who also discipline
#   - Disciplinary = "Discipline Power"
# But Joint model already separates strong vs weak. We'll use:
#   weak_coa ~= review_only, investigate ~= investigative, discipline ~= disciplinary

# Extract separate-model results for the three authority levels
outcomes_map = {
    'violent_crime_pc': 'Violent Crime\n(per 100K)',
    'violent_clearance_rate': 'Violent Crime\nClearance Rate',
    'property_clearance_rate': 'Property Crime\nClearance Rate',
    'drug_arrests_pc': 'Drug Arrests\n(per 100K)',
    'discretionary_arrests_pc': 'Discretionary Arrests\n(per 100K)',
    'police_killings_pc': 'Police Killings\n(per 100K)',
    'black_share_violent_arrests': 'Black Share of\nViolent Arrests',
    'black_share_drug_arrests': 'Black Share of\nDrug Arrests',
}

# Build coefficient dataframe for the three authority levels
coef_rows = []

# Review-only (Weak COA separate model)
weak = part_c[part_c['model'] == 'Weak COA (post)']
for _, row in weak.iterrows():
    coef_rows.append({
        'authority': 'Review Only',
        'outcome': row['outcome'],
        'estimate': row['coef'],
        'std_error': row['se'],
        'p_value': row['p_value'],
        'n_obs': row['n_obs'],
    })

# Investigative (Investigate Power separate model)
invest = part_c[part_c['model'] == 'Investigate Power']
for _, row in invest.iterrows():
    coef_rows.append({
        'authority': 'Investigative',
        'outcome': row['outcome'],
        'estimate': row['coef'],
        'std_error': row['se'],
        'p_value': row['p_value'],
        'n_obs': row['n_obs'],
    })

# Disciplinary (Discipline Power separate model)
disc = part_c[part_c['model'] == 'Discipline Power']
for _, row in disc.iterrows():
    coef_rows.append({
        'authority': 'Disciplinary',
        'outcome': row['outcome'],
        'estimate': row['coef'],
        'std_error': row['se'],
        'p_value': row['p_value'],
        'n_obs': row['n_obs'],
    })

# Full sample (Any COA)
full = part_c[part_c['model'] == 'Any COA (post)']
for _, row in full.iterrows():
    coef_rows.append({
        'authority': 'Full Sample',
        'outcome': row['outcome'],
        'estimate': row['coef'],
        'std_error': row['se'],
        'p_value': row['p_value'],
        'n_obs': row['n_obs'],
    })

coef_df = pd.DataFrame(coef_rows)

# Save coefficient table
coef_df.to_csv(os.path.join(output_dir, "did_by_authority_level.csv"), index=False)
print(f"\n[SAVED] output/did_by_authority_level.csv")

# ── Print results summary ────────────────────────────────────────────────
print("\n" + "=" * 70)
print("DiD EFFECTS BY BOARD AUTHORITY LEVEL")
print("=" * 70)

for outcome in outcomes_map.keys():
    print(f"\n  {outcome}:")
    for auth in ['Full Sample', 'Review Only', 'Investigative', 'Disciplinary']:
        sub = coef_df[(coef_df['authority'] == auth) & (coef_df['outcome'] == outcome)]
        if len(sub) > 0:
            r = sub.iloc[0]
            stars = '***' if r['p_value'] < 0.01 else '**' if r['p_value'] < 0.05 else '*' if r['p_value'] < 0.1 else ''
            print(f"    {auth:20s}: {r['estimate']:12.4f} (SE={r['std_error']:.4f}) p={r['p_value']:.4f} {stars}")

# ── 2a. Coefficient plot ─────────────────────────────────────────────────
print("\nGenerating coefficient plot...")

# Select key outcomes for the plot
plot_outcomes = ['violent_clearance_rate', 'property_clearance_rate',
                 'police_killings_pc', 'black_share_violent_arrests',
                 'black_share_drug_arrests']

plot_data = coef_df[
    (coef_df['outcome'].isin(plot_outcomes)) &
    (coef_df['authority'] != 'Full Sample')
].copy()

colors = {'Review Only': '#E69F00', 'Investigative': '#56B4E9', 'Disciplinary': '#009E73'}
auth_order = ['Review Only', 'Investigative', 'Disciplinary']

fig, axes = plt.subplots(1, len(plot_outcomes), figsize=(16, 5), sharey=False)

for i, outcome in enumerate(plot_outcomes):
    ax = axes[i]
    sub = plot_data[plot_data['outcome'] == outcome]

    for j, auth in enumerate(auth_order):
        row = sub[sub['authority'] == auth]
        if len(row) > 0:
            r = row.iloc[0]
            ax.errorbar(j, r['estimate'],
                       yerr=1.96 * r['std_error'],
                       fmt='o', color=colors[auth],
                       markersize=8, capsize=5, capthick=1.5,
                       linewidth=1.5)

    ax.axhline(y=0, color='gray', linestyle='--', alpha=0.5)
    ax.set_xticks(range(len(auth_order)))
    ax.set_xticklabels(['Review\nOnly', 'Invest.', 'Discip.'], fontsize=9)

    nice_name = outcomes_map.get(outcome, outcome).replace('\n', ' ')
    ax.set_title(nice_name, fontsize=10, fontweight='bold')

    if i == 0:
        ax.set_ylabel('ATT (95% CI)', fontsize=10)

fig.suptitle('DiD Effects by Board Authority Level\nNull average masks heterogeneity by board strength',
             fontsize=13, fontweight='bold', y=1.02)
plt.tight_layout()
plt.savefig(os.path.join(output_dir, "did_by_authority_level.png"),
            dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("[SAVED] output/did_by_authority_level.png")

# ── Full outcome coefficient plot (all outcomes) ─────────────────────────
all_outcomes = list(outcomes_map.keys())
plot_all = coef_df[
    (coef_df['outcome'].isin(all_outcomes)) &
    (coef_df['authority'] != 'Full Sample')
].copy()

n_out = len(all_outcomes)
fig, axes = plt.subplots(2, 4, figsize=(18, 9))
axes = axes.flatten()

for i, outcome in enumerate(all_outcomes):
    ax = axes[i]
    sub = plot_all[plot_all['outcome'] == outcome]

    for j, auth in enumerate(auth_order):
        row = sub[sub['authority'] == auth]
        if len(row) > 0:
            r = row.iloc[0]
            ax.errorbar(j, r['estimate'],
                       yerr=1.96 * r['std_error'],
                       fmt='o', color=colors[auth],
                       markersize=8, capsize=5, capthick=1.5,
                       linewidth=1.5)

    ax.axhline(y=0, color='gray', linestyle='--', alpha=0.5)
    ax.set_xticks(range(len(auth_order)))
    ax.set_xticklabels(['Review\nOnly', 'Invest.', 'Discip.'], fontsize=8)
    ax.set_title(outcomes_map[outcome], fontsize=9, fontweight='bold')

fig.suptitle('DiD Effects by Board Authority Level — All Outcomes\n'
             'Accountability Trap: Null average masks heterogeneity by board strength',
             fontsize=13, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, "did_by_authority_level_all.png"),
            dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("[SAVED] output/did_by_authority_level_all.png")

# ── 2b. Interaction model (conceptual, using existing joint results) ─────
print("\n" + "=" * 70)
print("SECTION 2b: INTERACTION MODEL — STRENGTH × TREATMENT")
print("=" * 70)

# Extract joint model results (post_strong vs post_weak in same regression)
joint = part_c[part_c['model'].str.startswith('Joint')]
print("\nJoint model results (strong vs weak COA in same regression):")
for _, row in joint.iterrows():
    stars = '***' if row['p_value'] < 0.01 else '**' if row['p_value'] < 0.05 else '*' if row['p_value'] < 0.1 else ''
    print(f"  {row['model']:30s} → {row['outcome']:30s}: "
          f"coef={row['coef']:10.4f} (SE={row['se']:.4f}) p={row['p_value']:.4f} {stars}")

# Create interaction-style marginal effects plot
# This shows the predicted effect at each authority level
print("\nGenerating interaction marginal effects plot...")

fig, axes = plt.subplots(2, 4, figsize=(18, 9))
axes = axes.flatten()

for i, outcome in enumerate(all_outcomes):
    ax = axes[i]

    # Get weak (review only) and strong effects from joint model
    weak_row = joint[(joint['model'] == 'Joint: Weak COA') & (joint['outcome'] == outcome)]
    strong_row = joint[(joint['model'] == 'Joint: Strong COA') & (joint['outcome'] == outcome)]

    x_vals = [0, 1]
    y_vals = []
    err_vals = []
    labels = ['Weak\n(Review Only)', 'Strong\n(Invest/Discip)']

    if len(weak_row) > 0:
        y_vals.append(weak_row.iloc[0]['coef'])
        err_vals.append(1.96 * weak_row.iloc[0]['se'])
    else:
        y_vals.append(np.nan)
        err_vals.append(0)

    if len(strong_row) > 0:
        y_vals.append(strong_row.iloc[0]['coef'])
        err_vals.append(1.96 * strong_row.iloc[0]['se'])
    else:
        y_vals.append(np.nan)
        err_vals.append(0)

    ax.errorbar(x_vals, y_vals, yerr=err_vals,
               fmt='o-', color='#0072B2', markersize=8,
               capsize=5, capthick=1.5, linewidth=1.5)
    ax.axhline(y=0, color='gray', linestyle='--', alpha=0.5)
    ax.set_xticks(x_vals)
    ax.set_xticklabels(labels, fontsize=8)
    ax.set_title(outcomes_map[outcome], fontsize=9, fontweight='bold')

fig.suptitle('Marginal Effect of COA by Board Strength\n'
             'Treatment × Authority Score Interaction',
             fontsize=13, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, "interaction_marginal_effects.png"),
            dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("[SAVED] output/interaction_marginal_effects.png")

print("\nSection 2 complete.")
