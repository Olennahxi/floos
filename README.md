A hobby tracker for **HorizonXI**, for Ashita v4.

Floos follows all eight of them — mining, logging, harvesting, excavation,
hunting, fishing, chocobo digging and clamming — and answers one question for
each: **is this still worth doing?**

It reads. It never sends a packet, never acts for you, and never automates
anything.

## The name

**Floos** — *فلوس* — is Arabic for **money**.

Which is the whole point. Eight hobbies, one question each: *is this still
worth doing?* Every tab ends in the same number — what an hour of it is
actually worth. The gathering is the means; the floos is the point.

---

## Install

1. Download the repository (**Code -> Download ZIP**) and drop the inner
   `floos` folder into `Ashita/addons/`, so you end up with
   `Ashita/addons/floos/floos.lua`.
2. `/addon load floos`
3. `/floos` to open the settings window.

Add `/addon load floos` to your Ashita boot script to have it load every time.

**Upgrading from Olenna?** Rename `Ashita/config/addons/olenna` to
`Ashita/config/addons/floos` before loading, and your prices, zone history,
lifetime gil and per-character sessions all come with you. Skip it and the
addon starts fresh — nothing breaks, you just re-enter your prices.

### Fonts

Floos can draw in Tahoma, Segoe UI, Consolas or Verdana, but those are
Microsoft Windows fonts and are not mine to redistribute, so they are not in
this repository. Copy them from `C:\Windows\Fonts` into
`floos/assets/fonts/` if you want them - you already have them if you are on
Windows, and nothing needs installing.

Without them Floos uses Ashita's built-in font and works normally.

---

## What each tab tells you

| Tab | The number that matters |
|---|---|
| **Mine / Logg / Harv / Exca** | gil/hr, fatigue against a cap that corrects itself, and a stay-or-move verdict per zone |
| **Hunt** | kills/hr, drop rate, steal rate, respawn timers |
| **Fish** | bite rate, catch rate, losses split by cause, and when the water restocks |
| **Dig** | greens left, daily cap on the real JST clock, and whether the elemental ore window is open |
| **Clam** | bucket weight against capacity, what it is worth, and the real odds the next scoop bursts it |

Eight tabs will not fit a narrow panel, so **/floos → Interface** lets you
switch off the ones you do not use. They keep tracking; they just stop taking
space.

---

## Commands

```
Panel
  /floos              Open the settings window.
  /floos show|hide    Show or hide the tracker.
  /floos detail       full | compact | mini.
Session
  /floos report       Print session stats to chat.
  /floos clear        Clear every session.
  /floos zones        Rank zones by gil/hr.  (+ clear)
  /floos insights     What your journal shows.  (+ tab name)
Activity
  /floos ore          Can you dig elemental ore right now?
  /floos dig          Daily count and JST reset.  (+ a number)
  /floos clam         Bucket weight, value, break odds.
  /floos fatigue      Reset countdown.  (+ reset)
Setup
  /floos prices import <file>   Merge a name:price file.
  /floos debug        What the addon is actually seeing.  (+ on | off)
```

`/floos help` prints the same list in game.

### Prices

Items are priced in the config window's price list, one per line:

```
chunk of iron ore:650
tropical clam:5100
```

Lowercase, no spaces around the colon. The defaults are rough starting values —
edit them to your server's actual prices or every gil figure will be wrong.

---

## What it does and does not do

**Reads:** chat text, the outgoing trade and action packets your client already
sends, your inventory count, and two values out of the client's own memory —
the Vana'diel clock and the current weather — the same way other Ashita addons
have read them for years.

**Never:** sends a packet, injects input, moves your character, repeats an
action, reads other players' data, or scans the entity list.

If a HorizonXI staff member wants to read it, every one of those claims is
checkable in about ten minutes, which is the point.

---

## Thanks

Floos stands on other people's work. In rough order of debt:

- **[XIUI](https://github.com/tirem/XIUI)** by *tirem* — GPLv3. The rendering
  layer Floos is drawn with: window backgrounds, progress bars, texture and
  font handling, D3D helpers, colour utilities, and most of the visual assets.
  Without it this would look like a debug console.
- **[HGather](https://github.com/SlowedHaste/HGather)** by *Hastega*,
  maintained by *SlowedHaste* — the original HELM tracker, and the source of
  the gathering detection approach: the `0x36` trade handshake and reading the
  outcome out of chat. Floos began as an attempt to extend it.
- **[HXIClam](https://github.com/jimmy58663/hxiclam)** by *jimmy58663* —
  BSD 3-Clause. The reference clamming tracker for HorizonXI. No code was
  taken, but it is what the Clam tab was checked against, and tracking bucket
  weight is its idea.
- **[LuAshitacast](https://github.com/ThornyFFXI/LuAshitacast)** by
  *ThornyFFXI* — independent confirmation of the weather signature, and the
  better habit of resolving a scan once rather than every frame.
- **[Lua-Bitmap](https://github.com/RexmecK/Lua-Bitmap)** by *RexmecK* —
  `libs/bitmap.lua`, by way of XIUI.
- **[LandSandBoat](https://github.com/LandSandBoat/server)**, AirSkyBoat and
  DarkStar and their contributors — reading open server implementations is how
  the exact message strings, the clamming cooldown and the digging rank formula
  were verified instead of guessed.
- **[XiPackets](https://github.com/atom0s/XiPackets)** by *atom0s* — packet
  documentation. The trade and weather offsets are right because it exists.
- **[Windower](https://github.com/Windower/Resources)** — cross-checked the
  weather table and packet field layouts.
- **[Ashita](https://ashitaxi.com)** by *atom0s* and contributors — the
  framework all of this runs on.
- **The [HorizonXI wiki](https://horizonffxi.wiki) editors**, and *Sushomi*
  whose clamming analysis is where the ponze weights and drop abundances come
  from. Every number Floos treats as fact was published by somebody who
  measured it and wrote it down.

The same list is in the **About** tab in game.

---

## Licence

Floos contains code derived from XIUI and is distributed under the **GNU
General Public License v3.0**. See `THIRD_PARTY_NOTICES.md` for the full
notices.

The fonts under `assets/fonts/` are Microsoft Windows fonts included for local
use and are **not** covered by that grant — do not redistribute them publicly
unless you have the rights to do so.


This Addon Was Created and gathered by Claude Opus 5 / Fable
