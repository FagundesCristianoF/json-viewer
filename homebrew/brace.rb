cask "brace" do
  version "0.2.3"

  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/Brace-#{version}.dmg"
  sha256 "869446575cde4abb494bb5f030766086e695be74e77741360009b562725663e3"

  name "Brace"
  desc "Native macOS developer toolkit — JSON viewer, editor, and HTTP scanner"
  homepage "https://github.com/FagundesCristianoF/json-viewer"

  depends_on macos: ">= :ventura"

  app "Brace.app"

  zap trash: [
    "~/Library/Application Support/com.fagundes.brace",
    "~/Library/Preferences/com.fagundes.brace.plist",
    "~/Library/Saved Application State/com.fagundes.brace.savedState",
  ]
end
