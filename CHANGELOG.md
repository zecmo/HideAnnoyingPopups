# Changelog

## 1.1
- Hides the Draenor garrison "Call to Arms" button, which no amount of dragging
  to an action bar will remove
- Only while the garrison ability is the active one, so other zone abilities
  are untouched
- Deferred out of combat, since hiding a frame that owns secure buttons mid-fight
  would raise the blocked-action error this addon exists to suppress

## 1.0
- First release
- Hides the "blocked from an action only available to the Blizzard UI" popup
- Dismisses the stray "leave instance group?" prompt that costs you a Deserter debuff
- A checkbox per popup under Options > AddOns, or `/hap`
- `/hap status`, and an info button on the panel, show how many of each were dismissed
- `/hap clear`, or right-clicking that button, resets the counts
- `/hap watch` records every popup that appears, to identify an unfamiliar one
