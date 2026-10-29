-- Tests for HideAnnoyingPopups. Run from the repo root:  lua test.lua
-- Stubs just enough of the WoW API to drive core.lua headlessly.
local SAY = print
local chat = {}
print = function(...) local p={} for i=1,select('#',...) do p[#p+1]=tostring((select(i,...))) end chat[#chat+1]=table.concat(p," ") end
date = function() return "2026-10-26 09:00:00" end
local now = 1000 ; GetTime = function() return now end
local inInstance = false
IsInInstance = function() return inInstance, inInstance and "scenario" or "none" end
local grouped, lfgMode = false, {}
IsInGroup = function() return grouped end
GetLFGMode = function(cat) return lfgMode[cat] end
LE_PARTY_CATEGORY_INSTANCE = 2

local hidden, visible = {}, nil
StaticPopup_Hide = function(w) if visible == w then visible=nil; hidden[w]=(hidden[w] or 0)+1 end end
C_Timer = { After=function(_,fn) fn() end }
local uiReg = { ADDON_ACTION_FORBIDDEN=true, ADDON_ACTION_BLOCKED=true }
UIParent = { UnregisterEvent=function(_,e) uiReg[e]=false end, RegisterEvent=function(_,e) uiReg[e]=true end }
local hooks, hookExtra = {}, {}
hooksecurefunc = function(n,f) hooks[n]=f end
StaticPopup_Show = function() end
StaticPopupDialogs = { TALENT_THING = { text = "Learn these talents?" } }
local onEvent
CreateFrame = function() return {
  RegisterEvent=function() end, UnregisterEvent=function() end,
  SetScript=function(_,_,f) onEvent=f end,
  HookScript=function(_,_,f) hookExtra[#hookExtra+1]=f end } end
SlashCmdList = {}
Settings = nil

assert(loadfile("HideAnnoyingPopups/core.lua"))("HideAnnoyingPopups")
local function fire(ev,a,b) onEvent(nil,ev,a,b); for _,h in ipairs(hookExtra) do h(nil,ev,a,b) end end
fire("ADDON_LOADED","HideAnnoyingPopups")
local show, cmd = hooks["StaticPopup_Show"], SlashCmdList["HIDEANNOYINGPOPUPS"]

local pass,fail=0,0
local function ok(l,c,e) if c then pass=pass+1 SAY("  PASS  "..l) else fail=fail+1 SAY("  FAIL  "..l.."  "..tostring(e)) end end
local function popup(w, expect, label)
  local before = hidden[w] or 0
  visible = w; show(w)
  local got = (hidden[w] or 0) - before
  ok(label, got == expect, "dismissed "..got..", expected "..expect)
end

ok("UIParent unregistered for taint events", uiReg.ADDON_ACTION_FORBIDDEN == false)
popup("ADDON_ACTION_FORBIDDEN", 1, "blocked-action popup dismissed")

inInstance = true; fire("PLAYER_ENTERING_WORLD")
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 1, "stray leave prompt dismissed")
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 0, "  second in same transition left alone (one-shot)")
fire("PLAYER_ENTERING_WORLD"); now = now + 52
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 1, "  52s after a transition still caught")
fire("PLAYER_ENTERING_WORLD"); now = now + 300
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 0, "  300s later not touched")

-- the Normal-vs-Mythic report: both prompts fired 1-2s before the instance
-- loaded, so the only difference was a 59s queue versus a 176s one
grouped = true; lfgMode[4] = "lfgparty"
fire("PLAYER_ENTERING_WORLD")
for _ = 1, 18 do now = now + 10; fire("LFG_QUEUE_STATUS_UPDATE") end
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 1, "  prompt after a 3-minute queue is caught")
now = now + 10; fire("LFG_QUEUE_STATUS_UPDATE")
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 0, "  a queue tick alone cannot re-arm a spent guard")
fire("LFG_PROPOSAL_SUCCEEDED")
popup("CONFIRM_LEAVE_INSTANCE_PARTY", 1, "  but a queue popping does re-arm it")

local blockedBefore = HideAnnoyingPopupsDB.counts.blocked or 0
fire("LFG_QUEUE_STATUS_UPDATE"); fire("GROUP_JOINED"); fire("SOME_OTHER_EVENT")
ok("queue events never reach the blocked-popup path",
   (HideAnnoyingPopupsDB.counts.blocked or 0) == blockedBefore,
   tostring(HideAnnoyingPopupsDB.counts.blocked))

