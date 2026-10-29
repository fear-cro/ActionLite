# ActionLITE v1.0.25 Release Notes

Version 1.0.25  |  October 16 2026

This full build combines the class and specialization upgrades with revised rotation selection, display controls, Cast Trail and bug reporting. It also includes compatibility updates for the latest WoW Forever class changes.

## Rotation selection

- Added Leveling Rotation as the default choice for every class, using the previously finalized leveling behavior.
- Added separate DPS and tank build selections. Choosing a build automatically unchecks the previous selection. Unchecking a talent build returns to Leveling Rotation, so one rotation always remains selected.
- Retained saved valid build choices, spell permissions, sliders and icon assignments. Optional rotations use learned spells through level 60. Burst abilities require Burst On; area damage requires AoE On and the configured thresholds.
- The included rotations do not add consumable use or depend on external raid buffs.

## Display and controls

- Added clickable Burst and AoE controls beside the main spell icon for all classes. Removed the redundant Burst status text below the icon.
- Added Hide Burst and AoE boxes in General settings, disabled by default. Enabling it replaces the labeled buttons with clickable squares: red means off and green means on.

## Cast Trail

- Integrated Cast Trail addon with its right edge aligned to the main icon, five pixels below it. Cast Trail On and Lock Cast Trail are enabled by default.
- Unlock the trail to move or resize it independently. Lock it again to retain its position and size. Visibility, lock state, scale and custom location are saved.

## Bug reporting

- Added a Bug report tab with instructions and an Open Debugger button. Opening it closes the main menu.
- Click Start outside combat, immediately engage and reproduce the issue, then wait five seconds after combat ends. Click Results, Select All and copy the report with your description of the issue.
- Reports include current class settings, checkbox and slider states, rotation decisions, spell events and available API information. Results are copied from a selectable text dialog; reports are not sent automatically.

## WoW Forever compatibility updates

### Mage

- Updated Arcane Blast tracking to retain its stacks through other damaging spells. The buff now uses a fifteen-second window from its first application; additional Arcane Blast casts do not extend that window.
- Added learned Arcane Wrath to the Arcane rotation, with a Use Arcane Wrath checkbox. At full stacks it takes priority when ready, followed by Arcane Missiles filler. Existing wand and mana controls retain priority.
- Corrected Heating Up tracking: Fire Blast grants one charge on a successful cast, with an additional charge from a qualifying critical strike. A Presence of Mind Pyroblast preserves Heating Up.
- Added Frost Blast to the spell menu and an optional quick slow opener checkbox, disabled by default. It requires the spell to be learned at level 24 or above.
- Added an AoE option to build the player's own observable Winter's Chill stacks before Cone of Cold, or spend them near expiry. Unknown aura information retains the established AoE fallback. Cone of Cold still requires AoE On and enough nearby enemies.

### Warlock

- Fixed new Warlocks stopping before their first attack when Drain Soul has not been learned. Soul Shard upkeep now runs only when Drain Soul is learned and enabled.
- The Shoot mana threshold and 10% wand protection now apply only while a wand is equipped. Without a wand, usable Shadow Bolt remains available in Leveling Rotation and the optional talent builds.

### Priest

- Corrected protected-API cooldown fallbacks for Devouring Plague to 24 seconds, Vampiric Embrace to 30 seconds and Shadow Word Death to 18 seconds. Updated the shared Devouring Plague fallback used by the leveling rotation.

### Shaman

- Added Elemental Mastery to the spell menu and an Elemental Mastery during Burst checkbox. It requires the learned ability, Burst On, spell range and the configured mana and target-health thresholds.
- Tracked the fifteen-second Elemental Mastery effect so Chain Lightning can repeat during it. Chain Lightning still requires AoE On and enough engaged enemies; its normal cooldown returns after the effect ends.
- Extended inferred Flame Shock duration by three seconds per Call of Flame point, up to 21 seconds. Shared and specialization tracking use the same duration, reducing early reapplication when aura information is protected.
- Added recognition of the renamed Trial By Fire talent for Fire Nova cooldown tracking.

### Druid

- Updated the Feral Cat Shred level requirement from 22 to 20. The spell must still be learned and enabled, and existing position and resource checks remain in place.

### Paladin

- Added Salvation, Mass Salvation and Revoke to the spell menu for icon assignment and manual queuing.

## Included rotations and spell menu additions

Every class includes Leveling Rotation in addition to the optional builds below. Selecting a build changes ActionLITE priorities; it does not allocate talents or equip items.

| Class | Optional builds |
| --- | --- |
| Warrior | Fury 18/31/2; Arms 39/10/2; Protection 0/20/31 |
| Paladin | Shockadin 23/0/28; Retribution 10/8/33; Protection 8/33/10 |
| Hunter | Survival 5/11/35; Marksmanship 5/31/15; Beast Mastery 31/20/0 |
| Warlock | Demonology 2/31/18; Affliction 33/0/18; Destruction 11/11/29 |
| Mage | Arcane 35/11/5; Frostfire 0/29/22; Fire 16/31/4; Frost 16/3/32 |
| Druid | Feral Cat 9/34/8; Balance 41/0/10; Feral Bear Tank 0/41/10 |
| Rogue | Combat 17/32/2; Subtlety 12/8/31; Assassination 38/11/2 |
| Shaman | Enhancement 18/33/0; Elemental 31/7/13 |
| Priest | Shadow 18/0/33 |

### New spell menu entries

The following six spells are available for Universal icon assignment. New spell identities are resolved from the learned spellbook. Enable and configure the spells you have trained in the Spells tab.

| Class | Added spells |
| --- | --- |
| Mage | Arcane Wrath; Frost Blast |
| Shaman | Elemental Mastery |
| Paladin | Salvation; Mass Salvation; Revoke |

### Installation

Install the complete ActionLITE folder in Interface/AddOns and reload the game. Keep your WTF folder to preserve saved settings. Disable the old standalone CastTrail addon if it is still installed; Cast Trail is included in this build.
