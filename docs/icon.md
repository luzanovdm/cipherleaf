# App icon

`Resources/Cipherleaf.icon` is the only app-icon source. It is an Apple Icon
Composer document containing a vector glass-leaf mark with a recessed keyhole.

The icon is intentionally near-monochrome:

- the organic leaf is rendered as a translucent glass layer;
- the keyhole is a dark inset with a restrained inner rim, not a raised object;
- the keyhole follows the leaf's optical center instead of the canvas center;
- the leaf tip and lower corner are softly rounded;
- horizontal, irregular cipher glyphs fade toward the leaf edges;
- cipher glyphs are stored as vector outlines for deterministic rendering;
- there is no accent color or legacy asset-catalog fallback.

Render a local 1024 px preview:

```sh
Scripts/render-icon.sh
```

Xcode compiles the `.icon` document into `Cipherleaf.icns` and `Assets.car`.
The packaging script fails if either compiled resource is absent.
