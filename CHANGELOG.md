# Floos

## 1.0.0 - first release (formerly Olenna)

Renamed from **Olenna** to **Floos**. The addon folder, the slash command and
every internal identifier changed with it:

- `/olenna` is now `/floos` (every subcommand is unchanged otherwise)
- the folder is `Ashita4/addons/floos/`
- settings now live in `Ashita4/config/addons/floos/`

**Upgrading from Olenna:** rename your settings folder to keep lifetime gil,
zone history and your price list:

    Ashita4/config/addons/olenna    ->    Ashita4/config/addons/floos

Skip that and everything still works, it just starts from zero. Delete the old
`addons/olenna` folder either way, or you will have both loaded at once.

### Release changes

- **Fonts are no longer bundled.** Tahoma, Segoe UI, Consolas and Verdana are
  Microsoft fonts and redistributing them is not permitted. Floos now loads them
  from `C:\Windows\Fonts` at runtime instead, so the look is identical and the
  download drops from 1.9 MB to 380 KB. Falls back to Agave if they are missing.
- **LICENSE added.** GPL v3, inherited from XIUI. Replace the notice with the
  full text from gnu.org before publishing.
- **README added** covering install, commands, prices, safety and the HorizonXI
  approval situation.
- Version reset to 1.0.0 for the first public release. The history below is the
  development record under the old name.

---

# Floos 1.8.2 - excavation skill wording

Excavation skill-ups read:

    Your excavating skill has increased by 0.1 raising it to 19.3.

1.8.1 looked for "excavation skill", so it never matched and Exca sat at
Skill 0.0. Each activity now carries a list of possible words rather than one
guess - harvest accepts "harvesting" and "harvest", excavate accepts
"excavating" and "excavation" - so a wording difference cannot silently break a
tab again.

Your excavation skill will pick up its real value on the next skill-up.

---

# Floos 1.8.1 - Logging, Harvesting and Excavation audit

I went through the three neglected tabs. Six real bugs, all fixed and unit-tested.

## Drop names were being truncated

Mining and excavation captured the item with `([%w%s]+)` - letters, digits and
spaces only. Any drop with an apostrophe or a hyphen got cut short, so it was
counted under a mangled name and never matched your price list. Now all four
activities use the same `([^,!]+)` capture (which is what the addon this logic
came from actually used), plus proper trimming of trailing punctuation and the
", but your pickaxe breaks in the process." tail.

## Excavation could miss failures

Excavation reused mining's failure line only. It now accepts both
"unable to mine anything" and "unable to excavate anything", so a miss is
counted either way. This matters: a missed failure inflates your accuracy and
corrupts the skill-up attribution for that swing.

## Skill-up parsing broke on the comma

The pattern required whitespace between the amount and "raising", but the game
writes "... increases by 0.1, raising it to 23.6." Now tolerant of both forms.

## Harvesting and Excavation had no skill tracking at all

Only mining and logging were parsed. Both now have skill level, skill/hr, the
skill bar, skill-up attribution and zone credit, with settings under Config >
HELM. If Horizon has no skill for these, the patterns simply never fire and
nothing changes.

## Logging skill never fed zone tracking

Only mining did. All four gathering activities now credit their zone.

## Tool counts could be wrong

Hatchet, Sickle and Pickaxe ids were hardcoded. Pickaxe (605) and Hatchet (1021)
check out, but the Sickle id was unverified. Ids are now resolved by name from
the game's own resource table at runtime, falling back to the constants. The
Sickles counter is correct regardless of what the id actually is.

## Also

- An unresolved swing now expires after 20 seconds instead of hanging around to
  capture an unrelated chat line later.
- Excavation's fatigue cap, tool cost and break subtraction are wired properly;
  the config notes that excavation uses the Mining pickaxe cost.
- Harvesting gained a "Show Harvesting Skillups" toggle to match the others.

Note: the default price list has no excavation items in it, so Excavation will
show 0 gil until you add them under Config > HELM. I did not want to guess at
item names and give you a list that silently does not match.

---

# Floos 1.8.0 - zone tracking reworked

## The bug

The old verdict compared this zone against the average of **every zone you had
ever visited, blended together**. Standing in Oldton, "vs 0.4 avg" was your
lifetime average across Ifrit's, Palborough and everywhere else. It was never
comparing like with like, so STAY and MOVE meant nothing.

It also judged on **skill/hr**, which at 0.2 skill per half hour is one or two
events - pure noise. It only recorded a visit when you *left* a zone, so
crashing or reloading threw the sample away, and hopping Oldton to Newton and
back reset you to SAMPLING every time.

