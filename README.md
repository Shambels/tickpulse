# TickPulse (WoW Forever)

TickPulse shows a rotating overlay on your periodic aura icons that resets on every tick:

- DoTs: the swipe goes from one damage tick to the next.
- HoTs: the swipe goes from one heal tick to the next.

This branch targets the **WoW Forever** client (`## Interface: 16001`). The original TBC Anniversary build is in git history before `0.2.0`.

## Install

1. Create a folder named `TickPulse` in your WoW Forever addons directory.
2. Copy these files into that folder:
   - `TickPulse.toc`
   - `spells.lua`
   - `core.lua`
3. Launch or reload the game (`/reload`).

Typical path:

`World of Warcraft/_forever_/Interface/AddOns/TickPulse/`

## Quick update script (Windows)

Run this from the repository root in PowerShell:

`./deploy-addon.ps1`

By default it copies repository files (excluding `.git` and the script itself) to:

`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\TickPulse`

Optional custom destination:

`./deploy-addon.ps1 -Destination "D:\Games\WoW\_forever_\Interface\AddOns\TickPulse"`

## Commands

- `/tpulse show`
- `/tpulse hide`
- `/tpulse scan`
- `/tpulse options`
- `/tpulse debug`
- `/tpulse debug player|target|focus`

- `/tpulse test` / `/tpulse test off`

`/tpulse debug` also prints the client interface version and whether aura data is currently readable or secret.

## Test mode

Addons cannot put real auras on you, so `/tpulse test` (run out of combat) fakes them:

- A small draggable "TickPulse test" frame shows a fake DoT icon (3s ticks) and a fake HoT icon (2s ticks). Use it to check the swipe, the numbers, opacity and the Settings toggles.
- If you have any buff (food, a class self-buff), a fake 3s tick schedule is attached to its icon on the real buff frame. This tests matching against Blizzard's buff buttons. It follows the "Show ticker on player auras" toggle.

`/tpulse debug test` lists the test trackers and which button each one is bound to (`(missing)` means the real buff icon could not be matched). `/tpulse test off` removes everything.

## Options

- Open with `/tickpulse options` (or `/tpulse options`), or go to Options -> AddOns -> TickPulse.
- Settings are saved per account in `TickPulseDB`.
- Toggles:
   - Show ticker on player auras
   - Show ticker on target frame
   - Show ticker on focus frame
   - Track other players' HoTs/DoTs on you
   - Show rotating ticker
   - Show numeric values on ticker
   - Overlay opacity slider (0% to 100%)
   - Reset visual defaults (numeric off, rotating on, opacity 65%)

## How it works on WoW Forever

WoW Forever runs on the modern client and applies the same addon restrictions as Midnight:

- Addons cannot register the combat log (`COMBAT_LOG_EVENT_UNFILTERED`), so TickPulse can no longer see ticks happen.
- While restrictions are active (combat, encounters, PvP), aura data is *secret*: addons can pass it to the UI but cannot read or compare it.

Classic-era DoTs and HoTs tick on a fixed schedule from the moment they are applied, so TickPulse predicts the ticks:

1. **Aura data readable** (usually out of combat): the tick schedule is anchored at `expirationTime - duration` from `C_UnitAuras`. This is exact, and covers refreshes and auras cast by other players.
2. **Aura data secret** (usually in combat): your own spellcasts are still readable. When you cast a tracked spell, TickPulse anchors the schedule at the cast time. Durations learned while auras were readable are saved and used to expire trackers.
3. **Never-hidden spells**: the client can mark individual spells as never secret. TickPulse asks `C_Secrets.ShouldSpellAuraBeSecret` for each tracked spell. For the ones that stay readable, it keeps reading your real auras in combat instead of predicting from the cast. `/tpulse debug` lists those spells and marks their trackers "live aura data".
4. When restrictions lift (leaving combat, encounter end), TickPulse rescans and corrects everything from real aura data.

## Known limitations

These come from the client's addon restrictions and need in-game confirmation:

- While auras are secret, matching an overlay to the right Blizzard icon depends on the icon's texture or aura instance ID being readable. If Blizzard hides those too, overlays for spells applied *during* combat may not appear until combat ends. Overlays bound before combat stay attached.
- While auras are secret, TickPulse cannot see auras that other players apply to you, and it cannot tell whether your cast was resisted.
- For projectiles (Fireball, Pyroblast, Serpent Sting, Viper Sting) the aura lands after the cast, so their in-combat schedule is only started from aura data.
- When you switch target or focus, TickPulse parks the old unit's trackers by GUID and restores them when you switch back (kept until they expire, or 2 minutes if the duration is unknown). If the client hides the unit's GUID, the trackers are dropped instead. The new target's own auras still can't be read until restrictions lift.
- Talents or effects that change tick speed are not learned anymore: there is no combat log to learn from. Adjust `interval` in `spells.lua` if a spell ticks differently.

## Tracked spells

`spells.lua` lists the Classic-era 1-60 periodic spells for all nine classes, plus First Aid (every bandage heal aura is named "First Aid"). Matching is by localized spell name, so all ranks are covered. Each entry also has an enUS name fallback in case the client cannot resolve the spell ID. A few later-expansion spells are kept in case Forever's new abilities reuse them; they are ignored when the spell does not exist.

## License

TickPulse is licensed under the MIT License. See [LICENSE](LICENSE).
