# Third-Party Notices

These are licence terms, not credits. The thank-you list lives in `README.md`
and in the addon's About tab; this file exists because the code below arrived
under conditions that travel with it.

Floos as a whole is distributed under the **GNU General Public License v3.0**,
because it contains code derived from XIUI.

## XIUI

Floos's panel backgrounds, progress bars, and related UI rendering are adapted from
[XIUI](https://github.com/tirem/XIUI) by the XIUI contributors.

- **License:** GNU General Public License v3.0
- **Components used:** color utilities, bitmap gradient generation, texture loading,
  window background renderer, progress bar renderer, and bundled PNG assets under
  `floos/assets/` (Window1 backgrounds, optional gil/arrow icons).

Floos is a separate addon and is not affiliated with or endorsed by the XIUI project.

`libs/vis.lua` (meters, swing strip, sparkline, markers) is original to Floos and is
not derived from XIUI.

## HGather

HELM detection logic (the 0x36 packet handshake and the chat-line outcome matching)
is adapted from [HGather](https://github.com/SlowedHaste/HGather) by Hastega,
maintained by SlowedHaste.

## Bundled fonts (`floos/assets/fonts/`)

Optional overlay fonts (Tahoma, Tahoma Bold, Segoe UI, Consolas, Verdana) are
Microsoft Windows fonts copied for local/offline use with the addon. They are
not redistributed as part of Floos's open-source license grant — do not ship them
publicly unless you have rights to do so. The Agave option uses
Ashita's built-in ImGui font and requires no bundled files.

## Lua-Bitmap (via XIUI)

`libs/bitmap.lua` is based on [Lua-Bitmap](https://github.com/RexmecK/Lua-Bitmap)
by RexmecK, as included in XIUI.
