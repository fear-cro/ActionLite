# ActionLITE v0.25 Beta Patch Notes

October 16, 2026

Built from v0.24 with the Warrior hotfixes included. This beta continues to use the original leveling rotations and controls.

## Warrior

- Fixed the Protection rotation stopping on Auto Attack when the game hides who the enemy is attacking.
- Unknown target information now skips the optional taunt check while allowing other abilities to continue.
- Fixed Heroic Strike, Cleave, Slam, and Sweeping Strikes bypassing their Rage reserves when Rage is hidden. Being able to afford a spell no longer bypasses its selected reserve.
- Keep the main icon, small icon, hotkey, and action-bar glow aligned with the Rage threshold. If the client cannot check a threshold, the optional spender waits while other attacks and defensive abilities continue.
- Clarified the separate DPS and Protection sliders. Defensive Stance uses **Tank Heroic Strike threshold** and **Protection Cleave Rage**.
- Retained the existing 80-Rage overflow protection in the DPS rotation.

## Paladin and Druid review

- Verified Paladin's existing mana gates and Bear-form Druid resource checks. No additional rotation changes were needed for these Warrior-specific bugs.
- The level-60 Protection Paladin and Feral Tank builds remain part of the separate v1.0.25 package.

## Installation

Copy the `ActionLITE` folder from `older-versions/ActionLITEv0.25/` into `Interface/AddOns/`, replacing the installed addon, then reload the UI. Saved settings are retained.

For the wand timing, Priest, Shaman, and spell-menu fixes included from v0.24, see [patchnotes-v0.24.MD](patchnotes-v0.24.MD).
