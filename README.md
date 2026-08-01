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

### 2. Build and run TokenPanel

Open `TokenPanel.xcodeproj` in Xcode, choose the **TokenPanel** scheme and **My Mac**, then Run (⌘R).

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
