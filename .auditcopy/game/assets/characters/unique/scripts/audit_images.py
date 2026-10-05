#!/usr/bin/env python3
"""Audit generated images for background removal (alpha channel)."""
from pathlib import Path
from PIL import Image
import sys

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "outputs"

def audit():
    images = sorted(OUTPUT_DIR.glob("ilsa_*.png"))
    print(f"Auditing {len(images)} images...\n")
    
    issues = []
    for img_path in images:
        img = Image.open(img_path)
        name = img_path.name
        
        # Check if has alpha channel
        if img.mode != "RGBA":
            issues.append((name, "NO ALPHA CHANNEL", "background removal NOT enabled"))
            continue
        
        # Check alpha channel stats
        alpha = img.getchannel("A")
        extrema = alpha.getextrema()
        transparent_pct = sum(1 for p in alpha.getdata() if p < 128) / (img.width * img.height) * 100
        
        if transparent_pct < 10:
            issues.append((name, f"only {transparent_pct:.1f}% transparent", "background removal WEAK"))
        elif extrema[0] == 0 and extrema[1] == 255:
            print(f"  OK  {name}: {img.width}x{img.height}, {transparent_pct:.1f}% transparent")
        else:
            issues.append((name, f"alpha range {extrema}", "background removal PARTIAL"))
    
    print(f"\n=== Issues ({len(issues)}) ===")
    for name, issue, fix in issues:
        print(f"  {name}: {issue} → {fix}")
    
    return issues

if __name__ == "__main__":
    audit()
