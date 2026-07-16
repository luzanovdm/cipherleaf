# App icon

`Resources/Cipherleaf.icon` is the only app-icon source. It is an Apple Icon
Composer document containing a vector leaf-lock mark.

The icon is intentionally near-monochrome:

- the leaf forms the lock body;
- the separate lightweight shackle is optically shifted left and down;
- the leaf tip is slightly rounded;
- horizontal, irregular cipher text fades toward the leaf edges;
- there is no accent color or legacy asset-catalog fallback.

Render a local 1024 px preview:

```sh
Scripts/render-icon.sh
```

Xcode compiles the `.icon` document into `Cipherleaf.icns` and `Assets.car`.
The packaging script fails if either compiled resource is absent.
