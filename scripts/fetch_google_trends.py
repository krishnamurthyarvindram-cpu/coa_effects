#!/usr/bin/env python3
"""
Fetch Google Trends data for policing-related search terms.

Produces two outputs:
  1. National monthly time series (2010-01 to 2023-12)
  2. Cross-sectional DMA-level interest scores

Handles rate limiting with exponential back-off and generous sleep
intervals between requests.
"""

import os
import sys
import time
import random
import datetime
import traceback

import pandas as pd
from pytrends.request import TrendReq

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
TERMS = [
    "police brutality",
    "police killings",
    "defund the police",
    "police accountability",
    "police reform",
]

# Fallback subset if we get rate-limited on the full list
TERMS_FALLBACK = [
    "police brutality",
    "police reform",
]

TIMEFRAME_FULL = "2010-01-01 2023-12-31"

OUT_DIR = "/home/user/coa_effects/raw_data"
TS_OUT  = os.path.join(OUT_DIR, "google_trends_national_timeseries.tsv")
DMA_OUT = os.path.join(OUT_DIR, "google_trends_dma_crosssection.tsv")

BASE_DELAY   = 30   # seconds between normal calls
MAX_RETRIES  = 5
BACKOFF_BASE = 60   # starting back-off on 429 errors

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def make_pytrend():
    """Create a fresh TrendReq session."""
    return TrendReq(hl="en-US", tz=360, retries=3, backoff_factor=1)


def sleep_between(lo=30, hi=60, label=""):
    """Sleep a random amount between lo and hi seconds."""
    t = random.uniform(lo, hi)
    print(f"  [sleep] waiting {t:.0f}s {label}...")
    time.sleep(t)


def fetch_with_retry(func, *args, max_retries=MAX_RETRIES, **kwargs):
    """
    Call *func* with exponential back-off on rate-limit (429) errors.
    Returns the result of func(*args, **kwargs).
    """
    for attempt in range(1, max_retries + 1):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            err_str = str(e)
            is_429 = "429" in err_str or "Too Many Requests" in err_str
            if is_429 and attempt < max_retries:
                wait = BACKOFF_BASE * (2 ** (attempt - 1)) + random.uniform(0, 30)
                print(f"  [retry {attempt}/{max_retries}] rate-limited; "
                      f"waiting {wait:.0f}s ...")
                time.sleep(wait)
            else:
                raise


# ---------------------------------------------------------------------------
# 1.  National time-series  (one call per term to get monthly data)
# ---------------------------------------------------------------------------

def fetch_national_timeseries(terms):
    """
    Fetch monthly national time-series for each term individually, then
    combine.  Fetching one term at a time avoids the 5-term comparison
    scaling and gives absolute (0-100) interest for each term.
    """
    frames = []
    for i, term in enumerate(terms):
        print(f"\n>>> Time-series for '{term}' ({i+1}/{len(terms)}) ...")
        pytrend = make_pytrend()

        def _build_and_fetch(pt=pytrend, kw=term):
            pt.build_payload([kw], timeframe=TIMEFRAME_FULL, geo="US")
            df = pt.interest_over_time()
            return df

        try:
            df = fetch_with_retry(_build_and_fetch)
        except Exception as exc:
            print(f"  *** FAILED for '{term}': {exc}")
            traceback.print_exc()
            continue

        if df is None or df.empty:
            print(f"  (no data returned for '{term}')")
            continue

        # df has columns = [term, 'isPartial']; index = date
        if "isPartial" in df.columns:
            df = df.drop(columns=["isPartial"])

        # Melt to long form
        df = df.reset_index()
        df = df.rename(columns={"date": "date", term: "interest"})
        df["term"] = term
        frames.append(df[["date", "term", "interest"]])

        print(f"  got {len(df)} rows  (range {df['interest'].min()}-{df['interest'].max()})")

        if i < len(terms) - 1:
            sleep_between(30, 60, "before next term")

    if not frames:
        return pd.DataFrame(columns=["date", "term", "interest"])
    return pd.concat(frames, ignore_index=True)


# ---------------------------------------------------------------------------
# 2.  DMA cross-section (interest_by_region at DMA resolution)
# ---------------------------------------------------------------------------

