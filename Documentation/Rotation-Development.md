# Writing ActionLITE rotations

This guide describes the v1.1.0 class-rotation and HealingEngine contracts for WoW Forever.

## Repository layout

| Path | Purpose |
| --- | --- |
| `ActionLITE/rotation/<Class>.lua` | Combat decisions, spell list, defaults, build selection and debug state |
| `ActionLITE/<Class>_UI.lua` | Checkboxes, sliders, help text and build controls |
| `ActionLITE/Core.lua` | Shared spellbook, cooldown, cast, resource and saved-profile services |
| `ActionLITE/HealingEngine.lua` | Friendly roster eligibility, protected-health masks and target-pixel output |
| `ActionLITE/ProtocolPixels.lua` | Universal colors and Action-compatible protocol pixels |
| `ActionLITE/Display.lua` | Main recommendation, A slots and protected visual layers |

## Rotation module contract

A class module registers one table under its class token:

```lua
local ADDON, AL = ...
local M = {
    defaults = {
        leveling = true,
        exampleSpell = true,
        exampleMana = 25,
    },
    spells = {
        { 12345, "Example Spell" },
    },
}

function M.NextSpell()
    local profile = AL.S()
    if profile.exampleSpell and AL.known["Example Spell"]
        and AL.Allowed("Example Spell", profile)
        and AL.IsReady("Example Spell") then
        return "Example Spell", "example priority"
    end
end

AL.RegisterRotation("PRIEST", M)
```

Use stable English spell names for settings, permissions, queues and return values. Put every spell the module can recommend or manually queue in `M.spells`. The spellbook scan resolves the highest learned rank and localized name. A base spell ID may identify the spell, but learned state must still come from `AL.known`.

Return a spell name and a short reason from `NextSpell`. Preserve an active cast or channel before proposing another cast. Do not turn an unavailable, secret or failed API result into zero, false, full health or full resources.

## Defaults and UI settings

Profile defaults belong in `M.defaults` or the shared `AL.defaults`. Existing saved values must win; defaults fill missing keys only.

Declarative class pages use controls such as:

```lua
{ key = "exampleSpell", label = "Use Example Spell", spell = "Example Spell" },
{ type = "slider", key = "exampleMana", label = "Minimum mana",
  min = 0, max = 100, step = 5, default = 25, suffix = " %" },
```

Dedicated class pages use `ui.SettingCheck` and `ui.Slider`. Always bind the UI and rotation to the same profile key. The integrated debugger records registered controls and their saved/effective values automatically.

Leveling Rotation remains the default build. Build checkboxes are mutually exclusive, and turning the active optional build off returns the profile to Leveling Rotation. A new build must preserve the user's spell permissions, icon assignments and unrelated settings.

## Protected values in WoW Forever

Party health, incoming heals, absorbs, range and some aura data can become secret in combat. Lua cannot compare, calculate with or perform a boolean test on those values.

Follow these rules:

1. Use readable roster facts for eligibility: unit existence, friendly/assist status, connection, visibility, role and death state.
2. Never write `if UnitHealth(unit) < ...`, sort by protected health, convert an unreadable value to zero, or inspect a protected alpha.
3. Use `UnitHealthPercent(unit, true, colorCurve)` or the heal-prediction calculator through HealingEngine. Pass the resulting alpha directly to a frame or texture.
4. Track your own successful casts when an aura cannot be read. Do not guess an enemy or ally aura from a failed aura query.
5. Treat unknown spell range as unknown. A confirmed `false` can reject a unit; a nil or protected result is not the same as out of range.

## HealingEngine settings

The Druid, Paladin, Priest and Shaman profiles include these shared settings:

| Key | Default | Meaning |
| --- | ---: | --- |
| `healingEngine` | `false` | Master gate for party/raid healing recommendations and target selection |
| `healingInitiateHP` | `80` | Routine threshold for efficient direct heals and HoTs |
| `healingEmergencyHP` | `30` | Emergency threshold for the largest heals and cooldowns |

The effective emergency threshold is capped at the initiate threshold. With HealingEngine disabled, its visual rows are cleared and the healing target pixel is Universal Color 0 (black). Current damage and self-healing rotations continue unchanged.

## Adding a HealingEngine provider

