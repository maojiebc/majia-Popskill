---
version: alpha
name: Popskill
belongsTo: "A Mac-native AI capability App Store with a Surge-inspired utility surface."
description: |
  Popskill uses Apple system colors, SF Pro / SF Mono typography, an 8pt
  spacing grid, restrained section accents, and native macOS split-view
  structure. The product signature is capability management that feels like a
  Mac utility: quick scanning, direct controls, quiet surfaces, and large
  readable metrics.
colors:
  background-main: "windowBackgroundColor"
  background-card: "controlBackgroundColor"
  background-header: "unemphasizedSelectedContentBackgroundColor"
  label: "labelColor"
  label-secondary: "secondaryLabelColor"
  label-tertiary: "tertiaryLabelColor"
  separator: "separatorColor"
  border: "rgba(separatorColor, 0.58)"
  hover-fill: "rgba(accentColor, 0.08)"
  highlight-fill: "rgba(accentColor, 0.15)"
  section-orange: "#FF9500"
  section-purple: "#AF52DE"
  section-blue: "#007AFF"
  section-green: "#34C759"
  status-ok: "#34C759"
  status-warning: "#FF9500"
  status-error: "#FF3B30"
  status-neutral: "secondaryLabelColor"
typography:
  display-xl:
    fontFamily: "SF Pro Rounded"
    fontSize: "48px"
    fontWeight: 700
    usage: "Hero metric, token count, high-value number"
  display-lg:
    fontFamily: "SF Pro"
    fontSize: "32px"
    fontWeight: 700
    usage: "Page title"
  heading-lg:
    fontFamily: "SF Pro"
    fontSize: "22px"
    fontWeight: 600
    usage: "Detail title"
  heading-md:
    fontFamily: "SF Pro"
    fontSize: "17px"
    fontWeight: 600
    usage: "Card or row title"
  body-md:
    fontFamily: "SF Pro"
    fontSize: "14px"
    fontWeight: 400
    usage: "Primary body text"
  body-sm:
    fontFamily: "SF Pro"
    fontSize: "12px"
    fontWeight: 400
    usage: "Secondary metadata"
  metric:
    fontFamily: "SF Mono"
    fontSize: "28px"
    fontWeight: 600
    usage: "Tabular numbers and counters"
  caption:
    fontFamily: "SF Pro"
    fontSize: "11px"
    fontWeight: 600
    letterSpacing: "0px"
    textTransform: "uppercase"
    usage: "Colored section label"
---

## 1. Visual Theme & Atmosphere

Popskill should feel like a native Mac asset manager, not a web dashboard. The mood is calm, utilitarian, and precise: light/dark adaptive surfaces, native controls, compact information density, and enough whitespace to keep repeated maintenance work comfortable.

Use color as a signal, not as decoration. Large areas stay neutral; accent color appears in CTA controls, selected states, status dots, and section labels. The app should feel closer to Surge, Raycast, Finder, and System Settings than to a SaaS landing page.

## 2. Color Palette & Roles

Use system colors first. Custom RGB is only allowed for the four section accents and standard macOS status colors listed in frontmatter.

Foundation:
- Main background: `Color.popMainBackground`
- Card surface: `Color.popCardBackground`
- Header strip: `Color.popHeaderBackground`
- Hairline border: `Color.popBorder`

Content accents:
- Orange, purple, blue, green rotate through section labels.
- Purple identifies composite capability packages.
- Blue identifies standalone packages and skill-focused components.

Status:
- Green means installed, verified, healthy, or enabled.
- Orange means declared, available, pending, warning, or needs setup.
- Red means blocked, destructive, or failed.
- Secondary label color means neutral or unavailable.

## 3. Typography Rules

Use SF Pro for UI and SF Mono only for tabular metrics, hashes, paths, and code-like identifiers. Do not add custom fonts.

Hierarchy:
- Page title: 32px, bold.
- Detail title: 22px, semibold.
- Row title: headline, semibold, one line when possible.
- Body copy: 14px, regular.
- Metadata: 12px, secondary.
- Status pill: caption2, semibold.
- Metric: rounded or monospaced digits, 26-48px depending on density.

