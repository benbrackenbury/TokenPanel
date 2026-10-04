cask "tokenpanel" do
  version "0.2.0"
  sha256 "e386c5b36501c26b51d128b2b9ea8b8f0c2ca5c57b47a07050eeef4c28c675f8"

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
