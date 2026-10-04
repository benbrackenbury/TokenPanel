# TokenPanel

A macOS menu bar app that shows **plan usage** for tools you already signed into on this Mac.

Supported:

- [x] Grok (SuperGrok credits)
- [x] Cursor
- [x] Claude Code
- [x] Codex / ChatGPT

It does **not** track xAI, Anthropic, or OpenAI developer API prepaid balances. Claude Code only works with the subscription (claude.ai) login, not an API key.

## How it works

TokenPanel reuses each product’s local session. No extra API keys.

1. Sign in once in that product (`grok login`, Cursor, `claude`, or `codex login`).
2. The app reads that session and asks the same usage endpoint the product uses.
3. The menu bar shows how much you’ve used, when it resets, and a per-product breakdown.

Pick which provider’s percentage appears in the menu bar in Settings, or turn on **Show all providers in menu bar** to stack every connected session.

Usage endpoints are undocumented and can change. Product labels in the breakdown are best-effort.

## How to use

### 1. Sign in to the tools you care about

```bash
grok login
codex login
claude
```

Cursor: sign in inside the Cursor app.

### 2. Install TokenPanel

**From a release (recommended):** download the DMG from [GitHub Releases](../../releases), open it, and drag TokenPanel to Applications. On first launch, right-click → **Open** if macOS warns about an unsigned app.

**From source:** open `TokenPanel.xcodeproj` in Xcode, choose the **TokenPanel** scheme and **My Mac**, then Run (⌘R).

### 3. Use the menu bar

Look for the TokenPanel icon in the menu bar (there is no Dock icon).

- Click the icon to open the usage panel
- Use the provider switcher when more than one session is present
- **Refresh** updates numbers immediately
- **Settings** lets you:
  - Choose which provider’s percentage shows in the menu bar, or show all connected providers at once
  - Change how often usage auto-refreshes
  - Show or hide the percentage next to the menu bar icon
  - Point at a different Grok session file if needed
- Links open that product’s usage and billing pages

If numbers stop loading, sign in again in that product (sessions expire), then refresh.

## Releases

Pushing a version tag builds a macOS app and publishes a DMG on GitHub Releases:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Tags must look like `v1.0.0` (optional pre-release suffixes such as `v1.0.0-beta.1` are treated as pre-releases). Builds are ad-hoc signed, not notarized.
