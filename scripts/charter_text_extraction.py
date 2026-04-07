###############################################################################
# charter_text_extraction.py
# Section 1b: Extract additional features from charter PDFs
#
# For each PDF in coa_charter_pdfs/, extract full text and search for:
#   - Sunset clause language
#   - Voluntary cooperation language
#   - Mandatory cooperation language
#   - Budget language
#   - Union exclusion language
#
# Output: output/charter_features.csv
###############################################################################

import os
import re
import pandas as pd
from PyPDF2 import PdfReader

base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pdf_dir = os.path.join(base_dir, "coa_charter_pdfs")
output_dir = os.path.join(base_dir, "output")
os.makedirs(output_dir, exist_ok=True)

# --- Define search patterns ---

SUNSET_TERMS = [
    r"sunset", r"expires", r"expiration", r"shall terminate",
    r"unless reauthorized", r"subject to renewal"
]

VOLUNTARY_COOPERATION_TERMS = [
    r"shall cooperate", r"may cooperate", r"upon request",
    r"voluntary", r"if requested", r"with the consent of"
]

MANDATORY_COOPERATION_TERMS = [
    r"shall provide", r"must provide", r"required to cooperate",
    r"shall appear", r"compelled", r"subpoena"
]

BUDGET_TERMS = [
    r"appropriation", r"budget", r"funding", r"fiscal year"
]

UNION_EXCLUSION_TERMS = [
    r"collective bargaining", r"union contract", r"\bMOU\b",
    r"memorandum of understanding"
]


def search_text(text, patterns):
    """Return True if any pattern found in text (case-insensitive)."""
    text_lower = text.lower()
    for pat in patterns:
        if re.search(pat, text_lower):
            return True
    return False


def extract_pdf_text(pdf_path):
    """Extract all text from a PDF using PyPDF2."""
    text = ""
    try:
        reader = PdfReader(pdf_path)
        for page in reader.pages:
            page_text = page.extract_text()
            if page_text:
                text += page_text + "\n"
    except Exception as e:
        print(f"  ERROR reading {os.path.basename(pdf_path)}: {e}")
    return text


# --- Process all PDFs ---
print("=" * 70)
print("CHARTER TEXT EXTRACTION")
print("=" * 70)

pdf_files = sorted([f for f in os.listdir(pdf_dir) if f.lower().endswith('.pdf')])
print(f"Found {len(pdf_files)} PDF files in coa_charter_pdfs/\n")

results = []

for i, pdf_file in enumerate(pdf_files):
    pdf_path = os.path.join(pdf_dir, pdf_file)
    print(f"  [{i+1:3d}/{len(pdf_files)}] Processing {pdf_file}...", end=" ")

    text = extract_pdf_text(pdf_path)
    text_length = len(text)

    row = {
        "filename": pdf_file,
        "has_sunset": search_text(text, SUNSET_TERMS),
        "voluntary_cooperation": search_text(text, VOLUNTARY_COOPERATION_TERMS),
        "mandatory_cooperation": search_text(text, MANDATORY_COOPERATION_TERMS),
        "has_budget_language": search_text(text, BUDGET_TERMS),
        "has_union_exclusion": search_text(text, UNION_EXCLUSION_TERMS),
        "text_length": text_length
    }
    results.append(row)

    flags = []
    if row["has_sunset"]: flags.append("sunset")
    if row["voluntary_cooperation"]: flags.append("voluntary")
    if row["mandatory_cooperation"]: flags.append("mandatory")
    if row["has_budget_language"]: flags.append("budget")
    if row["has_union_exclusion"]: flags.append("union")

    print(f"({text_length:,} chars) [{', '.join(flags) if flags else 'none'}]")

# --- Create output dataframe ---
df = pd.DataFrame(results)

# Save
output_path = os.path.join(output_dir, "charter_features.csv")
df.to_csv(output_path, index=False)
print(f"\n[SAVED] {output_path}")

# --- Print feature frequencies ---
print("\n" + "=" * 70)
print("FEATURE FREQUENCIES ACROSS ALL CHARTERS")
print("=" * 70)

feature_cols = ["has_sunset", "voluntary_cooperation", "mandatory_cooperation",
                "has_budget_language", "has_union_exclusion"]

for col in feature_cols:
    n_true = df[col].sum()
    pct = n_true / len(df) * 100
    print(f"  {col:30s}: {n_true:3d} / {len(df)} ({pct:5.1f}%)")

print(f"\n  Mean text length: {df['text_length'].mean():,.0f} chars")
print(f"  Median text length: {df['text_length'].median():,.0f} chars")
print(f"  Min text length: {df['text_length'].min():,} chars")
print(f"  Max text length: {df['text_length'].max():,} chars")

# PDFs with zero text (extraction failed)
zero_text = df[df['text_length'] == 0]
if len(zero_text) > 0:
    print(f"\n  ⚠ {len(zero_text)} PDFs had no extractable text:")
    for _, row in zero_text.iterrows():
        print(f"    - {row['filename']}")