def fetch_dma_crosssection(terms):
    """
    For each term, fetch interest_by_region with resolution='DMA'.
    Uses the full timeframe so the score is an aggregate over the period.
    """
    frames = []
    for i, term in enumerate(terms):
        print(f"\n>>> DMA cross-section for '{term}' ({i+1}/{len(terms)}) ...")
        pytrend = make_pytrend()

        def _build_and_fetch(pt=pytrend, kw=term):
            pt.build_payload([kw], timeframe=TIMEFRAME_FULL, geo="US")
            df = pt.interest_by_region(resolution="DMA", inc_low_vol=True, inc_geo_code=True)
            return df

        try:
            df = fetch_with_retry(_build_and_fetch)
        except Exception as exc:
            print(f"  *** FAILED for '{term}': {exc}")
            traceback.print_exc()
            continue

        if df is None or df.empty:
            print(f"  (no data returned for '{term}')")
            continue

        # df index = geoName, columns include the search term and 'geoCode'
        df = df.reset_index()
        # Columns: geoName, geoCode (if present), <term>
        rename_map = {term: "interest"}
        if "geoName" not in df.columns and df.index.name == "geoName":
            df = df.reset_index()
        df = df.rename(columns=rename_map)
        df["term"] = term

        # Ensure we have geoName and geoCode
        cols_keep = []
        for c in ["geoName", "geoCode", "term", "interest"]:
            if c in df.columns:
                cols_keep.append(c)
        df = df[cols_keep]

        print(f"  got {len(df)} DMAs  (non-zero: {(df['interest'] > 0).sum()})")

        frames.append(df)

        if i < len(terms) - 1:
            sleep_between(30, 60, "before next term")

    if not frames:
        return pd.DataFrame(columns=["geoName", "geoCode", "term", "interest"])
    return pd.concat(frames, ignore_index=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    start = datetime.datetime.now()
    print(f"=== Google Trends fetch started at {start.isoformat()} ===")
    print(f"Terms: {TERMS}")
    print(f"Timeframe: {TIMEFRAME_FULL}")
    print()

    active_terms = list(TERMS)

    # ---- Part 1: national time series ----
    print("=" * 60)
    print("PART 1: National monthly time series")
    print("=" * 60)
    try:
        ts_df = fetch_national_timeseries(active_terms)
    except Exception as exc:
        print(f"\n*** Full term list failed: {exc}")
        print("*** Falling back to reduced term list ...")
        active_terms = list(TERMS_FALLBACK)
        sleep_between(60, 90, "before retry with fewer terms")
        ts_df = fetch_national_timeseries(active_terms)

    if not ts_df.empty:
        ts_df.to_csv(TS_OUT, sep="\t", index=False)
        print(f"\nSaved time-series ({len(ts_df)} rows) -> {TS_OUT}")
    else:
        print("\n*** No time-series data obtained.")

    # Pause before Part 2
    sleep_between(45, 75, "between Part 1 and Part 2")

    # ---- Part 2: DMA cross-section ----
    print("\n" + "=" * 60)
    print("PART 2: DMA cross-sectional scores")
    print("=" * 60)
    try:
        dma_df = fetch_dma_crosssection(active_terms)
    except Exception as exc:
        print(f"\n*** Full term list failed: {exc}")
        print("*** Falling back to reduced term list ...")
        active_terms = list(TERMS_FALLBACK)
        sleep_between(60, 90, "before retry with fewer terms")
        dma_df = fetch_dma_crosssection(active_terms)

    if not dma_df.empty:
        dma_df.to_csv(DMA_OUT, sep="\t", index=False)
        print(f"\nSaved DMA cross-section ({len(dma_df)} rows) -> {DMA_OUT}")
    else:
        print("\n*** No DMA data obtained.")

    end = datetime.datetime.now()
    elapsed = (end - start).total_seconds()
    print(f"\n=== Done at {end.isoformat()} ({elapsed/60:.1f} min) ===")

    # Summary
    print("\n--- SUMMARY ---")
    if not ts_df.empty:
        print(f"Time-series: {len(ts_df)} rows, "
              f"{ts_df['term'].nunique()} terms, "
              f"date range {ts_df['date'].min()} to {ts_df['date'].max()}")
    if not dma_df.empty:
        n_dma = dma_df["geoName"].nunique() if "geoName" in dma_df.columns else "?"
        print(f"DMA cross-section: {len(dma_df)} rows, "
              f"{dma_df['term'].nunique()} terms, "
              f"{n_dma} unique DMAs")


if __name__ == "__main__":
    main()
