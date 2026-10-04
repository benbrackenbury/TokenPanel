cask "tokenpanel" do
  version "0.3.0"
  sha256 "9bbce79752bfe334a6c8496dd1b6d3615870b5c3a9787edbcab2156b360d9f7a"

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
