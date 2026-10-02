#!/usr/bin/env python3
"""LifeOS design-token generator.

Reads design/tokens/*.json (the single source of truth) and writes
LifeOS/DesignSystem/Tokens/LXTokens.generated.swift.

  python3 tools/design-tokens/gen_tokens.py          # regenerate
  python3 tools/design-tokens/gen_tokens.py --check  # CI: fail if stale or a rule breaks
  python3 tools/design-tokens/gen_tokens.py --report # print the contrast / colour-blind sheet (Markdown)

Zero dependencies (stdlib only) so it runs on a free Mac with only the Command
Line Tools. It plays the role Style Dictionary plays in the UI/UX plan
(Phase 2 §2) without needing node_modules in the repo.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOKENS = ROOT / "design" / "tokens"
OUT = ROOT / "LifeOS" / "DesignSystem" / "Tokens" / "LXTokens.generated.swift"
DIRECTION_ORDER = ["obsidian", "porcelain", "aurora"]
MODES = ["dark", "light"]

# --------------------------------------------------------------------------- colour maths

def _lin(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def rgb(hex_: str) -> tuple[float, float, float]:
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))  # type: ignore[return-value]


def luminance(hex_: str) -> float:
    r, g, b = (_lin(c) for c in rgb(hex_))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a: str, b: str) -> float:
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


# Machado et al. (2009) full-severity CVD matrices, applied in linear RGB.
CVD = {
    "protanopia": ((0.152286, 1.052583, -0.204868), (0.114503, 0.786281, 0.099216), (-0.003882, -0.048116, 1.051998)),
    "deuteranopia": ((0.367322, 0.860646, -0.227968), (0.280085, 0.672501, 0.047413), (-0.011820, 0.042940, 0.968881)),
    "tritanopia": ((1.255528, -0.076749, -0.178779), (-0.078411, 0.930809, 0.147602), (0.004733, 0.691367, 0.303900)),
}


def _to_lab(lin: tuple[float, float, float]) -> tuple[float, float, float]:
    r, g, b = (min(max(c, 0.0), 1.0) for c in lin)
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116  # noqa: E731
    fx, fy, fz = f(x), f(y), f(z)
    return 116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)


def delta_e(a: str, b: str, cvd: str | None = None) -> float:
    def lin(h: str):
        v = tuple(_lin(c) for c in rgb(h))
        if cvd:
            m = CVD[cvd]
            v = tuple(sum(m[i][j] * v[j] for j in range(3)) for i in range(3))
        return v
    la, lb = _to_lab(lin(a)), _to_lab(lin(b))
    return math.dist(la, lb)


# --------------------------------------------------------------------------- loading

def load():
    core = json.loads((TOKENS / "core.json").read_text())
    shared = json.loads((TOKENS / "color.shared.json").read_text())
    directions = [json.loads((TOKENS / "directions" / f"{d}.json").read_text()) for d in DIRECTION_ORDER]
    return core, shared, directions


def roles(shared, direction) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = dict(direction["color"])
    for k, v in shared["data"].items():
        out["data" + k[0].upper() + k[1:]] = v
    for k, v in shared["status"].items():
        out["status" + k[0].upper() + k[1:]] = v
    return out


# --------------------------------------------------------------------------- rules (Phase 2 §3)

RULES = [
    # (role, against, minimum, why)
    ("textPrimary", "background", 7.0, "primary text ≥ 7:1 on background"),
    ("textPrimary", "surfaceRaised", 4.5, "primary text ≥ 4.5:1 on raised surface"),
    ("textSecondary", "surface", 4.5, "secondary text ≥ 4.5:1 on its surface"),
    ("textSecondary", "background", 4.5, "secondary text ≥ 4.5:1 on background"),
    ("textTertiary", "background", 3.0, "tertiary text ≥ 3:1"),
    ("accentPrimary", "background", 4.5, "accent usable as text/icons (fixes A11)"),
    ("accentPrimary", "surface", 4.5, "accent usable on cards"),
    ("onAccent", "accentPrimary", 4.5, "label on a filled accent button"),
]
DATA_MIN = 4.5   # data colours label numbers directly, so they meet body-text contrast
CVD_MIN_DE = 8.0  # minimum ΔE (CIE76) between any two data colours under each CVD simulation
CVD_EXEMPT = {frozenset({"dataEnergy", "dataCarbs"}), frozenset({"dataSleep", "dataWater"})}


def check_rules(shared, directions) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    report: list[str] = []
    for d in directions:
        r = roles(shared, d)
        report.append(f"\n### {d['name']}\n\n| Pair | Dark | Light | Min |\n| --- | --- | --- | --- |")
        for role, against, minimum, why in RULES:
            vals = []
            for mode in MODES:
                c = contrast(r[role][mode], r[against][mode])
                vals.append(c)
                if c < minimum:
                    errors.append(f"{d['id']}.{mode}: {role} on {against} = {c:.2f} < {minimum} ({why})")
            report.append(f"| `{role}` on `{against}` | {vals[0]:.1f}:1 | {vals[1]:.1f}:1 | {minimum}:1 |")
        for role in r:
            if role.startswith(("data", "status")):
                for mode in MODES:
                    for bg in ("background", "surface", "surfaceRaised"):
                        c = contrast(r[role][mode], r[bg][mode])
                        if c < DATA_MIN:
                            errors.append(f"{d['id']}.{mode}: {role} on {bg} = {c:.2f} < {DATA_MIN}")
    data = {k: v for k, v in roles(shared, directions[0]).items() if k.startswith("data")}
    names = sorted(data)
    report.append("\n### Data colours under colour-blindness simulation (min ΔE between any pair)\n")
    report.append("| Mode | Normal | Protanopia | Deuteranopia | Tritanopia |\n| --- | --- | --- | --- | --- |")
    for mode in MODES:
        row = []
        for cvd in (None, "protanopia", "deuteranopia", "tritanopia"):
            worst = (1e9, "")
            for i, a in enumerate(names):
                for b in names[i + 1:]:
                    de = delta_e(data[a][mode], data[b][mode], cvd)
                    if de < worst[0]:
                        worst = (de, f"{a}/{b}")
                    if cvd and de < CVD_MIN_DE and frozenset({a, b}) not in CVD_EXEMPT:
                        errors.append(f"data.{mode}: {a} vs {b} ΔE {de:.1f} < {CVD_MIN_DE} under {cvd}")
            row.append(f"{worst[0]:.1f} ({worst[1]})")
        report.append(f"| {mode} | " + " | ".join(row) + " |")
    report.append(
        "\nExempt pairs (never shown side by side without labels): "
        + ", ".join(sorted("/".join(sorted(p)) for p in CVD_EXEMPT))
        + ". Every chart labels its series directly (Phase 2 §3.3)."
    )
    return errors, report


# --------------------------------------------------------------------------- Swift emission

def hex_literal(h: str) -> str:
    return "0x" + h.lstrip("#").upper()


def swift_string(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(core, shared, directions) -> str:
    role_names = list(roles(shared, directions[0]).keys())
    L: list[str] = []
    w = L.append
    w("// GENERATED FILE — DO NOT EDIT.")
    w("// Source: design/tokens/*.json · Generator: tools/design-tokens/gen_tokens.py")
    w("// Regenerate with: python3 tools/design-tokens/gen_tokens.py")
    w("")
    w("import SwiftUI")
    w("")
    w("/// The three Phase 1 visual directions. The owner picks one at gate D1;")
    w("/// all three stay selectable in the Direction Lab until then.")
    w("enum LXDirection: String, CaseIterable, Codable, Identifiable, Sendable {")
    for d in directions:
        w(f"    case {d['id']}")
    w("")
    w("    nonisolated var id: String { rawValue }")
    w("")
    w("    nonisolated var displayName: String {")
    w("        switch self {")
    for d in directions:
        w(f"        case .{d['id']}: return {swift_string(d['name'])}")
    w("        }")
    w("    }")
    w("")
    w("    nonisolated var mood: String {")
    w("        switch self {")
    for d in directions:
        w(f"        case .{d['id']}: return {swift_string(d['mood'])}")
    w("        }")
    w("    }")
    w("")
    w("    /// Font design for numbers and display type.")
    w("    nonisolated var numericDesign: Font.Design {")
    w("        switch self {")
    for d in directions:
        w(f"        case .{d['id']}: return .{d['numericDesign']}")
    w("        }")
    w("    }")
    w("")
    w("    nonisolated var displayDesign: Font.Design {")
    w("        switch self {")
    for d in directions:
        w(f"        case .{d['id']}: return .{d['displayDesign']}")
    w("        }")
    w("    }")
    w("")
    w("    /// Multiplier on spring bounce: 0 = weighty and precise, 1 = lightly springy.")
    w("    nonisolated var motionBounceScale: Double {")
    w("        switch self {")
    for d in directions:
        w(f"        case .{d['id']}: return {d['motionBounceScale']}")
    w("        }")
    w("    }")
    w("")
    w("    /// Where Liquid Glass is allowed: controls only, the tab bar, or every floating layer.")
    w("    nonisolated var glassUsage: LXGlassUsage {")
    w("        switch self {")
    for d in directions:
        w(f"        case .{d['id']}: return .{d['glassUsage']}")
    w("        }")
    w("    }")
    w("}")
    w("")
    w("enum LXGlassUsage: String, Sendable { case controls, tabBar, everywhere }")
    w("")
    w("/// Semantic colour roles (Phase 2 §3). Feature code names a role, never a hex value.")
    w("enum LXColorRole: String, CaseIterable, Sendable {")
    for r in role_names:
        w(f"    case {r}")
    w("}")
    w("")
    w("enum LXTokens {")
    w("    /// sRGB hex values for one role: (dark, light).")
    w("    struct Pair: Sendable, Equatable { let dark: UInt32; let light: UInt32 }")
    w("")
    w("    nonisolated static func pair(_ role: LXColorRole, _ direction: LXDirection) -> Pair {")
    w("        switch direction {")
    for d in directions:
        r = roles(shared, d)
        w(f"        case .{d['id']}:")
        w("            switch role {")
        for name in role_names:
            w(f"            case .{name}: return Pair(dark: {hex_literal(r[name]['dark'])}, light: {hex_literal(r[name]['light'])})")
        w("            }")
    w("        }")
    w("    }")
    w("")
    w("    struct OrbPalette: Sendable { let liquidTop: UInt32; let liquidBottom: UInt32; let rim: UInt32; let shell: String }")
    w("")
    w("    nonisolated static func orb(_ direction: LXDirection) -> OrbPalette {")
    w("        switch direction {")
    for d in directions:
        o = d["orb"]
        w(f"        case .{d['id']}: return OrbPalette(liquidTop: {hex_literal(o['liquidTop'])}, liquidBottom: {hex_literal(o['liquidBottom'])}, rim: {hex_literal(o['rim'])}, shell: {swift_string(o['shell'])})")
    w("        }")
    w("    }")
    w("")
    w("    enum Space {")
    for k, v in core["space"].items():
        name = f"s{k}" if k[0].isdigit() else k
        w(f"        nonisolated static let {name}: CGFloat = {v}")
    w("    }")
    w("")
    w("    enum Radius {")
    for k, v in core["radius"].items():
        w(f"        nonisolated static let {k}: CGFloat = {v}")
    w("    }")
    w("")
    w("    struct TypeSpec: Sendable { let size: CGFloat; let lineHeight: CGFloat; let weight: Font.Weight; let relativeTo: Font.TextStyle; let isDisplay: Bool }")
    w("")
    w("    enum TypeRamp {")
    for k, v in core["type"].items():
        w(f"        nonisolated static let {k} = TypeSpec(size: {v['size']}, lineHeight: {v['lineHeight']}, weight: .{v['weight']}, relativeTo: .{v['relativeTo']}, isDisplay: {'true' if v['family'] == 'display' else 'false'})")
    w("    }")
    w("")
    w("    enum Motion {")
    for k, v in core["motion"].items():
        if isinstance(v, dict):
            w(f"        nonisolated static let {k}Duration: Double = {v['duration']}")
            if "bounce" in v:
                w(f"        nonisolated static let {k}Bounce: Double = {v['bounce']}")
        else:
            w(f"        nonisolated static let {k}: Double = {v}")
    w("    }")
    w("")
    w("    enum Orb {")
    for k, v in core["orb"].items():
        w(f"        nonisolated static let {k}: CGFloat = {v}")
    w("    }")
    w("}")
    w("")
    return "\n".join(L)


def main(argv: list[str]) -> int:
    core, shared, directions = load()
    errors, report = check_rules(shared, directions)
    source = emit(core, shared, directions)
    if "--report" in argv:
        print("## Contrast and colour-blindness sheet (generated)\n")
        print("\n".join(report))
    if "--check" in argv:
        if not OUT.exists() or OUT.read_text() != source:
            errors.append(f"{OUT.relative_to(ROOT)} is stale — run python3 tools/design-tokens/gen_tokens.py")
        for e in errors:
            print("✗", e, file=sys.stderr)
        if errors:
            return 1
        print("✓ tokens up to date; all contrast and colour-blindness rules pass")
        return 0
    if errors:
        for e in errors:
            print("✗", e, file=sys.stderr)
        return 1
    if "--report" not in argv:
        OUT.parent.mkdir(parents=True, exist_ok=True)
        OUT.write_text(source)
        print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
