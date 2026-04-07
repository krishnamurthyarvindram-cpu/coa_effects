###############################################################################
# run_all_analyses.py
# Master script to run all accountability trap analyses in order.
#
# Sections:
#   0. Orientation (already produced as output/orientation_memo.txt)
#   1a. Audit authority coding (already completed)
#   1b. Charter text extraction (scripts/charter_text_extraction.py)
#   1c. Merge charter features (scripts/merge_charter_features.py)
#   2. DiD by board strength (scripts/did_by_board_strength.py)
#   3. Post-Floyd analysis (scripts/post_floyd_analysis.py)
#   4. Board strength trajectory (scripts/board_strength_trajectory.py)
#   5. Police political capacity (scripts/police_political_capacity.py)
#   6. Electoral by strength (scripts/electoral_by_strength.py)
#   7. Complaint volume (scripts/complaint_volume_analysis.py)
#   8. Summary tables (scripts/summary_tables.py)
###############################################################################

import subprocess
import sys
import os

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
scripts_dir = os.path.join(base_dir, "scripts")

scripts = [
    ("1b", "charter_text_extraction.py"),
    ("1c", "merge_charter_features.py"),
    ("2",  "did_by_board_strength.py"),
    ("3",  "post_floyd_analysis.py"),
    ("4",  "board_strength_trajectory.py"),
    ("5",  "police_political_capacity.py"),
    ("6",  "electoral_by_strength.py"),
    ("7",  "complaint_volume_analysis.py"),
    ("8",  "summary_tables.py"),
]

print("=" * 70)
print("RUNNING ALL ACCOUNTABILITY TRAP ANALYSES")
print("=" * 70)

for section, script in scripts:
    print(f"\n{'#' * 70}")
    print(f"# Section {section}: {script}")
    print(f"{'#' * 70}")

    script_path = os.path.join(scripts_dir, script)
    result = subprocess.run(
        [sys.executable, script_path],
        capture_output=True, text=True, cwd=base_dir
    )

    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(f"STDERR: {result.stderr}", file=sys.stderr)

    if result.returncode != 0:
        print(f"  ⚠ Section {section} exited with code {result.returncode}")
    else:
        print(f"  ✓ Section {section} complete")

print("\n" + "=" * 70)
print("ALL ANALYSES COMPLETE")
print("=" * 70)