Do not scale font size with viewport width. Letter spacing stays `0`; uppercase section labels use `.textCase(.uppercase)` rather than manually uppercasing strings.

## 4. Component Stylings

Buttons:
- Primary actions use `.borderedProminent` with icons where possible.
- Secondary actions use `.bordered`.
- Row-local actions use fixed minimum widths so labels do not jitter.
- Destructive actions stay explicit but visually quiet until confirmation.

Cards:
- Detail cards use 8px radius and subtle shadow.
- Repeated list rows are not wrapped in extra cards.
- Do not put cards inside cards.

Navigation:
- Sidebar selected state uses accent opacity around `0.15`, 6px radius, and primary readable text.
- Avoid the default full blue selected row when it blocks labels or badges.
- Badges use capsules with subtle opacity, never high-contrast blocks.

Package rows:
- Composite packages use a purple package icon and can reveal a component tree.
- Standalone packages use a blue document/package icon and show a compact component line.
- Component status is always visible through icon color and a small status pill.

## 5. Layout Principles

Use an 8pt grid:
- `xs`: 4
- `sm`: 8
- `md`: 16
- `lg`: 24
- `xl`: 32
- `2xl`: 48
- `3xl`: 64

Core dimensions:
- Sidebar width: 220-280px.
- Detail pane width: 320-400px.
- List row min height: 68px for compact rows, 94px for skill rows, 130px for expanded composite package rows.
- Header padding: 28px horizontal, 18-20px vertical.

Section rhythm:
- Large page blocks: 64-96px.
- Settings/detail card stacks: 20-24px.
- Row internal spacing: 5-14px.

## 6. Depth & Elevation

Depth is subtle. Most separation should come from system surfaces, dividers, hairline borders, and spacing.

Radii:
- Sidebar selected row: 6px.
- Buttons: 6px.
- Small cards/avatar tiles: 8px.
- Larger grouped surfaces: 12px.

Shadows:
- Card shadow opacity around 0.02-0.04.
- Elevated panels may use 0.08.
- Avoid large glowing shadows, gradient blobs, or decorative orbs.

## 7. Do's And Don'ts

Do:
- Keep Mac-native controls and platform behavior.
- Keep list rows scannable with title, metadata, status, then actions.
- Show capability packages as user-facing products and components as their tree.
- Preserve existing skill management workflows while adding package-level views.
- Localize visible navigation, titles, buttons, empty states, and primary labels.

Do not:
- Do not make Popskill feel like a marketing landing page.
- Do not hide skill toggles behind a package-only abstraction.
- Do not accept secrets in argv or visible logs.
- Do not delete `STYLE.md`; it remains the detailed teardown and token reference.
- Do not modify the `cc-switch/` submodule for Popskill UI iteration.

## 8. Page-Specific Rules

Discover:
- First screen should expose capability packages and standalone skills as two browse modes.
- Package rows may be read-only previews in v0.3.
- Install controls remain tied to the existing skill install flow.

Library:
- Header shows package count, skill count, and enabled count.
- Filter package type with All / Composite / Standalone.
- All mode preserves installed skill rows below capability packages.
- Composite package rows should make the component tree visible quickly.

Agents:
- Treat agents as role/persona files, not runtime execution.
- Show category, tools, model, file path, and target diagnostics.

Insights:
- Emphasize metrics and attribution, not dense charts.
- Avoid reading transcript message bodies for attribution.

Settings:
- Keep diagnostics compact.
- Language switch belongs near the top and must apply immediately.
- Secrets and WebDAV boundaries should be explicit and calm.

## 9. Agent Prompt Guide

When generating Popskill UI, follow this prompt pattern:

```text
Build a SwiftUI macOS 14 view following Popskill DESIGN.md.
Use NavigationSplitView or existing page containers.
Use system colors, 8pt spacing, 8px cards, 6px sidebar selected rows.
Use SF Symbols for controls and status. Avoid decorative gradients.
Preserve existing skill workflows while exposing capability packages.
Localize visible strings with Localizable.strings keys or LocalizedStringKey.
```

For Library/package work:

```text
Show capability packages as first-class rows. Composite rows include CLI,
Skill, MCP, Agent, and Config status. Standalone rows stay compact. Existing
Skill rows and app toggles remain available in All mode.
```

