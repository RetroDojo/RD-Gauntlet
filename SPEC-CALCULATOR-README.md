# Console-to-Screen Scaling Calculator

Standalone static reference tool for retro-native-resolution scaling math.

- Main file: `console-to-screen-calculator.html`
- Device DB: `device-specs.json`
- Console DB: `console-specs.json`

## What it does

Pick a **console/system** and a **handheld device** and it computes:

- Native console resolution
- Device panel resolution + diagonal + calculated PPI
- Largest integer scale factor that fits
- Resulting integer-scaled content size and black bars/pillarbox in pixels
- Non-integer fit scale and full-screen stretch factors
- Aspect-ratio distortion % if stretched to full screen
- Simple visual comparison of device panel vs centered integer-scaled content

## Running it

Open `console-to-screen-calculator.html` directly in a browser.

- Preferred path: keep `device-specs.json` and `console-specs.json` in the same folder.
- Some browsers block `fetch()` from `file://` for local JSON. To keep this tool usable without a server, the HTML includes a small fallback dataset when JSON fetch is blocked.

## Data conventions

### `device-specs.json`

Each device entry uses:

- `id`: stable slug
- `name`
- `panelWidth`, `panelHeight` (pixels)
- `diagonalInches`
- `specSource`: URL or note describing source
- `sourceType`: `official`, `third-party catalog`, etc.
- `verification`: `verified` or `unverified - needs confirmation`
- optional: `wmSizeMeasured`, `notes`, `panelCount`
- for controller-only inventory items, set `panelWidth/panelHeight/diagonalInches` to `null` and add `isScreenDevice: false`

For this repo-specific requirement:

- `RPC6` uses measured `wmSize` **1240x1080** from suite artifacts.
- `RG476H` uses measured `wmSize` **1280x960** from suite artifacts.

### `console-specs.json`

Each console entry uses:

- `id`, `name`, `shortName`
- `nativeModes`: array of one or more `{ label, width, height }`
- `notes` for caveats (variable-resolution systems, anamorphic modes, etc.)

## Adding new devices/consoles

1. Add a JSON object in the relevant file.
2. Include a real source in `specSource`.
3. If uncertain, set `verification` to `unverified - needs confirmation` (do not guess).
4. Keep names human-readable and IDs stable for future references.

## Source notes

- Console native-resolution references are standard retro-emulation baseline values with caveats noted in `console-specs.json`.
- Device entries use RetroCatalog/Retrosizer as discovery aids, then cross-check against official manufacturer pages (Anbernic/Retroid/AYN/AYANEO/Valve) or reputable review coverage.
- Entries that still lack trustworthy first-party confirmation remain marked `unverified - needs confirmation`.
