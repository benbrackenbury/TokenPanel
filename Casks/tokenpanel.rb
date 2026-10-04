cask "tokenpanel" do
  version "0.2.1"
  sha256 "27c99b9fa7ba910e3c81998b636a8448054185ad3f300f74c63a50ec86692277"

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
