# Hide Annoying Popups

Dismisses popups that interrupt you for no good reason. Each one is a separate
checkbox, so you only silence what you want silenced.

**Options → AddOns → Hide Annoying Popups**, or `/hap`.

## What it handles

### "AddOn X has been blocked from an action only available to the Blizzard UI"

Fires constantly, names an addon that is working perfectly well, and tells you
to disable it. Usually harmless: the addon asked for something it was never
going to be allowed to do, and the game said no.

Over a few days of normal play on one character this fired **10,225 times**
across 7 addons and 146 distinct calls — ConsolePort_Bar alone accounted for
5,131 of them.

It keeps counting while it hides, so you still get the diagnostic — which
addon, which call, how many times — without the interruption.

### The stray "leave instance group?" prompt

Entering an instance — Island Expeditions especially — can raise this on its
own, with nobody having asked to leave anything. Answer *Yes* and you are out
of the run with a **Deserter** debuff and a wait before you can re-queue.

The same dialog appears when you genuinely do want to leave, so this dismisses
**at most one per zone change or queue pop**: the stray one. Click Leave Group
again and the next prompt is yours. Worst case you click twice.

The timing was measured rather than assumed. The prompt arrives one to two
seconds *before* the new instance finishes loading, which makes the queue the
thing to watch rather than your last zone change: an identical pair of runs
differed only in a 59-second queue versus a 176-second one. So queue activity
keeps the guard armed for a wait of any length, and it lapses once you have
stopped queueing. The one-shot is the safety, not the clock.

## Using it

Each popup is a checkbox under **Options → AddOns → Hide Annoying Popups**, or
just type `/hap` to open that panel. Hovering a row explains what it hides. The
**ⓘ** button in the corner prints how many of each have been dismissed.

```
/hap                    open the options panel
/hap status             how many of each popup have been dismissed
/hap clear              reset those counts (or right-click the info button)
```

Resetting keeps the previous totals in the saved variables rather than throwing
them away, so a stray right-click is not the end of a long-running tally.

It tells you in chat each time it dismisses something, so it is never acting
invisibly on your behalf.

## Finding another popup

If some other dialog is pestering you, this will name it:

```
/hap watch              start recording every popup that appears
/hap popups             list what was seen, with its text, and whether we have a rule
```

Send that output along with a description of when it fires and it can become a
checkbox of its own.

That is how both of the current rules were identified. Watching only observes
— it cannot suppress or alter anything.

## What it does not do

**It never presses a button.** Dismissing closes a dialog and nothing else, so
it cannot answer Yes, leave a group, or spend anything for you.

**It does not fix the underlying problem.** A blocked action still fails; this
hides the complaint, not the cause.

Dialogs with no rule are never touched.
