local addonName = ...
local L = Levelmate.L
Levelmate = Levelmate or {}
Levelmate.name = addonName
Levelmate.version = "1.0.4"

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(L("|cff66ccffLevelmate|r: ") .. tostring(msg))
end
Levelmate.Print = Print

-- Leistungsmessung (/lm leistung): Wie viel Rechenzeit braucht das Addon?
Levelmate.Perf = { log = {} }
function Levelmate.Perf.Add(kind, ms, why, sections)
    local now = GetTime and GetTime() or 0
    local l = Levelmate.Perf.log
    l[#l + 1] = { t = now, kind = kind, ms = ms, why = why, sections = sections }
    while #l > 400 or (l[1] and now - l[1].t > 300) do table.remove(l, 1) end
end
function Levelmate.Perf.Report(seconds)
    seconds = seconds or 60
    local now = GetTime and GetTime() or 0
    local agg = {}
    for _, e in ipairs(Levelmate.Perf.log) do
        if now - e.t <= seconds then
            local a = agg[e.kind] or { n = 0, sum = 0, max = 0, why = {} }
            a.n = a.n + 1; a.sum = a.sum + e.ms
            if e.ms > a.max then a.max = e.ms end
            if e.why then a.why[e.why] = (a.why[e.why] or 0) + 1 end
            agg[e.kind] = a
        end
    end
    Print(string.format(L("Leistung der letzten %d s:"), seconds))
    local names = { refresh = L("Neuplanung"), preview = L("Vorschau (Hintergrund)") }
    local any = false
    for kind, a in pairs(agg) do
        any = true
        local w = {}
        for k, v in pairs(a.why) do w[#w + 1] = L(k) .. " " .. v .. "x" end
        Print(string.format(L("  %s: %d-mal, zusammen %d ms, längste %d ms%s"), names[kind] or kind, a.n,
            math.floor(a.sum + 0.5), math.floor(a.max + 0.5), #w > 0 and (L(" (Auslöser: ") .. table.concat(w, ", ") .. ")") or ""))
    end
    if not any then Print(L("  keine Berechnungen in dieser Zeit")) end
    -- Die langsamste Neuplanung genauer
    local worst
    for _, e in ipairs(Levelmate.Perf.log) do
        if now - e.t <= seconds and e.kind == "refresh" and (not worst or e.ms > worst.ms) then worst = e end
    end
    if worst and worst.sections then
        local parts, planSum = {}, 0
        for k, v in pairs(worst.sections) do parts[#parts + 1] = { k, v }; planSum = planSum + v end
        table.sort(parts, function(a, b) return a[2] > b[2] end)
        local txt = {}
        for i = 1, math.min(4, #parts) do txt[#txt + 1] = string.format("%s %d", L(parts[i][1]), math.floor(parts[i][2] + 0.5)) end
        Print(string.format(L("  Langsamste (%d ms, vor %d s, %s): Planung %d ms [%s], Anzeige/Rest %d ms"),
            math.floor(worst.ms + 0.5), math.floor(now - worst.t), L(worst.why or "?"), math.floor(planSum + 0.5),
            table.concat(txt, ", "), math.floor(worst.ms - planSum + 0.5)))
    end
    if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
        UpdateAddOnMemoryUsage()
        Print(string.format(L("  Speicher: %.1f MB"), (GetAddOnMemoryUsage("Levelmate") or 0) / 1024))
    end
    Print(L("  Zum Vergleich: Ein Bild bei 60 FPS dauert 16 ms. Was deutlich länger ist, merkt man als Ruckler."))
end

Levelmate.failedEvents = {}
local function SafeRegister(frame, event)
    -- Unbekannte Events werfen im modernen Client einen Fehler; pcall faengt ihn ab.
    local ok = pcall(frame.RegisterEvent, frame, event)
    if not ok then table.insert(Levelmate.failedEvents, event) end
end

local WIDTH = 320
local INNER = WIDTH - 24

local function CharDB()
    Levelmate_CharDB = Levelmate_CharDB or {}
    Levelmate_CharDB.skipStack = Levelmate_CharDB.skipStack or {}
    if Levelmate_CharDB.mode == "fastest" then Levelmate_CharDB.mode = "quests" end  -- Modus entfernt (0.9.62)
    return Levelmate_CharDB
end

---------------------------------------------------------------------------
-- Hauptfenster
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "LevelmateQuestPanel", UIParent, "BackdropTemplate")
panel:SetSize(WIDTH, 300)
panel:SetFrameStrata("MEDIUM")
panel:SetMovable(true)
panel:EnableMouse(true)
panel:SetClampedToScreen(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    Levelmate_DB.panelPos = { point, rel, x, y }
end)
panel:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
panel:SetBackdropColor(0.035, 0.055, 0.12, 0.72)
panel:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)

-- Unterer Bereich (Vorschau + Questlog) ist scrollbar.
local SCROLL_W = INNER - 14
local scroll = CreateFrame("ScrollFrame", nil, panel)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(SCROLL_W, 10)
scroll:SetScrollChild(content)
scroll:EnableMouseWheel(true)

local slider = CreateFrame("Slider", nil, panel, "BackdropTemplate")
slider:SetOrientation("VERTICAL")
slider:SetWidth(10)
slider:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
slider:SetBackdropColor(1, 1, 1, 0.08)
slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
local thumb = slider:GetThumbTexture()
if thumb then thumb:SetSize(14, 24) end
slider:SetMinMaxValues(0, 0)
slider:SetValueStep(1)
slider:SetValue(0)
slider:SetScript("OnValueChanged", function(_, v) scroll:SetVerticalScroll(v) end)
scroll:SetScript("OnMouseWheel", function(_, delta)
    local lo, hi = slider:GetMinMaxValues()
    slider:SetValue(math.max(lo, math.min(hi, slider:GetValue() - delta * 30)))
end)

-- Schrift-Helfer. SetText merkt sich den letzten Text: Ist er gleich, passiert
-- nichts (spart Neuberechnung von Zeilenumbruch und Hoehe bei jedem Refresh).
local function SolidColor(tex, r, g, b, a)
    if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a)
    else tex:SetTexture("Interface\\Buttons\\WHITE8X8"); tex:SetVertexColor(r, g, b, a) end
end
local function CachedSetText(fs)
    local orig = fs.SetText
    fs.SetText = function(self, t)
        if self._flaText == t then return end
        self._flaText = t
        orig(self, t)
    end
end
local function Text(template, parent, width)
    local fs = (parent or panel):CreateFontString(nil, "OVERLAY", template)
    fs:SetWidth(width or (parent == content and SCROLL_W or INNER))
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    if fs.SetWordWrap then fs:SetWordWrap(true) end
    CachedSetText(fs)
    return fs
end

-- Klickbare Questnamen: "|Hlevelmate:q:<id>|h...|h" oeffnet die Quest im Questlog
local function QLink(id, text)
    if not id then return text end
    return "|Hlevelmate:q:" .. id .. "|h" .. text .. "|h"
end
local function OpenQuest(id)
    id = tonumber(id)
    if not id then return end
    local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
    if not idx or idx == 0 then
        local q = Levelmate.DB.Quest and Levelmate.DB.Quest(id)
        Print(string.format(L("„%s“ ist noch nicht in deinem Questlog – erst annehmen."), q and q.name or tostring(id)))
        return
    end
    -- neuer Client: Questlog neben der Karte; alter: eigenes Questlog-Fenster
    if QuestMapFrame_OpenToQuestDetails then
        pcall(QuestMapFrame_OpenToQuestDetails, id)
    elseif QuestLog_OpenToQuest then
        pcall(QuestLog_OpenToQuest, idx)
    else
        if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
        if QuestLog_SetSelection then pcall(QuestLog_SetSelection, idx) end
        if ToggleQuestLog then pcall(ToggleQuestLog) elseif QuestLogFrame then ShowUIPanel(QuestLogFrame) end
    end
end
Levelmate.OpenQuest = OpenQuest
local function EnableQuestLinks(frame)
    if not frame or not frame.SetHyperlinksEnabled then return end
    frame:SetHyperlinksEnabled(true)
    -- Klicks brauchen Maus; Ziehen weiter ans Fenster durchreichen
    frame:EnableMouse(true)
    if frame.RegisterForDrag then
        frame:RegisterForDrag("LeftButton")
        frame:SetScript("OnDragStart", function() panel:StartMoving() end)
        frame:SetScript("OnDragStop", function()
            local f = panel:GetScript("OnDragStop")
            if f then f(panel) else panel:StopMovingOrSizing() end
        end)
    end
    frame:SetScript("OnHyperlinkClick", function(_, link)
        local id = type(link) == "string" and link:match("^levelmate:q:(%d+)")
        if id then OpenQuest(id) end
    end)
    frame:SetScript("OnHyperlinkEnter", function(self, link)
        if type(link) ~= "string" or not link:match("^levelmate:q:") then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(L("Klicken: Quest im Questlog öffnen"))
        GameTooltip:Show()
    end)
    frame:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
end

local function Button(text, width)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end
local function Tip(frame, title, text)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L(title))
        if text then GameTooltip:AddLine(L(text), 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local GOLD = { 0.95, 0.76, 0.31 }
panel.logo = panel:CreateTexture(nil, "ARTWORK")
panel.logo:SetSize(20, 20)
panel.logo:SetTexture("Interface\\AddOns\\Levelmate\\Media\\Logo")
panel.logo:SetPoint("TOPLEFT", panel, "TOPLEFT", 11, -8)
panel.title = Text("GameFontNormal")
panel.title:SetText("Levelmate")
panel.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])

-- Kleine Symbol-Knoepfe oben rechts
local function IconButton(icon)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(18, 18)
    b:SetNormalTexture(icon)
    local t = b:GetNormalTexture()
    if t then t:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return b
end
local function SetIconActive(b, on)
    local t = b and (b.icon or b:GetNormalTexture())
    if not t then return end
    if t.SetDesaturated then t:SetDesaturated(not on) end
    if b.icon then
        if on then t:SetVertexColor(1, 0.82, 0.3) else t:SetVertexColor(0.45, 0.45, 0.45) end
        if b.SetBackdropBorderColor then b:SetBackdropBorderColor(0.79, 0.60, 0.23, on and 0.9 or 0.3) end
    else
        local v = on and 1 or 0.45
        t:SetVertexColor(v, v, v)
    end
end

panel.optionsButton = IconButton("Interface\\Icons\\INV_Misc_Gear_01")
panel.optionsButton:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -9)
panel.optionsButton:SetScript("OnClick", function() if Levelmate.Options then Levelmate.Options.Toggle() end end)
Tip(panel.optionsButton, "Einstellungen")

