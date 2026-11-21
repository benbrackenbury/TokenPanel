cask "tokenpanel" do
  version "0.6.0"
  sha256 "38746a012d7d41e02ee7fdd4e9205a874725606fac8b3630ac2d43926ac77ae1"

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