chat={}; cmd("trace")
local tr = table.concat(chat,"\n"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
ok("trace names the events that armed the guard",
   tr:find("LFG_QUEUE_STATUS_UPDATE") ~= nil, tr)
ok("  and records client state at the prompt", tr:find("lfg4=lfgparty") and tr:find("igroup=true"), tr)
grouped = false; lfgMode[4] = nil

popup("TALENT_THING", 0, "a popup with no rule is never touched")

-- tallies are per rule
ok("per-rule counts kept", (HideAnnoyingPopupsDB.counts.blocked or 0) >= 1
   and (HideAnnoyingPopupsDB.counts.leaveinstance or 0) >= 2,
   tostring(HideAnnoyingPopupsDB.counts.blocked)..'/'..tostring(HideAnnoyingPopupsDB.counts.leaveinstance))

-- watch finds unknown popups by name
cmd("watch")
visible="TALENT_THING"; show("TALENT_THING")
chat={}; cmd("popups")
local out = table.concat(chat,"\n"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
ok("watch names an unknown popup", out:find("TALENT_THING") and out:find("no rule"), out)
ok("  and captures its text", out:find("Learn these talents") ~= nil, out)


-- ---- options panel: checkbox first, title full width, tooltip kept ----
local created = {}
local function widget(kind, tpl)
  local w = { kind = kind, template = tpl, points = {}, scripts = {}, _checked = false }
  function w:SetPoint(...) self.points[#self.points+1] = { ... } end
  function w:ClearAllPoints() self.points = {} end
  function w:SetSize() end
  function w:SetHeight() end
  function w:SetWidth(v) self.width = v end
  function w:GetWidth() return self.width or 560 end
  function w:GetStringHeight() return 20 end
  function w:SetText(t) self.text = t end
  function w:SetJustifyH() end
  function w:SetFontObject(f) self.font = f end
  function w:SetScript(k, fn) self.scripts[k] = fn end
  function w:HookScript(k, fn) self.scripts[k] = fn end
  function w:RegisterEvent() end
  function w:UnregisterEvent() end
  function w:SetChecked(v) self._checked = v and true or false end
  function w:GetChecked() return self._checked end
  function w:CreateFontString() return widget("fontstring") end
  function w:CreateTexture() return widget("texture") end
  function w:SetNormalTexture() self.iconButton = true end
  function w:RegisterForClicks() end
  function w:SetColorTexture() end
  created[#created+1] = w
  return w
end

GameFontNormalMed1 = { name = "GameFontNormalMed1" }
local tip = { lines = {} }
GameTooltip = {
  SetOwner = function(_, owner, anchor) tip.owner, tip.anchor = owner, anchor end,
  SetText = function(_, t, r, g, b) tip.header = t; tip.headerRGB = { r, g, b }; tip.lines = {} end,
  AddLine = function(_, t, r, g, b)
    tip.lines[#tip.lines+1] = t; tip.bodyRGB = { r, g, b }
  end,
  Show = function() tip.shown = true end,
  Hide = function() tip.shown = false end,
}
CreateFrame = function(kind, name, parent, tpl) return widget(kind, tpl) end
local panelCaptured
local opened
Settings = {
  RegisterCanvasLayoutCategory = function(panel)
    panelCaptured = panel
    return { GetID = function() return 42 end }
  end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) opened = id end,
}
fire("ADDON_LOADED", "HideAnnoyingPopups")

ok("options panel is registered", panelCaptured ~= nil)

local checks, rowFrames = {}, {}
for _, w in ipairs(created) do
  if w.kind == "CheckButton" then checks[#checks+1] = w end
  if w.kind == "Button" and w.scripts.OnEnter and not w.iconButton then
    rowFrames[#rowFrames+1] = w
  end
end
ok("  one checkbox per rule", #checks == 2, "got "..#checks)

-- what was asked for: the box comes first, the title is anchored to its right
local boxFirst = 0
for _, w in ipairs(created) do
  for _, pt in ipairs(w.points) do
    if pt[1] == "LEFT" and type(pt[2]) == "table" and pt[2].kind == "CheckButton"
       and pt[3] == "RIGHT" then boxFirst = boxFirst + 1 end
  end
end
ok("  checkbox sits to the LEFT of its title", boxFirst == 2, "matched "..boxFirst)

ok("  laying out on show does not error", pcall(function() panelCaptured.scripts.OnShow() end))

-- and the title gets most of the panel rather than Blizzard's narrow column
local widest = 0
for _, w in ipairs(created) do
  if w.kind == "fontstring" and w.width and w.width > widest then widest = w.width end
end
ok("  title has room to breathe", widest >= 480, "widest label "..widest.." of 560")

local labels = {}
for _, w in ipairs(created) do if w.kind == "fontstring" and w.text then labels[w.text] = true end end
ok("  rows are named for the popup",
   labels["Login / Reload Popup"] and labels["Island Expeditions Popup"])

local bigFonts = 0
for _, w in ipairs(created) do
  if w.font and w.font.name == "GameFontNormalMed1" then bigFonts = bigFonts + 1 end
end
ok("  row titles use the larger font", bigFonts == 2, "got "..bigFonts)

local divs = 0
for _, w in ipairs(created) do if w.kind == "texture" then divs = divs + 1 end end
ok("  a divider sits under the header", divs == 1, "textures "..divs)

local infoBtn
for _, w in ipairs(created) do if w.iconButton then infoBtn = w end end
ok("  an info button sits in the panel", infoBtn ~= nil)
chat = {}
infoBtn.scripts.OnClick()
local out2 = table.concat(chat,"\n"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
ok("    clicking it prints the counts",
   out2:find("dismissed") and out2:find("Login / Reload Popup", 1, true), out2)

-- resetting, by right-click and by command, keeps the old totals recoverable
local had = HideAnnoyingPopupsDB.total
chat = {}
infoBtn.scripts.OnClick(infoBtn, "RightButton")
ok("    right-clicking it resets the counts", (HideAnnoyingPopupsDB.total or 0) == 0,
   tostring(HideAnnoyingPopupsDB.total))
ok("      and keeps the old total recoverable",
   HideAnnoyingPopupsDB.cleared and HideAnnoyingPopupsDB.cleared.total == had,
   tostring(HideAnnoyingPopupsDB.cleared and HideAnnoyingPopupsDB.cleared.total))

popup("ADDON_ACTION_FORBIDDEN", 1, "  counting resumes after a reset")
cmd("clear")
ok("/hap clear resets them too", (HideAnnoyingPopupsDB.total or 0) == 0,
   tostring(HideAnnoyingPopupsDB.total))

-- the tooltip survived the move
rowFrames[1].scripts.OnEnter(rowFrames[1])
ok("  hovering shows a tooltip", tip.shown == true)
ok("    with the descriptive title as its header",
   tip.header == "\"Addon has been blocked from an action...\"", tostring(tip.header))
ok("      quoted, since it is the popup's own wording",
   tip.header:sub(1, 1) == '"' and tip.header:sub(-1) == '"', tip.header)
ok("    and the body beneath it",
   (tip.lines[1] or ""):find("do not want to disable the addon!", 1, true) ~= nil,
   tostring(tip.lines[1]))
ok("    with its line break kept",
   (tip.lines[1] or ""):find("working fine.\nNo thanks", 1, true) ~= nil,
   tostring(tip.lines[1]))
rowFrames[1].scripts.OnLeave()
ok("  and leaving hides it", tip.shown == false)
ok("    title is yellow",
   tip.headerRGB[1] == 1 and tip.headerRGB[2] == 0.82 and tip.headerRGB[3] == 0,
   table.concat(tip.headerRGB, ","))
ok("    body is white",
   tip.bodyRGB[1] == 1 and tip.bodyRGB[2] == 1 and tip.bodyRGB[3] == 1,
   table.concat(tip.bodyRGB, ","))
ok("    anchored to the cursor, not the panel-wide row",
   tostring(tip.anchor):find("CURSOR") ~= nil, tostring(tip.anchor))

rowFrames[2].scripts.OnEnter(rowFrames[2])
ok("    leave-prompt body starts at \"Accidentally\"",
   (tip.lines[1] or ""):sub(1, 12) == "Accidentally", tostring(tip.lines[1]))
ok("      with the lead-in removed",
   not (tip.lines[1]):find("This bug occurs") and not (tip.lines[1]):find("Let's not"),
   tostring(tip.lines[1]))
ok("      and signing off with Never again!",
   (tip.lines[1]):find("yay!\nNever again!", 1, true) ~= nil, tostring(tip.lines[1]))
ok("      leave title is quoted too",
   tip.header == "\"Leave Instance Group?\"", tostring(tip.header))

-- clicking anywhere on the row toggles, not just the box
local before = HideAnnoyingPopupsDB.rules.blocked
rowFrames[1].scripts.OnClick()
ok("  clicking the row toggles the rule",
   HideAnnoyingPopupsDB.rules.blocked == (not before),
   tostring(HideAnnoyingPopupsDB.rules.blocked))
ok("    and re-registers UIParent when turned off", uiReg.ADDON_ACTION_FORBIDDEN == true)
rowFrames[1].scripts.OnClick()
ok("    and unregisters when turned back on", uiReg.ADDON_ACTION_FORBIDDEN == false)

rowFrames[1].scripts.OnClick()
popup("ADDON_ACTION_FORBIDDEN", 0, "  a rule turned off stops dismissing")
rowFrames[1].scripts.OnClick()
popup("ADDON_ACTION_FORBIDDEN", 1, "  and turning it back on resumes")

-- /hap on its own opens the panel rather than printing a wall of text
opened = nil; chat = {}
cmd("")
ok("/hap opens the options panel", opened == 42, tostring(opened))
ok("  and prints nothing when it can", #chat == 0, table.concat(chat, " / "))

opened = nil; chat = {}
cmd("status")
local st = table.concat(chat,"\n"):gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
ok("/hap status still lists the rules",
   st:find("Login / Reload Popup", 1, true) and st:find("Island Expeditions Popup", 1, true), st)

print = SAY
SAY(""); SAY(string.format("%d passed, %d failed", pass, fail))
os.exit(fail==0 and 0 or 1)