panel.modeButton = IconButton("Interface\\Icons\\INV_Misc_Book_09")
panel.modeButton:SetPoint("RIGHT", panel.optionsButton, "LEFT", -6, 0)
panel.modeButton.SetText = function(self, t) self.modeLabel = t end
panel.modeButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L("Modus"))
    if self.modeLabel then GameTooltip:AddLine(self.modeLabel, 1, 1, 1) end
    GameTooltip:AddLine(L("Klicken zum Wechseln."), 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
panel.modeButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Pfeil-Knopf: zeigt denselben Pfeil wie der Richtungspfeil selbst
panel.arrowButton = CreateFrame("Button", nil, panel, "BackdropTemplate")
panel.arrowButton:SetSize(18, 18)
panel.arrowButton:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
panel.arrowButton:SetBackdropColor(0.075, 0.115, 0.22, 0.9)
panel.arrowButton:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
panel.arrowButton.icon = panel.arrowButton:CreateTexture(nil, "ARTWORK")
panel.arrowButton.icon:SetSize(16, 16)
panel.arrowButton.icon:SetPoint("CENTER", panel.arrowButton, "CENTER", 0, 0)
panel.arrowButton.icon:SetTexture("Interface\\Minimap\\MinimapArrow")
panel.arrowButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
panel.arrowButton:SetPoint("RIGHT", panel.modeButton, "LEFT", -6, 0)
Tip(panel.arrowButton, "Pfeil", "Richtungspfeil ein- oder ausblenden.")

-- Neue Zauber beim Lehrer: Symbol mit Anzahl, nur sichtbar wenn es etwas zu lernen gibt
panel.learnButton = IconButton("Interface\\Icons\\INV_Scroll_03")
panel.learnButton:SetPoint("RIGHT", panel.arrowButton, "LEFT", -6, 0)

---------------------------------------------------------------------------
-- Dungeon-Fenster (Modi mit Dungeons): Dungeons deiner Stufe und ihre Quests
---------------------------------------------------------------------------
panel.dungeonButton = IconButton("Interface\\Icons\\INV_Misc_Key_03")
panel.dungeonButton:SetPoint("RIGHT", panel.arrowButton, "LEFT", -6, 0)
panel.dungeonButton:Hide()
Tip(panel.dungeonButton, "Dungeons", "Dungeons deiner Stufe mit ihren Quests. Quests abholen oder direkt hingehen.")

local dframe = CreateFrame("Frame", "LevelmateDungeonFrame", UIParent, "BackdropTemplate")
dframe:SetSize(300, 120)
dframe:SetFrameStrata("MEDIUM")
dframe:SetBackdrop(panel:GetBackdrop())
dframe:SetBackdropColor(0.035, 0.055, 0.12, 0.92)
dframe:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
dframe:SetPoint("TOPLEFT", panel, "TOPRIGHT", 6, 0)
dframe:SetClampedToScreen(true)
dframe:EnableMouse(true)
dframe:Hide()
table.insert(UISpecialFrames, "LevelmateDungeonFrame")
dframe.title = dframe:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dframe.title:SetPoint("TOPLEFT", 10, -9)
dframe.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
dframe.title:SetText(L("Dungeons"))
dframe.sub = dframe:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dframe.sub:SetPoint("TOPLEFT", dframe.title, "BOTTOMLEFT", 0, -2)
dframe.sub:SetTextColor(0.7, 0.7, 0.7)
dframe.close = CreateFrame("Button", nil, dframe, "UIPanelCloseButton")
dframe.close:SetPoint("TOPRIGHT", dframe, "TOPRIGHT", 2, 2)
dframe.slots = {}
Levelmate.DungeonFrame = dframe

local STATUS_TXT = { ideal = "ideal", soon = "bald grau", low = "ab Stufe %d", grey = "grau" }
local STATUS_COL = { ideal = { 0.4, 1, 0.4 }, soon = { 1, 0.75, 0.2 }, low = { 0.8, 0.5, 0.5 }, grey = { 0.6, 0.6, 0.6 } }

local function DSlot(i)
    local s = dframe.slots[i]
    if s then return s end
    s = CreateFrame("Frame", nil, dframe, "BackdropTemplate")
    s:SetWidth(280)
    s:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    s:SetBackdropColor(0.06, 0.09, 0.17, 0.85)
    s.name = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.name:SetPoint("TOPLEFT", 8, -6)
    s.name:SetJustifyH("LEFT")
    s.lvl = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.lvl:SetPoint("TOPRIGHT", -8, -8)
    s.info = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    s.info:SetPoint("TOPLEFT", s.name, "BOTTOMLEFT", 0, -3)
    s.info:SetWidth(264); s.info:SetJustifyH("LEFT")
    if s.info.SetWordWrap then s.info:SetWordWrap(true) end
    s.focus = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    s.focus:SetSize(120, 20)
    s.go = CreateFrame("Button", nil, s, "UIPanelButtonTemplate")
    s.go:SetSize(110, 20)
    s.focus:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("Quests abholen"))
        GameTooltip:AddLine(L("Levelmate holt die Dungeonquests dieses Dungeons als Nächstes ab (nochmal klicken: aus)."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    s.go:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L("Jetzt hin"))
        GameTooltip:AddLine(L("Der Dungeon wird sofort der nächste Schritt, z. B. wenn deine Gruppe bereit ist. Danach geht die Route normal weiter."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    s.focus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    s.go:SetScript("OnLeave", function() GameTooltip:Hide() end)
    dframe.slots[i] = s
    return s
end

local function QuestList(list, n)
    local names = {}
    for i = 1, math.min(#list, n) do
        local x = list[i]
        local zone = x.map and Levelmate.Planner.MapName(x.map)
        names[#names + 1] = (x.q.name or "?") .. (zone and (" (" .. zone .. ")") or "")
    end
    if #list > n then names[#names + 1] = string.format(L("+%d weitere"), #list - n) end
    return table.concat(names, ", ")
end

function Levelmate.UpdateDungeonFrame()
    if not dframe:IsShown() then return end
    local list = Levelmate.Planner.DungeonOverview and Levelmate.Planner.DungeonOverview() or {}
    dframe.sub:SetText(string.format(L("Stufe %d · passend für dich"), UnitLevel("player") or 0))
    local y, shown = -40, 0
    for i, e in ipairs(list) do
        if i > 6 then break end
        shown = i
        local s = DSlot(i)
        s:ClearAllPoints()
        s:SetPoint("TOPLEFT", dframe, "TOPLEFT", 10, y)
        s:SetBackdropBorderColor(0.79, 0.60, 0.23, (e.going or e.focused or e.status == "ideal") and 0.9 or 0.25)
        s.name:SetText(e.name)
        local st = STATUS_TXT[e.status] or ""
        if e.status == "low" then st = string.format(L(st), e.min) else st = L(st) end
        local col = STATUS_COL[e.status] or { 1, 1, 1 }
        s.lvl:SetText(string.format("%d–%d · %s", e.min or 0, e.max or 0, st))
        s.lvl:SetTextColor(col[1], col[2], col[3])
        local lines = {}
        local ready = 0
        for _, x in ipairs(e.inLog) do if x.ready then ready = ready + 1 end end
        local parts = {}
        parts[#parts + 1] = string.format(L("%d im Log"), #e.inLog) .. (ready > 0 and string.format(L(" (%d fertig)"), ready) or "")
        parts[#parts + 1] = string.format(L("%d abholbar"), #e.available)
        if #e.blocked > 0 then parts[#parts + 1] = string.format(L("%d brauchen eine Vorquest"), #e.blocked) end
        lines[#lines + 1] = table.concat(parts, " · ")
        if #e.available > 0 then lines[#lines + 1] = L("Abholen: ") .. QuestList(e.available, 2) end
        if e.story and CharDB().mode == "story" then lines[#lines + 1] = "|cffb070ff" .. L("Finale von: ") .. e.story .. "|r" end
        local ent = e.entrance and Levelmate.Planner.MapName(e.entrance.map)
        lines[#lines + 1] = (e.xp > 0 and string.format(L("≈ %d XP aus Quests"), math.floor(e.xp + 0.5)) or L("keine Quests bekannt"))
            .. (ent and (L(" · Eingang: ") .. ent) or "")
        s.info:SetText(table.concat(lines, "\n"))
        local infoH = s.info:GetStringHeight() or 40
        s.focus:ClearAllPoints(); s.go:ClearAllPoints()
        s.focus:SetPoint("TOPLEFT", s.info, "BOTTOMLEFT", 0, -5)
        s.go:SetPoint("LEFT", s.focus, "RIGHT", 6, 0)
        s.focus:SetText(e.focused and L("Abholen: an") or L("Quests abholen"))
        s.focus:SetShown(#e.available > 0)
        if not s.focus:IsShown() then s.go:ClearAllPoints(); s.go:SetPoint("TOPLEFT", s.info, "BOTTOMLEFT", 0, -5) end
        s.go:SetText(e.going and L("Doch nicht") or L("Jetzt hin"))
        local area, name = e.area, e.name
        s.focus:SetScript("OnClick", function()
            local on = Levelmate.Planner.SetDungeonFocus(area)
            Print(on and string.format(L("Levelmate holt jetzt zuerst die Quests für %s ab."), name)
                or string.format(L("Quests für %s: wieder normal eingeplant."), name))
            Levelmate.Refresh()
        end)
        s.go:SetScript("OnClick", function()
            local on = Levelmate.Planner.SetDungeonGo(area)
            Print(on and string.format(L("Nächster Schritt: %s. Viel Spaß!"), name)
                or string.format(L("%s abgebrochen – die Route geht normal weiter."), name))
            Levelmate.Refresh()
        end)
        local h = 6 + 16 + 3 + infoH + 5 + 20 + 8
        s:SetHeight(h)
        s:Show()
        y = y - h - 6
    end
    for i = shown + 1, #dframe.slots do dframe.slots[i]:Hide() end
    if shown == 0 then
        dframe.sub:SetText(L("Gerade kein Dungeon für deine Stufe bekannt."))
        y = y - 4
    end
    dframe:SetHeight(-y + 6)
end
dframe:SetScript("OnShow", function()
    local ok, err = pcall(Levelmate.UpdateDungeonFrame)
    if not ok then Print("|cffff4040Dungeon-Fenster:|r " .. tostring(err)) end
end)
panel.dungeonButton:SetScript("OnClick", function()
    if dframe:IsShown() then dframe:Hide() else dframe:Show() end
end)
panel.learnButton.count = panel.learnButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
panel.learnButton.count:SetPoint("BOTTOMRIGHT", panel.learnButton, "BOTTOMRIGHT", 3, -2)
panel.learnButton.count:SetTextColor(0.5, 1, 0.5)
panel.learnButton:Hide()
panel.learnButton:SetScript("OnEnter", function(self)
    local Tr = Levelmate.Trainer
    local n, cost = 0, 0
    if Tr and Tr.Learnable then n, cost = Tr.Learnable() end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(n == 1 and L("1 neuer Zauber kann gelernt werden") or (n .. L(" neue Zauber können gelernt werden")))
    GameTooltip:AddLine(L("Kosten: ") .. Tr.Money(cost), 1, 1, 1)
    local t, d = Tr.Nearest and Tr.Nearest()
    if t then
        local zone = Levelmate.Planner.MapName(t.point.map) or "?"
        GameTooltip:AddLine(string.format(L("Nächster Lehrer: %s (%s, ca. %d m)"), t.name or "?", zone,
            math.floor((d or 0) * 0.9144 + 0.5)), 1, 1, 1, true)
    end
    GameTooltip:AddLine(L("Der Lehrer kommt als Schritt dran, sobald du in seiner Nähe oder in seiner Hauptstadt bist."),
        0.7, 0.7, 0.7, true)
    GameTooltip:Show()
end)
panel.learnButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Fortschrittsbalken: Stufe und Zeit bis zur naechsten Stufe
panel.bar = CreateFrame("StatusBar", nil, panel)
panel.bar:SetSize(INNER, 8)
panel.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
panel.bar:SetStatusBarColor(0.85, 0.66, 0.22)
panel.bar:SetMinMaxValues(0, 1)
panel.bar:SetValue(0)
do
    local bg = panel.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    SolidColor(bg, 0.10, 0.14, 0.25, 1)
end
panel.bar:EnableMouse(true)
panel.bar:RegisterForDrag("LeftButton")
panel.bar:SetScript("OnDragStart", function() panel:StartMoving() end)
panel.bar:SetScript("OnDragStop", function() local f = panel:GetScript("OnDragStop"); if f then f(panel) end end)
panel.bar:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local faction = UnitFactionGroup("player")
    GameTooltip:SetText(string.format("%s · %s · %s", UnitRace("player") or "?", UnitClass("player") or "?",
        faction == "Alliance" and L("Allianz") or faction or "?"))
    local xp, max = UnitXP("player") or 0, UnitXPMax("player") or 0
    if max > 0 then GameTooltip:AddLine(string.format(L("Erfahrung: %d / %d (%d%%)"), xp, max, math.floor(xp / max * 100)), 1, 1, 1) end
    local pace, sec = Levelmate.Smart.Pace()
    if pace then
        GameTooltip:AddLine(string.format(L("Restzeit aus deinem Spieltempo (letzte Stunde): %d XP/min."), math.floor(pace + 0.5)), 0.7, 0.7, 0.7, true)
    else
        GameTooltip:AddLine(string.format(L("Restzeit geschätzt – dein Tempo wird noch gemessen (%d von 10 Minuten)."),
            math.floor((sec or 0) / 60)), 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
end)
panel.bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
panel.barLeft = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.barRight = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
panel.barRight:SetTextColor(0.75, 0.75, 0.75)
CachedSetText(panel.barLeft)
CachedSetText(panel.barRight)

-- Gebietszeile (2-3 empfohlene Gebiete, das aktuelle hervorgehoben)
panel.zone = Text("GameFontHighlightSmall")
panel.planText = Text("GameFontHighlightSmall")   -- alt, bleibt leer
panel.player = Text("GameFontHighlightSmall")     -- alt, wird nicht mehr angezeigt
panel.player:Hide()

-- Karte fuer den aktuellen Schritt
local CARD_PAD = 10
local CARD_TEXT_W = INNER - CARD_PAD - 12
panel.card = CreateFrame("Frame", nil, panel, "BackdropTemplate")
panel.card:SetWidth(INNER)
panel.card:SetBackdrop({
    bgFile = "Interface/Buttons/WHITE8X8",
    edgeFile = "Interface/Buttons/WHITE8X8",
    edgeSize = 1,
})
panel.card:SetBackdropColor(0.075, 0.115, 0.22, 0.75)
panel.card:SetBackdropBorderColor(0.18, 0.23, 0.38, 1)
panel.cardAccent = panel.card:CreateTexture(nil, "ARTWORK")
panel.cardAccent:SetPoint("TOPLEFT", panel.card, "TOPLEFT", 1, -1)
panel.cardAccent:SetPoint("BOTTOMLEFT", panel.card, "BOTTOMLEFT", 1, 1)
panel.cardAccent:SetWidth(3)
SolidColor(panel.cardAccent, 1, 0.82, 0, 0.9)
panel.kindLabel = Text("GameFontNormalSmall", panel.card, CARD_TEXT_W)
panel.stepTitle = Text("GameFontNormalLarge", panel.card, CARD_TEXT_W)
EnableQuestLinks(panel.card)
EnableQuestLinks(content)
panel.stepDetail = Text("GameFontHighlightSmall", panel.card, CARD_TEXT_W)
panel.stepDetail:SetTextColor(0.82, 0.82, 0.82)
panel.badge = Text("GameFontHighlightSmall", panel.card, CARD_TEXT_W)
panel.nextText = Text("GameFontDisableSmall")
panel.nextText:SetJustifyH("CENTER")

local function HeaderText(label, open)
    local icon = open and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up"
    return "|T" .. icon .. ":12:12|t " .. label
end
local function SectionHeader(fs, key)
    fs:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local line = content:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("BOTTOMLEFT", fs, "TOPLEFT", 0, 4)
    line:SetWidth(SCROLL_W)
    SolidColor(line, GOLD[1], GOLD[2], GOLD[3], 0.25)
    local b = CreateFrame("Button", nil, content)
    b:SetPoint("TOPLEFT", fs, "TOPLEFT", -2, 2)
    b:SetSize(SCROLL_W + 4, 18)
    local h = b:CreateTexture(nil, "HIGHLIGHT")
    h:SetAllPoints()
    SolidColor(h, 1, 1, 1, 0.06)
    b:SetScript("OnClick", function()
        CharDB()[key] = not CharDB()[key]
        if Levelmate.Refresh then Levelmate.Refresh() end
    end)
    fs.toggle, fs.line = b, line
end
panel.previewTitle = Text("GameFontNormal", content)
panel.previewTitle:SetText(HeaderText(L("Nächste Schritte"), true))
SectionHeader(panel.previewTitle, "previewHidden")
panel.previewText = Text("GameFontHighlightSmall", content)

-- Knoepfe in der Karte: Zurueckholen (Symbol) und Ueberspringen
panel.backButton = CreateFrame("Button", nil, panel.card)
panel.backButton:SetSize(22, 22)
panel.backButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
panel.backButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down")
panel.backButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
Tip(panel.backButton, "Zurückholen", "Holt die zuletzt übersprungene Quest sofort wieder in die Route.")
panel.skipButton = CreateFrame("Button", nil, panel.card, "UIPanelButtonTemplate")
panel.skipButton:SetSize(100, 20)
panel.skipButton:SetText(L("Überspringen"))
Tip(panel.skipButton, "Überspringen", "Diese Quest kommt nicht mehr in die Route. Der Pfeil holt sie zurück, /lm ausgelassen zeigt alle.")
panel.laterButton = CreateFrame("Button", nil, panel.card, "UIPanelButtonTemplate")
panel.laterButton:SetSize(70, 20)
panel.laterButton:SetText(L("Später"))
Tip(panel.laterButton, "Später", "Stellt diesen Schritt zurück. Er kommt nach einem halben Level von selbst wieder.")

panel.questTitle = Text("GameFontNormal", content)
panel.questTitle:SetText(HeaderText(L("Questlog"), true))
SectionHeader(panel.questTitle, "questHidden")
panel.questText = Text("GameFontHighlightSmall", content)
panel.xpText = Text("GameFontHighlightSmall", content)

-- Oberer Teil fest, unterer Teil (Danach + Questlog) scrollbar.
-- Die Fensterhoehe stellst du mit der Ecke unten rechts ein (wird gespeichert).
local DEFAULT_HEIGHT = 400
local function HasText(fs)
    local t = fs:GetText()
    return t ~= nil and t ~= ""
end
local function Layout()
    local y = -10
    local function Place(fs, gap, parent, x)
        y = y - (gap or 0)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", parent or panel, "TOPLEFT", x or (parent and 0 or 12), y)
        local h = HasText(fs) and fs:GetStringHeight() or 0
        y = y - h
    end
    panel.title:SetWidth(INNER - 110)
    Place(panel.title, 0, nil, 36)
    y = math.min(y, -32)

    -- Stufe und Restzeit ueber einem schmalen Balken
    panel.barLeft:ClearAllPoints()
    panel.barLeft:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    panel.barRight:ClearAllPoints()
    panel.barRight:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -12, y)
    y = y - 14
    panel.bar:ClearAllPoints()
    panel.bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, y)
    y = y - 8
    -- Gebiete
    if HasText(panel.zone) then Place(panel.zone, 6) end

    -- Karte
    y = y - 8
    local cardTop = y
    panel.card:ClearAllPoints()
    panel.card:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, cardTop)
    y = -8
    if HasText(panel.kindLabel) then Place(panel.kindLabel, 0, panel.card, CARD_PAD + 2) end
    Place(panel.stepTitle, HasText(panel.kindLabel) and 3 or 0, panel.card, CARD_PAD + 2)
    if HasText(panel.stepDetail) then Place(panel.stepDetail, 4, panel.card, CARD_PAD + 2) end
    if HasText(panel.badge) then Place(panel.badge, 6, panel.card, CARD_PAD + 2) end
    y = y - 8
    if panel.UpdateSkip then panel.UpdateSkip() end
    panel.skipButton:ClearAllPoints()
    panel.skipButton:SetPoint("TOPRIGHT", panel.card, "TOPRIGHT", -8, y)
    panel.laterButton:ClearAllPoints()
    if panel.skipButton:IsShown() then
        panel.laterButton:SetPoint("RIGHT", panel.skipButton, "LEFT", -4, 0)
    else
        panel.laterButton:SetPoint("TOPRIGHT", panel.card, "TOPRIGHT", -8, y)
    end
    panel.backButton:ClearAllPoints()
    panel.backButton:SetPoint("RIGHT", panel.laterButton, "LEFT", -4, 0)
    y = y - 20
    local cardH = -y + 9
    panel.card:SetHeight(cardH)
    y = cardTop - cardH

    if HasText(panel.nextText) then Place(panel.nextText, 5) end

    y = y - 14

    -- Scrollbereich
    local top = y
    local height = (Levelmate_DB and Levelmate_DB.panelHeight) or DEFAULT_HEIGHT
    -- Ganz klein gezogen: nur die Karte, ohne "Naechste Schritte"/Questlog
    local collapsed = Levelmate_DB and Levelmate_DB.panelCollapsed
    if collapsed then
        height = -top + 2
        scroll:Hide(); slider:Hide()
    else
        scroll:Show()
        if height < -top + 60 then height = -top + 60 end
    end
    panel:SetHeight(height)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, top)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 14)
    slider:ClearAllPoints()
    slider:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -9, top)
    slider:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -9, 14)

    y = -6
    local cdb = CharDB()
    local function ShowHeader(fs, on)
        if on then fs:Show(); fs.toggle:Show(); fs.line:Show() else fs:Hide(); fs.toggle:Hide(); fs.line:Hide() end
    end
    local previewOpen = not cdb.previewHidden
    if cdb.previewHidden or HasText(panel.previewText) then
        ShowHeader(panel.previewTitle, true)
        panel.previewTitle:SetText(HeaderText(L("Nächste Schritte"), previewOpen))
        Place(panel.previewTitle, 0, content)
        if previewOpen and HasText(panel.previewText) then
            panel.previewText:Show()
            Place(panel.previewText, 4, content)
        else
            panel.previewText:Hide()
        end
        y = y - 14
    else
        ShowHeader(panel.previewTitle, false); panel.previewText:Hide()
    end
    local questOpen = not cdb.questHidden
    panel.questTitle:SetText(HeaderText(L("Questlog"), questOpen))
    Place(panel.questTitle, 0, content)
    if questOpen then
        panel.questText:Show()
        Place(panel.questText, 4, content)
    else
        panel.questText:Hide()
    end
    if HasText(panel.xpText) then Place(panel.xpText, 8, content) end
    if collapsed then return end
    local contentH = -y + 4
    content:SetHeight(contentH)
    local visible = height + top - 14
    local maxScroll = math.max(0, contentH - visible)
    slider:SetMinMaxValues(0, maxScroll)
    if slider:GetValue() > maxScroll then slider:SetValue(maxScroll) end
    if maxScroll > 0 then slider:Show() else slider:Hide() end
end

-- Ecke unten rechts: Fensterhoehe ziehen
panel:SetResizable(true)
if panel.SetResizeBounds then
    pcall(panel.SetResizeBounds, panel, WIDTH, 100, WIDTH, 1000)
elseif panel.SetMinResize then
    pcall(panel.SetMinResize, panel, WIDTH, 100); pcall(panel.SetMaxResize, panel, WIDTH, 1000)
end
local grip = CreateFrame("Button", nil, panel)
grip:SetSize(14, 14)
grip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnMouseDown", function()
    -- eingeklappt: beim Ziehen wieder Platz fuer den Scrollbereich lassen
    panel.cardBottom = panel:GetHeight()
    panel:StartSizing("BOTTOM")
end)
grip:SetScript("OnMouseUp", function()
    panel:StopMovingOrSizing()
    local h = math.floor(panel:GetHeight() + 0.5)
    -- Unter die Karte (+ ca. 2 Zeilen) gezogen -> nur die Karte zeigen
    local cardOnly = scroll:IsShown() and (panel:GetTop() and scroll:GetTop()) and (panel:GetTop() - scroll:GetTop()) or nil
    local limit = (cardOnly or (panel.cardBottom or h)) + 40
    if Levelmate_DB.panelCollapsed then
        -- eingeklappt: nur wieder aufklappen, wenn deutlich groesser gezogen
        if h > (panel.cardBottom or h) + 30 then Levelmate_DB.panelCollapsed = nil end
    elseif h < limit then
        Levelmate_DB.panelCollapsed = true
    end
    Levelmate_DB.panelHeight = h
    -- StartSizing kann den Anker veraendern -> Position neu speichern
    local point, _, rel, x, y = panel:GetPoint()
    Levelmate_DB.panelPos = { point, rel, x, y }
    Layout()
end)

local function AnchorPanel()
    panel:ClearAllPoints()
    local p = Levelmate_DB and Levelmate_DB.panelPos
    if p then
        panel:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4])
    elseif ObjectiveTrackerFrame and ObjectiveTrackerFrame.GetPoint then
        panel:SetPoint("TOPRIGHT", ObjectiveTrackerFrame, "TOPLEFT", -12, 0)
    else
        panel:SetPoint("CENTER", UIParent, "CENTER", -260, 0)
    end
end

---------------------------------------------------------------------------
-- Startdialog: Modus waehlen
---------------------------------------------------------------------------
local dialog = CreateFrame("Frame", "LevelmateModeDialog", UIParent, "BackdropTemplate")
dialog:SetSize(360, 310)
dialog:SetPoint("CENTER")
dialog:SetFrameStrata("DIALOG")
dialog:SetBackdrop(panel:GetBackdrop())
dialog:SetBackdropColor(0.025, 0.035, 0.055, 0.97)
dialog:EnableMouse(true)
dialog:Hide()
local dTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dTitle:SetPoint("TOP", 0, -14)
dTitle:SetText("Wie möchtest du leveln?")
local dText = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
dText:SetPoint("TOP", dTitle, "BOTTOM", 0, -6)
dText:SetWidth(330)
dText:SetText("Du kannst den Modus jederzeit oben im Fenster ändern.")

local MODE_INFO = {
    { key = "quests",   text = "Nur Quests",        desc = "Solo questen. Dungeon- und Elitequests werden ausgelassen." },
    { key = "dungeons", text = "Quests + Dungeons", desc = "Mit Dungeonquests und deren Vorquests." },
    { key = "story",    text = "Story + Dungeons",  desc = "Slow-Leveling: Die Geschichte zählt, nicht das Tempo. Questreihen bis zum Ende, Dungeons als Finale, kaum Füllquests." },
}

local function SetMode(key)
    CharDB().mode = key
    dialog:Hide()
    panel:Show()
    Print(L("Modus: ") .. L(Levelmate.Planner.MODES[key].label))
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
end

local prev
for i, m in ipairs(MODE_INFO) do
    local b = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    b:SetSize(150, 24)
    if prev then b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -30) else b:SetPoint("TOPLEFT", dialog, "TOPLEFT", 16, -64) end
    b:SetText(m.text)
    b:SetScript("OnClick", function() SetMode(m.key) end)
    local d = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("LEFT", b, "RIGHT", 8, 0)
    d:SetWidth(180)
    d:SetJustifyH("LEFT")
    d:SetText(m.desc)
    m.button, m.descFS = b, d
    prev = b
