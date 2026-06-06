cask "dev-json-viewer" do
  version "0.1.2"

  # Update url and sha256 after each release (run `make brew-sha` to get the hash).
  url "https://github.com/FagundesCristianoF/json-viewer/releases/download/v#{version}/JsonViewer-#{version}.dmg"
  sha256 "597c70875c8e795f0dbe35677ed7c4d85590a389357c99abdfc4bd0d37dc54f9"

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
