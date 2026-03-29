#!/usr/bin/env python3
"""Download COA charter/ordinance PDFs from various sources."""

import csv
import json
import os
import re
import ssl
import time
import urllib.request
import urllib.error
from pathlib import Path

OUTPUT_DIR = Path("/home/user/coa_effects/coa_charter_pdfs")
MANIFEST_PATH = OUTPUT_DIR / "places_manifest.json"

# Create a more permissive SSL context
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_peer = False

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,application/pdf,*/*;q=0.8',
}

def download_url(url, filepath, max_retries=2):
    """Download a URL to a file."""
    for attempt in range(max_retries + 1):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
                content_type = resp.headers.get('Content-Type', '')
                data = resp.read()

                # Check if it's actually a PDF
                if data[:4] == b'%PDF':
                    with open(filepath, 'wb') as f:
                        f.write(data)
                    return True, 'pdf'
                elif 'html' in content_type.lower() or data[:5] == b'<html' or data[:5] == b'<!DOC':
                    # Save HTML for later conversion
                    html_path = filepath.replace('.pdf', '.html')
                    with open(html_path, 'wb') as f:
                        f.write(data)
                    return True, 'html'
                else:
                    with open(filepath, 'wb') as f:
                        f.write(data)
                    return True, 'unknown'
        except Exception as e:
            if attempt < max_retries:
                time.sleep(2)
            else:
                return False, str(e)
    return False, 'max retries'

def main():
    with open(MANIFEST_PATH) as f:
        places = json.load(f)

    results = {'success': [], 'html_saved': [], 'failed': [], 'no_link': []}

    for place in places:
        name = place['name']
        state = place['state']
        filename = place['filename']
        links = place['links']

        if not links:
            results['no_link'].append(f"{name}, {state}")
            continue

        # Try each link
        downloaded = False
        for i, link in enumerate(links):
            suffix = f"_{i+1}" if i > 0 else ""
            filepath = str(OUTPUT_DIR / f"{filename}{suffix}.pdf")

            print(f"Downloading: {name}, {state} -> {link[:80]}...")
            success, ftype = download_url(link, filepath)

            if success:
                if ftype == 'pdf':
                    results['success'].append(f"{name}, {state}: {filepath}")
                    downloaded = True
                    print(f"  -> PDF saved: {filepath}")
                elif ftype == 'html':
                    results['html_saved'].append(f"{name}, {state}: {filepath.replace('.pdf', '.html')}")
                    print(f"  -> HTML saved (not a PDF): {filepath.replace('.pdf', '.html')}")
                else:
                    results['html_saved'].append(f"{name}, {state}: {filepath}")
                    print(f"  -> File saved (type: {ftype}): {filepath}")
            else:
                results['failed'].append(f"{name}, {state}: {ftype}")
                print(f"  -> FAILED: {ftype}")

        time.sleep(0.5)  # Be polite

    # Summary
    print("\n" + "="*60)
    print(f"PDFs downloaded: {len(results['success'])}")
    print(f"HTML pages saved: {len(results['html_saved'])}")
    print(f"Failed: {len(results['failed'])}")
    print(f"No link: {len(results['no_link'])}")

    with open(OUTPUT_DIR / "download_results.json", 'w') as f:
        json.dump(results, f, indent=2)

if __name__ == '__main__':
    main()
