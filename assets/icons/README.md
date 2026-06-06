# App Icons

Place PNG icons here before running `make bundle`:

| File | Size | Used for |
|------|------|----------|
| `32x32.png` | 32×32 px | Cargo.toml bundle metadata |
| `128x128.png` | 128×128 px | Cargo.toml bundle metadata |
| `512x512.png` | 512×512 px | macOS App Store / Finder |

## Generating from a master SVG / PNG

```bash
# Requires sips (built into macOS)
sips -z 32 32   master.png --out 32x32.png
sips -z 128 128 master.png --out 128x128.png
sips -z 512 512 master.png --out 512x512.png
```

For a proper `.icns` bundle (used by cargo-bundle automatically if found):
```bash
mkdir JsonView.iconset
sips -z 16 16     master.png --out JsonView.iconset/icon_16x16.png
sips -z 32 32     master.png --out JsonView.iconset/icon_16x16@2x.png
sips -z 32 32     master.png --out JsonView.iconset/icon_32x32.png
sips -z 64 64     master.png --out JsonView.iconset/icon_32x32@2x.png
sips -z 128 128   master.png --out JsonView.iconset/icon_128x128.png
sips -z 256 256   master.png --out JsonView.iconset/icon_128x128@2x.png
sips -z 256 256   master.png --out JsonView.iconset/icon_256x256.png
sips -z 512 512   master.png --out JsonView.iconset/icon_256x256@2x.png
sips -z 512 512   master.png --out JsonView.iconset/icon_512x512.png
sips -z 1024 1024 master.png --out JsonView.iconset/icon_512x512@2x.png
iconutil -c icns JsonView.iconset
mv JsonView.icns ./
```
Then reference `JsonView.icns` in `Cargo.toml` `[package.metadata.bundle] icon`.
