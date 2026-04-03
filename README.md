# native-ui

SwiftUI rendered from Bun over FFI. The current runtime is a PoC architecture where Bun hosts the process and manually pumps AppKit events.

## Install

```bash
bun install
```

## Run in dev

```bash
bun run dev
```

## Build a macOS app bundle

```bash
bun run build
```

This creates `dist/mativeUi.app` with:

- a compiled Bun executable
- an embedded `libmative.dylib`
- a launcher script that runs the app from `Contents/MacOS`
- a generated `Info.plist`

## Direct bridge build

```bash
swiftc -emit-library -o libmative.dylib bridge.swift -Xlinker -install_name -Xlinker @rpath/libmative.dylib
```

## API snapshot

- typed node builders for stacks, `zstack`, `scrollView`, text, buttons, spacers, dividers, and text fields
- common styling via `padding`, `frame`, `background`, `selectable`, layout priority, fixed sizing, and stack alignment
- typed native events for `action`, `change`, `submit`, and `menu`, including `source` and `label`
- menu bar sections and items configurable from TypeScript
- minimal render diffing by skipping unchanged tree and menu payloads

## Current state

- native window + SwiftUI rendering works
- Bun can send tree updates and receive button, menu, and input events
- app quit/menu handling is now bridged back to Bun
- text selection is enabled for rendered text by default
- AppKit is still polled from Bun, so this is not yet a full native app lifecycle