end
-- Texte erst beim Anzeigen setzen (dann ist die gewaehlte Sprache bekannt)
dialog:SetScript("OnShow", function()
    dTitle:SetText(L("Wie möchtest du leveln?"))
    dText:SetText(L("Du kannst den Modus jederzeit oben im Fenster ändern."))
    for _, m in ipairs(MODE_INFO) do
        if m.button then m.button:SetText(L(m.text)) end
        if m.descFS then m.descFS:SetText(L(m.desc)) end
    end
end)

local function ShowModeDialog() dialog:Show() end

-- Story-Modus: graue Questreihe zu Ende spielen oder ueberspringen?
local greyAsked = {}
if StaticPopupDialogs then
    StaticPopupDialogs["LEVELMATE_GREY_STORY"] = {
        text = L("Levelmate: Die Geschichte „%s“ ist für deine Stufe grau geworden (kaum noch Erfahrung).\n\nWillst du sie trotzdem zu Ende spielen?"),
        button1 = L("Zu Ende spielen"),
        button2 = L("Überspringen"),
        OnAccept = function(_, root)
            Levelmate.Planner.SetGreyChoice(root, "finish")
            Print(L("Die Geschichte wird zu Ende gespielt."))
            Levelmate.Refresh()
        end,
        OnCancel = function(_, root, reason)
            if reason == "clicked" then
                Levelmate.Planner.SetGreyChoice(root, "skip")
                Print(L("Die graue Geschichte wird übersprungen. Ihre Quests kannst du abbrechen, wenn das Log voll wird."))
                Levelmate.Refresh()
            end
        end,
        timeout = 0, whileDead = true, hideOnEscape = false, preferredIndex = 3,
    }
