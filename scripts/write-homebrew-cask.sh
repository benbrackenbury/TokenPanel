#!/usr/bin/env bash
# write-homebrew-cask.sh <version> <sha256>
# Rewrites Casks/tokenpanel.rb for the given GitHub Release DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${CASK_PATH:-$ROOT/Casks/tokenpanel.rb}"

self_check() {
  local dir version sha
  dir="$(mktemp -d "${TMPDIR:-/tmp}/tokenpanel-cask.XXXXXX")"
  trap 'rm -rf "$dir"' RETURN
  export CASK_PATH="$dir/tokenpanel.rb"
  version="1.2.3"
  sha="e386c5b36501c26b51d128b2b9ea8b8f0c2ca5c57b47a07050eeef4c28c675f8"
  "$0" "$version" "$sha"
  grep -q "version \"$version\"" "$CASK_PATH"
  grep -q "sha256 \"$sha\"" "$CASK_PATH"
  grep -q "TokenPanel-#{version}.dmg" "$CASK_PATH"
  grep -q 'strategy :github_latest' "$CASK_PATH"
  if "$0" "nope" "$sha" 2>/dev/null; then
    echo "expected invalid version to fail" >&2
    return 1
  fi
  if "$0" "$version" "deadbeef" 2>/dev/null; then
    echo "expected invalid sha256 to fail" >&2
    return 1
  fi
  echo "self-check ok"
}

if [[ "${1:-}" == "--self-check" ]]; then
  self_check
  exit 0
fi

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <version> <sha256>" >&2
  exit 1
fi

VERSION="$1"
SHA256="$(printf '%s' "$2" | tr 'A-F' 'a-f')"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?([.-].*)?$ ]]; then
  echo "Invalid version: $VERSION" >&2
  exit 1
fi

if [[ ! "$SHA256" =~ ^[a-f0-9]{64}$ ]]; then
  echo "sha256 must be 64 hex characters (got: $SHA256)" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<RUBY
cask "tokenpanel" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/benbrackenbury/TokenPanel/releases/download/v#{version}/TokenPanel-#{version}.dmg"
  name "TokenPanel"
  desc "Menu bar app for Grok, Cursor, Claude, and Codex plan usage"
  homepage "https://github.com/benbrackenbury/TokenPanel"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :golden_gate

  app "TokenPanel.app"

  zap trash: [
    "~/Library/Preferences/devplaceholder.P74EYVEP.TokenPanel.plist",
  ]

  caveats <<~EOS
    TokenPanel is ad-hoc signed and not notarized. If macOS refuses to
    open it, right-click the app and choose Open.
  EOS
end
RUBY

echo "Wrote $OUT (version=$VERSION)"
