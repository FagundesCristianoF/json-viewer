cask "brace" do
  version "0.2.8"

  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/Brace-#{version}.dmg"
  sha256 "66c28130785b069b46c382dc40b98e5baaa3bc3b2ef90ea7268e58527eb54cba"

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
