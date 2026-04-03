## Done

- baseline app lifecycle with `NSApplicationDelegate`
- app menu with `Quit mativeUi`
- quit handshake from Swift back to Bun
- runtime process name set to `mativeUi` as a partial identity fix
- common node modifiers for `padding`, `frame`, `background`, and alignment
- text inputs with change and submit events bridged back to Bun
- stable child identity via explicit node keys
- menu bar sections configurable from TypeScript
- selectable text enabled by default
- CLI build flow that produces `dist/mativeUi.app`
- minimal render diffing that skips unchanged tree and menu payloads
- stack sizing rules with min/max frame sizing, layout priority, fixed sizing, and more button style variants
- scroll containers and basic layout primitives via `scrollView`, `zstack`, and sized spacers
- richer event payloads with `type`, `source`, `label`, and `value`
- cleaner runtime structure around boot, poll, queued state, and teardown

## Next

- add structural subtree diffing instead of whole-tree JSON equality checks
- add more complete layout controls like grid, split panes, and explicit intrinsic sizing policies
- separate dev hot-reload concerns from the core runtime lifecycle

## Later

- move to smoother event loop integration with a host-owned run loop
- add a real app icon and bundle assets to the generated `.app`
- split the Swift host from the Bun logic engine if the framework graduates from PoC to product