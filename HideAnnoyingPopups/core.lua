--[[ Hide Annoying Popups

Popups that interrupt you for no good reason, each behind its own checkbox.

Adding another is deliberately a data change, not a code change: append an
entry to RULES below. A rule says which StaticPopup to dismiss, and may carry
a guard deciding whether this particular appearance is the annoying one.

Dismissing only ever closes a dialog. It never presses a button, so it cannot
answer Yes, leave a group, or spend anything on your behalf.
]]

local ADDON = ...

HideAnnoyingPopupsDB = HideAnnoyingPopupsDB or {}
local db = HideAnnoyingPopupsDB

--------------------------------------------------------------------------
-- Guards
--------------------------------------------------------------------------

-- "Leave instance group?" is raised spontaneously as you enter an instance
-- (Island Expeditions especially), and answering Yes costs you the run plus
-- a Deserter debuff. But the same dialog appears when you *do* mean to leave,
-- so this dismisses at most one per arming: the stray one. Click Leave Group
-- again and the next prompt is yours.
--
-- Anchoring that arming on the last zone change was wrong. Measured twice,
-- the prompt lands 1-2s *before* the new instance finishes loading, so the
-- clock was really measuring how long you sat in the queue: a one-minute
-- queue was caught and a three-minute one was not. Queue events re-arm it
-- instead, which keeps the guard alive across a wait of any length and still
-- lets it lapse once you have stopped queueing.
local armedUntil, consumed = 0, false

-- A zone change or a queue popping clears the latch. A plain queue tick will
-- not: once the guard is spent it stays spent until you go somewhere.
local function Arm(hard)
    if hard then
        consumed = false
    elseif consumed then
        return
    end
    armedUntil = GetTime() + (tonumber(db.window) or 120)
end

