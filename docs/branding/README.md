# TindaSari PH branding

`TindaSari_PH_Brand_Guidelines.png` is an unchanged copy of the user-supplied `logos.png` and the approved visual reference, not an application asset.

Open `review.html` to compare the first hand-traced SVG with the reference.
The editable draft is `assets/branding/source/tindasari_ts_review.svg`.
The user approved this symbol trace and authorized the horizontal wordmark and app integration.

Open `wordmark-review.html` for the proposed horizontal logo, sidebar-scale
preview, and light/dark icons. These previews embed SVG directly to avoid
broken local image paths. The horizontal wordmark uses Arial Rounded MT Bold
as an approved visual match, not an exact tracing. The SVG source retains live text;
Flutter uses rendered PNGs so installed fonts do not affect its appearance.
The approved TS paths are unchanged.

## Android launcher

The light TS icon is now configured for the launcher, with the visible name
`TindaSari PH`. Android 8+ uses separate adaptive foreground/background resources;
the foreground is inset to keep the complete TS silhouette inside launcher masks.
Android 5–7 uses a vector icon override. The source paths and brand colors are
unchanged. Existing bitmap resources remain as fallbacks.

The trace follows the icon-only panel, using flat primary green `#0F6B46`
and mint `#A7D7B4`. It omits raster damage and shading; it is not claimed to
recover the exact original paths. Background: `#F8FAF9`. Text: `#1F2D28`.

Flutter uses the horizontal logo in the expanded sidebar and icon-only branding
when collapsed. Login, startup, and About use the TS icon and TindaSari PH name.
The Android launch background also uses the TS mark. Internal database, package,
and backup identifiers remain unchanged for compatibility.
Retain the original sheet as the master reference.
