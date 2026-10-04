# TokenPanel

macOS menu bar app for plan usage on Grok, Cursor, Claude Code, and Codex / ChatGPT.

It reuses each product's local session. No extra API keys.

It does not track xAI, Anthropic, or OpenAI developer API prepaid balances. Claude Code only works with the claude.ai subscription login, not an API key.

## Install

**Homebrew (recommended):**

```bash
brew trust --cask benbrackenbury/tokenpanel/tokenpanel
brew tap benbrackenbury/tokenpanel https://github.com/benbrackenbury/TokenPanel
brew install --cask tokenpanel
```

Homebrew 6 refuses to load casks from an untrusted third-party tap. `brew trust` is required once per machine.

A version tag updates this tap after the GitHub Release is published. Then `brew upgrade --cask tokenpanel`.

**DMG:** [Releases](https://github.com/benbrackenbury/TokenPanel/releases)

1. Download the `.dmg` from a release
2. Open the DMG and drag TokenPanel to Applications
3. On first launch, right-click the app and choose **Open** if macOS blocks the unsigned build
4. Sign in to the tools you care about:

```bash
grok login
codex login
claude
```

Cursor: sign in inside the Cursor app.

The build is ad-hoc signed, not notarized. Gatekeeper may ask you to Open it from the context menu once.

**From source:** open `TokenPanel.xcodeproj` in Xcode, choose the TokenPanel scheme and My Mac, then Run (⌘R).

## Use

Look for TokenPanel in the menu bar. There is no Dock icon.

- Click the icon to open the usage panel
- Switch providers when more than one session is present
- Refresh updates numbers immediately
- Settings chooses which provider's percentage shows in the menu bar, or shows all connected sessions at once. You can also change the auto-refresh interval, hide the percentage, and point at a different Grok session file.

Desktop widgets (small, medium, large, extra large) live in the macOS widget gallery under TokenPanel. Edit Widget has a toggle for each provider, so one tile can show just Grok or several at once. Widgets read the last refresh from the menu bar app, so keep TokenPanel running.

If numbers stop loading, sign in again in that product (sessions expire), then refresh.

## How it works

1. Sign in once in that product (`grok login`, Cursor, `claude`, or `codex login`).
2. TokenPanel reads that session and asks the same usage endpoint the product uses.
3. The menu bar shows how much you've used, when it resets, and a per-product breakdown.

Usage endpoints are undocumented and can change. Product labels in the breakdown are best-effort.
