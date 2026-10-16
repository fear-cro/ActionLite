# ActionLITE 1.0.25 TEST

This is the separate UI test package based on the v1.0.25 release. The addon identifies itself as **1.0.25-TEST**.

## Installation

Use this folder's inner **ActionLITE** folder as the installed addon folder:

`Interface/AddOns/ActionLITE/ActionLITE.toc`

Replace the installed ActionLITE folder with this test copy, then reload the UI. Keep the existing SavedVariables to test with your current configuration. Install one ActionLITE copy at a time.

## In-game checks

- Open General and try its smaller settings groups. Click a section heading to collapse or expand it.
- On each class page, select a talent build, switch to another, and turn it off. Exactly one rotation should remain checked; turning a talent build off should restore Leveling Rotation.
- Check that relevant build sections appear and unrelated sections disappear. Existing spell checkboxes, sliders and their saved values should remain available.
- Check the earlier DPS/Tank or casting preferences under Leveling Rotation where applicable.
- Check main-icon controls, Cast Trail visibility and lock, action-bar glow, swing timer and pause conditions.
- In Spells, test search, the learned-spell filter, spell permissions and Universal icons. Left-click **Macro** to create a queue macro; right-click it to queue immediately. Paladin's Holy Strike artwork control is also here.
- Reload and confirm the selected rotation, sliders, icon assignments and collapsed sections are retained.
- For an issue, use **Bug report → Open Debugger** and follow the capture instructions. Include the class, selected rotation and steps that reproduce the issue.

Combat rotation files and the combat core match the release. The repository's release package, older versions and release changelog have not been changed by this test package.