## The rework

Every zone now keeps a lifetime aggregate per activity: time actually swinging,
gil, skill, swings, items, breaks, visits. It updates on every swing instead of
on zone exit, so nothing is lost to a reload.

- **Judged on gil/hr by default.** Far less noisy than skill. Switch to skill/hr
  in Config > Appearance ("Judge zones by").
- **Compared against a real zone, and it names it.** MOVE now means "somewhere
  specific is better", and the panel line reads
  `Oldton Movalpolos  24,545/hr  vs  Ifrit's Cauldron 72,400/hr`.
- **Only trustworthy zones are used as the benchmark** - 10 minutes and 40 swings
  before a zone can be the thing you are measured against.
- **SAMPLING now counts down.** `SAMPLING 00:03:40` tells you how long until the
  verdict means something, instead of sitting there forever.
- **Quick zone hops resume.** Leaving and returning within 4 minutes continues
  the same sample rather than starting over.
- **AFK never counts.** Gaps longer than the idle limit are dropped from zone time.
- **Breaks are charged against the zone** when Subtract Tool Breaks is on, so a
  break-heavy zone shows its true rate.
- Logging skill-ups feed zone tracking now; previously only mining did.
- The verdict shows on all four gathering tabs, not just Mine and Exca.

## /floos zones

Now a ranked table for the current activity, best rate first, with time invested
and swing counts. Zones with a thin sample are marked and sorted below the solid
ones so three lucky swings never top the list. `/floos zones clear` wipes it.

---

# Floos 1.7.3 - mini mode

`/floos mini` collapses the panel to the four things you actually act on:

    MINE  Skill 23.6              50,951 gil/hr
    Fatigue   25%  49 / 200  1:36:18
    [====                    ]
    Swings 92            Breaks 14
    Pickaxes 124      Net 26,537g
    Session 00:31:15

Tabs stay (thinner), so you can still switch activity. Gone in mini: the moon and
Vana'diel line, area and verdict, accuracy meter, drop list, sparkline, lifetime
gil, skill rate and the swing strip.

## One setting instead of two toggles

Compact and mini are now levels of a single **Detail** setting:

- **Full** - everything, the default.
- **Compact** - no drop list, no footer. The old compact mode.
- **Mini** - the five-line panel above.

Set it in Config > Appearance, or:

- `/floos mini` - toggle Mini
- `/floos compact` - toggle Compact
- `/floos detail full | compact | mini` - set it directly

Your old compact setting migrates automatically. Switching level also releases a
locked panel height, so the box shrinks with the content instead of leaving a gap.

---

# Floos 1.7.2

DarkGold is now the default theme. It is first in the Appearance list, it is what
a fresh install boots with, and it is the fallback everywhere the code previously
fell back to OceanBlue.

Your saved theme is untouched - if you already picked one, you keep it. This only
changes what new installs and new characters get.

---

# Floos 1.7.1

Install: drop the `floos` folder into `Ashita4/addons/`, overwriting the old one,
then `/addon reload floos`. Settings, lifetime gil and zone history are preserved.

## Removed in 1.7.1

The node map, circuit routing and node store from 1.8.0 are gone. Deleted:
`libs/nodes.lua`, `libs/route.lua`, `modules/map.lua`, the Map config tab, the
`/floos map` and `/floos nodes` commands, and the entity scanner.

Nothing reads or records entity positions any more. The addon is back to what it
was in 1.7.0: it listens for the HELM packet, reads chat lines, and draws a panel.

If you ran 1.8.x, it may have written a node file at
`Ashita4/config/addons/floos/nodes.lua`. Nothing reads it now - delete it.

---

# Floos 1.7.0 — the expert panel

- Hero gil/hr number at 1.5x, reading `--` until a session has two minutes on it.
- Accent color per activity: Mine amber, Logg green, Harv teal, Exca orange, Hunt crimson.
- Fatigue meter with percentage, count, ETA, and a green-to-red gradient.
- Accuracy meter with a tick at your lifetime average.
- Skill bar showing progress to the next whole level.
- Swing history strip — last 30 outcomes as colored ticks, skill-ups dotted above.
- Zone STAY / MOVE verdict chip from your own per-zone skill/hr history.
- Rate sparkline, reward rows sorted by value with share bars, tab badges,
  low-tool warnings, skill-up flash, gil count-up.
- Fixed: the `?` glyph on the best drop, the panel not auto-fitting, Skill/hr
  printing twice, the width slider disagreeing with the renderer, and three
  latent nil crashes in `ui.lua`.
- `/floos compact`, `/floos auto`.
