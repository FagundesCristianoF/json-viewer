cask "json-viewer" do
  version "0.1.1"

  # Update url and sha256 after each release (run `make brew-sha` to get the hash).
  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/JsonViewer-#{version}.dmg"
  sha256 "c5674ede897f69b343f10332f77cb88200029ca94085b133a74aa8e5f927562e"

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
