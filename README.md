# TokenPanel

A macOS menu bar app that shows your **Grok usage** — SuperGrok credits for chat, voice, Build, Imagine, and related products.

**More providers coming later**:

- [x] Grok
- [] Cursor

Maybe:

- [] Claude
- [] Codex/ChatGPT

It does **not** track xAI developer API spend or prepaid API balance.

## How it works

TokenPanel uses the same login session as Grok Build:

1. You sign in with `grok login` (once).
2. The app reads that session and asks grok.com for your current credit usage.
3. The menu bar shows how much you’ve used, when it resets, and a breakdown by product.

Usage numbers come from Grok’s account credits surface (not a public developer API). Product labels in the breakdown are best-effort.

## How to use

### 1. Sign in to Grok

```bash
grok login
```

### 2. Install TokenPanel

**From a release (recommended):** download the DMG from [GitHub Releases](../../releases), open it, and drag TokenPanel to Applications. On first launch, right-click → **Open** if macOS warns about an unsigned app.

**From source:** open `TokenPanel.xcodeproj` in Xcode, choose the **TokenPanel** scheme and **My Mac**, then Run (⌘R).

### 3. Use the menu bar

Look for the TokenPanel icon in the menu bar (there is no Dock icon).

- Click the icon to open the usage panel
- **Refresh** updates numbers immediately
- **Settings** lets you:
  - Change how often usage auto-refreshes
  - Show or hide the percentage next to the menu bar icon
  - Point at a different session file if needed
- Links open Grok’s usage and billing pages on grok.com

If numbers stop loading, run `grok login` again (sessions expire after about a week), then refresh.

## Releases

Pushing a version tag builds a macOS app and publishes a DMG on GitHub Releases:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Tags must look like `v1.0.0` (optional pre-release suffixes such as `v1.0.0-beta.1` are treated as pre-releases). Builds are ad-hoc signed, not notarized.
