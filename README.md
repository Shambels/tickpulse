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

## Commands

- `/tpulse show`
- `/tpulse hide`
- `/tpulse scan`
- `/tpulse debug`
- `/tpulse debug player|target|focus`

## Notes

- `spells.lua` now seeds periodic spells across all TBC classes/specs (DoTs + HoTs).
- Matching is done by localized spell name (from `GetSpellInfo`) and cached per runtime spell ID, so all ranks are covered.
- Your `player` unit now tracks matching DoTs/HoTs cast by other players (`trackExternalOnPlayer = true` in `TickPulse.Config`).
- If a spell ticks at a different cadence due to talents/procs, the addon learns from combat log deltas after first ticks.
- Rendering is done on Blizzard aura buttons (`target`, `focus`, and `player`) with a cooldown swipe overlay.
- If a new overlay frame would need to be created during combat, TickPulse waits until out of combat to attach it.

## Next steps

- Optionally integrate with unit frame addons via custom anchors.
