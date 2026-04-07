###############################################################################
# post_floyd_analysis.py
# Section 3: The Post-Floyd Equilibrium Robustness Test
#
# Tests whether Floyd-era board creations (2020-2021) are any stronger
# than pre-Floyd boards — the accountability trap prediction is that they
# should NOT be, because the political equilibrium absorbs the shock.
#
# Uses coa_classification.csv and coa_creation_data_actual.csv
###############################################################################

import os
import re
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from scipy.stats import chi2_contingency

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")
os.makedirs(output_dir, exist_ok=True)

print("=" * 70)
print("SECTION 3: POST-FLOYD EQUILIBRIUM ROBUSTNESS TEST")
print("=" * 70)

# ── Load data ────────────────────────────────────────────────────────────
classif = pd.read_csv(os.path.join(output_dir, "tables/coa_classification.csv"))
merged = pd.read_csv(os.path.join(base_dir, "merged_data/panel_with_charter_features.csv"))

# Clean year
def clean_year(y):
    if pd.isna(y):
        return None
    s = str(y).strip()
    m = re.search(r'(\d{4})', s)
    if m and 1800 <= int(m.group(1)) <= 2030:
        return int(m.group(1))
    return None

merged['year_num'] = merged['year_created'].apply(clean_year)

# ── 3a. Check for post-2020 data ────────────────────────────────────────
print("\n3a. Checking for post-2020 data...")
post2020 = merged[merged['year_num'] > 2020]
print(f"  Cities with creation year after 2020: {len(post2020)}")
if len(post2020) > 0:
    print(f"  Years: {sorted(post2020['year_num'].unique())}")
    for _, row in post2020.iterrows():
        print(f"    {row['city']}, {row['state']} — {row['year_num']}")
else:
    print("  NOTE: No post-2020 charter data available. Working with existing panel.")

# ── 3b. Identify Floyd-era board creations ───────────────────────────────
print("\n3b. Flagging Floyd-era board creations...")

def classify_era(year):
    if pd.isna(year):
        return None
    if year in (2020, 2021):
        return f"Floyd-era ({int(year)})"
    elif 2015 <= year < 2020:
        return "Pre-Floyd (2015-2019)"
    elif year < 2015:
        return "Early adoption (pre-2015)"
    else:
        return f"Post-Floyd ({int(year)})"

merged['floyd_era'] = merged['year_num'].apply(classify_era)

print("\nFloyd-era distribution:")
print(merged['floyd_era'].value_counts().sort_index())

# ── 3c. Compare authority levels across adoption eras ────────────────────
print("\n3c. Authority levels by adoption era...")

era_authority = merged.dropna(subset=['floyd_era']).groupby(
    ['floyd_era', 'authority_level']).size().reset_index(name='n')

# Calculate percentages
era_totals = era_authority.groupby('floyd_era')['n'].transform('sum')
era_authority['pct'] = era_authority['n'] / era_totals * 100

print("\n--- Authority Level by Adoption Era ---")
pivot = era_authority.pivot_table(index='floyd_era', columns='authority_level',
                                  values='n', fill_value=0)
pivot = pivot.reindex(columns=['review_only', 'investigative', 'disciplinary'], fill_value=0)
pivot['total'] = pivot.sum(axis=1)
print(pivot.to_string())

pivot_pct = era_authority.pivot_table(index='floyd_era', columns='authority_level',
                                      values='pct', fill_value=0)
pivot_pct = pivot_pct.reindex(columns=['review_only', 'investigative', 'disciplinary'], fill_value=0)
print("\nPercentages:")
print(pivot_pct.round(1).to_string())

# Save
era_authority.to_csv(os.path.join(output_dir, "authority_by_floyd_era.csv"), index=False)
print(f"\n[SAVED] output/authority_by_floyd_era.csv")

# ── Bar chart ────────────────────────────────────────────────────────────
# Colorblind-safe palette (Okabe-Ito)
colors = {'review_only': '#E69F00', 'investigative': '#56B4E9', 'disciplinary': '#009E73'}

era_order = ['Early adoption (pre-2015)', 'Pre-Floyd (2015-2019)',
             'Floyd-era (2020)', 'Floyd-era (2021)']
# Add any post-Floyd eras if they exist
for era in sorted(merged['floyd_era'].dropna().unique()):
    if era not in era_order:
        era_order.append(era)

fig, ax = plt.subplots(figsize=(10, 6))

pivot_plot = era_authority.pivot_table(index='floyd_era', columns='authority_level',
                                       values='pct', fill_value=0)
pivot_plot = pivot_plot.reindex(columns=['review_only', 'investigative', 'disciplinary'], fill_value=0)
pivot_plot = pivot_plot.reindex([e for e in era_order if e in pivot_plot.index])

