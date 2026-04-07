###############################################################################
# electoral_by_strength.py
# Section 6: Electoral Mechanism — Does Strong vs. Weak Board Creation Differ
#            in Political Consequences?
#
# The paper shows politicians gain ~2.4pp from creating any board. The trap
# argument requires showing the gain is specifically tied to creating WEAK boards.
#
# Uses existing electoral DiD results from coa_strength_analysis.tsv (Part B)
# and reconstructs the split-sample analysis from those results.
###############################################################################

import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")

print("=" * 70)
print("SECTION 6: ELECTORAL MECHANISM BY BOARD STRENGTH")
print("=" * 70)

# ── Load existing electoral results ──────────────────────────────────────
strength = pd.read_csv(os.path.join(output_dir, "tables/coa_strength_analysis.tsv"), sep='\t')
electoral = pd.read_csv(os.path.join(output_dir, "tables/did_electoral_incumbent.tsv"), sep='\t')

# Part B: Electoral effects by COA strength
part_b = strength[strength['part'] == 'B'].copy()
print(f"Part B (electoral by strength) results: {len(part_b)} rows")
print(f"  Models: {part_b['model'].unique()}")
print(f"  Samples: {part_b['sample'].unique()}")

# ── Display results ──────────────────────────────────────────────────────
print("\n" + "=" * 70)
print("ELECTORAL EFFECTS: STRONG vs. WEAK COA CREATION")
print("=" * 70)

# Group by sample and compare strong vs weak
for sample in part_b['sample'].unique():
    sample_data = part_b[part_b['sample'] == sample]
    print(f"\n  --- {sample} ---")
    for _, row in sample_data.iterrows():
        stars = '***' if row['p_value'] < 0.01 else '**' if row['p_value'] < 0.05 else '*' if row['p_value'] < 0.1 else ''
        print(f"    {row['model']:35s} → {row['outcome']:15s}: "
              f"coef={row['coef']:8.4f} (SE={row['se']:.4f}) p={row['p_value']:.4f} {stars}")

# ── Focus on key comparisons ─────────────────────────────────────────────
print("\n" + "=" * 70)
print("KEY COMPARISONS: During-Term Creation Effect")
print("=" * 70)

# Compare during-term effects for all incumbents
all_incumb = part_b[part_b['sample'] == 'All Incumbents']

for outcome in ['vote_share', 'win']:
    print(f"\n  Outcome: {outcome}")
    strong = all_incumb[(all_incumb['model'] == 'Strong COA During Term') &
                        (all_incumb['outcome'] == outcome)]
    weak = all_incumb[(all_incumb['model'] == 'Weak COA During Term') &
                      (all_incumb['outcome'] == outcome)]

    if len(strong) > 0:
        s = strong.iloc[0]
        print(f"    Strong COA: {s['coef']:8.4f} (SE={s['se']:.4f}, p={s['p_value']:.4f})")
    if len(weak) > 0:
        w = weak.iloc[0]
        print(f"    Weak COA:   {w['coef']:8.4f} (SE={w['se']:.4f}, p={w['p_value']:.4f})")

    # Trap prediction: weak COA should have LARGER (more positive) coefficient
    if len(strong) > 0 and len(weak) > 0:
        s_coef = strong.iloc[0]['coef']
        w_coef = weak.iloc[0]['coef']
        diff = w_coef - s_coef
        print(f"    Difference (weak - strong): {diff:+8.4f}")
        if w_coef > s_coef:
            print(f"    → CONSISTENT with trap: weak board creators benefit MORE")
        else:
            print(f"    → NOT consistent with trap prediction")

# ── Also check post-COA effects ──────────────────────────────────────────
print("\n" + "=" * 70)
print("POST-COA EFFECTS (longer-term)")
print("=" * 70)

for outcome in ['vote_share', 'win']:
    print(f"\n  Outcome: {outcome}")
    post_strong = all_incumb[(all_incumb['model'] == 'Post Strong COA') &
                              (all_incumb['outcome'] == outcome)]
    post_weak = all_incumb[(all_incumb['model'] == 'Post Weak COA') &
                            (all_incumb['outcome'] == outcome)]

    if len(post_strong) > 0:
        s = post_strong.iloc[0]
        stars = '**' if s['p_value'] < 0.05 else '*' if s['p_value'] < 0.1 else ''
        print(f"    Post Strong COA: {s['coef']:8.4f} (SE={s['se']:.4f}, p={s['p_value']:.4f}) {stars}")
    if len(post_weak) > 0:
        w = post_weak.iloc[0]
        stars = '**' if w['p_value'] < 0.05 else '*' if w['p_value'] < 0.1 else ''
        print(f"    Post Weak COA:   {w['coef']:8.4f} (SE={w['se']:.4f}, p={w['p_value']:.4f}) {stars}")

