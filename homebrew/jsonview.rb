cask "jsonview" do
  version "0.1.0"

  # Update url and sha256 after each release (run `make brew-sha` to get the hash).
  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/JsonViewer-#{version}.dmg"
  sha256 "REPLACE_WITH_SHA256_FROM_make_brew-sha"

  name "Json Viewer"
  desc "Fast native macOS JSON workspace — browse, edit, and query JSON with JSONPath"
  homepage "https://github.com/FagundesCristianoF/json-viewer"

  # macOS 12+ (Monterey) required
  depends_on macos: ">= :monterey"

  app "Json Viewer.app"

  zap trash: [
    "~/Library/Application Support/json-viewer",
    "~/Library/Preferences/com.fagundes.jsonview.plist",
  ]
end
