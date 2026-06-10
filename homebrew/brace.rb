cask "brace" do
  version "0.2.6"

  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/Brace-#{version}.dmg"
  sha256 "e62da9c140cb84ce9c8a49a1f7d922fca7f60dce2f49d829229781fe2c737cf4"

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
