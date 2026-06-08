cask "devkit" do
  version "0.2.0"

  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/DevKit-#{version}.dmg"
  sha256 "PLACEHOLDER"

  name "DevKit"
  desc "Native macOS developer toolkit — JSON viewer, editor, and HTTP scanner"
  homepage "https://github.com/FagundesCristianoF/json-viewer"

  depends_on macos: ">= :ventura"

  app "DevKit.app"

  zap trash: [
    "~/Library/Application Support/com.fagundes.devkit",
    "~/Library/Preferences/com.fagundes.devkit.plist",
    "~/Library/Saved Application State/com.fagundes.devkit.savedState",
  ]
end
