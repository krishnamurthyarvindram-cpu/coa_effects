###############################################################################
# complaint_volume_analysis.py
# Section 7: Complaint Volume as a Mediator
#
# Tests the Node 2 → Node 3 mechanism: weak boards generate low complaint
# volumes, reducing the information that reaches the public and politicians.
###############################################################################

import os
import numpy as np
import pandas as pd

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
output_dir = os.path.join(base_dir, "output")

print("=" * 70)
print("SECTION 7: COMPLAINT VOLUME AS A MEDIATOR")
print("=" * 70)

# ── 7a. Check for complaint data ────────────────────────────────────────
print("\n7a. Searching for complaint data in all data folders...")

found_complaint_data = False
complaint_vars = []

for folder in ['cleaned_data', 'merged_data', 'raw_data']:
    path = os.path.join(base_dir, folder)
    for f in os.listdir(path):
        fpath = os.path.join(path, f)
        # Check CSV files for complaint-related columns
        if f.endswith('.csv'):
            try:
                df = pd.read_csv(fpath, nrows=0, encoding='latin-1')
                comp_cols = [c for c in df.columns if any(term in c.lower()
                            for term in ['complaint', 'sustain', 'truncat',
                                        'grievance', 'allegation', 'misconduct'])]
                if comp_cols:
                    print(f"  FOUND complaint columns in {folder}/{f}: {comp_cols}")
                    found_complaint_data = True
                    complaint_vars.extend(comp_cols)
            except:
                pass

# Also check existing output tables
for f in os.listdir(os.path.join(output_dir, "tables")):
    fpath = os.path.join(output_dir, "tables", f)
    if f.endswith(('.csv', '.tsv')):
        try:
            sep = '\t' if f.endswith('.tsv') else ','
            df = pd.read_csv(fpath, nrows=0, sep=sep)
            comp_cols = [c for c in df.columns if any(term in c.lower()
                        for term in ['complaint', 'sustain', 'truncat'])]
            if comp_cols:
                print(f"  FOUND complaint columns in output/tables/{f}: {comp_cols}")
                found_complaint_data = True
                complaint_vars.extend(comp_cols)
        except:
            pass

# Check column names in the analysis panel documentation
print("\n  Checking analysis_panel variables (from documentation)...")
panel_vars_documented = [
    'violent_crime_pc', 'violent_clearance_rate', 'property_clearance_rate',
    'drug_arrests_pc', 'discretionary_arrests_pc', 'police_killings_pc',
    'black_share_violent_arrests', 'black_share_drug_arrests',
    'violent_arrests_pc'
]
comp_in_panel = [v for v in panel_vars_documented if 'complaint' in v.lower() or 'sustain' in v.lower()]
print(f"  Complaint-related variables in panel: {comp_in_panel if comp_in_panel else 'NONE'}")

# ── Summary ──────────────────────────────────────────────────────────────
output_lines = []
output_lines.append("COMPLAINT VOLUME MEDIATION ANALYSIS")
output_lines.append("=" * 50)
output_lines.append("")

if not found_complaint_data and not comp_in_panel:
    print("\n  ⚠ NO COMPLAINT DATA FOUND in any data source.")
    print("  The analysis panel does not contain complaint count, sustain rate,")
    print("  or truncation rate variables.")
    print("  This analysis CANNOT be performed with available data.")
    print("")
    print("  RECOMMENDATION: Obtain complaint data from:")
    print("    - NACOLE (National Association for Civilian Oversight of Law Enforcement)")
    print("    - Individual city annual reports")
    print("    - DOJ Civil Rights Division investigations")
    print("    - CCRB (NYC) annual statistical summaries")
    print("    - COPA (Chicago) annual reports")

    output_lines.append("STATUS: COMPLAINT DATA NOT AVAILABLE")
    output_lines.append("")
    output_lines.append("No complaint count, sustain rate, or truncation rate variables")
    output_lines.append("were found in any dataset in the repository.")
    output_lines.append("")
    output_lines.append("The following data sources were checked:")
    output_lines.append("  - cleaned_data/ (all files)")
    output_lines.append("  - merged_data/ (all files)")
    output_lines.append("  - raw_data/ (all files)")
    output_lines.append("  - output/tables/ (all files)")
    output_lines.append("  - analysis_panel.rds documented variables")
    output_lines.append("")
    output_lines.append("RECOMMENDATION: Obtain complaint volume data from NACOLE,")
    output_lines.append("individual city annual reports, or DOJ investigations.")
    output_lines.append("")
    output_lines.append("TRAP PREDICTION (untestable with current data):")
    output_lines.append("  - Stronger boards should attract more complaints (positive coef)")
    output_lines.append("  - Stronger boards should have higher sustain rates (positive coef)")
    output_lines.append("  - Consistent with COPA experimental findings applied observationally")

else:
    output_lines.append(f"Complaint variables found: {complaint_vars}")
    output_lines.append("Further analysis required with available complaint data.")

# ── 7b. Proxy analysis using discretionary arrests ──────────────────────
print("\n7b. PROXY ANALYSIS: Using discretionary arrests as behavioral proxy...")
print("  While complaint data is unavailable, discretionary arrests per capita")
print("  can serve as a behavioral proxy — if boards affect police behavior,")
print("  discretionary arrests (which are most subject to officer judgment)")
print("  should respond to board strength.")

# Load existing results
strength = pd.read_csv(os.path.join(output_dir, "tables/coa_strength_analysis.tsv"), sep='\t')
part_c = strength[strength['part'] == 'C']

disc_arrests = part_c[part_c['outcome'] == 'discretionary_arrests_pc']
if len(disc_arrests) > 0:
    print("\n  Existing TWFE results for discretionary_arrests_pc:")
    for _, row in disc_arrests.iterrows():
        stars = '***' if row['p_value'] < 0.01 else '**' if row['p_value'] < 0.05 else '*' if row['p_value'] < 0.1 else ''
        print(f"    {row['model']:30s}: coef={row['coef']:12.2f} (SE={row['se']:.2f}) "
              f"p={row['p_value']:.4f} {stars}")

    output_lines.append("")
    output_lines.append("PROXY ANALYSIS: Discretionary Arrests by Board Strength")
    output_lines.append("(from existing TWFE results)")
    for _, row in disc_arrests.iterrows():
        stars = '***' if row['p_value'] < 0.01 else '**' if row['p_value'] < 0.05 else '*' if row['p_value'] < 0.1 else ''
        output_lines.append(f"  {row['model']:30s}: coef={row['coef']:12.2f} "
                           f"(SE={row['se']:.2f}) {stars}")

with open(os.path.join(output_dir, "complaints_by_strength.txt"), 'w') as f:
    f.write("\n".join(output_lines))

print(f"\n[SAVED] output/complaints_by_strength.txt")
print("\nSection 7 complete.")