end
Levelmate.ShowModeDialog = ShowModeDialog

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------
local Q = Levelmate.Quests
local currentAction
local RenderPreview

local function QuestName(c)
    if c.live then return c.live.title end
    return c.q.name or (L("Quest ") .. c.q.id)
end

local function Coord(p)
    if not p then return "" end
    return string.format("(%.1f, %.1f)", p.x, p.y)
end

local function FirstOpenObjective(c)
    if c.live then
        for _, o in ipairs(c.live.objectives) do if not o.done then return Levelmate.Quests.ShowText(o) end end
    end
    local t = c.a and c.a.targets[1]
    if t then
        local what = t.name or "?"
        if t.kind == "item" and t.source then what = what .. L(" (von ") .. t.source .. ")" end
        return string.format("%dx %s", t.need or 1, what)
    end
    return nil
end

local ShortAction
local CLASS_TAG = L(" |cffb070ff(Klassenquest)|r")
local DescribeActionRaw
local function XPText(act)
    local c = act and act.c
    return string.format(L("≈%d XP%s · geschätzt ~%d XP/min"), math.floor((c and c.xp) or act.value or 0),
        (c and c.q and c.q.xpSource == "geschätzt" and not c.live) and L(" (XP geschätzt)") or "",
        math.floor((c and c.xpPerMin) or act.xpPerMin or 0))
end
-- keepXP: XP-Angabe im Text lassen (Minimap-Tooltip). Im Fenster steht sie
-- stattdessen in der Bewertungszeile der Karte.
local function DescribeAction(act, keepXP)
    local title, detail = DescribeActionRaw(act)
    if detail and detail:find("{XP}", 1, true) then
        if keepXP then
            local x = XPText(act)
            detail = detail:gsub("{XP}", function() return x end)
        else
            detail = detail:gsub(" · {XP}", ""):gsub("\n{XP}", ""):gsub("{XP}", "")
        end
    end
    if act and act.danger and detail then
        detail = detail .. string.format(L("\n|cffff4040Achtung: Gebiet ca. Stufe %d – unterwegs gefährlich.|r"), act.danger)
    end
    if act and act.c and act.c.classQuest and act.kind ~= "FLY" and title ~= "" then
        title = "|cffb070ff" .. title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") .. "|r"
        detail = L("|cffb070ffKlassenquest|r · ") .. (detail or "")
    end
    return title, detail