bottom = np.zeros(len(pivot_plot))
for auth_level in ['review_only', 'investigative', 'disciplinary']:
    vals = pivot_plot[auth_level].values
    bars = ax.bar(range(len(pivot_plot)), vals, bottom=bottom,
                  label=auth_level.replace('_', ' ').title(),
                  color=colors[auth_level])

    # Add percentage labels
    for j, (v, b) in enumerate(zip(vals, bottom)):
        if v > 3:  # Only label if big enough
            ax.text(j, b + v/2, f'{v:.0f}%', ha='center', va='center',
                   fontsize=9, color='white', fontweight='bold')
    bottom += vals

ax.set_xticks(range(len(pivot_plot)))
ax.set_xticklabels(pivot_plot.index, fontsize=9, rotation=15, ha='right')
ax.set_ylabel('Share of Boards (%)', fontsize=12)
ax.set_xlabel('Adoption Era', fontsize=12)
ax.set_title('Board Authority Level by Adoption Era\n'
             'If the accountability trap holds, Floyd-era boards should be no stronger',
             fontsize=13, fontweight='bold')
ax.legend(title='Authority Level', fontsize=10)
ax.set_ylim(0, 105)

plt.tight_layout()
plt.savefig(os.path.join(output_dir, "authority_by_floyd_era.png"),
            dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("[SAVED] output/authority_by_floyd_era.png")

# ── 3d. Chi-square test ─────────────────────────────────────────────────
print("\n3d. Chi-square test: Floyd-era vs Pre-Floyd authority distribution...")

merged_test = merged.dropna(subset=['floyd_era', 'authority_level']).copy()
merged_test['floyd_binary'] = merged_test['floyd_era'].apply(
    lambda x: 'Floyd-era' if 'Floyd' in str(x) else 'Pre-Floyd'
)

contingency = pd.crosstab(merged_test['floyd_binary'], merged_test['authority_level'])
contingency = contingency.reindex(columns=['review_only', 'investigative', 'disciplinary'], fill_value=0)
print("\nContingency table:")
print(contingency)

try:
    chi2, p_value, dof, expected = chi2_contingency(contingency)
    print(f"\nChi-square test results:")
    print(f"  Chi-square statistic: {chi2:.4f}")
    print(f"  Degrees of freedom: {dof}")
    print(f"  p-value: {p_value:.4f}")
    print(f"\n  Expected frequencies:")
    print(pd.DataFrame(expected, index=contingency.index,
                       columns=contingency.columns).round(2))
except Exception as e:
    print(f"  Chi-square test error: {e}")
    chi2, p_value, dof = np.nan, np.nan, np.nan

# ── Interpretation ───────────────────────────────────────────────────────
interpretation = []
interpretation.append("FLOYD-ERA EQUILIBRIUM TEST — INTERPRETATION")
interpretation.append("=" * 50)
interpretation.append("")

# Floyd-era disciplinary share
floyd_boards = merged_test[merged_test['floyd_binary'] == 'Floyd-era']
pre_floyd = merged_test[merged_test['floyd_binary'] == 'Pre-Floyd']

floyd_disc_pct = (floyd_boards['authority_level'] == 'disciplinary').mean() * 100
pre_disc_pct = (pre_floyd['authority_level'] == 'disciplinary').mean() * 100

interpretation.append(f"Floyd-era boards with disciplinary authority: {floyd_disc_pct:.1f}%")
interpretation.append(f"Pre-Floyd boards with disciplinary authority: {pre_disc_pct:.1f}%")
interpretation.append(f"")
interpretation.append(f"Chi-square test p-value: {p_value:.4f}")
interpretation.append(f"")

if p_value > 0.05:
    interpretation.append(
        "RESULT: The chi-square test is NOT significant (p > 0.05). Floyd-era "
        "boards are NOT significantly different in their authority distribution from "
        "pre-Floyd boards. This is CONSISTENT with the accountability trap hypothesis: "
        "even after the massive political shock of George Floyd's murder and the "
        "subsequent nationwide protests, the structural equilibrium produced boards "
        "of similar (weak) design. The political system absorbed the shock without "
        "fundamentally altering the institutional architecture of oversight."
    )
else:
    interpretation.append(
        f"RESULT: The chi-square test IS significant (p = {p_value:.4f}). Floyd-era "
        "boards show a statistically different authority distribution compared to "
        "pre-Floyd boards. This provides PARTIAL evidence against the strongest "
        "form of the accountability trap, suggesting the Floyd shock may have "
        "shifted the equilibrium. However, examining whether the shift is toward "
        "stronger or weaker boards is necessary for full interpretation."
    )

interp_text = "\n".join(interpretation)
print(f"\n{interp_text}")

# Save
with open(os.path.join(output_dir, "floyd_era_test.txt"), 'w') as f:
    f.write(interp_text)
    f.write(f"\n\n--- Raw Data ---\n")
    f.write(f"\nContingency table:\n{contingency.to_string()}\n")
    f.write(f"\nChi-square: {chi2:.4f}, df={dof}, p={p_value:.4f}\n")
    f.write(f"\nAuthority by era:\n{pivot.to_string()}\n")
    f.write(f"\nPercentages:\n{pivot_pct.round(1).to_string()}\n")

print(f"\n[SAVED] output/floyd_era_test.txt")
print("\nSection 3 complete.")
