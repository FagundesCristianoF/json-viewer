cask "brace" do
  version "0.2.9"

  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/Brace-#{version}.dmg"
  sha256 "c7091ed303bc74a02e4f29f4467c7988df0516417239688ce3e9ffd1636cbe22"

  name "Brace"
  desc "Native macOS developer toolkit — JSON viewer, editor, and HTTP scanner"
  homepage "https://github.com/FagundesCristianoF/json-viewer"

  depends_on macos: :ventura

  app "Brace.app"

  zap trash: [
    "~/Library/Application Support/com.fagundes.brace",
    "~/Library/Preferences/com.fagundes.brace.plist",
    "~/Library/Saved Application State/com.fagundes.brace.savedState",
  ]
end
