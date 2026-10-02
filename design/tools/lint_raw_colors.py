#!/usr/bin/env python3
"""Raw-colour ratchet for feature code (Phase 2 §2: "no hand-typed colours left in feature code").

Counts raw colour usages per file in the iPhone and Watch apps, outside the design
system, and compares them with design/tools/raw_colors_baseline.json:

  python3 design/tools/lint_raw_colors.py            # CI: fail if any file got worse or a new file adds raw colours
  python3 design/tools/lint_raw_colors.py --update   # after a migration: lower the baseline (never raises it silently)
  python3 design/tools/lint_raw_colors.py --report   # print per-file counts

A file may only go down. Migrating a screen to `.lx(...)` tokens and running
--update locks the gain in, so the count can only fall until it reaches zero.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BASELINE = Path(__file__).with_name("raw_colors_baseline.json")
SCAN = [ROOT / "LifeOS", ROOT / "LifeOS Watch App"]
EXCLUDE = [ROOT / "LifeOS" / "DesignSystem", ROOT / "LifeOS" / "AI"]

PATTERNS = [
    re.compile(r"Color\(\s*red:"),
    re.compile(r"Color\(\s*\.sRGB"),
    re.compile(r"UIColor\(\s*red:"),
    re.compile(r"Color\(\s*hex:"),
    # Named system colours used as styling (excludes .primary/.secondary/.clear, which adapt).
    re.compile(r"(?:foregroundColor|foregroundStyle|fill|background|tint|stroke|strokeBorder|shadow\(color:)\s*\(?\s*(?:Color)?\.(?:white|black|gray|red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown)\b"),
    re.compile(r"\bColor\.(?:white|black|gray|red|orange|yellow|green|mint|teal|cyan|blue|indigo|purple|pink|brown)\b"),
]


def count(path: Path) -> int:
    n = 0
    for line in path.read_text(errors="ignore").splitlines():
        s = line.strip()
        if s.startswith("//"):
            continue
        n += sum(len(p.findall(s)) for p in PATTERNS)
    return n


def scan() -> dict[str, int]:
    out: dict[str, int] = {}
    for base in SCAN:
        if not base.exists():
            continue
        for f in sorted(base.rglob("*.swift")):
            if any(f.is_relative_to(e) for e in EXCLUDE):
                continue
            c = count(f)
            if c:
                out[str(f.relative_to(ROOT))] = c
    return out


def main(argv: list[str]) -> int:
    current = scan()
    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else {}
    if "--report" in argv:
        for k, v in sorted(current.items(), key=lambda kv: -kv[1]):
            print(f"{v:5d}  {k}")
        print(f"{sum(current.values()):5d}  total")
        return 0
    if "--update" in argv or not BASELINE.exists():
        merged = {k: min(v, baseline.get(k, v)) if baseline else v for k, v in current.items()}
        BASELINE.write_text(json.dumps(dict(sorted(merged.items())), indent=2) + "\n")
        print(f"baseline written: {sum(merged.values())} raw colours in {len(merged)} files")
        return 0
    errors = []
    for f, n in current.items():
        allowed = baseline.get(f, 0)
        if n > allowed:
            errors.append(f"{f}: {n} raw colours (baseline {allowed}). Use .lx(<role>) tokens from LifeOS/DesignSystem.")
    for e in errors:
        print("✗", e, file=sys.stderr)
    if errors:
        return 1
    improved = sum(baseline.values()) - sum(current.values())
    print(f"✓ raw colours: {sum(current.values())} (baseline {sum(baseline.values())}{', ' + str(improved) + ' fewer — run --update to lock in' if improved > 0 else ''})")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