-- Recorded next to every decision. If the guard ever misses again, this says
-- what the client thought was going on at that exact moment, which is how the
-- queue-length mistake above was found.
local function State()
    local bits = {}
    local ok, inInstance, kind = pcall(IsInInstance)
    if ok then bits[#bits + 1] = "inst=" .. tostring(inInstance) .. "/" .. tostring(kind) end
    local okg, grouped = pcall(IsInGroup, LE_PARTY_CATEGORY_INSTANCE or 2)
    if okg then bits[#bits + 1] = "igroup=" .. tostring(grouped) end
    if GetLFGMode then
        for cat = 1, 7 do
            local okm, mode, sub = pcall(GetLFGMode, cat)
            if okm and mode then
                bits[#bits + 1] = "lfg" .. cat .. "=" .. tostring(mode)
                    .. (sub and ("/" .. tostring(sub)) or "")
            end
        end
    end
    return table.concat(bits, " ")
end

local function OneShotWhileArmed(rule)
    local state = State()
    if armedUntil == 0 then return false, "not armed; " .. state end
    local late = GetTime() - armedUntil
    if late > 0 then
        return false, string.format("stale by %.1fs; %s", late, state)
    end
    armedUntil, consumed = 0, true
    return true, string.format("%.1fs of window left; %s", -late, state)
end

--------------------------------------------------------------------------
-- Rules. Add a popup here; everything else follows.
--------------------------------------------------------------------------
local RULES = {
    {
        key     = "blocked",
        popup   = "ADDON_ACTION_FORBIDDEN",
        name    = "Login / Reload Popup",
        -- quoted: the titles are the wording of the popup being referenced
        title   = "\"Addon has been blocked from an action...\"",
        desc    = "Usually harmless, fires constantly, and names an addon that is working fine."
                  .. "\nNo thanks, I do not want to disable the addon!",
        default = true,
        -- these are what build the popup, so stop it at the source too
        events  = { "ADDON_ACTION_FORBIDDEN", "ADDON_ACTION_BLOCKED" },
    },
    {
        key     = "leaveinstance",
        popup   = "CONFIRM_LEAVE_INSTANCE_PARTY",
        name    = "Island Expeditions Popup",
        title   = "\"Leave Instance Group?\"",
        desc    = "Accidentally clicking 'Yes' awards you with the Deserter debuff, yay!"
                  .. "\nNever again!",
        default = true,
        guard   = OneShotWhileArmed,
    },
}

local byPopup = {}
for _, r in ipairs(RULES) do byPopup[r.popup] = r end

--------------------------------------------------------------------------

local function Setting(rule)
    db.rules = db.rules or {}
    local v = db.rules[rule.key]
    if v == nil then return rule.default end
    return v
end

local function SetSetting(rule, on)
    db.rules = db.rules or {}
    db.rules[rule.key] = on and true or false
end

local function say(s)
    print("|cff58C6FAHideAnnoyingPopups|r: " .. s)
end

local MAX_TRACE = 40
local function trace(what, detail)
    db.trace = db.trace or {}
    if #db.trace >= MAX_TRACE then table.remove(db.trace, 1) end
    db.trace[#db.trace + 1] = { at = date("%H:%M:%S"), what = what, detail = detail }
end

local function PrintStatus()
    db.counts = db.counts or {}
    say((db.total or 0) .. " popup(s) dismissed"
        .. (db.last and (", last " .. db.last) or "") .. ":")
    for _, r in ipairs(RULES) do
        print(string.format("  %s  x%d  %s",
            Setting(r) and "|cff20ff20hidden|r" or "|cffff2020shown|r ",
            db.counts[r.key] or 0, r.name))
    end
end

-- The old totals are kept rather than discarded: a stray right-click should
-- not be the end of a tally someone has been building for months.
local function ClearStatus()
    local was = db.total or 0
    db.cleared = { total = was, counts = db.counts, at = date("%Y-%m-%d %H:%M:%S") }
    db.counts, db.total, db.last, db.seen = {}, 0, nil, nil
    say("counts reset (" .. was .. " dismissals cleared).")
end

local function Tally(rule)
    db.counts = db.counts or {}
    db.counts[rule.key] = (db.counts[rule.key] or 0) + 1
    db.total = (db.total or 0) + 1
    db.last = date("%Y-%m-%d %H:%M:%S")
end

local function HidePopup(which)
    if StaticPopup_Hide then StaticPopup_Hide(which) end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function() if StaticPopup_Hide then StaticPopup_Hide(which) end end)
    end
end

--------------------------------------------------------------------------
-- Watch mode: record every popup that appears, so an unfamiliar one can be
-- identified by name before anyone writes a rule for it. Observation only.
--------------------------------------------------------------------------
local MAX_WATCH = 60
local function RecordSeen(which)
    if not db.watch then return end
    which = tostring(which or "?")
    db.popups = db.popups or {}
    for _, e in ipairs(db.popups) do
        if e.which == which then
            e.count, e.last = e.count + 1, date("%Y-%m-%d %H:%M:%S")
            return
        end
    end
    local text
    local def = StaticPopupDialogs and StaticPopupDialogs[which]
    if def then
        local ok, t = pcall(function() return def.text end)
        if ok and type(t) == "string" then text = t:sub(1, 160) end
    end
    if #db.popups >= MAX_WATCH then table.remove(db.popups, 1) end
    db.popups[#db.popups + 1] = {
        which = which, text = text, known = byPopup[which] ~= nil,
        count = 1, first = date("%Y-%m-%d %H:%M:%S"), last = date("%Y-%m-%d %H:%M:%S"),
    }
end

local function OnPopupShown(which)
    RecordSeen(which)
    local rule = byPopup[which]
    if not rule then return end
    if not Setting(rule) then trace("seen", which .. ": rule off") return end
    if rule.guard then
        local allow, why = rule.guard(rule)
        if not allow then trace("seen", which .. ": " .. (why or "guard declined")) return end
        trace("dismissed", which .. ": " .. (why or ""))
    end
    HidePopup(which)
    Tally(rule)
    if not db.quiet then
        say("dismissed \"" .. rule.name .. "\"."
            .. (rule.guard and " Repeat the action if you meant it." or ""))
    end
end

if StaticPopup_Show then hooksecurefunc("StaticPopup_Show", OnPopupShown) end

--------------------------------------------------------------------------

local f = CreateFrame("Frame")

-- Rules with `events` are stopped at the source: unregister them from
-- UIParent so the popup is never built. Only UIParent -- other addons listen
-- to these for their own reasons and breaking them helps nobody.
local function ApplyEventRules()
    for _, r in ipairs(RULES) do
        if r.events then
            local on = Setting(r)
            for _, ev in ipairs(r.events) do
                if on then
                    if UIParent and UIParent.UnregisterEvent then UIParent:UnregisterEvent(ev) end
                    pcall(f.RegisterEvent, f, ev)
                else
                    if UIParent and UIParent.RegisterEvent then UIParent:RegisterEvent(ev) end
                    pcall(f.UnregisterEvent, f, ev)
                end
            end
        end
    end
end

-- A queue popping is the moment the stray prompt appears, so the hard events
-- arm the leave guard exactly as a zone change does. The soft ones repeat
-- while you sit in a queue, which is what covers a long wait. Registered
-- through pcall so a name this client does not know is simply skipped, and
-- `/hap trace` reports which ones actually did the work.
local ARM_HARD = { LFG_PROPOSAL_SUCCEEDED = true, LFG_PROPOSAL_SHOW = true, GROUP_JOINED = true }
local ARM_SOFT = { LFG_QUEUE_STATUS_UPDATE = true, LFG_UPDATE = true, LFG_ROLE_CHECK_SHOW = true }
local TAINT = { ADDON_ACTION_FORBIDDEN = true, ADDON_ACTION_BLOCKED = true }

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
for ev in pairs(ARM_HARD) do pcall(f.RegisterEvent, f, ev) end
for ev in pairs(ARM_SOFT) do pcall(f.RegisterEvent, f, ev) end
f:SetScript("OnEvent", function(self, event, a1, a2)
    if event == "ADDON_LOADED" then
        if a1 ~= ADDON then return end
        db = HideAnnoyingPopupsDB or {}
        HideAnnoyingPopupsDB = db
        db.window = tonumber(db.window) or 120

        -- Carry over tallies from the two addons this replaces, latching only
        -- once something was actually found. With the old addons uninstalled
        -- their saved variables never load, so latching on an empty first pass
        -- would discard the tally for good.
        if not db.migrated then
            local function carry(old, key)
                local n = old and tonumber(old.total)
                if not n or n <= 0 then return false end
                db.counts = db.counts or {}
                db.counts[key] = (db.counts[key] or 0) + n
                db.total = (db.total or 0) + n
                return true
            end
            local gotBlocked = carry(_G.HideBlockedPopupDB, "blocked")
            local gotLeave = carry(_G.HideLeavePopupDB, "leaveinstance")
            if gotBlocked or gotLeave then db.migrated = true end
        end

        ApplyEventRules()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        Arm(true)
        trace("entering", State() .. " -> armed "
            .. tostring(tonumber(db.window) or 120) .. "s")
        return
    end

    if ARM_HARD[event] or ARM_SOFT[event] then
        Arm(ARM_HARD[event])
        db.arms = db.arms or {}
        db.arms[event] = (db.arms[event] or 0) + 1
        return
    end

    if not TAINT[event] then return end

    -- a taint event we are suppressing at the source
    local rule = byPopup["ADDON_ACTION_FORBIDDEN"]
    if rule and Setting(rule) then
        HidePopup(rule.popup)
        Tally(rule)
        db.seen = db.seen or {}
        local k = tostring(a1 or "?") .. " -> " .. tostring(a2 or "?")
        db.seen[k] = (db.seen[k] or 0) + 1
    end
end)

--------------------------------------------------------------------------
-- Options panel: one checkbox per rule
--------------------------------------------------------------------------
local optionsBuilt = false
local optionsCategory

-- Opening the panel is what `/hap` is for; the ID form is preferred and the
-- name is a fallback for clients where GetID is not available.
local function OpenOptions()
    if not (Settings and Settings.OpenToCategory and optionsCategory) then return false end
    if optionsCategory.GetID then
        local gotID, id = pcall(optionsCategory.GetID, optionsCategory)
        if gotID and id and pcall(Settings.OpenToCategory, id) then return true end
    end
    return pcall(Settings.OpenToCategory, optionsCategory)
end

-- Blizzard's setting rows put the label left and the control right, and give
-- the label only about half the panel. Drawing the rows here instead puts the
-- checkbox first and lets the title run the full width. The tooltip is kept:
-- title as its white header, the longer description wrapped underneath.
local function MakeCheck(parent)
    for _, tpl in ipairs({ "UICheckButtonTemplate", "InterfaceOptionsCheckButtonTemplate",
                           "OptionsBaseCheckButtonTemplate" }) do
        local ok, box = pcall(CreateFrame, "CheckButton", nil, parent, tpl)
        if ok and box then return box end
    end
end

-- BOX_Y lifts the checkbox to sit on the text's cap centre: measured from a
-- screenshot, centring it on the row left it 2.5px low against this font.
local ROW_H, BOX, BOX_Y, PAD_L, GAP = 30, 26, 2, 16, 8

local function BuildOptions()
    if optionsBuilt then return end
    if not (Settings and Settings.RegisterCanvasLayoutCategory
            and Settings.RegisterAddOnCategory) then
        return
    end

    optionsBuilt = pcall(function()
        db.rules = db.rules or {}

        local panel = CreateFrame("Frame")
        panel.name = "Hide Annoying Popups"

        local heading = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        heading:SetPoint("TOPLEFT", PAD_L, -16)
        heading:SetText("Hide Annoying Popups")

        local intro = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        intro:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -8)
        intro:SetJustifyH("LEFT")
        intro:SetText("Tick a popup to stop it interrupting you. Hover for details.")

        local info = CreateFrame("Button", nil, panel)
        info:SetSize(18, 18)
        info:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
        info:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        info:SetScript("OnClick", function(_, button)
            if button == "RightButton" then ClearStatus() else PrintStatus() end
        end)
        info:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Counts", 1, 0.82, 0)
            GameTooltip:AddLine("Print how many of each popup have been dismissed."
                .. "\nRight-click to reset, or /hap clear.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        info:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

        local divider = panel:CreateTexture(nil, "ARTWORK")
        divider:SetHeight(1)
        divider:SetColorTexture(1, 1, 1, 0.18)

        local rows = {}
        for _, r in ipairs(RULES) do
            if db.rules[r.key] == nil then db.rules[r.key] = r.default end

            -- the row spans the panel so the tooltip and a click work anywhere
            -- along it, not just on the box itself
            local row = CreateFrame("Button", nil, panel)
            row:SetHeight(ROW_H)

            local box = MakeCheck(row)
            if not box then error("no usable check button template") end
            box:SetSize(BOX, BOX)
            -- LEFT-to-LEFT and LEFT-to-RIGHT both align vertical centres, so the
            -- box, the row and the title all share one centre line
            box:SetPoint("LEFT", row, "LEFT", 0, BOX_Y)

            local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
            -- a step up from the default row font; fall back if a client has
            -- neither of the larger objects
            local bigger = GameFontNormalMed1 or GameFontNormalMed2 or GameFontNormalLarge
            if bigger then pcall(label.SetFontObject, label, bigger) end
            label:SetPoint("LEFT", box, "RIGHT", GAP, 0)
            label:SetJustifyH("LEFT")
            label:SetText(r.name)

            local function Toggle(on)
                SetSetting(r, on)
                box:SetChecked(on)
                ApplyEventRules()
            end
            box:SetScript("OnClick", function(self) Toggle(self:GetChecked() and true or false) end)
            row:SetScript("OnClick", function() Toggle(not Setting(r)) end)

            row:SetScript("OnEnter", function(self)
                if not GameTooltip then return end
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 12, 0)
                -- the first line uses GameTooltipHeaderText, so SetText is what
                -- makes the title the larger one
                GameTooltip:SetText(r.title, 1, 0.82, 0)
                GameTooltip:AddLine(r.desc, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)

            rows[#rows + 1] = { row = row, box = box, label = label, rule = r }
        end

        local function Layout()
            local width = panel:GetWidth() or 0
            if width < 200 then width = 560 end
            local inner = width - PAD_L * 2
            info:ClearAllPoints()
            info:SetPoint("TOPRIGHT", -PAD_L, -16)
            intro:SetWidth(inner)

            local y = -16 - heading:GetStringHeight() - 8 - intro:GetStringHeight() - 14
            divider:ClearAllPoints()
            divider:SetPoint("TOPLEFT", PAD_L, y)
            divider:SetWidth(inner)
            y = y - 14

            for _, e in ipairs(rows) do
                e.row:ClearAllPoints()
                e.row:SetPoint("TOPLEFT", PAD_L, y)
                e.row:SetWidth(inner)
                e.label:SetWidth(inner - BOX - GAP)
                y = y - ROW_H - 10
            end
        end

        local function Refresh()
            for _, e in ipairs(rows) do
                e.box:SetChecked(Setting(e.rule) and true or false)
            end
        end

        panel:SetScript("OnShow", function() Refresh() Layout() end)
        panel:SetScript("OnSizeChanged", Layout)

        -- Do not assign category.ID here. Blizzard registers the category under
        -- the id it generated, so overwriting it makes GetID return a key that
        -- is not in the lookup table and OpenToCategory quietly does nothing.
        local category = Settings.RegisterCanvasLayoutCategory(panel, "Hide Annoying Popups")
        Settings.RegisterAddOnCategory(category)
        optionsCategory = category
    end)
end
f:HookScript("OnEvent", function(_, event, a1)
    if event == "ADDON_LOADED" and a1 == ADDON then BuildOptions() end
end)

--------------------------------------------------------------------------

SLASH_HIDEANNOYINGPOPUPS1 = "/hap"
SLASH_HIDEANNOYINGPOPUPS2 = "/hideannoying"
SlashCmdList["HIDEANNOYINGPOPUPS"] = function(arg)
    arg = (arg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

    if arg == "" then
        if OpenOptions() then return end
        say("could not open the options panel.")
        PrintStatus()
        return
    end
    if arg == "status" then PrintStatus() return end
    if arg == "clear" then ClearStatus() return end

    -- Finding a popup that has no rule yet: watch names it, popups lists what
    -- was seen. This is the only way to learn a dialog's internal key.
    if arg == "watch" then
        db.watch = not db.watch
        say("popup watch " .. (db.watch and "|cff20ff20on|r" or "|cffff2020off|r")
            .. " -- reproduce the popup, then |cffffff78/hap popups|r.")
        return
    end
    if arg == "popups" then
        if not db.popups or #db.popups == 0 then
            say("nothing recorded. |cffffff78/hap watch|r first, then reproduce it.")
            return
        end
        say(#db.popups .. " popup type(s) seen:")
        for _, e in ipairs(db.popups) do
            print(string.format("  %-34s x%-4d %s", e.which, e.count,
                e.known and "|cffff8040(we have a rule)|r" or "|cff909090(no rule)|r"))
            if e.text then print("      " .. e.text) end
        end
        return
    end

    -- Undeclared diagnostics, kept for working out why a guard did or did not
    -- fire. Deliberately absent from the help text below.
    if arg == "popups clear" then db.popups = nil say("recorded popups cleared.") return end
    if arg == "trace" then
        if db.arms then
            local parts = {}
            for ev, n in pairs(db.arms) do parts[#parts + 1] = ev .. " x" .. n end
            table.sort(parts)
            if #parts > 0 then say("armed by: " .. table.concat(parts, ", ")) end
        end
        if not db.trace or #db.trace == 0 then say("no trace yet.") return end
        for _, t in ipairs(db.trace) do
            print(string.format("  %s  %-10s %s", t.at, t.what, t.detail or ""))
        end
        return
    end
    local secs = arg:match("^window%s+(%d+)$")
    if secs then db.window = tonumber(secs) say("window: " .. db.window .. "s.") return end

    say("|cffffff78/hap|r opens the options. |cffffff78/hap status|r shows the counts,"
        .. " |cffffff78/hap clear|r resets them.")
    print("   Pestered by some other dialog? |cffffff78/hap watch|r then |cffffff78/hap popups|r names it.")
end