Add `HealingEnginePlan` to the class rotation module. It is queried by the display driver after the normal combat decision. Return routine and emergency recommendations that are actually learned, enabled, ready and affordable.

```lua
function M.HealingEnginePlan(profile, context)
    if not profile.healingEngine then return nil end

    local routine
    if AL.known["Renew"] and AL.Allowed("Renew", profile)
        and AL.IsReady("Renew") then
        routine = {
            spell = "Renew",
            reason = "HealingEngine HoT",
        }
    end

    local emergency
    if AL.known["Flash Heal"] and AL.Allowed("Flash Heal", profile)
        and AL.IsReady("Flash Heal") then
        emergency = {
            spell = "Flash Heal",
            reason = "HealingEngine emergency",
        }
    end

    return {
        routine = routine,
        emergency = emergency,
    }
end
```

Accepted request fields are:

| Field | Type | Behavior |
| --- | --- | --- |
| `spell` | string | Required stable English spell name |
| `reason` | string | Optional debugger/display reason |
| `enabled` | boolean | `false` removes this request |
| `requireKnown` | boolean | Defaults to `true` |
| `threshold` | number | Optional public override for the category threshold |
| `includePlayer` | boolean | Defaults to `true`; `false` limits the request to group members |
| `roles` | table | Optional allow-list such as `{ TANK=true, HEALER=true }` |

`routine`, `lowCost` and `hot` are aliases for the routine category. `emergency` is the emergency category. Each category is divided into two client-evaluated health bands. The draw order is routine, urgent, emergency, then critical. Within a band, the deterministic role order is Tank, Healer, Damager, then None; earlier roster positions win ties. Exact health sorting is unavailable because health is secret, but these bands prevent a substantially healthier unit from covering a more injured unit while retaining stable role priority.

The engine validates friendly roster units, excludes confirmed dead, disconnected, invisible and out-of-range units, and uses predicted health. It sends the selected unit through the Action-compatible pixel at physical position `(163, 0)`:

| Unit | Universal color index |
| --- | ---: |
| `raid1` … `raid40` | 1 … 40 |
| `party1` … `party4` | 41 … 44 |
| `player` | 45 |

The matching spell art, A-slot output and target color use the same protected alpha. Do not set the target pixel independently from a healing recommendation.

## HoT tracking

When combat aura reads are blocked, track only the addon's own successful casts. Cache the highest learned rank and talent modifiers outside protected decision paths, then record the intended unit, successful-cast time, modified duration and tick interval.

```lua
hotState[unitGUID][spellName] = {
    spellID = learnedRankID,
    appliedAt = GetTime(),
    expiresAt = GetTime() + modifiedDuration,
    tickInterval = modifiedTickInterval,
    expectedTicks = modifiedTickCount,
    talentSnapshot = cachedTalentRanks,
}
```

Use tracked HoTs to avoid immediate reapplication and to decide whether a routine request is useful. Treat calculated healing per tick as an estimate because temporary bonuses, target modifiers, dispels, overwrites and critical ticks may be hidden. The native predicted-health mask remains the final authority for whether a recommendation is visible.

## Universal icons and A slots

Original spells and original Universal icons use A[3]. Passive `UniversalN Unit1` textures use A[6]. A provider returns the spell name; `AL.SlotFor(spell)` applies the saved icon assignment. Add new spells to the class spell list so the Spells menu can assign them.

Do not create borders around A frames or protocol pixels. The protocol column immediately after A[10] uses physical 1×1 pixels, including the HealingEngine target pixel at `(163, 0)`.

## Validation checklist

Before submitting a rotation:

- Load with all optional build boxes off and confirm Leveling Rotation remains selected.
- Confirm new checkboxes and sliders persist after `/reload`.
- Test every recommendation with the spell learned, unlearned, disabled, cooling down, unaffordable and out of range.
- Test solo, five-player party/follower dungeon and raid rosters when available.
- Start ActionLiteDebug outside combat, reproduce the case, wait five seconds after combat and copy Results.
- Confirm no `attempt to compare`, `perform arithmetic`, or `boolean test` error references a secret value.
- Confirm a healing spell and its target pixel change together, and the pixel returns to black when HealingEngine is disabled or no provider request is active.
- Parse every Lua file and review the TOC load order before packaging.
