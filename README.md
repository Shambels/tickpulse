# TickPulse (TBC Anniversary MVP)

TickPulse tracks your player-cast periodic auras and shows a rotating overlay directly on the original aura icons:

- DoTs: rotates from apply -> next damage tick, then resets every tick.
- HoTs: rotates from apply -> next heal tick, then resets every tick.

## Install

1. Create a folder named `TickPulse` in your WoW addons directory.
2. Copy these files into that folder:
   - `TickPulse.toc`
   - `spells.lua`
   - `core.lua`
3. Launch/reload the game (`/reload`).

Typical path on macOS:

`World of Warcraft/_classic_/Interface/AddOns/TickPulse/`

## Quick update script (Windows)

Run this from the repository root in PowerShell:

`./deploy-addon.ps1`

By default it copies repository files (excluding `.git` and the script itself) to:

`C:\Program Files (x86)\World of Warcraft\_anniversary_\Interface\AddOns\TickPulse`

Optional custom destination:

`./deploy-addon.ps1 -Destination "D:\Games\WoW\_anniversary_\Interface\AddOns\TickPulse"`

## Commands

- `/tpulse show`
- `/tpulse hide`
- `/tpulse scan`
- `/tpulse options`
- `/tpulse debug`
- `/tpulse debug player|target|focus`

## Options

- Open via `/tickpulse options` (or `/tpulse options`).
- Also available in the WoW Interface Options menu under AddOns -> TickPulse.
- Current toggles:
   - Show ticker on main UI (player auras)
   - Show ticker on target frame
   - Show ticker on focus frame
   - Show numeric values on ticker
   - Show rotating ticker
   - Overlay opacity slider (0% to 100%)
   - Reset Visual Defaults button (numeric off, rotating on, opacity 65%)

## Notes

- `spells.lua` now seeds periodic spells across all TBC classes/specs (DoTs + HoTs).
- First Aid bandages are also seeded as tracked periodic heals.
- Matching is done by localized spell name (from `GetSpellInfo`) and cached per runtime spell ID, so all ranks are covered.
- Your `player` unit now tracks matching DoTs/HoTs cast by other players (`trackExternalOnPlayer = true` in `TickPulse.Config`).
- If a spell ticks at a different cadence due to talents/procs, the addon learns from combat log deltas after first ticks.
- Rendering is done on Blizzard aura buttons (`target`, `focus`, and `player`) with a cooldown swipe overlay.
- For `player`, TickPulse targets the default top-right aura buttons first (`BuffButton`/`DebuffButton`) and falls back to player-frame aura button names if needed.
- If a new overlay frame would need to be created during combat, TickPulse waits until out of combat to attach it.

## Next steps

- Optionally integrate with unit frame addons via custom anchors.
