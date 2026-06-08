cask "brace" do
  version "0.2.2"

  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/Brace-#{version}.dmg"
  sha256 "ac09e5867e5403b09c28ad0a84a90b198f2994a3e5e596cbe422ba3867c36fc8"

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