# ── Racial subgroup analysis ─────────────────────────────────────────────
print("\n" + "=" * 70)
print("RACIAL SUBGROUP ANALYSIS")
print("=" * 70)

for race_sample in ['Race: Black', 'Race: White']:
    race_data = part_b[part_b['sample'] == race_sample]
    if len(race_data) > 0:
        print(f"\n  --- {race_sample} candidates ---")
        for _, row in race_data.iterrows():
            stars = '***' if row['p_value'] < 0.01 else '**' if row['p_value'] < 0.05 else '*' if row['p_value'] < 0.1 else ''
            print(f"    {row['model']:35s} → {row['outcome']:15s}: "
                  f"coef={row['coef']:8.4f} (p={row['p_value']:.4f}) {stars}")

# ── Create comparison figure ─────────────────────────────────────────────
print("\nGenerating electoral effects comparison figure...")

fig, axes = plt.subplots(1, 2, figsize=(12, 5))

for i, outcome in enumerate(['vote_share', 'win']):
    ax = axes[i]

    categories = []
    coefs = []
    errors = []
    colors_list = []

    for model_type, color in [('During Term', '#0072B2'), ('Post', '#D55E00')]:
        for strength_label, strength_filter in [('Strong', 'Strong'), ('Weak', 'Weak')]:
            if model_type == 'During Term':
                match = all_incumb[(all_incumb['model'] == f'{strength_filter} COA During Term') &
                                    (all_incumb['outcome'] == outcome)]
            else:
                match = all_incumb[(all_incumb['model'] == f'Post {strength_filter} COA') &
                                    (all_incumb['outcome'] == outcome)]

            if len(match) > 0:
                r = match.iloc[0]
                categories.append(f'{strength_label}\n({model_type})')
                coefs.append(r['coef'])
                errors.append(1.96 * r['se'])
                colors_list.append(color)

    x = range(len(categories))
    ax.bar(x, coefs, yerr=errors, color=colors_list, alpha=0.7,
           capsize=5, edgecolor='black', linewidth=0.5)
    ax.axhline(y=0, color='gray', linestyle='--', alpha=0.5)
    ax.set_xticks(x)
    ax.set_xticklabels(categories, fontsize=9)
    ax.set_ylabel('Coefficient (95% CI)')
    ax.set_title(f'Electoral Effect: {outcome.replace("_", " ").title()}',
                fontsize=12, fontweight='bold')

fig.suptitle('Electoral Benefits of COA Creation by Board Strength\n'
             'Trap prediction: weak board creators should benefit more',
             fontsize=13, fontweight='bold')
plt.tight_layout()
plt.savefig(os.path.join(output_dir, "electoral_by_strength.png"),
            dpi=300, bbox_inches='tight', facecolor='white')
plt.close()
print("[SAVED] output/electoral_by_strength.png")

# ── Save text output ─────────────────────────────────────────────────────
output_lines = []
output_lines.append("ELECTORAL BENEFITS OF COA CREATION BY BOARD STRENGTH")
output_lines.append("=" * 60)
output_lines.append("")
output_lines.append("Data: LEDB candidate-level electoral data")
output_lines.append("Method: PanelOLS with candidate + year FEs, clustered at city level")
output_lines.append("")
output_lines.append("KEY RESULTS:")
output_lines.append("")

for outcome in ['vote_share', 'win']:
    output_lines.append(f"Outcome: {outcome}")
    for model in ['Strong COA During Term', 'Weak COA During Term',
                   'Post Strong COA', 'Post Weak COA']:
        match = all_incumb[(all_incumb['model'] == model) &
                            (all_incumb['outcome'] == outcome)]
        if len(match) > 0:
            r = match.iloc[0]
            stars = '***' if r['p_value'] < 0.01 else '**' if r['p_value'] < 0.05 else '*' if r['p_value'] < 0.1 else ''
            output_lines.append(
                f"  {model:35s}: {r['coef']:8.4f} (SE={r['se']:.4f}) {stars}")
    output_lines.append("")

output_lines.append("NOTE: The disciplinary subsample is very small (N treated ≈ 9-28)")
output_lines.append("for most electoral specifications, limiting statistical power.")
output_lines.append("Results should be interpreted with caution.")
output_lines.append("")
output_lines.append("TRAP INTERPRETATION:")
output_lines.append("  The trap hypothesis predicts weak board creators should see LARGER")
output_lines.append("  electoral benefits than strong board creators, because strong board")
output_lines.append("  creators face police political retaliation that offsets reform credit.")

with open(os.path.join(output_dir, "electoral_by_strength.txt"), 'w') as f:
    f.write("\n".join(output_lines))

print(f"[SAVED] output/electoral_by_strength.txt")
print("\nSection 6 complete.")
