###############################################################################
# merge_charter_features.py
# Section 1c: Merge charter features back to the panel, create board_weakness_index
#
# Since the analysis_panel.rds is a Git LFS pointer (not accessible),
# we merge charter_features.csv with coa_classification.csv and
# coa_creation_data_actual.csv to create a comprehensive city-level dataset.
###############################################################################

import os
import re
import pandas as pd
import numpy as np

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")

print("=" * 70)
print("SECTION 1c: MERGE CHARTER FEATURES TO PANEL")
print("=" * 70)

# ── 1. Load charter features ────────────────────────────────────────────
charter = pd.read_csv(os.path.join(output_dir, "charter_features.csv"))
print(f"Charter features: {len(charter)} rows")

# ── 2. Parse city names from PDF filenames ──────────────────────────────
def parse_city_from_filename(filename):
    """Extract city name and state from PDF filename."""
    name = filename.replace('.pdf', '')
    # Remove suffixes like _2, _ordinance
    name = re.sub(r'_\d+$', '', name)
    name = re.sub(r'_ordinance$', '', name)

    # Try pattern: City_Name_city_ST or City_Name_ST
    # Most files follow: Name_city_ST.pdf or Name_ST.pdf
    parts = name.split('_')

    # Try to find state abbrev (last part, 2 chars)
    state = parts[-1] if len(parts[-1]) == 2 else None

    if state:
        remaining = parts[:-1]
        # Remove 'city' suffix if present
        # Also handle 'unified_government__balance_', 'metro_government__balance_', etc.
        city_parts = []
        skip_rest = False
        for p in remaining:
            if p in ('city', 'CDP'):
                continue
            if p in ('unified', 'metro', 'metropolitan', 'urban', 'county'):
                city_parts.append(p)
                continue
            if p in ('government', 'balance'):
                continue
            city_parts.append(p)
        city = ' '.join(city_parts).strip()
    else:
        city = ' '.join(parts)
        state = None

    return city, state

charter[['city_parsed', 'state_parsed']] = charter['filename'].apply(
    lambda f: pd.Series(parse_city_from_filename(f)))

# ── 3. Load detailed classification ─────────────────────────────────────
classif = pd.read_csv(os.path.join(output_dir, "tables/coa_classification.csv"))

# Standardize city names for matching
def standardize_city(name):
    """Standardize city name for matching."""
    if pd.isna(name):
        return ""
    s = str(name).lower().strip()
    s = re.sub(r'\s+', ' ', s)
    # Remove common suffixes
    s = re.sub(r'\s*(city|town|village|cdp|borough|municipality)\s*$', '', s)
    s = re.sub(r'\s*(unified government|metro government|metropolitan government)\s*(\(balance\))?\s*$', '', s)
    s = re.sub(r'\s*\(balance\)\s*$', '', s)
    s = s.replace('st.', 'st').replace('saint ', 'st ')
    return s.strip()

charter['city_std'] = charter['city_parsed'].apply(standardize_city)
classif['city_std'] = classif['city'].apply(standardize_city)

# ── 4. Merge charter features with classification ───────────────────────
# Use city_std + state for matching
classif['state_clean'] = classif['state'].str.strip()
charter['state_clean'] = charter['state_parsed'].str.strip()

# Handle duplicates (e.g. Portland_city_OR and Portland_city_OR_2)
# Keep longest text for duplicates
charter = charter.sort_values('text_length', ascending=False).drop_duplicates(
    subset=['city_std', 'state_clean'], keep='first')

merged = classif.merge(
    charter[['city_std', 'state_clean', 'has_sunset', 'voluntary_cooperation',
             'mandatory_cooperation', 'has_budget_language', 'has_union_exclusion',
             'text_length', 'filename']],
    left_on=['city_std', 'state_clean'],
    right_on=['city_std', 'state_clean'],
    how='left'
)

print(f"Classification cities: {len(classif)}")
print(f"Merged (with charter features): {merged['has_sunset'].notna().sum()} matched")
print(f"Unmatched: {merged['has_sunset'].isna().sum()}")

# Show unmatched
unmatched = merged[merged['has_sunset'].isna()][['city', 'state', 'city_std']]
if len(unmatched) > 0:
    print("\nUnmatched cities:")
    for _, row in unmatched.iterrows():
        print(f"  {row['city']}, {row['state']} (std: '{row['city_std']}')")

# ── 5. Create authority level classification ─────────────────────────────
def classify_authority(row):
    disc = str(row.get('independent_discipline', '')).strip().upper()
    inv = str(row.get('independent_investigation', '')).strip().upper()
    if disc == 'Y':
        return 'disciplinary'
    elif inv == 'Y':
        return 'investigative'
    else:
        return 'review_only'

merged['authority_level'] = merged.apply(classify_authority, axis=1)

# ── 6. Create board_weakness_index ───────────────────────────────────────
# Sum: has_sunset + voluntary_cooperation + has_union_exclusion
# Higher = weaker board design
merged['board_weakness_index'] = (
    merged['has_sunset'].fillna(False).astype(int) +
    merged['voluntary_cooperation'].fillna(False).astype(int) +
    merged['has_union_exclusion'].fillna(False).astype(int)
)

# Also create a broader weakness index including lack of mandatory cooperation
merged['board_weakness_index_broad'] = (
    merged['board_weakness_index'] +
    (~merged['mandatory_cooperation'].fillna(False)).astype(int)
)

# Create numeric authority score (higher = stronger)
merged['authority_score'] = merged['authority_level'].map({
    'review_only': 0, 'investigative': 1, 'disciplinary': 2
})

print("\n--- Board Weakness Index Distribution ---")
print(merged['board_weakness_index'].value_counts().sort_index())

print("\n--- Cross-tab: Board Weakness Index × Authority Level ---")
crosstab = pd.crosstab(merged['board_weakness_index'], merged['authority_level'])
print(crosstab)

print("\n--- Mean Weakness Index by Authority Level ---")
for auth in ['review_only', 'investigative', 'disciplinary']:
    sub = merged[merged['authority_level'] == auth]['board_weakness_index']
    print(f"  {auth:20s}: mean={sub.mean():.3f}, n={len(sub)}")

# ── 7. Clean year and create decade ─────────────────────────────────────
def clean_year(y):
    if pd.isna(y):
        return None
    s = str(y).strip()
    m = re.search(r'(\d{4})', s)
    if m and 1800 <= int(m.group(1)) <= 2030:
        return int(m.group(1))
    return None

merged['year_num'] = merged['year_created'].apply(clean_year)
merged['decade'] = (merged['year_num'] // 10 * 10).astype('Int64')

# ── 8. Save augmented panel ─────────────────────────────────────────────
os.makedirs(os.path.join(base_dir, "merged_data"), exist_ok=True)
merged.to_csv(os.path.join(base_dir, "merged_data/panel_with_charter_features.csv"), index=False)
print(f"\n[SAVED] merged_data/panel_with_charter_features.csv ({len(merged)} rows)")

# Also save a summary
print("\n" + "=" * 70)
print("MERGED PANEL SUMMARY")
print("=" * 70)
print(f"Total cities: {len(merged)}")
print(f"Authority levels: {merged['authority_level'].value_counts().to_dict()}")
print(f"Board weakness index range: {merged['board_weakness_index'].min()} - {merged['board_weakness_index'].max()}")
print(f"Year range: {merged['year_num'].min()} - {merged['year_num'].max()}")
print(f"\nColumns: {list(merged.columns)}")