end
function DescribeActionRaw(act)
    if not act then return "", "" end
    local c = act.c
    local xp = "{XP}"   -- Platzhalter, siehe DescribeAction
    if act.kind == "ACCEPT" then
        local shared = c.sharedTrip and c.destMap
            and (L("\n|cffaaaaaaMitnehmen: führt auch nach ") .. Levelmate.Planner.MapName(c.destMap) .. "|r") or ""
        if act.dungeonPickup then
            shared = shared .. L("\n|cffff8040Für den Dungeon ") .. act.dungeonPickup .. L(" – vorher annehmen, dann nur einmal rein.|r")
        end
        return L("|cffffd100Annehmen:|r ") .. QuestName(c) .. (c.a.optional and L(" |cffaaaaaa(optional)|r") or ""),
            string.format(L("bei %s %s\n%s%s"), act.targetName or "?", Coord(act.target), xp, shared)
    elseif act.kind == "TURNIN" then
        if act.clientWaypoint then
            return L("|cff00ff00Abgeben:|r ") .. QuestName(c),
                string.format("%s %s\n%s", act.targetName or "?", Coord(act.target), xp)
        end
        return L("|cff00ff00Abgeben:|r ") .. QuestName(c),
            string.format(L("bei %s %s\n%s"), act.targetName or "?", Coord(act.target), xp)
    elseif act.kind == "DO" and act.obj and act.obj.kind == "escort" then
        return L("|cff66ccffBegleiten:|r ") .. QuestName(c) .. L(" |cffaaaaaa(optional)|r"),
            string.format(L("Starten bei %s %s\n%s\nIst der NPC nicht da (andere Spieler eskortieren ihn): \"Überspringen\"."),
                act.targetName or "?", Coord(act.target), act.obj.name or "")
    elseif act.kind == "DO" and act.obj and act.obj.kind == "explore" then
        return L("|cff66ccffErkunden:|r ") .. QuestName(c),
            string.format(L("Zielort %s\n%s"), Coord(act.target), act.obj.name or "")
    elseif act.kind == "DO" and act.key then
        return L("|cff66ccffSchlüssel holen:|r ") .. (act.obj.name or "?"),
            string.format(L("von %s %s\nwird gebraucht für \"%s\" (erst holen, dann öffnen/befreien)"),
                act.obj.source or act.targetName or "?", Coord(act.target), QuestName(c))
    elseif act.kind == "DO" and act.buy == "ah" then
        local where = act.targetName and string.format(L("Auktionator %s %s"), act.targetName, Coord(act.target)) or L("Auktionshaus")
        return L("|cffffd100Besorgen:|r ") .. (act.obj.name or "?"),
            string.format(L("im %s kaufen, bei einem Händler suchen oder selbst herstellen\nfür \"%s\" (dafür ca. 5 min eingeplant)"),
                where, QuestName(c))
    elseif act.kind == "DO" and act.obj and act.obj.buy == "vendor" then
        return L("|cffffd100Kaufen:|r ") .. (act.obj.name or "?"),
            string.format(L("bei %s %s\nfür \"%s\""), act.obj.source or act.targetName or L("Händler"), Coord(act.target), QuestName(c))
    elseif act.kind == "DO" and act.trade then
        return L("|cffffd100Tauschen:|r ") .. (act.obj.name or "?"),
            string.format(L("bei %s %s für \"%s\"\nDafür brauchst du einen Gegenstand (Tausch/Beruf/Auktionshaus).\nWillst du das nicht: \"Überspringen\" drücken."),
                act.targetName or "?", Coord(act.target), QuestName(c))
    elseif act.kind == "DO" then
        local obj
        if act.liveObj and act.liveObj.text then
            obj = Levelmate.Quests.ShowText(act.liveObj)
        elseif act.obj then
            local t = act.obj
            obj = string.format("%dx %s", t.need or 1, t.name or "?")
            if t.kind == "item" and t.source then obj = obj .. L(" (von ") .. t.source .. ")" end
        end
        obj = obj or FirstOpenObjective(c) or L("Questziele erledigen")
        return L("|cff66ccffErledigen:|r ") .. QuestName(c),
            string.format(L("%s\nbei %s %s · %s"), obj, act.targetName or "?", Coord(act.target), xp)
    elseif act.kind == "FLY" then
        local dest = Levelmate.Travel.PlaceName(act.to)
        local nxt = act.next and ShortAction(act.next) or ""
        local hint = Levelmate.Travel.Captured() and "" or L("\n|cffaaaaaa(Deine Flugpunkte sind noch nicht erfasst – öffne einmal die Flugkarte.)|r")
        if act.atFP then
            return L("|cff40c0ffFliegen:|r nach ") .. dest,
                string.format(L("Flugmeister %s ansprechen\nDort: %s%s"), act.from.name, nxt, hint)
        end
        local here = Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
        local fromPlace = Levelmate.Travel.PlaceName(act.from)
        if here and act.from.point and here.map == act.from.point.map then
            return L("|cff40c0ffFliegen:|r nach ") .. dest,
                string.format(L("Erst hier zum Flugmeister %s %s laufen\nDort: %s%s"),
                    act.from.name, Coord(act.from.point), nxt, hint)
        end
        return L("|cff40c0ffFliegen:|r nach ") .. dest,
            string.format(L("Abflug in %s: Flugmeister %s %s\nDort: %s%s"),
                fromPlace, act.from.name, Coord(act.from.point), nxt, hint)
    elseif act.kind == "SHIP" then
        local l = act.leg
        local nxt = act.next and ShortAction(act.next) or ""
        if act.atDock then
            local den = (l.kind == "Tiefenbahn") and L("die") or L("den")
            return "|cff40c0ff" .. (L(l.kind):gsub("^%l", string.upper)) .. L(":|r nach ") .. l.toName,
                string.format(L("Hier auf %s %s nach %s warten (fährt alle paar Minuten)\nDort: %s"), den, L(l.kind), l.toName, nxt)
        end
        local art = (l.kind == "Tiefenbahn") and L("Zur ") or L("Zum ")
        return "|cff40c0ff" .. art .. L(l.kind) .. ":|r " .. l.fromName .. " > " .. l.toName,
            string.format(L("%s %s · %s nach %s (ca. %d min mit Warten)\nDort: %s"),
                l.master or "?", Coord(l.from), L(l.kind), l.toName, math.floor((l.seconds or 300) / 60 + 0.5), nxt)
    elseif act.kind == "HEARTH" then
        local nxt = act.next and ShortAction(act.next) or ""
        return L("|cff40c0ffRuhestein:|r nach ") .. Levelmate.Travel.HearthName(),
            string.format(L("Ruhestein benutzen (spart ca. %d min)%s\nDort: %s"),
                math.floor((act.saves or 0) / 60 + 0.5),
                Levelmate.Travel.HearthGuessed() and L(" |cffaaaaaa(Ort geschätzt)|r") or "", nxt)
    elseif act.kind == "ABANDON" then
        return L("|cffff6060Abbrechen:|r ") .. QuestName(c),
            L("Dein Questlog ist fast voll und diese Quest lohnt sich nicht mehr (") .. Levelmate.LT(c.skipReason or "") .. L(").\nQuestlog öffnen (L) > Quest auswählen > Abbrechen.")
    elseif act.kind == "DUNGEON" then
        local names = {}
        for _, dc in ipairs(act.group.list) do table.insert(names, QuestName(dc)) end
        if act.atEntrance then
            return L("|cffff8040Jetzt rein:|r ") .. (act.group.name or "?"),
                string.format(L("Du stehst am Eingang. Quests im Dungeon:\n%s"), table.concat(names, ", "))
        end
        local more = ""
        if act.upcoming then
            local p = {}
            for _, q in ipairs(act.upcoming) do table.insert(p, q.name or "?") end
            more = string.format(L("\n|cffaaaaaaLohnt sich mehr ab Stufe %d – dann auch: %s|r"),
                act.upcomingLevel or 0, table.concat(p, ", "))
        end
        if act.pickups and #act.pickups > 0 then
            local p = {}
            for _, pa in ipairs(act.pickups) do table.insert(p, QuestName(pa.c)) end
            more = L("\n|cffffd100Vorher noch annehmen:|r ") .. table.concat(p, ", ")
        end
        if act.goNow then more = more .. L("\n|cff80ff80Von dir gewählt (Dungeon-Fenster).|r") end
        if act.storyFinale then
            local head = act.storyName and string.format(L("|cffb070ffDie Geschichte „%s“ geht weiter:|r "), act.storyName)
                or L("|cffb070ffDie Geschichte geht weiter:|r ")
            return head .. (act.group.name or "?"),
                string.format(L("%d Quests: %s\nEingang %s · Gruppe über die Dungeonsuche · %s%s"),
                    #names, table.concat(names, ", "), Coord(act.target), xp, more)
        end
        return L("|cffff8040Dungeon:|r ") .. (act.group.name or "?"),
            string.format(L("%d Quests: %s\nEingang %s · Gruppe über die Dungeonsuche · %s%s"),
                #names, table.concat(names, ", "), Coord(act.target), xp, more)
    end
    return "", ""
end

function ShortAction(act)
    if not act then return nil end
    if act.kind == "FLY" then return L("Fliegen: nach ") .. Levelmate.Travel.PlaceName(act.to) end
    if act.kind == "HEARTH" then return L("Ruhestein: nach ") .. Levelmate.Travel.HearthName() end
    if act.kind == "SHIP" then return (L(act.leg.kind):gsub("^%l", string.upper)) .. ": " .. act.leg.fromName .. " > " .. act.leg.toName end
    local kinds = { ACCEPT = L("Annehmen"), TURNIN = L("Abgeben"), DO = L("Erledigen"), DUNGEON = L("Dungeon"), ABANDON = L("Abbrechen") }
    local name = act.c and QuestName(act.c) or (act.group and act.group.name) or "?"
    if act.c and act.c.a and act.c.a.optional then name = name .. L(" (optional)") end
    if act.c and act.c.classQuest then name = name .. L(" (Klassenquest)") end
    if act.kind == "DO" and act.key then
        return L("Schlüssel holen: ") .. (act.obj.name or "?") .. " (" .. (act.c and QuestName(act.c) or "?") .. ")"
    end
    if act.kind == "DO" and act.trade then
        return L("Tauschen: ") .. (act.obj.name or "?") .. L(" bei ") .. (act.targetName or "?")
    end
    if act.kind == "DO" and act.buy == "ah" then
        return L("Besorgen: ") .. (act.obj.name or "?") .. L(" (kaufen/herstellen)")
    end
    if act.kind == "DO" and act.obj and act.obj.buy == "vendor" then
        return L("Kaufen: ") .. (act.obj.name or "?") .. L(" bei ") .. (act.obj.source or L("Händler"))
    end
    if act.kind == "DO" and act.obj and act.c and #act.c.a.targets > 1 and act.obj.name then
        name = name .. " (" .. act.obj.name .. ")"
    end
    return (kinds[act.kind] or act.kind) .. ": " .. name
end

local function RenderQuestLog(plan)
    local live = Q.GetList()
    if #live == 0 then return L("Keine Quests im Questlog.") end
    local lines = {}
    for i, lq in ipairs(live) do
        if i > 40 then break end
        local title = lq.title
        if lq.status == Q.STATUS_READY then title = "|cff00ff00" .. title .. "|r"
        elseif lq.status == Q.STATUS_FAILED then title = "|cffff4040" .. title .. "|r" end
        local note = ""
        local c = plan and plan.entries and plan.entries[lq.questID]
        if c and c.skipReason then
            note = " |cffff9933– " .. Levelmate.LT(c.skipReason) .. "|r"
        elseif lq.status == Q.STATUS_READY then
            note = " – " .. L(Q.Labels.READY)
        end
        table.insert(lines, Q.Icon(lq.status) .. " " .. QLink(lq.questID, title) .. note)
        if lq.status == Q.STATUS_ACTIVE then
            for j = 1, math.min(#lq.objectives, 3) do
                local o = lq.objectives[j]
                table.insert(lines, "     " .. (o.done and "|cff00ff00" or "|cffcccccc") .. Levelmate.Quests.ShowText(o) .. "|r")
            end
        end
    end
    return table.concat(lines, "\n")
end

-- Routenvorschau: nur neu berechnen, wenn sich der aktuelle Schritt aendert
-- oder alle 15 Sekunden (die Berechnung spielt mehrere Planungen durch).
local previewCache = { key = nil, time = 0, text = "" }
local KIND_COLOR = { HEARTH = "|cff40c0ff", SHIP = "|cff40c0ff", ACCEPT = "|cffffd100", TURNIN = "|cff00ff00", DO = "|cff66ccff",
    DUNGEON = "|cffff8040", FLY = "|cff40c0ff", ABANDON = "|cffff6060" }
local KIND_RGB = { HEARTH = { 0.25, 0.75, 1 }, SHIP = { 0.25, 0.75, 1 }, FLY = { 0.25, 0.75, 1 },
    ACCEPT = { 1, 0.82, 0 }, TURNIN = { 0, 1, 0 }, DO = { 0.4, 0.8, 1 }, DUNGEON = { 1, 0.5, 0.25 },
    ABANDON = { 1, 0.38, 0.38 }, CLASS = { 0.69, 0.44, 1 } }
local function RGBOf(act)
    if act and act.c and act.c.classQuest and act.kind ~= "FLY" then return KIND_RGB.CLASS end
    return (act and KIND_RGB[act.kind]) or { 0.6, 0.6, 0.6 }
end
local function Hex(rgb)
    return string.format("|cff%02x%02x%02x", math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
end
-- kleines farbiges Quadrat als Aufzaehlungspunkt
local function Dot(rgb)
    return string.format("|TInterface\\Buttons\\WHITE8X8:8:8:0:0:8:8:0:8:0:8:%d:%d:%d|t",
        math.floor(rgb[1] * 255), math.floor(rgb[2] * 255), math.floor(rgb[3] * 255))
end
local function StripColors(s)
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Bewertung des Schritts im Vergleich zu den anderen Quests, die gerade
-- zur Auswahl stehen (Median = "gut").
local medianCache = setmetatable({}, { __mode = "k" })
local function MedianRate(plan)
    if not plan or not plan.byId then return 0 end
    if medianCache[plan] then return medianCache[plan] end
    local r = {}
    for _, c in pairs(plan.byId) do
        if not c.skipReason and not c.isDungeon and c.xpPerMin and c.xpPerMin > 0 then r[#r + 1] = c.xpPerMin end
    end
    table.sort(r)
    local m = (#r >= 5) and r[math.ceil(#r / 2)] or 0
    medianCache[plan] = m
    return m
end
local function RatingText(act, plan)
    local c = act and act.c
    if not c or not c.xp or c.xp <= 0 or act.kind == "ABANDON" then return "" end
    local est = (c.q and c.q.xpSource == "geschätzt" and not c.live) and L(" (geschätzt)") or ""
    -- Abgeben lohnt sich immer - die Arbeit ist ja schon getan.
    if act.kind == "TURNIN" then return string.format(L("|cff40ff40Belohnung abholen|r  |cff888888·|r  ≈%d XP%s"), math.floor(c.xp), est) end
    local ref = MedianRate(plan)
    local rate = c.xpPerMin or 0
    local label = ""
    if ref > 0 and rate > 0 then
        local r = rate / ref
        if r >= 1.5 then label = L("|cff40ff40sehr gut|r")
        elseif r >= 0.9 then label = L("|cffa0e060gut|r")
        elseif r >= 0.5 then label = L("|cffffd100geht so|r")
        else label = L("|cffff8040lohnt kaum|r") end
        label = label .. "  |cff888888·|r  "
    end
    local mob = c.mobXP or 0
    if mob >= 50 then est = est .. string.format(L(" + ≈%d Gegner"), math.floor(mob / 10 + 0.5) * 10) end
    local mins = (rate > 0) and ((c.xp + mob) / rate) or nil
    if mins then
        return string.format(L("%s≈%d XP%s · ~%d min"), label, math.floor(c.xp), est, math.max(1, math.floor(mins + 0.5)))
    end
    return string.format(L("%s≈%d XP%s"), label, math.floor(c.xp), est)
end

-- Karte fuellen. act darf nil sein (Fehler, Dungeon, keine Quest).
local function SetCard(title, detail, act, plan, rgb, noSplit)
    local label, name = nil, title or ""
    if not noSplit then
        local plain = StripColors(name)
        local l, n = plain:match("^(.-):%s+(.*)$")
        if l and #l <= 22 then label, name = l, n end
    end
    rgb = rgb or (act and RGBOf(act)) or { 1, 0.82, 0 }
    if label then
        local where = ""
        if act and act.target and act.target.map and act.kind ~= "FLY" and act.kind ~= "HEARTH" and act.kind ~= "SHIP" then
            local mn = Levelmate.Planner.MapName(act.target.map)
            if mn and mn ~= "" and mn ~= "?" then where = "  |cff888888· " .. mn .. "|r" end
        end
        panel.kindLabel:SetText(Hex(rgb) .. label .. "|r" .. where)
        local nameColor = (act and act.c and act.c.classQuest and act.kind ~= "FLY") and Hex(KIND_RGB.CLASS) or "|cffffffff"
        local qid = act and act.c and act.c.q and act.c.q.id
        panel.stepTitle:SetText(nameColor .. QLink(qid, name) .. "|r")
    else
        panel.kindLabel:SetText("")
        panel.stepTitle:SetText(name)
    end
    panel.stepDetail:SetText(detail or "")
    panel.badge:SetText(act and RatingText(act, plan) or "")
    SolidColor(panel.cardAccent, rgb[1], rgb[2], rgb[3], 0.9)
end

-- Fortschrittsbalken: aktuelle XP und Zeit bis zur naechsten Stufe
-- Unverteilte Talentpunkte. WoW Forever laeuft auf einem neuen Client - je nach
-- Version gibt es UnitCharacterPoints nicht mehr. Darum mehrere Wege, zuletzt
-- selbst zaehlen: (Stufe - 9) minus aller vergebenen Talentraenge.
-- Neues Talentsystem (C_ClassTalents / C_Traits), wie es moderne Clients nutzen.
local function TraitPoints()
    local CT, TR = C_ClassTalents, C_Traits
    if CT and CT.HasUnspentTalentPoints then
        local ok, has, a, b = pcall(CT.HasUnspentTalentPoints)
        if ok then
            local n = (tonumber(a) or 0) + (tonumber(b) or 0)
            if n > 0 then return n end
            if has == true then return 1 end
        end
    end
    if CT and CT.GetActiveConfigID and TR and TR.GetConfigInfo and TR.GetTreeCurrencyInfo then
        local ok, configID = pcall(CT.GetActiveConfigID)
        if ok and configID then
            local okI, info = pcall(TR.GetConfigInfo, configID)
            local sum = 0
            for _, treeID in ipairs(okI and info and info.treeIDs or {}) do
                local okC, cur = pcall(TR.GetTreeCurrencyInfo, configID, treeID, false)
                for _, c in ipairs(okC and cur or {}) do sum = sum + (tonumber(c.quantity) or 0) end
            end
            if sum > 0 then return sum end
        end
    end
    return 0
end

local function UnspentTalentPoints()
    local tp = TraitPoints()
    if tp > 0 then return tp end
    if UnitCharacterPoints then
        local ok, p = pcall(UnitCharacterPoints, "player")
        if ok and tonumber(p) and tonumber(p) > 0 then return tonumber(p) end
    end
    if GetUnspentTalentPoints then
        local ok, p = pcall(GetUnspentTalentPoints)
        if ok and tonumber(p) and tonumber(p) > 0 then return tonumber(p) end
    end
    local level = UnitLevel("player") or 1
    if level < 10 or not (GetNumTalentTabs and GetNumTalents and GetTalentInfo) then return 0 end
    local okTabs, tabs = pcall(GetNumTalentTabs)
    if not okTabs or not tonumber(tabs) or tabs < 1 then return 0 end
    local spent, seen = 0, false
    for t = 1, tabs do
        local okN, n = pcall(GetNumTalents, t)
        for i = 1, (okN and tonumber(n) or 0) do
            local ok, _, _, _, _, rank = pcall(GetTalentInfo, t, i)
            if ok and tonumber(rank) then spent = spent + rank; seen = true end
        end
    end
    if not seen then return 0 end
    return math.max(0, (level - 9) - spent)
end
Levelmate.UnspentTalentPoints = UnspentTalentPoints

local function TalentNote()
    local pts = UnspentTalentPoints()
    if pts > 0 then
        return string.format("  |cff7fd67f+%d %s|r", pts, pts == 1 and L("Talentpunkt") or L("Talentpunkte"))
    end
    return ""
end
local function UpdateBar(plan)
    local level = UnitLevel("player") or 1
    local xp = UnitXP and UnitXP("player") or 0
    local max = UnitXPMax and UnitXPMax("player") or 0
    if level >= 60 or max <= 0 then
        panel.bar:SetMinMaxValues(0, 1); panel.bar:SetValue(1)
        panel.barLeft:SetText(string.format(L("Stufe |cfff2c14e%d|r"), level) .. TalentNote())
        panel.barRight:SetText("")
        return
    end
    panel.bar:SetMinMaxValues(0, max)
    panel.bar:SetValue(xp)
    local rest = max - xp
    local pace = Levelmate.Smart.Pace and Levelmate.Smart.Pace()
    local rate = pace or (plan and plan.referenceXPPerMin) or 0
    if rate and rate > 0 then
        local mins = rest / rate
        local t = mins >= 90 and (Levelmate.Language() == "de" and (string.format("~%.1f h", mins / 60):gsub("%.", ",")) or string.format("~%.1f h", mins / 60)) or string.format(L("~%d min"), math.max(1, math.floor(mins + 0.5)))
        panel.barLeft:SetText(string.format(L("Stufe |cfff2c14e%d|r"), level) .. TalentNote())
        panel.barRight:SetText(string.format(L("noch %s bis %d"), t, level + 1))
    else
        panel.barLeft:SetText(string.format(L("Stufe |cfff2c14e%d|r"), level) .. TalentNote())
        panel.barRight:SetText(string.format(L("noch %d XP bis %d"), rest, level + 1))
    end
end

-- Gebietszeile: bis zu 3 empfohlene Gebiete, das aktuelle hervorgehoben
local function ZoneLine(plan)
    local zp = Levelmate.Planner.ZonePlan(5)
    local cur = plan and plan.zone
    if not zp or #zp == 0 then
        return cur and (L("|cff888888Gebiet:|r |cffffd100") .. (cur.name or "–") .. "|r") or ""
    end
    local parts = {}
    for i = 1, math.min(3, #zp) do
        local z = zp[i]
        local txt = string.format("%d–%d %s", z.lo, z.hi, z.name or "?")
        if cur and z.map == cur.map then
            table.insert(parts, "|cffffd100" .. txt .. "|r")
        else
            table.insert(parts, "|cff9a9a9a" .. txt .. "|r")
        end
    end
    return table.concat(parts, "  |cff666666›|r  ")
end

-- Ruhige Vorschau: Die berechnete Reihenfolge bleibt stehen. Ist der aktuelle
-- Schritt ein Eintrag weiter unten (z. B. nach einer Abgabe), wird die Liste
-- nur nachgerueckt statt neu berechnet. Neu berechnet wird hoechstens alle 30 s
-- oder wenn der aktuelle Schritt gar nicht in der Liste steht - und dann im
-- Hintergrund in kleinen Portionen, damit das Spiel nicht ruckelt.
local previewRoute = { list = nil, mode = nil, time = -1000, busy = false }
function Levelmate.InvalidatePreview() previewRoute.time = -1000 end
local function PreviewLines(list, from)
    local lines = {}
    if not list or not list[from] then return "" end
    -- Der aktuelle Schritt steht schon in der Karte -> Liste beginnt danach.
    local startLevel, base = list[from].level, (from > 1) and list[from - 1].seconds or 0
    for i = from + 1, #list do
        local e = list[i]
        local txt = ShortAction(e.act) or "?"
        if e.act and e.act.c and e.act.c.q then txt = QLink(e.act.c.q.id, txt) end
        local rgb = RGBOf(e.act)
        local zone = e.zone and (" |cff888888· " .. e.zone .. "|r") or ""
        local lvl = (e.level ~= startLevel) and (L(" |cffffff00[Stufe ") .. e.level .. "]|r") or ""
        local when = string.format(L(" |cff888888(~%d min)|r"), math.max(1, math.floor((e.seconds - base) / 60 + 0.5)))
        table.insert(lines, string.format("%s |cffe6e6e6%s|r%s%s%s", Dot(rgb), txt, zone, lvl, when))
    end
    if #lines == 0 then return L("|cff888888Danach wird neu geplant.|r") end
    return table.concat(lines, "\n")
end
RenderPreview = function(mode, current)
    local now = GetTime and GetTime() or 0
    local key = Levelmate.Planner.ActionKey and Levelmate.Planner.ActionKey(current) or tostring(current.kind)
    local from
    if previewRoute.list and previewRoute.mode == mode then
        for i, e in ipairs(previewRoute.list) do
            if Levelmate.Planner.ActionKey(e.act) == key then from = i; break end
        end
    end
    local stale = (not from) or (now - previewRoute.time > 60)
    if stale and not previewRoute.busy then
        previewRoute.busy = true
        local started = now
        local function Done(list)
            previewRoute.busy = false
            if list then previewRoute.list, previewRoute.mode, previewRoute.time = list, mode, started end
            if panel:IsShown() and currentAction and not CharDB().previewHidden then
                local k = Levelmate.Planner.ActionKey(currentAction)
                local f
                for i, e in ipairs(previewRoute.list or {}) do
                    if Levelmate.Planner.ActionKey(e.act) == k then f = i; break end
                end
                if f then
                    panel.previewText:SetText(PreviewLines(previewRoute.list, f)); Layout()
                end
            end
        end
        if Levelmate.Planner.PreviewAsync then Levelmate.Planner.PreviewAsync(mode, 10, Done)
        else Done(Levelmate.Planner.Preview(mode, 10)) end
        -- synchron fertig geworden (z. B. ohne C_Timer)? Dann neu suchen.
        if previewRoute.list and previewRoute.mode == mode and not from then
            for i, e in ipairs(previewRoute.list) do
                if Levelmate.Planner.ActionKey(e.act) == key then from = i; break end
            end
        end
    end
    if from then
        previewCache.text = PreviewLines(previewRoute.list, from)
        return previewCache.text
    end
    -- Noch keine passende Liste: Rest folgt gleich.
    return L("|cff888888Reihenfolge wird berechnet …|r")
end

-- Hinweis im Chat, sobald eine neue Klassenquest verfuegbar ist (einmal je Quest)
local function AnnounceClassQuests(plan)
    if not Levelmate.Planner.ClassQuestsOn() or (Levelmate_DB and Levelmate_DB.classNotify == false) then return end
    if not Levelmate.Planner.poolReady then return end
    local seen = CharDB()
    seen.seenClassQuests = seen.seenClassQuests or {}
    seen = seen.seenClassQuests
    -- Nur melden, was auch wirklich in der Route steht - mit Ort und Schritt,
    -- damit klar ist, wann Levelmate die Quest einplant.
    local stepOf = {}
    for i, act in ipairs(plan.actions or {}) do
        if act.kind == "ACCEPT" and act.c and not stepOf[act.c] then stepOf[act.c] = { i = i, act = act } end
    end
    local new = {}
    for id, c in pairs(plan.byId or {}) do
        local st = stepOf[c]
        if c.classQuest and not c.live and not c.skipReason and not seen[id] and st then
            seen[id] = true
            local zone = st.act.target and Levelmate.Planner.MapName(st.act.target.map)
            local when = st.i == 1 and L("als Nächstes") or string.format(L("Schritt %d der Route"), st.i)
            table.insert(new, (c.q.name or (L("Quest ") .. id)) .. " (" .. (zone and (zone .. ", ") or "") .. when .. ")")
        end
    end
    if #new > 0 then
        table.sort(new)
        Print(L("|cffb070ffNeue Klassenquest verfügbar:|r ") .. table.concat(new, ", ", 1, math.min(#new, 4))
            .. (#new > 4 and string.format(L(" (+%d weitere)"), #new - 4) or ""))
        if PlaySound and SOUNDKIT and SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01 then
            pcall(PlaySound, SOUNDKIT.UI_QUEST_ROLLING_FORWARD_01)
        end
    end
end

local RefreshInner
local refreshWhy
local function Refresh()
    local t0 = debugprofilestop and debugprofilestop()
    RefreshInner()
    if t0 then Levelmate.Perf.Add("refresh", debugprofilestop() - t0, refreshWhy or L("Zeit/Bewegung"), Levelmate.Planner.lastSections) end
    refreshWhy = nil
end
function Levelmate.SetRefreshReason(why) refreshWhy = why end
RefreshInner = function()
    do
        local p = Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
        Levelmate._lastPlanAt = { wx = p and p.wx, wy = p and p.wy, cont = p and p.cont, t = GetTime and GetTime() or 0 }
    end
    -- Waehrend eines Fluges nicht umplanen (Zwischenlandungen wuerden die Route verwirren)
    if UnitOnTaxi and UnitOnTaxi("player") then
        if not panel.onTaxi then
            panel.onTaxi = true
            panel.nextText:SetText(L("|cff40c0ffIm Flug – Route wird nach der Landung fortgesetzt.|r"))
            Layout()
        end
        return
    end
    panel.onTaxi = false
    local inInstance, instanceType = false, nil
    if IsInInstance then inInstance, instanceType = IsInInstance() end
    if inInstance and (instanceType == "party" or instanceType == "raid") then
        Q.Rebuild()
        local name = GetInstanceInfo and GetInstanceInfo() or L("Dungeon")
        -- Welche Quests gehoeren zu dieser Instanz?
        -- 1) QuestieDB: Dungeon der Quest passt zur aktuellen Karte oder zum Namen
        -- 2) Das Spiel (C_QuestLog.IsOnMap) - aber nur, wenn es wirklich eine
        --    Auswahl trifft (Forever meldet in manchen Instanzen einfach alle).
        local curMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local list = Q.GetList() or {}
        local instanceID = GetInstanceInfo and select(8, GetInstanceInfo())
        local instArea = Levelmate.DB.InstanceArea and Levelmate.DB.InstanceArea(instanceID)
        -- "Jetzt hin" aus dem Dungeon-Fenster ist erledigt, sobald du drin bist
        local go = CharDB().dungeonGo
        if go and instArea and Levelmate.DB.SameDungeon(go.area, instArea) then CharDB().dungeonGo = nil end
        local function Matches(area)
            if not area then return false end
            if instArea then return Levelmate.DB.SameDungeon(area, instArea) end
            if curMap and Levelmate.DB.AreaToUiMap(area) == curMap then return true end
            local dname = Levelmate.DB.Dungeon(area)
            return dname ~= nil and dname == name
        end
        local picked = {}
        for _, lq in ipairs(list) do
            local qd = Levelmate.DB.Quest(lq.questID)
            local a = qd and Levelmate.Planner.Analyze and Levelmate.Planner.Analyze(qd)
            if a then
                local hit = Matches(a.dungeonArea)
                for _, t in ipairs(a.targets or {}) do
                    if hit then break end
                    hit = Matches(t.dungeonArea)
                end
                if hit then picked[lq.questID] = true end
            end
        end
        if not next(picked) and C_QuestLog and C_QuestLog.IsOnMap then
            local onMap, total = {}, 0
            for _, lq in ipairs(list) do
                local ok, on = pcall(C_QuestLog.IsOnMap, lq.questID)
                if ok and on then onMap[lq.questID] = true; total = total + 1 end
            end
            -- Nur verwenden, wenn hoechstens die Haelfte deiner Quests gemeldet wird.
            -- (In Forever-Instanzen meldet das Spiel oft fast alle Quests.)
            if total > 0 and total <= #list / 2 then picked = onMap end
        end
        local lines = {}
        for _, lq in ipairs(list) do
            if picked[lq.questID] then
                local open = {}
                for _, o in ipairs(lq.objectives or {}) do
                    if not o.done then table.insert(open, Levelmate.Quests.ShowText(o)) end
                end
                local status = (lq.status == Q.STATUS_READY) and L("|cff00ff00abgabebereit|r")
                    or (#open > 0 and table.concat(open, ", ") or "")
                table.insert(lines, "• " .. lq.title .. (status ~= "" and (" – " .. status) or ""))
            end
        end
        local unknown = false
        local todo = #lines > 0 and table.concat(lines, "\n") or L("Für diese Instanz sind keine Quests aus deinem Questlog bekannt.")
        SetCard(L("|cffff8040Im Dungeon:|r ") .. tostring(name), #lines > 0 and (unknown
            and string.format(L("%d offene Quests – siehe unten"), #lines)
            or string.format(L("%d Quests für diesen Dungeon – siehe unten"), #lines)) or todo,
            nil, nil, KIND_RGB.DUNGEON)
        panel.nextText:SetText(L("Die Route geht nach dem Dungeon weiter."))
        -- Unter "Als Nächstes": was im Dungeon zu erledigen ist
        -- Danach: die Route, wie sie vor dem Betreten zuletzt angezeigt wurde
        local after = previewCache and previewCache.text or ""
        panel.previewText:SetText(L("|cffff8040Im Dungeon erledigen:|r\n") .. todo
            .. (after ~= "" and (L("\n\n|cffaaaaaaDanach (Route von vorher):|r\n") .. after) or ""))
        panel.questText:SetText(RenderQuestLog(Levelmate.Planner.Last and Levelmate.Planner.Last()))
        Levelmate.Arrow.SetTarget(nil)
        Layout()
        return
    end
    local cdb = CharDB()
    local mode = cdb.mode or "quests"
    local className = UnitClass("player")
    local raceName = UnitRace("player")
    local faction = UnitFactionGroup("player")
    local factionDE = faction == "Alliance" and L("Allianz") or faction == "Horde" and "Horde" or (faction or "?")

    panel.modeButton:SetText(L(Levelmate.Planner.MODES[mode].label))
    do
        local dm = Levelmate.Planner.MODES[mode] and Levelmate.Planner.MODES[mode].dungeons
        panel.dungeonButton:SetShown(dm and true or false)
        if not dm then dframe:Hide() end
        panel.learnButton:ClearAllPoints()
        panel.learnButton:SetPoint("RIGHT", dm and panel.dungeonButton or panel.arrowButton, "LEFT", -6, 0)
    end
    panel.skipButton:SetText(L("Überspringen"))
    panel.laterButton:SetText(L("Später"))
    SetIconActive(panel.arrowButton, not (Levelmate_DB and Levelmate_DB.arrowHidden))
    do
        local n = (Levelmate.Trainer and Levelmate.Trainer.Learnable) and Levelmate.Trainer.Learnable() or 0
        if n and n > 0 then
            panel.learnButton.count:SetText(n)
            panel.learnButton:Show()
        else
            panel.learnButton:Hide()
        end
    end

    Q.Rebuild()
    local plan = Levelmate.Planner.Plan(mode)
    if not plan.error then AnnounceClassQuests(plan) end
    if Levelmate.UpdateDungeonFrame then pcall(Levelmate.UpdateDungeonFrame) end
    -- Story-Modus: Reihe ist grau geworden -> einmal fragen
    local ask = not plan.error and plan.greyChainAsk
    if ask and StaticPopup_Show and not greyAsked[ask.root] then
        greyAsked[ask.root] = true
        StaticPopup_Show("LEVELMATE_GREY_STORY", ask.name or "?", nil, ask.root)
    end

    UpdateBar(not plan.error and plan or nil)
    if plan.error then
        panel.zone:SetText(Levelmate.DB.Available() and "" or (L("Gebietshinweis: ") .. (Levelmate.Routes and Levelmate.Routes.GetHint(faction, UnitLevel("player") or 1) or "")))
        SetCard(plan.error, "", nil, nil, { 1, 0.38, 0.38 }, true)
        panel.previewText:SetText("")
        panel.nextText:SetText("")
        currentAction = nil
        Levelmate.Arrow.SetTarget(nil)
    else
        panel.zone:SetText(ZoneLine(plan))
        local act = plan.actions[1]
        currentAction = act
        if act and Levelmate.Journal and Levelmate.Journal.Step and Levelmate.Planner.ActionKey then
            pcall(Levelmate.Journal.Step, act, Levelmate.Planner.ActionKey(act))
        end
        local train = Levelmate.Trainer and Levelmate.Trainer.Suggest and Levelmate.Trainer.Suggest()
        if train then
            -- Lehrer in der Naehe: kurz hin, danach geht die Route weiter
            currentAction = train
            SetCard(L("Lehrer: ") .. (train.targetName or "?"), Levelmate.Trainer.Detail(train), nil, nil, { 0.95, 0.76, 0.31 })
            local nxt = act and ShortAction(act)
            panel.nextText:SetText(nxt and (L("Danach: ") .. nxt) or "")
            Levelmate.Arrow.SetTarget(train.target, train.targetName)
            panel.previewText:SetText((CharDB().previewHidden or not act) and "" or RenderPreview(mode, act))
        elseif act then
            local t, d = DescribeAction(act)
            SetCard(t, d, act, plan)
            local nxt = ShortAction(plan.actions[2])
            panel.nextText:SetText((nxt and CharDB().previewHidden) and (L("Danach: ") .. nxt) or "")
            -- Pfeil: Endziel + Zwischenziel (Uebergang / bekannter Weg). Das
            -- Zwischenziel wird laufend neu bestimmt, waehrend du dich bewegst.
            local finalTarget, finalName = act.target, act.targetName
            do
                local steps = {}
                for i = 1, 4 do
                    local a2 = plan.actions[i]
                    if not a2 then break end
                    steps[#steps + 1] = { target = a2.target }
                end
                Levelmate.Arrow.SetSteps(steps)
            end
            Levelmate.Arrow.SetRoute(finalTarget, finalName, function(here)
                if not here or not finalTarget then return nil end
                if finalTarget.map ~= here.map and Levelmate.Travel.NextWaypoint then
                    local wp, other = Levelmate.Travel.NextWaypoint(here, finalTarget)
                    if wp then
                        return wp, L("Übergang nach ") .. Levelmate.Planner.MapName(other) .. " (" .. (finalName or "?") .. ")", "gate"
                    end
                end
                local twp = Levelmate.Travel.TrailWaypoint and Levelmate.Planner.Yards(here, finalTarget)
                    and Levelmate.Travel.TrailWaypoint(here, finalTarget)
                if twp then return twp, L("Dem Weg folgen (") .. (finalName or "?") .. ")", "trail" end
                return nil
            end)
            panel.previewText:SetText(CharDB().previewHidden and "" or RenderPreview(mode, act))
        else
            panel.previewText:SetText("")
            SetCard(L("Keine passende Quest gefunden"), L("Für deine Stufe ist in der Nähe nichts Lohnendes verfügbar. Gegner in deinem Levelbereich besiegen oder Modus wechseln."),
                nil, nil, { 0.6, 0.6, 0.6 }, true)
            panel.nextText:SetText("")
            Levelmate.Arrow.SetTarget(nil)
        end
    end

    panel.questText:SetText(RenderQuestLog(plan))

    local pace, paceSec = Levelmate.Smart.Pace()
    if pace then
        panel.xpText:SetText(string.format(L("|cff66ccffDein Tempo:|r %.0f XP pro Spielminute (letzte Stunde)"), pace))
    else
        panel.xpText:SetText(string.format(L("|cff66ccffDein Tempo:|r wird gemessen (%d von 10 Minuten)"), math.floor((paceSec or 0) / 60)))
    end
    Layout()
end
Levelmate.Refresh = Refresh

-- Sprache gewechselt (Einstellungen): alles neu beschriften
function Levelmate.OnLanguageChanged()
    if Levelmate.Travel and Levelmate.Travel.ResetLegs then Levelmate.Travel.ResetLegs() end
    if Levelmate.InvalidatePreview then Levelmate.InvalidatePreview() end
    if Levelmate.Minimap and Levelmate.Minimap.Update then pcall(Levelmate.Minimap.Update) end
    if panel:IsShown() then Refresh() end
end

-- Fenster ein-/ausblenden (fuer Minimap-Knopf und Addon-Menue)
function Levelmate.TogglePanel()
    if panel:IsShown() then
        panel:Hide(); Levelmate.Arrow.SetTarget(nil)
    else
        panel:Show(); Refresh()
    end
end

-- Kurzinfo fuer den Tooltip des Minimap-Knopfs
function Levelmate.CurrentStepText()
    local plan = Levelmate.Planner.Last()
    local act = plan and plan.actions and plan.actions[1]
    if not act then return nil end
    local t, d = DescribeAction(act, true)
    return t, d
end

-- Mehrere Ereignisse kurz hintereinander -> eine Aktualisierung.
local pending = false
function Levelmate.RequestRefresh(now, delay)
    if not panel:IsShown() then return end
    if now or not (C_Timer and C_Timer.After) then Refresh(); return end
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.3, function() pending = false; if panel:IsShown() then Refresh() end end)
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
panel.modeButton:SetScript("OnClick", ShowModeDialog)
-- "Ueberspringen" nur bei Quest-/Dungeonschritten (dauerhaft); alles andere
-- (Lehrer, Reisen, Abbrechen-Vorschlag) ist ohnehin nur voruebergehend -> "Spaeter".
function panel.UpdateSkip()
    local act = currentAction
    local questStep = act and act.kind ~= "TRAIN" and act.kind ~= "FLY" and act.kind ~= "HEARTH"
        and act.kind ~= "SHIP" and act.kind ~= "ABANDON" and (act.c or act.group) and true or false
    panel.skipButton:SetShown(questStep)
end
local function SkipCurrent(perm)
    local act = currentAction
    if act and act.kind == "TRAIN" then
        CharDB().trainSkipLevel = UnitLevel("player")
        Print(L("Lehrer übersprungen – kommt mit der nächsten Stufe wieder (der Pfeil holt ihn sofort zurück)."))
    elseif act and (act.kind == "FLY" or act.kind == "HEARTH" or act.kind == "SHIP") then
        -- Reiseschritt ablehnen: 15 Minuten lang nicht mehr vorschlagen (dann wird gelaufen)
        CharDB().travelSkip = CharDB().travelSkip or {}
        local key = act.kind == "HEARTH" and "HEARTH"
            or act.kind == "SHIP" and ("SHIP:" .. tostring(act.leg and act.leg.master))
            or ("FLY:" .. tostring(act.from and act.from.name))
        CharDB().travelSkip[key] = (time and time() or 0) + 900
        Print(L("Reiseschritt übersprungen – für 15 Minuten wird stattdessen gelaufen."))
    elseif act and act.kind == "ABANDON" and act.c then
        -- "Abbrechen" ueberspringen: Vorschlag fuer diese Quest bis zur naechsten
        -- Stufe ausblenden (sonst kaeme sofort wieder derselbe Vorschlag).
        CharDB().abandonSnooze = CharDB().abandonSnooze or {}
        CharDB().abandonSnooze[act.c.q.id] = UnitLevel("player")
        Print(L("Abbrechen-Vorschlag ausgeblendet: ") .. QuestName(act.c) .. L(" – bis zur nächsten Stufe."))
    elseif act and act.c then
        Levelmate.Smart.SetDeferred(act.c.q.id, true, perm)
        table.insert(CharDB().skipStack, act.c.q.id)
        if perm then
            Print(L("Übersprungen: ") .. QuestName(act.c) .. L(" – kommt nicht mehr in die Route (der Pfeil holt sie zurück)."))
        else
            Print(L("Auf später verschoben: ") .. QuestName(act.c) .. L(" – kommt nach einem halben Level wieder (der Pfeil holt sie sofort zurück)."))
        end
    elseif act and act.group then
        for _, dc in ipairs(act.group.list) do
            Levelmate.Smart.SetDeferred(dc.q.id, true, perm); table.insert(CharDB().skipStack, dc.q.id)
        end
        Print(L("Dungeon übersprungen: ") .. (act.group.name or "?")
            .. (perm and L(" – kommt nicht mehr in die Route.") or L(" – kommt nach einem halben Level wieder.")))
    end
    Refresh()
end
panel.skipButton:SetScript("OnClick", function() SkipCurrent(true) end)
panel.laterButton:SetScript("OnClick", function() SkipCurrent(false) end)
panel.backButton:SetScript("OnClick", function()
    local stack = CharDB().skipStack
    if CharDB().trainSkipLevel then
        CharDB().trainSkipLevel = nil
        Print(L("Lehrer wieder eingeplant."))
        Refresh()
        return
    end
    local id = table.remove(stack)
    if id then
        Levelmate.Smart.SetDeferred(id, false)
        Print(L("Wieder aufgenommen: Quest ") .. id)
    else
        Print(L("Nichts zum Zurücknehmen."))
    end
    Refresh()
end)
panel.arrowButton:SetScript("OnClick", function()
    local on = Levelmate.Arrow.Toggle()
    SetIconActive(panel.arrowButton, on)
    Print(on and L("Pfeil eingeblendet.") or L("Pfeil ausgeblendet."))
end)

---------------------------------------------------------------------------
-- Befehle
---------------------------------------------------------------------------
SLASH_LEVELMATE1 = "/lm"
SLASH_LEVELMATE2 = "/levelmate"
SlashCmdList.LEVELMATE = function(msg)
    local cmd = string.lower(msg or "")
    if cmd == "hide" then
        panel:Hide(); Levelmate.Arrow.SetTarget(nil)
    elseif cmd == "" or cmd == "show" then
        panel:Show(); Refresh()
    elseif cmd:match("^scale") then
        local v = tonumber(cmd:match("^scale%s+([%d%.]+)"))
        if v and v >= 0.5 and v <= 1.5 then
            Levelmate_DB.scale = v
            panel:SetScale(v)
            Print(string.format(L("Fenstergröße: %d %%"), math.floor(v * 100 + 0.5)))
        else
            Print(L("Beispiel: /lm scale 0.8  (Werte von 0.5 bis 1.5)"))
        end
    elseif cmd:match("^warum") or cmd:match("^why") then
        local q = (msg or ""):match("^%S+%s+(.+)$")
        if q then Levelmate.Planner.Explain(q, Print) else Print(L("Beispiel: /lm warum Ruul")) end
    elseif cmd == "minimap" then
        Levelmate_DB.minimapHidden = not Levelmate_DB.minimapHidden
        if Levelmate.Minimap then Levelmate.Minimap.Update() end
        Print(Levelmate_DB.minimapHidden and L("Minimap-Knopf ausgeblendet.") or L("Minimap-Knopf eingeblendet."))
    elseif cmd == "fahrtenbuch" or cmd == "journal" then
        Levelmate_DB.journalOn = not Levelmate_DB.journalOn and true or nil
        if not Levelmate_DB.journalOn then Levelmate_DB.journal = nil; Levelmate_DB.mapDump = nil end
        Print(Levelmate_DB.journalOn and L("Fahrtenbuch eingeschaltet (nur für Tests, bleibt auf deinem PC).")
            or L("Fahrtenbuch ausgeschaltet und gelöscht."))
    elseif cmd:match("^leistung") or cmd:match("^perf") then
        Levelmate.Perf.Report(tonumber(cmd:match("(%d+)")) or 60)
    elseif cmd == "wege" or cmd == "paths" then
        local n, pairsN = Levelmate.Travel.GateCount()
        Print(string.format(L("Gelernte Gebietsübergänge: %d (zwischen %d Gebietspaaren)."), n, pairsN))
        Print(string.format(L("Gelernte Wegfelder (Trampelpfade, je 50 m): %d."), Levelmate.Travel.TrailCount and Levelmate.Travel.TrailCount() or 0))
        local T = Levelmate.Travel
        Print(string.format(L("Übergänge: %d gelernt, %d fest eingebaut, %d aus gelaufenen Wegen · Wegfelder: %d"),
            n or 0, T.StaticGateCount and T.StaticGateCount() or 0, T.TrailGateCount and T.TrailGateCount() or 0,
            T.TrailCount and T.TrailCount() or 0))
        local sh = Levelmate.Travel.shared or {}
        Print(string.format(L("Von Gruppenmitgliedern übernommen (diese Sitzung): %d Übergänge, %d Wegfelder."), sh.gates or 0, sh.cells or 0))
        Print(L("Das Addon lernt Wege, wenn du zu Fuß oder beritten unterwegs bist, und tauscht sie in der Gruppe aus."))
    elseif cmd == "karte" or cmd == "map" then
        Levelmate_DB.mapRoute = (Levelmate_DB.mapRoute == false) and true or false
        Print(Levelmate_DB.mapRoute and L("Route auf der Weltkarte eingeblendet.") or L("Route auf der Weltkarte ausgeblendet."))
        if Levelmate.Arrow.RefreshMap then Levelmate.Arrow.RefreshMap() end
    elseif cmd == "ausgelassen" or cmd == "skipped" then
        Print(string.format(L("Dauerhaft übersprungene Quests: %d. Alle zurückholen: /lm ausgelassen leeren"),
            Levelmate.Smart.PermanentCount and Levelmate.Smart.PermanentCount() or 0))
    elseif cmd == "ausgelassen leeren" or cmd == "skipped clear" then
        local n = Levelmate.Smart.ClearPermanent and Levelmate.Smart.ClearPermanent() or 0
        Print(string.format(L("%d übersprungene Quests sind wieder in der Route."), n))
        Refresh()
    elseif cmd == "optionen" or cmd == "options" or cmd == "einstellungen" or cmd == "settings" then
        if Levelmate.Options then Levelmate.Options.Toggle() end
    elseif cmd == "mode" or cmd == "modus" then
        ShowModeDialog()
    elseif cmd == "export" then
        if Levelmate.Export then Levelmate.Export.Show("export") end
    elseif cmd == "import" then
        if Levelmate.Export then Levelmate.Export.Show("import") end
    elseif cmd == "talente" or cmd == "talents" then
        local function T(f, ...) if not f then return "-" end local r = { pcall(f, ...) } return r[1] and tostring(r[2]) or "err" end
        local CT, TR = C_ClassTalents, C_Traits
        local has = "-"
        if CT and CT.HasUnspentTalentPoints then
            local r = { pcall(CT.HasUnspentTalentPoints) }
            has = r[1] and (tostring(r[2]) .. "/" .. tostring(r[3]) .. "/" .. tostring(r[4])) or "err"
        end
        Print("UnitCharacterPoints=" .. T(UnitCharacterPoints, "player") .. "  GetUnspentTalentPoints=" .. T(GetUnspentTalentPoints)
            .. "  Tabs=" .. T(GetNumTalentTabs) .. "  C_ClassTalents=" .. (CT and "ja" or "-") .. "  C_Traits=" .. (TR and "ja" or "-")
            .. "  HasUnspent=" .. has .. "  ConfigID=" .. T(CT and CT.GetActiveConfigID)
            .. "  Traits=" .. tostring(TraitPoints()) .. "  -> " .. tostring(UnspentTalentPoints()))
        local names = {}
        for k in pairs(_G) do
            if type(k) == "string" and (k:find("^C_.*Talent") or k:find("Talent") and type(_G[k]) == "function") then names[#names + 1] = k end
        end
        table.sort(names)
        Print("API: " .. table.concat(names, ", ", 1, math.min(#names, 40)))
    elseif cmd == "lehrer" or cmd == "trainer" then
        if Levelmate.Trainer and Levelmate.Trainer.Debug then Levelmate.Trainer.Debug(Print) end
    elseif cmd == "arrow" or cmd == "pfeil" then
        Levelmate.Arrow.Toggle()
    elseif cmd == "tomtom" then
        Levelmate_DB.useTomTom = not Levelmate_DB.useTomTom
        Print(Levelmate_DB.useTomTom and "TomTom-Wegpunkte an." or "TomTom-Wegpunkte aus.")
        Refresh()
    elseif cmd == "reset" then
        Levelmate_CharDB.skipStack = {}
        Levelmate.Smart.ClearDeferred()
        Levelmate_DB.panelPos = nil; Levelmate_DB.arrowPos = nil; Levelmate_DB.panelHeight = nil; Levelmate_DB.scale = nil; Levelmate_DB.panelCollapsed = nil
        panel:SetScale(1)
        AnchorPanel(); Levelmate.Arrow.Restore()
        Print(L("Übersprungene Quests und Fensterpositionen zurückgesetzt."))
        Refresh()
    elseif cmd == "smart" then
        local sum = Levelmate.Smart.GetSummary()
        if sum and sum.enough then
            Print(string.format(L("XP/min gemessen (Ø letzte %d Quests): %.0f"), sum.count, sum.avg))
        else
            Print(L("Noch zu wenig Messungen für XP/min."))
        end
        local cal = Levelmate.Smart.CalibrationText()
        Print(L("Abgleich mit deinen Zeiten: ") .. (cal or L("noch keine Messung (Quest annehmen und abgeben)")))
        local plan = Levelmate.Planner.Last()
        if plan and plan.referenceXPPerMin then
            Print(string.format(L("Geschätzter Ø der Quests in Reichweite: %.0f XP/min"), plan.referenceXPPerMin))
        end
    elseif cmd == "diag" then
        Levelmate.Quests.Diagnose(Print)
        Print("QuestieDB: " .. (Levelmate.DB.Available() and "aktiv" or L("|cffff4040nicht gefunden|r")))
        Print("TomTom: " .. (TomTom and "installiert" or L("nicht installiert")))
        if #Levelmate.failedEvents > 0 then
            Print(L("|cffff4040Nicht unterstützte Events:|r ") .. table.concat(Levelmate.failedEvents, ", "))
        else
            Print(L("Alle Events erfolgreich registriert."))
        end
        local plan = Levelmate.Planner.Last()
        if plan and plan.actions then
            Print(string.format(L("Planer: %d mögliche Schritte, Modus %s"), #plan.actions, L(plan.mode.label)))
            for i = 1, math.min(5, #plan.actions) do
                local a = plan.actions[i]
                Print(string.format(L("  %d. %s (%.0f XP/min geschätzt)"), i, ShortAction(a), a.xpPerMin or 0))
            end
        end
    else
        Print(L("Befehle: /lm | optionen | wege | export | import | hide | mode | arrow | tomtom | minimap | scale 0.8 | reset | smart | diag | lehrer | warum <Quest>"))
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA", "TAXIMAP_OPENED",
    "LEARNED_SPELL_IN_TAB", "TRAINER_CLOSED", "CHARACTER_POINTS_CHANGED",
}) do
    SafeRegister(events, event)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_LOGIN" then
        Levelmate_DB = Levelmate_DB or {}
        CharDB()
        if Levelmate_DB.scale then panel:SetScale(Levelmate_DB.scale) end
        AnchorPanel()
        Levelmate.Arrow.Restore()
        Levelmate.Planner.OnLogin()
        if Levelmate.Smart.ReleaseDeferred then Levelmate.Smart.ReleaseDeferred() end
        if Levelmate.Journal and Levelmate.Journal.DumpMaps then C_Timer.After(10, function() pcall(Levelmate.Journal.DumpMaps) end) end
        if Levelmate.Minimap then Levelmate.Minimap.Init() end
        if not Levelmate.DB.Available() then
            Print(L("|cffff4040QuestieDB nicht gefunden.|r Der Routenplaner braucht das Addon QuestieDB."))
        end
        Levelmate.Planner.BuildPool(function() Levelmate.RequestRefresh(true) end)
        if Levelmate.Travel.ApplySeed then pcall(Levelmate.Travel.ApplySeed) end
        Levelmate.Travel.Scan(function() Levelmate.RequestRefresh(true) end)
        if Levelmate.Travel.ScanInns then Levelmate.Travel.ScanInns() end
        if Levelmate.Trainer and Levelmate.Trainer.Scan then
            -- Sobald die Lehrer bekannt sind, gleich neu anzeigen (nicht erst beim naechsten Takt)
            C_Timer.After(5, function()
                pcall(Levelmate.Trainer.Scan, false, function() Levelmate.RequestRefresh(true) end)
            end)
        end
        Refresh()
        if not CharDB().mode then ShowModeDialog() end
        Print(L("Version ") .. Levelmate.version .. L(" geladen. /lm für Befehle."))
        -- Regelmaessig neu planen, aber nur wenn du dich spuerbar bewegt hast
        -- (mind. 25 Yards) oder 15 s vergangen sind. Der Pfeil zeigt die
        -- Richtung ohnehin laufend; staendiges Neuplanen kostet nur Leistung.
        if C_Timer and C_Timer.NewTicker then
            C_Timer.NewTicker(3, function()
                if not panel:IsShown() then return end
                local p = Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
                local now = GetTime and GetTime() or 0
                local last = Levelmate._lastPlanAt
                local moved = true
                if p and last and p.wx and last.wx and p.cont == last.cont then
                    local dx, dy = p.wx - last.wx, p.wy - last.wy
                    moved = (dx * dx + dy * dy) >= 50 * 50
                end
                if moved or not last or now - (last.t or 0) >= 30 then Refresh() end
            end)
        end
        return
    end
    if event == "PLAYER_XP_UPDATE" then
        -- Uebersprungenes nach einem halben Level zurueckholen (kein Neuplanen sonst)
        local back = Levelmate.Smart.ReleaseDeferred and Levelmate.Smart.ReleaseDeferred() or {}
        if #back > 0 then
            local names = {}
            for _, id in ipairs(back) do
                local q = Levelmate.DB.Quest(id)
                names[#names + 1] = q and q.name or (L("Quest ") .. id)
            end
            Print(L("Wieder eingeplant (übersprungen vor einem halben Level): ") .. table.concat(names, ", "))
            if Levelmate.InvalidatePreview then Levelmate.InvalidatePreview() end
            Levelmate.RequestRefresh()
        end
        return
    end
    if event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP" then
        if Levelmate.InvalidatePreview then Levelmate.InvalidatePreview() end
    end
    if event == "LEARNED_SPELL_IN_TAB" or event == "TRAINER_CLOSED" or event == "PLAYER_LEVEL_UP"
        or event == "CHARACTER_POINTS_CHANGED" then
        if Levelmate.Trainer and Levelmate.Trainer.Invalidate then Levelmate.Trainer.Invalidate() end
    end
    if event == "QUEST_ACCEPTED" then
        Levelmate.Smart.OnQuestAccepted(arg1)
    elseif event == "QUEST_TURNED_IN" then
        Levelmate.Smart.OnQuestTurnedIn(arg1, arg2)
        Levelmate.Planner.MarkDone(arg1)
    elseif event == "TAXIMAP_OPENED" then
        if Levelmate.Planner.InvalidateCostCache then Levelmate.Planner.InvalidateCostCache() end
        local n = Levelmate.Travel.OnTaxiOpened()
        if n and n > 0 then Print(string.format(L("Flugpunkte erfasst: %d bekannt an diesem Flugmeister."), n)) end
    elseif event == "PLAYER_LEVEL_UP" then
        Levelmate.Planner.BuildPool(function() Levelmate.RequestRefresh(true) end)
        -- Uebersprungene Quests kommen nach dem Aufstieg zurueck
        C_Timer.After(1, function()
            local back = Levelmate.Smart.ReleaseDeferred and Levelmate.Smart.ReleaseDeferred() or {}
            if #back > 0 then
                local names = {}
                for _, id in ipairs(back) do
                    local q = Levelmate.DB.Quest(id)
                    names[#names + 1] = q and q.name or (L("Quest ") .. id)
                end
                Print(L("Wieder eingeplant (übersprungen): ") .. table.concat(names, ", "))
                Levelmate.RequestRefresh(true)
            end
        end)
    end
    if Levelmate.SetRefreshReason then Levelmate.SetRefreshReason(event == "QUEST_LOG_UPDATE" and L("Questlog") or event == "QUEST_ACCEPTED" and L("Annahme") or event == "QUEST_TURNED_IN" and L("Abgabe") or event) end
    if event == "QUEST_LOG_UPDATE" then Levelmate.RequestRefresh(false, 1.0) else Levelmate.RequestRefresh() end
end)

AnchorPanel()
