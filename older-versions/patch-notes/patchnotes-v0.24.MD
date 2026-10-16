# ActionLITE v0.24 Beta Patch Notes

October 15, 2026

This beta update is based on ActionLITE v0.23 and retains its original leveling rotations, class menus, and controls.

## Wand timing

- Improved Shoot timing for Mage, Priest, and Warlock to prevent repeated recommendations while a wand command is pending or a shot is being cast.
- Use the current shot’s readable cast or channel timer, including delays. When that information is protected, use the last readable weapon speed; a conservative fallback is used if neither is available.
- Allow the next shot when the current shot finishes without adding a second full weapon delay.
- Keep active automatic wand fire from being repeatedly toggled. Mage’s deliberate wand stop before Fire Blast or Frost Nova remains available when automatic wand fire is confirmed.
- Preserve successful-shot recovery after rejected duplicate attempts. Failed initial casts and missing acknowledgements no longer leave a permanent wait state.
- Retain the existing mana sliders and Warlock’s 10% mana protection floor.

## Priest

- Updated the protected-API cooldown fallback for Devouring Plague to 24 seconds.
- Added a 30-second cooldown fallback for Vampiric Embrace.
- Readable cooldown information continues to take priority.

## Shaman

- Updated inferred Flame Shock duration for Call of Flame: 12 seconds without the talent, plus three seconds per talent point, up to 21 seconds.
- Refresh the talent duration when talent points change and retain the last known rank when combat hides talent information.

## Spell menu additions

The following spells now have spell-menu entries for icon assignment and manual queuing when learned. Their actual IDs are resolved from the learned spellbook; untrained entries are not treated as learned.

| Class | Added spells |
| --- | --- |
| Mage | Frost Blast |
| Paladin | Salvation, Mass Salvation, Revoke |

These spells can be assigned Universal icons in the Spells menu. Frost Blast does not replace the configured damage spell, and the Paladin utilities are not automatically applied to group members.

## Compatibility review

- Druid’s beta Shred logic already follows the learned spellbook and has no level-22 restriction, so the level-20 training change needs no rotation change.
- This build retains the original beta rotations. No simulation data, level-60 specialization rotations, Cast Trail integration, redesigned Burst/AoE controls, or new debugger features were added.

## Icon reminders

- Druid: Use a Universal icon for Demoralizing Roar.
- Paladin: Holy Strike requires a Universal icon.
- Rogue: Universal icons are needed for Gouge, Eviscerate, and Evasion.
- Priest: Divine Spirit defaults to Universal 9 and Penance defaults to Universal 8.

## Installation and verification

Copy the `ActionLITE` folder from `older-versions/ActionLITEv0.24/` into `Interface/AddOns/`, replacing the existing ActionLITE addon, then reload the game. Existing saved settings are retained.

Automated rotation, wand timing, spell-menu, and startup checks passed. Live verification of the wand animation and shot timing in the current beta client is still required.
