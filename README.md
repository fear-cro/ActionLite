# ActionLITE

World of Warcraft Forever rotation profiles and shared UI.

## Builds

- **Current beta: v0.25**, in [`older-versions/ActionLITEv0.25/ActionLITE/`](older-versions/ActionLITEv0.25/ActionLITE/). It uses the original beta leveling rotations with the Warrior hotfixes.
- **Current Level 60 build: 1.1.0**, in [`ActionLITE/`](ActionLITE/). It includes the WoW Forever HealingEngine framework and developer documentation.
- **Archived Level 60 build: 1.0.25**, in [`older-versions/ActionLITEv1.0.25/ActionLITE/`](older-versions/ActionLITEv1.0.25/ActionLITE/).

## Installation

Copy the `ActionLITE` folder into your game’s `Interface/AddOns/` directory, then restart the game or reload the UI. The resulting path should be `Interface/AddOns/ActionLITE/ActionLITE.toc`.

## Patch notes

See the [beta v0.25 patch notes](older-versions/patch-notes/patchnotes-v0.25.MD), the [current v1.1.0 patch notes](patch-notes/1.1.0.MD), or the [archived v1.0.25 patch notes](older-versions/patch-notes/patchnotes-v1.0.25.MD).

Level 60 release notes are Markdown files in [`patch-notes/`](patch-notes/). Beta and archived-version notes are in [`older-versions/patch-notes/`](older-versions/patch-notes/).

## Older versions

Older and beta builds are stored, decompressed, in [`older-versions/`](older-versions/). The original v0.23 archive remains unchanged.

## Development

See [`Documentation/`](Documentation/) for the combat-rotation and HealingEngine authoring contracts.

## Updates

Commit source changes directly to this repository. Keep the addon folder named `ActionLITE`, including its capitalization. Store future patch notes as Markdown files outside addon folders: level 60 releases in `patch-notes/`, and beta/archived-version updates in `older-versions/patch-notes/`. Use Fear-Cro for first-party author credits.

Automated checks have been completed for this build. Live verification in the game remains necessary.
