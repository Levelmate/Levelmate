local addonName = ...
local L = Levelmate.L
Levelmate = Levelmate or {}
Levelmate.name = addonName
Levelmate.version = "1.1.3"

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(L("|cff66ccffLevelmate|r: ") .. tostring(msg))
end
Levelmate.Print = Print

-- Leistungsmessung (/lm leistung): Wie viel Rechenzeit braucht das Addon?
Levelmate.Perf = { log = {} }
-- Haeufige kleine Arbeiten (Pfeil, Karte, Dungeon-Check) nur aufsummieren
Levelmate.Perf.acc = {}
function Levelmate.Perf.Acc(kind, ms)
    local now = GetTime and GetTime() or 0
    local a = Levelmate.Perf.acc[kind]
    if not a or now - a.since > 300 then a = { n = 0, sum = 0, max = 0, since = now }; Levelmate.Perf.acc[kind] = a end
    a.n = a.n + 1; a.sum = a.sum + ms
    if ms > a.max then a.max = ms end
    local pa = Levelmate.Perf.planAcc   -- waehrend einer gemessenen Planung: deren Anteil
    if pa then pa[kind] = (pa[kind] or 0) + ms end
end
function Levelmate.Perf.Time(kind, fn, ...)
    if not debugprofilestop then return pcall(fn, ...) end
    local t0 = debugprofilestop()
    local r = { pcall(fn, ...) }
    Levelmate.Perf.Acc(kind, debugprofilestop() - t0)
    return unpack(r)
end
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
    local accNames = { arrow = L("Pfeil/Wege"), map = L("Route auf der Weltkarte"), dungeon = L("Dungeon-Check"), rows = L("Fensteranzeige"),
        wegpunkte = L("Spiel-Abfrage Questorte"), reise = L("Reisezeit-Berechnung") }
    local accList = {}
    for kind, a in pairs(Levelmate.Perf.acc) do accList[#accList + 1] = { kind, a } end
    table.sort(accList, function(x, y) return x[2].sum > y[2].sum end)
    for _, ka in ipairs(accList) do
        local kind, a = ka[1], ka[2]
        local span = math.max(1, now - a.since)
        Print(string.format(L("  %s: %d-mal in %d s, zusammen %d ms, längste %d ms"), accNames[kind] or kind, a.n,
            math.floor(span), math.floor(a.sum + 0.5), math.floor(a.max + 0.5)))
    end
    Levelmate.Perf.acc = {}
    -- Die langsamste Neuplanung genauer
    local worst
    for _, e in ipairs(Levelmate.Perf.log) do
        if now - e.t <= seconds and e.kind == "refresh" and (not worst or e.ms > worst.ms) then worst = e end
    end
    if worst and worst.sections then
        local parts, planSum, sub = {}, 0, {}
        for k, v in pairs(worst.sections) do
            if k:sub(1, 1) == "~" then
                sub[#sub + 1] = string.format("%s %d", accNames[k:sub(2)] or k:sub(2), math.floor(v + 0.5))
            else
                parts[#parts + 1] = { k, v }; planSum = planSum + v
            end
        end
        table.sort(parts, function(a, b) return a[2] > b[2] end)
        local txt = {}
        for i = 1, math.min(6, #parts) do txt[#txt + 1] = string.format("%s %d", L(parts[i][1]), math.floor(parts[i][2] + 0.5)) end
        Print(string.format(L("  Langsamste (%d ms, vor %d s, %s): Planung %d ms [%s], Anzeige/Rest %d ms"),
            math.floor(worst.ms + 0.5), math.floor(now - worst.t), L(worst.why or "?"), math.floor(planSum + 0.5),
            table.concat(txt, ", "), math.floor(worst.ms - planSum + 0.5)))
        if #sub > 0 then Print(L("    darin enthalten: ") .. table.concat(sub, ", ")) end
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
panel:SetScript("OnDragStart", function(self) if not (Levelmate_DB and Levelmate_DB.locked) then self:StartMoving() end end)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.movingNow = nil
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
        -- Noch nicht angenommen: Questgeber auf der Weltkarte zeigen (wie mit M nachschauen)
        local plan = Levelmate.Planner.Last and Levelmate.Planner.Last()
        local best
        for _, a in ipairs(plan and plan.actions or {}) do
            if a.c and a.c.q and a.c.q.id == id and a.target and a.target.map then
                if a.kind == "ACCEPT" then best = a; break end
                best = best or a
            end
        end
        if best and Levelmate.ShowOnMap then
            Levelmate.ShowOnMap(best.target, q and q.name or tostring(id), best.targetName,
                L("„%s“ annehmen bei %s, %s (%.1f, %.1f)"))
            return
        end
        Print(string.format(L("„%s“ ist noch nicht in deinem Questlog – erst annehmen."), q and q.name or tostring(id)))
        return
    end
    -- neuer Client: Questlog neben der Karte; alter: eigenes Questlog-Fenster.
    -- Bei Dungeon- und manchen Elitequests kennt das Spiel keine Karte fuer die
    -- Quest - dann schlaegt der erste Weg still fehl. Darum mehrere Wege
    -- nacheinander, bis die Questdetails wirklich zu sehen sind.
    local function Shown(f) return f and f.IsShown and f:IsShown() and true or false end
    local function DetailsShown()
        return Shown(QuestMapFrame and QuestMapFrame.DetailsFrame) or Shown(QuestLogFrame)
            or Shown(QuestLogDetailFrame)
    end
    if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, id) end
    if QuestMapFrame_OpenToQuestDetails then
        pcall(QuestMapFrame_OpenToQuestDetails, id)
        if DetailsShown() then return end
        -- Karte selbst oeffnen (aktuelles Gebiet) und dann die Details zeigen
        if WorldMapFrame and not Shown(WorldMapFrame) then
            if ToggleWorldMap then pcall(ToggleWorldMap) else pcall(ShowUIPanel, WorldMapFrame) end
        end
        if QuestMapFrame_ShowQuestDetails then pcall(QuestMapFrame_ShowQuestDetails, id) end
        if DetailsShown() then return end
    end
    if QuestLog_OpenToQuest then
        pcall(QuestLog_OpenToQuest, idx)
        if DetailsShown() then return end
    end
    if QuestLog_SetSelection then pcall(QuestLog_SetSelection, idx) end
    if not DetailsShown() then
        if ToggleQuestLog then pcall(ToggleQuestLog) elseif QuestLogFrame then pcall(ShowUIPanel, QuestLogFrame) end
    end
    if QuestLog_SetSelection then pcall(QuestLog_SetSelection, idx) end
    if not DetailsShown() then
        Print(L("Das Spiel konnte diese Quest nicht im Questlog öffnen – bitte mit L (Questlog) nachsehen."))
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
        frame:SetScript("OnDragStart", function() if not (Levelmate_DB and Levelmate_DB.locked) then panel:StartMoving() end end)
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
        local qid = tonumber(link:match("^levelmate:q:(%d+)"))
        local li = qid and C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid)
        GameTooltip:SetText((li and li > 0) and L("Klicken: Quest im Questlog öffnen") or L("Klicken: Questgeber auf der Karte zeigen"))
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

-- Kleine Knoepfe hinter dem Titel: Kompaktmodus (nur Karte) und Fenster sperren
local function SmallButton(tex)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(14, 14)
    b:SetNormalTexture(tex)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    return b
end
panel.compactButton = SmallButton("Interface\\Buttons\\UI-MinusButton-Up")
panel.compactButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 100, -10)
panel.compactButton:SetScript("OnClick", function()
    if Levelmate_DB.panelCollapsed then
        Levelmate_DB.panelCollapsed = nil
        if (Levelmate_DB.panelHeight or 0) < 200 then Levelmate_DB.panelHeight = nil end
    else
        Levelmate_DB.panelCollapsed = true
    end
    if Levelmate.UpdateHeaderButtons then Levelmate.UpdateHeaderButtons() end
    if Levelmate.Refresh then Levelmate.Refresh() end
end)
panel.compactButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(Levelmate_DB.panelCollapsed and L("Aufklappen") or L("Kompakt"))
    GameTooltip:AddLine(L("Nur die Karte mit dem aktuellen Schritt zeigen – oder wieder alles."), 1, 1, 1, true)
    GameTooltip:Show()
end)
panel.compactButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
panel.lockButton = SmallButton("Interface\\Buttons\\LockButton-Unlocked-Up")
panel.lockButton:SetPoint("LEFT", panel.compactButton, "RIGHT", 4, 0)
panel.lockButton:SetScript("OnClick", function()
    Levelmate_DB.locked = not Levelmate_DB.locked or nil
    if Levelmate.UpdateHeaderButtons then Levelmate.UpdateHeaderButtons() end
    Print(Levelmate_DB.locked and L("Fenster gesperrt – Verschieben und Größe ändern sind aus.") or L("Fenster entsperrt."))
end)
panel.lockButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(Levelmate_DB.locked and L("Entsperren") or L("Sperren"))
    GameTooltip:AddLine(L("Levelmate- und Dungeon-Fenster gegen versehentliches Verschieben sperren."), 1, 1, 1, true)
    GameTooltip:Show()
end)
panel.lockButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
function Levelmate.UpdateHeaderButtons()
    if not Levelmate_DB then return end
    panel.compactButton:SetNormalTexture(Levelmate_DB.panelCollapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
    panel.lockButton:SetNormalTexture(Levelmate_DB.locked and "Interface\\Buttons\\LockButton-Locked-Up" or "Interface\\Buttons\\LockButton-Unlocked-Up")
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
dframe:SetSize(540, 440)
dframe:SetFrameStrata("MEDIUM")
dframe:SetBackdrop(panel:GetBackdrop())
dframe:SetBackdropColor(0.035, 0.055, 0.12, 0.92)
dframe:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
dframe:SetPoint("TOPLEFT", panel, "TOPRIGHT", 6, 0)
dframe:SetClampedToScreen(true)
dframe:EnableMouse(true)
dframe:Hide()
table.insert(UISpecialFrames, "LevelmateDungeonFrame")
-- Inhalt (Liste links, Details rechts) baut DungeonUI.lua
dframe.close = CreateFrame("Button", nil, dframe, "UIPanelCloseButton")
dframe.close:SetSize(24, 24)
dframe.close:SetPoint("TOPRIGHT", dframe, "TOPRIGHT", 0, 0)
dframe.close:SetFrameLevel((dframe:GetFrameLevel() or 1) + 12)
Levelmate.DungeonFrame = dframe
dframe:SetResizable(true)
if dframe.SetResizeBounds then
    pcall(dframe.SetResizeBounds, dframe, 470, 260, 900, 1200)
elseif dframe.SetMinResize then
    pcall(dframe.SetMinResize, dframe, 470, 260); pcall(dframe.SetMaxResize, dframe, 900, 1200)
end
dframe.grip = CreateFrame("Button", nil, dframe)
dframe.grip:SetSize(14, 14)
dframe.grip:SetPoint("BOTTOMRIGHT", dframe, "BOTTOMRIGHT", -3, 3)
dframe.grip:SetFrameLevel((dframe:GetFrameLevel() or 1) + 12)
dframe.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
dframe.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
dframe.grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
local function DLayout() if Levelmate.DungeonLayout then pcall(Levelmate.DungeonLayout) end end
dframe.grip:SetScript("OnMouseDown", function()
    if Levelmate_DB and Levelmate_DB.locked then return end
    dframe.sizing = true
    dframe:StartSizing("BOTTOMRIGHT")
end)
dframe.grip:SetScript("OnMouseUp", function()
    if not dframe.sizing then return end
    dframe:StopMovingOrSizing()
    dframe.sizing = nil
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.dungeonSize = { math.floor(dframe:GetWidth() + 0.5), math.floor(dframe:GetHeight() + 0.5) }
    -- StartSizing kann den Anker aendern: Position wie gehabt (angedockt oder gespeichert)
    if Levelmate_DB.dungeonPos then
        local point, _, _, x, y = dframe:GetPoint(1)
        Levelmate_DB.dungeonPos = { point or "TOPLEFT", x or 0, y or 0 }
    end
    if Levelmate.AnchorDungeonFrame then Levelmate.AnchorDungeonFrame() end
    DLayout()
end)
dframe:SetScript("OnSizeChanged", function()
    if dframe.sizing then DLayout() end
end)
-- Eigenstaendig verschiebbar: Position wird gemerkt. Ohne gespeicherte
-- Position (oder nach /lm reset) haengt es rechts am Levelmate-Fenster.
-- Zurueck an das Hauptfenster: nah an dessen rechten Rand ziehen.
local function AnchorDungeonFrame()
    dframe:ClearAllPoints()
    local p = Levelmate_DB and Levelmate_DB.dungeonPos
    if p then dframe:SetPoint(p[1], UIParent, p[1], p[2], p[3])
    else dframe:SetPoint("TOPLEFT", panel, "TOPRIGHT", 6, 0) end
    local sz = Levelmate_DB and Levelmate_DB.dungeonSize
    if sz and sz[1] >= 470 then dframe:SetSize(sz[1], sz[2]) else dframe:SetSize(540, 440) end
end
Levelmate.AnchorDungeonFrame = AnchorDungeonFrame
dframe:SetMovable(true)
dframe:RegisterForDrag("LeftButton")
dframe:SetScript("OnDragStart", function(self) if not (Levelmate_DB and Levelmate_DB.locked) then self:StartMoving() end end)
dframe:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Levelmate_DB = Levelmate_DB or {}
    local l, t = self:GetLeft(), self:GetTop()
    local pr, pt = panel:GetRight(), panel:GetTop()
    local ps = panel:GetEffectiveScale() / self:GetEffectiveScale()
    if l and t and pr and pt and math.abs(l - (pr * ps + 6)) < 25 and math.abs(t - pt * ps) < 25 then
        Levelmate_DB.dungeonPos = nil   -- wieder angedockt
    else
        local point, _, _, x, y = self:GetPoint(1)
        Levelmate_DB.dungeonPos = { point or "TOPLEFT", x or 0, y or 0 }
    end
    AnchorDungeonFrame()
end)
dframe:SetScript("OnShow", function()
    AnchorDungeonFrame()
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
panel.bar:SetScript("OnDragStart", function() if not (Levelmate_DB and Levelmate_DB.locked) then panel:StartMoving() end end)
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
panel.kindLabel = Text("GameFontNormalSmall", panel.card, CARD_TEXT_W - 38)
panel.stepTitle = Text("GameFontNormalLarge", panel.card, CARD_TEXT_W - 38)
EnableQuestLinks(panel.card)
EnableQuestLinks(content)
panel.stepDetail = Text("GameFontHighlightSmall", panel.card, CARD_TEXT_W)
panel.stepDetail:SetTextColor(0.82, 0.82, 0.82)
panel.badge = Text("GameFontHighlightSmall", panel.card, CARD_TEXT_W)
-- Oben rechts in der Schritt-Karte: (i) = warum dieser Schritt, daneben ggf. der
-- Questgegenstand zum Anklicken
-- Fortschrittsbalken fuer "Erledigen" (z. B. 7/12 Korn von Myzrael)
-- Fortschrittsbalken fuer "Erledigen": ein Balken je Questziel (z. B. 7/12 Korn)
panel.cardBars = {}
function panel.CardBar(i)
    local b = panel.cardBars[i]
    if b then return b end
    b = CreateFrame("StatusBar", nil, panel.card)
    b:SetSize(CARD_TEXT_W, 15)
    b:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    b:SetMinMaxValues(0, 1)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0, 0, 0, 0.5)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", b, "LEFT", 5, 0)
    b.text:SetPoint("RIGHT", b, "RIGHT", -5, 0)
    b.text:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")
    b:Hide()
    panel.cardBars[i] = b
    return b
end
panel.cardProgress = { on = false }   -- Kompatibilitaet (Layout fragt .on)
panel.cardExtra = Text("GameFontHighlightSmall", panel.card, CARD_TEXT_W)
-- Alle Questziele eines Erledigen-Schritts aus dem Questlog: { {have, need, text, done}, ... }
local function StepProgressList(act)
    if not (act and act.kind == "DO" and act.c and act.c.q) then return nil end
    local lq = Levelmate.Quests.Find and Levelmate.Quests.Find(act.c.q.id)
    if not lq then
        for _, x in ipairs(Levelmate.Quests.GetList() or {}) do if x.questID == act.c.q.id then lq = x; break end end
    end
    if not lq then return nil end
    local list = {}
    for _, o in ipairs(lq.objectives or {}) do
        local txt = Levelmate.Quests.ShowText and Levelmate.Quests.ShowText(o) or (o.text or "")
        if (o.need or 0) > 0 then
            list[#list + 1] = { have = o.have or 0, need = o.need, text = txt, done = o.done }
        elseif txt ~= "" then
            list[#list + 1] = { have = o.done and 1 or 0, need = 1, text = txt, done = o.done }
        end
    end
    return #list > 0 and list or nil
end
local function StepProgress(act)
    local l = StepProgressList(act)
    local o = l and l[1]
    if o then return o.have, o.need, o.text end
end
Levelmate.StepProgress = StepProgress
Levelmate.StepProgressList = StepProgressList

panel.cardInfo = CreateFrame("Button", nil, panel.card)
panel.cardInfo:SetSize(16, 16)
panel.cardInfo:SetPoint("TOPRIGHT", panel.card, "TOPRIGHT", -6, -6)
panel.cardInfo:SetNormalTexture("Interface\\Common\\help-i")
panel.cardInfo:SetHighlightTexture("Interface\\Common\\help-i")
panel.cardInfo:Hide()
panel.cardInfo:SetScript("OnEnter", function(self)
    if not self.lines then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L("Warum dieser Schritt?"), 1, 0.82, 0)
    for _, line in ipairs(self.lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
    GameTooltip:Show()
end)
panel.cardInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
panel.cardItem = CreateFrame("Button", nil, panel.card)
panel.cardItem:SetSize(18, 18)
panel.cardItem.icon = panel.cardItem:CreateTexture(nil, "ARTWORK")
panel.cardItem.icon:SetAllPoints()
panel.cardItem:Hide()
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
-- Questlog als Zeilen: je Quest ein Text, rechts oben (i) und ggf. Questgegenstand
local qrows, qrowCount = {}, 0
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
    panel.compactButton:ClearAllPoints()
    panel.compactButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 36 + math.ceil(panel.title:GetStringWidth() or 60) + 6, -10)
    if Levelmate.UpdateHeaderButtons then Levelmate.UpdateHeaderButtons() end
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
    local nb = panel.cardProgress.on and (panel.cardProgress.n or 0) or 0
    for i, bar in ipairs(panel.cardBars) do
        if i <= nb then
            y = y - (i == 1 and 7 or 3)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", panel.card, "TOPLEFT", CARD_PAD + 2, y)
            bar:Show()
            y = y - 15
        else
            bar:Hide()
        end
    end
    if HasText(panel.cardExtra) then Place(panel.cardExtra, 5, panel.card, CARD_PAD + 2) end
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
        for i = 1, qrowCount do
            local r = qrows[i]
            y = y - (i == 1 and 4 or 2)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
            local h = math.max(14, r.text:GetStringHeight() or 14)
            r:SetHeight(h)
            r:Show()
            y = y - h
        end
        for i = qrowCount + 1, #qrows do qrows[i]:Hide() end
    else
        panel.questText:Hide()
        for i = 1, #qrows do qrows[i]:Hide() end
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
    if Levelmate_DB and Levelmate_DB.locked then return end
    -- eingeklappt: beim Ziehen wieder Platz fuer den Scrollbereich lassen
    panel.cardBottom = panel:GetHeight()
    panel.sizingNow = true
    panel:StartSizing("BOTTOM")
    -- Sicherung: Maustaste ueber einem anderen Fenster losgelassen (z. B. Questtracker)
    -- -> OnMouseUp kommt nie an, das Fenster bliebe "am Ziehen" haengen.
    grip:SetScript("OnUpdate", function(self)
        if panel.sizingNow and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
            local up = self:GetScript("OnMouseUp")
            if up then up(self) end
        end
        if not panel.sizingNow then self:SetScript("OnUpdate", nil) end
    end)
end)
grip:SetScript("OnMouseUp", function()
    if not panel.sizingNow then return end
    panel.sizingNow = nil
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

-- Hintergrund-Deckkraft (Einstellungen > Anzeige)
function Levelmate.ApplyBackground()
    local a = (Levelmate_DB and Levelmate_DB.bgAlpha) or 0.72
    panel:SetBackdropColor(0.035, 0.055, 0.12, a)
    dframe:SetBackdropColor(0.035, 0.055, 0.12, math.min(1, a + 0.2))
end
local function AnchorPanel()
    if Levelmate.ApplyBackground then Levelmate.ApplyBackground() end
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
local ShowModeDialog
do
local W, PAD = 400, 14
local CW = W - 2 * PAD
local GOLD_ = { 1, 0.82, 0 }
local dialog = CreateFrame("Frame", "LevelmateModeDialog", UIParent, "BackdropTemplate")
dialog:SetSize(W, 320)
dialog:SetPoint("CENTER")
dialog:SetFrameStrata("DIALOG")
dialog:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
dialog:SetBackdropColor(0.035, 0.055, 0.12, 0.97)
dialog:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
dialog:EnableMouse(true)
dialog:SetMovable(true)
dialog:SetClampedToScreen(true)
dialog:RegisterForDrag("LeftButton")
dialog:SetScript("OnDragStart", dialog.StartMoving)
dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
dialog:Hide()
-- ESC und X schliessen; ohne Auswahl bleibt der bisherige Modus
if UISpecialFrames then table.insert(UISpecialFrames, "LevelmateModeDialog") end
local dClose = CreateFrame("Button", nil, dialog, "UIPanelCloseButton")
dClose:SetSize(24, 24)
dClose:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", 0, 0)

local dLogo = dialog:CreateTexture(nil, "ARTWORK")
dLogo:SetTexture("Interface\\AddOns\\Levelmate\\Media\\Logo")
dLogo:SetSize(30, 30)
dLogo:SetPoint("TOPLEFT", PAD, -PAD)
local dTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dTitle:SetPoint("TOPLEFT", dLogo, "TOPRIGHT", 8, 0)
dTitle:SetTextColor(GOLD_[1], GOLD_[2], GOLD_[3])
local dText = dialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dText:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -3)
dText:SetWidth(CW - 70)
dText:SetJustifyH("LEFT")

local MODE_INFO = {
    { key = "quests",   text = "Nur Quests",        icon = "Interface\\Icons\\INV_Misc_Note_01",
      desc = "Solo questen. Dungeon- und Elitequests werden ausgelassen." },
    { key = "dungeons", text = "Quests + Dungeons", icon = "Interface\\Icons\\INV_Misc_Key_03",
      desc = "Mit Dungeonquests und deren Vorquests." },
    { key = "story",    text = "Story + Dungeons",  icon = "Interface\\Icons\\INV_Misc_Book_09",
      desc = "Slow-Leveling: Die Geschichte zählt, nicht das Tempo. Questreihen bis zum Ende, Dungeons als Finale, kaum Füllquests." },
}

local function SetMode(key)
    CharDB().mode = key
    Levelmate_DB.introSeen = true
    dialog:Hide()
    panel:Show()
    Print(L("Modus: ") .. L(Levelmate.Planner.MODES[key].label))
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
end

for _, m in ipairs(MODE_INFO) do
    local b = CreateFrame("Button", nil, dialog, "BackdropTemplate")
    b:SetWidth(CW)
    b:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    local ic = b:CreateTexture(nil, "ARTWORK")
    ic:SetTexture(m.icon)
    ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic:SetSize(30, 30)
    ic:SetPoint("TOPLEFT", 10, -10)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", ic, "TOPRIGHT", 10, -1)
    local badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("TOPRIGHT", -10, -11)
    local d = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    d:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -4)
    d:SetWidth(CW - 64)
    d:SetJustifyH("LEFT")
    if d.SetSpacing then d:SetSpacing(2) end
    b:SetScript("OnClick", function() SetMode(m.key) end)
    b:SetScript("OnEnter", function(self) if not self.active then self:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9) end end)
    b:SetScript("OnLeave", function(self) if not self.active then self:SetBackdropBorderColor(0.165, 0.19, 0.28, 1) end end)
    m.button, m.title, m.descFS, m.badge = b, t, d, badge
end

-- Erster Start: kurze Erklaerung unter den Modi (einmal je Account)
local INTRO = {
    "Der Pfeil zeigt dir den Weg zum nächsten Schritt. Rechtsklick auf den Pfeil: direkt zum Ziel statt über bekannte Wege.",
    "„Später“ stellt einen Schritt für ein halbes Level zurück. „Überspringen“ lässt die Quest ganz aus (/lm ausgelassen zeigt sie).",
    "Der Schlüssel oben im Fenster öffnet das Dungeon-Fenster: passende Dungeons, ihre Quests und „Jetzt hin“.",
    "Quest anklicken öffnet sie im Questlog.",
    "/lm bug erstellt bei Fehlern einen Bericht zum Kopieren.",
}
local introBox = CreateFrame("Frame", nil, dialog, "BackdropTemplate")
introBox:SetWidth(CW)
introBox:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
introBox:SetBackdropColor(0.08, 0.105, 0.19, 0.95)
introBox:SetBackdropBorderColor(0.165, 0.19, 0.28, 1)
local introHead = introBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
introHead:SetPoint("TOPLEFT", 10, -8)
introHead:SetTextColor(GOLD_[1], GOLD_[2], GOLD_[3])
local introText = introBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
introText:SetPoint("TOPLEFT", introHead, "BOTTOMLEFT", 0, -6)
introText:SetWidth(CW - 20)
introText:SetJustifyH("LEFT")
if introText.SetSpacing then introText:SetSpacing(2) end

-- Texte und Hoehen erst beim Anzeigen setzen (dann ist die Sprache bekannt)
dialog:SetScript("OnShow", function()
    dTitle:SetText(L("Wie möchtest du leveln?"))
    dText:SetText(L("Du kannst den Modus jederzeit oben im Fenster ändern."))
    local cur = Levelmate_CharDB and Levelmate_CharDB.mode
    local y = -PAD - 30 - 14
    for _, m in ipairs(MODE_INFO) do
        local b = m.button
        local on = (m.key == cur)
        b.active = on
        m.title:SetText(L(m.text))
        m.descFS:SetText(L(m.desc))
        m.badge:SetText(on and L("Aktiv") or "")
        if on then
            b:SetBackdropColor(0.79, 0.60, 0.23, 0.16)
            b:SetBackdropBorderColor(GOLD_[1], GOLD_[2], GOLD_[3], 1)
        else
            b:SetBackdropColor(0.08, 0.105, 0.19, 0.95)
            b:SetBackdropBorderColor(0.165, 0.19, 0.28, 1)
        end
        local h = math.max(50, 10 + 14 + 4 + (m.descFS:GetStringHeight() or 12) + 10)
        b:SetHeight(h)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, y)
        y = y - h - 8
    end
    local intro = not (Levelmate_DB and Levelmate_DB.introSeen)
    introBox:SetShown(intro)
    if intro then
        introHead:SetText(L("Kurz erklärt"))
        local t = {}
        for _, line in ipairs(INTRO) do t[#t + 1] = "• " .. L(line) end
        introText:SetText(table.concat(t, "\n"))
        local h = 8 + 14 + 6 + (introText:GetStringHeight() or 110) + 10
        introBox:SetHeight(h)
        introBox:ClearAllPoints()
        introBox:SetPoint("TOPLEFT", dialog, "TOPLEFT", PAD, y)
        y = y - h - 8
    end
    dialog:SetHeight(-y + PAD - 8)
end)

ShowModeDialog = function() dialog:Show() end
end

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
local ridingHintShown = false

---------------------------------------------------------------------------
-- Questgegenstand: kleines Symbol bei der Quest im Questlog-Bereich. Benutzen
-- geht nur ueber einen sicheren Knopf. Der liegt unsichtbar bereit und wird beim
-- Draufzeigen genau ueber das Symbol gelegt (nur ausserhalb des Kampfes moeglich,
-- so wie bei allen Addons). Das Fenster selbst bleibt dadurch frei verschiebbar.
-- Tastenbelegung per Makro: /click LevelmateItemButton (Gegenstand des aktuellen Schritts)
---------------------------------------------------------------------------
local itemBtn = CreateFrame("Button", "LevelmateItemButton", UIParent, "SecureActionButtonTemplate")
itemBtn:SetSize(16, 16)
itemBtn:SetFrameStrata("TOOLTIP")
itemBtn:RegisterForClicks("AnyUp", "AnyDown")
itemBtn:Hide()
itemBtn.icon = itemBtn:CreateTexture(nil, "ARTWORK")
itemBtn.icon:SetAllPoints()
itemBtn.hl = itemBtn:CreateTexture(nil, "HIGHLIGHT")
itemBtn.hl:SetAllPoints()
itemBtn.hl:SetColorTexture(1, 1, 1, 0.25)

local function ItemCount(id)
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
end
local function Usable(id)
    local spell = (C_Item and C_Item.GetItemSpell and C_Item.GetItemSpell(id)) or (GetItemSpell and GetItemSpell(id))
    return spell ~= nil
end
local function ItemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id)) or 134400
end
-- Questgegenstand einer Quest im Log: zuerst, was das Spiel als Questgegenstand
-- kennt, sonst benutzbare Gegenstaende aus der Datenbank, die du dabeihast
local function QuestItemFor(qid)
    if not qid or (Levelmate_DB and Levelmate_DB.itemButton == false) then return nil end
    local idx = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid)
    if idx and GetQuestLogSpecialItemInfo then
        local ok, link = pcall(GetQuestLogSpecialItemInfo, idx)
        local id = ok and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        if id then return id end
    end
    local q = Levelmate.DB.Quest(qid)
    for _, id in ipairs(q and q.requiredSourceItems or {}) do
        if type(id) == "number" and ItemCount(id) > 0 and Usable(id) then return id end
    end
    return nil
end

local stepItem          -- Gegenstand des aktuellen Schritts (fuer das Makro)
local function SetItemAttr(id)
    if InCombatLockdown() then return false end
    if id then
        itemBtn:SetAttribute("type", "item"); itemBtn:SetAttribute("item", "item:" .. id)
    else
        itemBtn:SetAttribute("type", nil); itemBtn:SetAttribute("item", nil)
    end
    itemBtn.itemID = id
    return true
end
local function HideOverlay()
    if InCombatLockdown() then return end
    itemBtn:Hide()
    SetItemAttr(stepItem)
end
-- Sicheren Knopf genau ueber das Symbol legen
local function OverlayItem(anchor, id)
    if InCombatLockdown() then return false end
    local l, b = anchor:GetLeft(), anchor:GetBottom()
    if not l or not b then return false end
    local sc = anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
    itemBtn:ClearAllPoints()
    itemBtn:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * sc, b * sc)
    itemBtn:SetSize(anchor:GetWidth() * sc, anchor:GetHeight() * sc)
    SetItemAttr(id)
    itemBtn.icon:SetTexture(ItemIcon(id))
    itemBtn:Show()
    return true
end
itemBtn:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
    GameTooltip:AddLine(L("Klicken: benutzen · Makro für den aktuellen Schritt: /click LevelmateItemButton"), 0.4, 0.8, 1, true)
    GameTooltip:Show()
end)
itemBtn:SetScript("OnLeave", function() GameTooltip:Hide(); HideOverlay() end)

function Levelmate.UpdateItemButton(act)
    -- Nur noch fuers Makro: Gegenstand des aktuellen Schritts merken
    local qid = act and act.kind == "DO" and act.c and act.c.live and act.c.q and act.c.q.id
    local fq = Levelmate.Planner.forceQuest
    if fq and Q.Find(fq) then qid = fq end
    stepItem = QuestItemFor(qid)
    if not itemBtn:IsShown() then SetItemAttr(stepItem) end
end
local itemEv = CreateFrame("Frame")
itemEv:RegisterEvent("PLAYER_REGEN_ENABLED")
-- Nach dem Kampf: aufgeschobene Neuplanung nachholen - mit kurzer Pause,
-- damit das Looten nicht ruckelt.
do
    local cf = CreateFrame("Frame")
    cf:RegisterEvent("PLAYER_REGEN_ENABLED")
    cf:SetScript("OnEvent", function()
        Levelmate._combatEndAt = GetTime and GetTime() or 0
        if not Levelmate._combatRefresh then return end
        Levelmate._combatRefresh = nil
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() if Levelmate.RequestRefresh then Levelmate.RequestRefresh(false, 0.1) end end)
        end
    end)
end
itemEv:SetScript("OnEvent", function()
    if itemBtn:IsShown() and not itemBtn:IsMouseOver() then HideOverlay()
    elseif not itemBtn:IsShown() then SetItemAttr(stepItem) end
end)
Levelmate.QuestItemFor = QuestItemFor
Levelmate.OverlayItem = OverlayItem
Levelmate.ItemIcon = ItemIcon
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
-- Symbole fuer Dungeon- und Elitequests (wie im Questlog des Spiels)
local ICON_DUNGEON = "|TInterface\\Minimap\\Dungeon:14:14|t"
local ICON_ELITE = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t"  -- Stern
local function QuestIcons(c)
    if not c then return "" end
    local s = ""
    if c.dungeonTag or c.isDungeon then s = s .. ICON_DUNGEON .. " " end
    if c.eliteTag then s = s .. ICON_ELITE .. " " end
    return s
end
Levelmate.QuestIcons = QuestIcons
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
-- Begruendung, wenn eine Quest vor allem wegen ihrer Folgequest(s) eingeplant ist
function Levelmate.WhyLine(c)
    local ap = c.areaPrereq
    if ap and ap.follow then
        local area = ap.elite and ap.elite.destMap and C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, ap.elite.destMap))
        local aname = type(area) == "table" and area.name or nil
        return string.format(L("|cff88ccffVorquest für „%s“%s – so musst du nur einmal ins Elite-Gebiet.|r"),
            ap.follow.name or "?", aname and (" (" .. aname .. ")") or ""), L("Vorquest")
    end
    local fb = c.followBonus or 0
    if fb > 0 and c.followQuest then
        -- Kurz-Kennzeichen nur, wenn die Quest allein unter dem Schnitt laege
        local plan = Levelmate.Planner.Last()
        local ref = plan and plan.referenceXPPerMin or 0
        local th = plan and plan.mode and plan.mode.threshold or 0.35
        local weak = ref > 0 and (c.xpPerMin or 0) < ref * th
        local text
        if c.followDungeon then
            text = string.format(L("|cff88ccffVorquest für den Dungeon %s („%s“).|r"), c.followDungeon, c.followQuest.name or "?")
        else
            text = string.format(L("|cff88ccffLohnt sich auch wegen der Folgequest „%s“ (+≈%d XP).|r"), c.followQuest.name or "?", math.floor(fb))
        end
        return text, weak and L("Vorquest") or nil
    end
    return nil
end
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
    -- Begruendungen kommen in den Tooltip des Info-Symbols (Karte bleibt kurz)
    local info = {}
    if act and act.c and title ~= "" and (act.kind == "ACCEPT" or act.kind == "DO") then
        local why, short = Levelmate.WhyLine(act.c)
        if why then
            info[#info + 1] = why
            if short then title = title .. " |cff88ccff(" .. short .. ")|r" end
        end
    end
    if act and act.c and title ~= "" and (act.kind == "ACCEPT" or act.kind == "DO" or act.kind == "TURNIN") then
        local icons = QuestIcons(act.c)
        if icons ~= "" then
            title = icons .. title
            local tag = (act.c.dungeonTag or act.c.isDungeon) and L("|cffff8040Dungeonquest · 5 Spieler|r") or L("|cffff8040Elitequest · 2–5 Spieler empfohlen|r")
            detail = tag .. " · " .. (detail or "")
        end
    end
    if act then
        if act.elitePickups and #act.elitePickups > 0 then
            local n = {}
            for _, pa in ipairs(act.elitePickups) do n[#n + 1] = QuestName(pa.c) end
            info[#info + 1] = L("|cffffd100Vorher annehmen (gleiches Gebiet):|r ") .. table.concat(n, ", ")
        end
        if act.eliteWait and #act.eliteWait > 0 then
            local n = {}
            for _, wc in ipairs(act.eliteWait) do n[#n + 1] = QuestName(wc) end
            info[#info + 1] = L("|cffffd100Wartet auf:|r ") .. table.concat(n, ", ") .. L(" – danach alles hier in einem Gang.")
        end
        if act.dungeonEntrance then
            info[#info + 1] = L("|cffaaaaaaDas Ziel liegt im Dungeon – der Pfeil zeigt zum Eingang.|r")
        end
        if act.dungeonUnknown then
            info[#info + 1] = L("|cffaaaaaaOrt im Dungeon unbekannt – der Pfeil zeigt zum Questgeber.|r")
        end
        act.infoLines = (#info > 0) and info or nil
    end
    return title, detail
end
Levelmate.DescribeAction = DescribeAction   -- auch fuer Tests
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
    elseif act.kind == "ABANDON" and act.grey then
        return L("|cffff6060Abbrechen:|r ") .. QuestName(c),
            L("Dein Questlog ist fast voll und diese Quest ist grau (kaum noch XP).\nQuestlog öffnen (L) > Quest auswählen > Abbrechen. Behalten? Dann „Überspringen“.")
    elseif act.kind == "ABANDON" then
        return L("|cffff6060Abbrechen:|r ") .. QuestName(c),
            L("Dein Questlog ist voll und diese Quest lohnt sich nicht mehr (") .. Levelmate.LT(c.skipReason or "") .. L(").\nQuestlog öffnen (L) > Quest auswählen > Abbrechen.")
    elseif act.kind == "DUNGEON" then
        local names = {}
        for _, dc in ipairs(act.group.list) do table.insert(names, QuestName(dc)) end
        if act.atEntrance then
            return L("|cffff8040Jetzt rein:|r ") .. (act.group.name or "?"),
                #names > 0 and string.format(L("Du stehst am Eingang. Quests im Dungeon:\n%s"), table.concat(names, ", "))
                or L("Du stehst am Eingang. Keine offenen Quests mehr für diesen Dungeon – „Überspringen“, wenn du nicht rein willst.")
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
    local name = act.c and (QuestIcons(act.c) .. QuestName(act.c)) or (act.group and act.group.name) or "?"
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


-- Eine Zeile im Questlog-Bereich
local function QRow(i)
    local r = qrows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r:SetWidth(SCROLL_W)
    r.text = Text("GameFontHighlightSmall", r, SCROLL_W - 40)
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
    EnableQuestLinks(r)
    -- (i): warum diese Quest (bzw. warum ausgelassen)
    r.info = CreateFrame("Button", nil, r)
    r.info:SetSize(14, 14)
    r.info:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, 1)
    r.info:SetNormalTexture("Interface\\Common\\help-i")
    r.info:SetHighlightTexture("Interface\\Common\\help-i")
    r.info:SetScript("OnEnter", function(self)
        if not self.lines then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.title or L("Warum diese Quest?"), 1, 0.82, 0)
        for _, line in ipairs(self.lines) do GameTooltip:AddLine(line, 0.9, 0.9, 0.9, true) end
        GameTooltip:Show()
    end)
    r.info:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Questgegenstand: Symbol; beim Draufzeigen liegt der sichere Knopf darueber
    r.item = CreateFrame("Button", nil, r)
    r.item:SetSize(16, 16)
    r.item:SetPoint("RIGHT", r.info, "LEFT", -3, 0)
    r.item.icon = r.item:CreateTexture(nil, "ARTWORK")
    r.item.icon:SetAllPoints()
    r.item:SetScript("OnEnter", function(self)
        if not self.itemID then return end
        if not Levelmate.OverlayItem(self, self.itemID) then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
            GameTooltip:AddLine(L("Im Kampf hier nicht klickbar – Makro: /click LevelmateItemButton"), 1, 0.4, 0.4, true)
            GameTooltip:Show()
        end
    end)
    r.item:SetScript("OnLeave", function() GameTooltip:Hide() end)
    qrows[i] = r
    return r
end

-- Begruendung fuer eine Quest im Log (Tooltip des (i))
local function QuestInfoLines(plan, qid)
    local c = plan and plan.entries and plan.entries[qid]
    if not c then return nil end
    local lines = {}
    if c.skipReason then
        lines[#lines + 1] = "|cffff9933" .. L("Ausgelassen: ") .. Levelmate.LT(c.skipReason) .. "|r"
    end
    if c.xpPerMin and c.xpPerMin > 0 and plan.referenceXPPerMin then
        lines[#lines + 1] = string.format(L("≈%d XP · ~%d XP/min (Schnitt hier: %d)"), math.floor(c.xp or 0),
            math.floor(c.xpPerMin), math.floor(plan.referenceXPPerMin))
    end
    local why = Levelmate.WhyLine(c)
    if why then lines[#lines + 1] = why end
    for _, act in ipairs(plan.actions or {}) do
        if act.c == c and act.kind ~= "ABANDON" then
            Levelmate.DescribeAction(act)   -- fuellt act.infoLines
            for _, l in ipairs(act.infoLines or {}) do
                if l ~= why then lines[#lines + 1] = l end
            end
            break
        end
    end
    if c.longCollect then
        lines[#lines + 1] = "|cffffaa33" .. (c.longKills
            and string.format(L("Lange Sammelquest: ca. %d min (seltene Drops, ~%d Kills je Gegenstand)"), c.longCollect, c.longKills)
            or string.format(L("Lange Sammelquest: ca. %d min (Fundort unbekannt, grob geschätzt)"), c.longCollect)) .. "|r"
    end
    if c.dungeonTag then lines[#lines + 1] = L("|cffff8040Dungeonquest · 5 Spieler|r") end
    if c.eliteTag then lines[#lines + 1] = L("|cffff8040Elitequest · 2–5 Spieler empfohlen|r") end
    return #lines > 0 and lines or nil
end

function Levelmate.QuestRows() return qrows, qrowCount end   -- fuer Tests
panel.cardItem:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    if not Levelmate.OverlayItem(self, self.itemID) then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if GameTooltip.SetItemByID then GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:AddLine(L("Im Kampf hier nicht klickbar – Makro: /click LevelmateItemButton"), 1, 0.4, 0.4, true)
        GameTooltip:Show()
    end
end)
panel.cardItem:SetScript("OnLeave", function() GameTooltip:Hide() end)
-- Hauptgrund, warum genau dieser Schritt jetzt dran ist (erste Zeile im (i))
local function StepReason(act, plan)
    local c = act and act.c
    if not c then return nil end
    local function G(s) return "|cff00ff00" .. s .. "|r" end
    if act.timedLate then
        return "|cffff4040" .. string.format(L("Zeitquest: nur noch %s – reicht wahrscheinlich nicht mehr (~%d min nötig). Abbrechen und neu annehmen?"),
            Levelmate.Quests.FormatTime(act.timed), math.ceil((act.seconds or 0) / 60)) .. "|r"
    end
    if act.timed then
        return G(string.format(L("Zeitquest: noch %s – zuerst erledigen"), Levelmate.Quests.FormatTime(act.timed)))
    end
    if act.timedTotal then
        return G(string.format(L("Zeitquest (%s): jetzt annehmen, du schaffst sie direkt danach"), Levelmate.Quests.FormatTime(act.timedTotal)))
    end
    if Levelmate.Planner.forceQuest and c.q and c.q.id == Levelmate.Planner.forceQuest then
        return G(Levelmate.Planner.forceAccept and L("Von dir gewählt (Dungeon-Fenster: Zuerst)") or L("Von dir gewählt (/lm zuerst)"))
    end
    if act.groupWith then
        return "|cff66ccff" .. string.format(L("Gemeinsam mit %s"), table.concat(act.groupWith, ", ")) .. "|r"
    end
    if act.atNPC then return G(L("Folgequest gleich hier mitnehmen – du stehst schon am NPC")) end
    if act.onTheWay then return G(L("Liegt auf dem Weg zum nächsten Ziel – kurz mitnehmen")) end
    if act.logFull then return G(L("Questlog voll – erst erledigen und abgeben, das macht Platz für neue")) end
    if act.kind == "TURNIN" and (act.hubCount or 0) >= 2 then
        return G(string.format(L("Im selben Lager: %d fertige Quests abgeben"), act.hubCount))
    end
    if act.near then return G(L("Direkt neben dir – erst alles hier mitnehmen")) end
    if act.dungeonPickup then return G(string.format(L("Für den Dungeon %s – vorher annehmen, dann nur einmal rein"), act.dungeonPickup)) end
    if act.dungeonPrep then return G(string.format(L("Dungeon-Vorbereitung %s: Vorquest, schaltet eine Dungeonquest frei"), act.dungeonPrep)) end
    if act.dungeonFocus then return G(L("Dungeon-Vorbereitung: Quest für den gewählten Dungeon abholen")) end
    if act.elitePickup then return G(L("Gleiches Elite-Gebiet – vorher annehmen, dann nur einmal hin")) end
    if c.sharedTrip then return G(L("Du kommst ohnehin dorthin (gemeinsamer Weg)")) end
    if act.storyKeep then return G(L("Angefangene Questreihe weiterspielen")) end
    if c.classQuest then return G(L("Klassenquest")) end
    if c.areaPrereq then return G(L("Schaltet eine Quest fürs selbe Gebiet frei")) end
    local ref = plan and plan.referenceXPPerMin or 0
    if act.kind == "TURNIN" then return G(L("Fertig – Belohnung abholen")) end
    if act.kind == "ACCEPT" and c.longCollect then
        return "|cffffaa33" .. string.format(L("Lange Sammelquest (~%d min) – lohnt sich trotzdem, die Gegner geben XP"), c.longCollect) .. "|r"
    end
    if ref > 0 and (c.xpPerMin or 0) >= ref then return G(L("Überdurchschnittlich viel XP pro Minute")) end
    return G(L("Beste Wahl in deiner Nähe (Weg + Aufwand + XP)"))
end

-- (i) und Questgegenstand fuer den aktuellen Schritt
local function SetCardIcons(act, plan)
    local c = act and act.c
    local lines = c and c.q and QuestInfoLines(plan, c.q.id) or nil
    if act and act.infoLines and not (c and plan and plan.entries and plan.entries[c.q.id]) then lines = act.infoLines end
    local reason = act and StepReason(act, plan)
    if reason then
        local t = { reason }
        for _, l in ipairs(lines or {}) do t[#t + 1] = l end
        lines = t
    end
    panel.cardInfo.lines = lines
    panel.cardInfo:SetShown(lines ~= nil)
    local item = act and act.kind == "DO" and c and c.live and c.q and QuestItemFor(c.q.id) or nil
    panel.cardItem.itemID = item
    if item then panel.cardItem.icon:SetTexture(ItemIcon(item)) end
    panel.cardItem:ClearAllPoints()
    if lines then panel.cardItem:SetPoint("RIGHT", panel.cardInfo, "LEFT", -4, 0)
    else panel.cardItem:SetPoint("TOPRIGHT", panel.card, "TOPRIGHT", -6, -5) end
    panel.cardItem:SetShown(item ~= nil)
end
Levelmate.SetCardIcons = SetCardIcons
Levelmate.StepReason = StepReason   -- fuer Tests

-- Dungeon-Vorbereitung fertig? Einmal Bescheid sagen (hoechstens alle 10 s pruefen)
local readyCheckAt, readyTold = -100, nil
function Levelmate.CheckDungeonReady()
    local foc = Levelmate_CharDB and Levelmate_CharDB.dungeonFocus
    if not foc then readyTold = nil; return end
    local now = GetTime and GetTime() or 0
    if now - readyCheckAt < 10 then return end
    readyCheckAt = now
    local ok, list = Levelmate.Perf.Time("dungeon", Levelmate.Planner.DungeonOverview)
    if not ok or type(list) ~= "table" then return end
    for _, e in ipairs(list) do
        if e.focused and e.total > 0 and #e.available == 0 and #e.blocked == 0 and readyTold ~= e.name then
            readyTold = e.name
            Print(string.format(L("|cff00ff00Bereit für %s:|r %d/%d Quests im Log. „Jetzt hin“ im Dungeon-Fenster schickt dich zum Eingang."),
                e.name, e.have, e.total - (e.inside or 0)))
            Levelmate.Planner.SetDungeonFocus(e.area)   -- Vorbereitung beendet (Umschalter)
            if PlaySound and SOUNDKIT and SOUNDKIT.READY_CHECK then pcall(PlaySound, SOUNDKIT.READY_CHECK) end
        end
    end
end

-- Countdown der Zeitquest in der Karte jede Sekunde nachfuehren
do
    local acc = 0
    local tick = CreateFrame("Frame", nil, panel)
    tick:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1 then return end
        acc = 0
        if panel.timerQuest and panel.kindBase then
            local tt = Levelmate.Quests.TimerText(panel.timerQuest)
            if tt then panel.kindLabel:SetText(panel.kindBase .. "  " .. tt) end
        end
    end)
end

local function UpdateQuestRows(plan)
    local live = Q.GetList()
    qrowCount = 0
    if #live == 0 then panel.questText:SetText(L("Keine Quests im Questlog.")); return end
    panel.questText:SetText("")
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
        local icons = c and Levelmate.QuestIcons(c) or ""
        -- Gruppenmodus: wer aus der Gruppe hat diese Quest auch?
        local who = Levelmate.Group and Levelmate.Group.Who and Levelmate.Group.Who(lq.questID)
        if who then note = note .. " |cff66ccff(+" .. table.concat(who, ", ") .. ")|r" end
        local tt = Q.TimerText(lq.questID)
        local lines = { Q.Icon(lq.status) .. " " .. icons .. QLink(lq.questID, title) .. (tt and ("  " .. tt) or "") .. note }
        if lq.status == Q.STATUS_ACTIVE then
            for j = 1, math.min(#lq.objectives, 3) do
                local o = lq.objectives[j]
                lines[#lines + 1] = "     " .. (o.done and "|cff00ff00" or "|cffcccccc") .. Levelmate.Quests.ShowText(o) .. "|r"
            end
        end
        qrowCount = qrowCount + 1
        local r = QRow(qrowCount)
        r.text:SetText(table.concat(lines, "\n"))
        local info = QuestInfoLines(plan, lq.questID)
        r.info.lines, r.info.title = info, lq.title
        r.info:SetShown(info ~= nil)
        local item = lq.status ~= Q.STATUS_READY and QuestItemFor(lq.questID) or nil
        r.item.itemID = item
        if item then r.item.icon:SetTexture(ItemIcon(item)) end
        r.item:SetShown(item ~= nil)
        r.item:ClearAllPoints()
        if info then r.item:SetPoint("RIGHT", r.info, "LEFT", -3, 0)
        else r.item:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, 1) end
    end
end


-- Routenvorschau: nur neu berechnen, wenn sich der aktuelle Schritt aendert
-- oder alle 15 Sekunden (die Berechnung spielt mehrere Planungen durch).
local previewCache = { key = nil, time = 0, text = "" }
local KIND_COLOR = { HEARTH = "|cff40c0ff", SHIP = "|cff40c0ff", ACCEPT = "|cffffd100", TURNIN = "|cff00ff00", DO = "|cff66ccff",
    DUNGEON = "|cffff8040", FLY = "|cff40c0ff", ABANDON = "|cffff6060" }
local KIND_RGB = { HEARTH = { 0.25, 0.75, 1 }, SHIP = { 0.25, 0.75, 1 }, FLY = { 0.25, 0.75, 1 },
    ACCEPT = { 1, 0.82, 0 }, TURNIN = { 0, 1, 0 }, DO = { 0.4, 0.8, 1 }, DUNGEON = { 1, 0.5, 0.25 },
    ABANDON = { 1, 0.38, 0.38 }, CLASS = { 0.69, 0.44, 1 } }
-- Symbole fuer die "Naechsten Schritte" (statt "Annehmen:", "Abgeben:" ...)
local KIND_ICON = {
    ACCEPT = "Interface\\GossipFrame\\AvailableQuestIcon",
    TURNIN = "Interface\\GossipFrame\\ActiveQuestIcon",
    DO = "Interface\\Icons\\Ability_DualWield",
    DUNGEON = "Interface\\Minimap\\Dungeon",
    FLY = "Interface\\Icons\\Ability_Mount_Wyvern_01",
    SHIP = "Interface\\Icons\\INV_Misc_Spyglass_02",
    HEARTH = "Interface\\Icons\\INV_Misc_Rune_01",
    ABANDON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
}
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
    SetCardIcons(nil)   -- Schritt-Symbole erst wieder zeigen, wenn sie zu diesem Schritt passen
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
        panel.kindBase = Hex(rgb) .. label .. "|r" .. where
        panel.timerQuest = act and act.c and act.c.live and act.c.q and act.c.q.id or nil
        local tt = panel.timerQuest and Levelmate.Quests.TimerText(panel.timerQuest)
        panel.kindLabel:SetText(panel.kindBase .. (tt and ("  " .. tt) or ""))
        local nameColor = (act and act.c and act.c.classQuest and act.kind ~= "FLY") and Hex(KIND_RGB.CLASS) or "|cffffffff"
        local qid = act and act.c and act.c.q and act.c.q.id
        panel.stepTitle:SetText(nameColor .. QLink(qid, name) .. "|r")
    else
        panel.kindBase, panel.timerQuest = nil, nil
        panel.kindLabel:SetText("")
        panel.stepTitle:SetText(name)
    end
    panel.stepDetail:SetText(detail or "")
    panel.badge:SetText(act and RatingText(act, plan) or "")
    SolidColor(panel.cardAccent, rgb[1], rgb[2], rgb[3], 0.9)
    local list = (Levelmate_DB.cardProgress ~= false) and StepProgressList(act) or nil
    panel.cardProgress.on, panel.cardProgress.n = false, 0
    panel.cardExtra:SetText("")
    if list then
        -- Questziele stehen jetzt in den Balken: dieselben Zeilen nicht nochmal im Text
        local shown = {}
        local n = math.min(#list, 4)
        for i = 1, n do
            local o = list[i]
            local bar = panel.CardBar(i)
            bar:SetValue(math.min(1, (o.have or 0) / math.max(1, o.need)))
            if o.done then bar:SetStatusBarColor(0.3, 0.85, 0.3, 0.9) else bar:SetStatusBarColor(0.25, 0.6, 0.95, 0.9) end
            bar.text:SetText(o.text ~= "" and o.text or string.format("%d / %d", o.have, o.need))
            shown[o.text] = true
        end
        panel.cardProgress.on, panel.cardProgress.n = true, n
        local d = panel.stepDetail:GetText() or ""
        if d ~= "" then
            local keep = {}
            for line in (d .. "\n"):gmatch("(.-)\n") do
                local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                local trimmed = plain:match("^%s*(.-)%s*$")
                if not shown[trimmed] then keep[#keep + 1] = line end
            end
            panel.stepDetail:SetText(table.concat(keep, "\n"))
        end
        -- Gleichzeitig hier: weitere offene Quests, deren Ziele im selben Gebiet liegen
        local top = act and act.target
        if top and plan and plan.actions and Levelmate.Planner.Yards then
            local extra, seen = {}, { [act.c.q.id] = true }
            for i = 1, math.min(#plan.actions, 12) do
                local x = plan.actions[i]
                if x ~= act and x.kind == "DO" and x.c and x.c.q and x.c.live and not seen[x.c.q.id]
                   and x.target and x.target.map == top.map then
                    local ok, yd = pcall(Levelmate.Planner.Yards, top, x.target)
                    if ok and yd and yd <= 220 then
                        seen[x.c.q.id] = true
                        local h, nd = StepProgress(x)
                        local prog = ""
                        local l2 = StepProgressList(x)
                        if l2 and l2[1] then prog = string.format(" (%d/%d)", l2[1].have or 0, l2[1].need or 0) end
                        extra[#extra + 1] = (x.c.q.name or "?") .. prog
                        if #extra >= 3 then break end
                    end
                end
            end
            if #extra > 0 then
                panel.cardExtra:SetText("|cffffd100" .. L("Gleichzeitig hier: ") .. "|r" .. table.concat(extra, ", "))
            end
        end
    end
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
    if not list or (from > 0 and not list[from]) or not list[1] then return "" end
    -- Der aktuelle Schritt steht schon in der Karte -> Liste beginnt danach.
    -- from = 0: aktueller Schritt fehlt in der Liste (z. B. Lehrer) -> ganze Liste.
    local startLevel = from > 0 and list[from].level or list[1].level
    local base = (from > 1) and list[from - 1].seconds or 0
    -- Uebersichtlich (Standard): nach Gebiet gruppiert, Symbol statt Wort, Zeit rechts.
    local compact = not (Levelmate_DB and Levelmate_DB.classicList)
    local lastZone
    -- Weitere Ziele derselben Quest stehen schon als Balken in der Karte
    local cur = from > 0 and list[from].act
    local curQ = cur and cur.kind == "DO" and cur.c and cur.c.q and cur.c.q.id
    if Levelmate_DB and Levelmate_DB.cardProgress == false then curQ = nil end
    for i = from + 1, #list do
        local e = list[i]
        if curQ and e.act and e.act.kind == "DO" and e.act.c and e.act.c.q and e.act.c.q.id == curQ then
            -- ueberspringen
        else
        local txt = ShortAction(e.act) or "?"
        local rgb = RGBOf(e.act)
        local lvl = (e.level ~= startLevel) and (L(" |cffffff00[Stufe ") .. e.level .. "]|r") or ""
        local mins = math.max(1, math.floor((e.seconds - base) / 60 + 0.5))
        if compact then
            if e.zone and e.zone ~= lastZone then
                table.insert(lines, "|cffffd100" .. e.zone .. "|r")
                lastZone = e.zone
            end
            local icon = KIND_ICON[e.act and e.act.kind or ""]
            if icon then txt = txt:gsub("^[^:]+: ", "", 1) end
            if e.act and e.act.c and e.act.c.q then txt = QLink(e.act.c.q.id, txt) end
            table.insert(lines, string.format("  %s %s%s|r%s |cff888888%d min|r",
                icon and ("|T" .. icon .. ":12:12|t") or Dot(rgb), Hex(rgb), txt, lvl, mins))
        else
            if e.act and e.act.c and e.act.c.q then txt = QLink(e.act.c.q.id, txt) end
            local zone = e.zone and (" |cff888888· " .. e.zone .. "|r") or ""
            local when = string.format(L(" |cff888888(~%d min)|r"), mins)
            table.insert(lines, string.format("%s |cffe6e6e6%s|r%s%s%s", Dot(rgb), txt, zone, lvl, when))
        end
        end
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
    -- Neu rechnen: keine passende Liste, aelter als 60 s, oder der aktuelle Schritt
    -- fehlt darin (dann aber hoechstens alle 15 s - sonst "wird berechnet" ohne Ende,
    -- wenn der Schritt in der Vorschau nie vorkommt, z. B. Lehrer oder Abgabe gerade erledigt).
    local fresh = previewRoute.list and previewRoute.mode == mode
    local age = now - previewRoute.time
    local stale = (not fresh) or age > 60 or (not from and age > 15)
    if stale and not previewRoute.busy then
        previewRoute.busy = true
        local started = now
        local function Done(list)
            previewRoute.busy = false
            if list then previewRoute.list, previewRoute.mode, previewRoute.time = list, mode, started
            else previewRoute.failed = started end
            if panel:IsShown() and currentAction and not CharDB().previewHidden then
                local k = Levelmate.Planner.ActionKey(currentAction)
                local f
                for i, e in ipairs(previewRoute.list or {}) do
                    if Levelmate.Planner.ActionKey(e.act) == k then f = i; break end
                end
                if previewRoute.list then
                    panel.previewText:SetText(PreviewLines(previewRoute.list, f or 0)); Layout()
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
    -- Liste da, aber der aktuelle Schritt kommt darin nicht vor: trotzdem zeigen
    if previewRoute.list and previewRoute.mode == mode then
        previewCache.text = PreviewLines(previewRoute.list, 0)
        return previewCache.text
    end
    if previewRoute.failed and now - previewRoute.failed < 30 then
        return L("|cff888888Reihenfolge gerade nicht berechenbar – nächster Versuch gleich.|r")
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
    Levelmate.Planner.lastSections = nil   -- nur die Abschnitte dieser Planung zeigen
    -- Fehler beim Anzeigen festhalten (fuer /lm bug) statt das Fenster stehen zu lassen
    local ok, err = xpcall(RefreshInner, function(e)
        return tostring(e) .. (debugstack and (" | " .. (debugstack(2, 3, 0) or ""):gsub("\n", " / ")) or "")
    end)
    if ok and Levelmate.QuestMobs then pcall(Levelmate.QuestMobs.Refresh) end
    if not ok then
        Levelmate.lastRefreshError = err
        -- nicht mit veraltetem Inhalt (z. B. "Questdaten werden geladen") stehen bleiben
        pcall(SetCard, L("Anzeigefehler"), L("Bitte /lm bug eingeben und den Bericht auf Discord schicken.")
            .. "\n|cff888888" .. tostring(err):sub(1, 120) .. "|r", nil, nil, { 1, 0.38, 0.38 }, true)
        if geterrorhandler then pcall(geterrorhandler(), err) end
    end
    if t0 then Levelmate.Perf.Add("refresh", debugprofilestop() - t0, refreshWhy or L("Zeit/Bewegung"), Levelmate.Planner.lastSections) end
    refreshWhy = nil
end
function Levelmate.SetRefreshReason(why) refreshWhy = why end
RefreshInner = function()
    -- Waehrend eines Fluges nicht umplanen (Zwischenlandungen wuerden die Route verwirren)
    -- und den Planungsort nicht merken - sonst wartete Levelmate nach der Landung
    -- bis zu 30 s, weil du dich "noch nicht bewegt" hattest.
    if not (Levelmate.Flag(UnitOnTaxi, false, "player")) then
        local p = Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
        Levelmate._lastPlanAt = { wx = p and p.wx, wy = p and p.wy, cont = p and p.cont, t = GetTime and GetTime() or 0 }
    end
    if Levelmate.Flag(UnitOnTaxi, false, "player") then
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
        -- neue Forever-Dungeons kennt die Instanz-Tabelle nicht: ueber den Namen
        if not instArea and Levelmate.DB.ForeverDungeonByName then instArea = Levelmate.DB.ForeverDungeonByName(name) end
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
        UpdateQuestRows(Levelmate.Planner.Last and Levelmate.Planner.Last())
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
    if not plan.error then pcall(AnnounceClassQuests, plan) end
    if Levelmate.UpdateItemButton then pcall(Levelmate.UpdateItemButton, currentAction) end
    -- Ab Stufe 40 ohne Reitfertigkeit: einmal je Sitzung an Reiten erinnern
    if not ridingHintShown and (UnitLevel("player") or 0) >= 40 and Levelmate.Planner.HasRidingSkill
       and not Levelmate.Planner.HasRidingSkill() and Levelmate_DB.ridingHint ~= false then
        ridingHintShown = true
        local _, cls = UnitClass("player")
        if cls == "WARLOCK" or cls == "PALADIN" then
            Print(L("Du kannst jetzt dein Klassenreittier bekommen (beim Klassenlehrer bzw. über die Klassenquest). Mit Reittier plant Levelmate schnellere Wege ein."))
        else
            Print(L("Du kannst jetzt reiten lernen. Mit Reittier plant Levelmate schnellere Wege ein (Reittier-Lehrer in deiner Hauptstadt)."))
        end
    end
    if Levelmate.UpdateDungeonFrame then pcall(Levelmate.UpdateDungeonFrame) end
    -- Story-Modus: Reihe ist grau geworden -> einmal fragen
    local ask = not plan.error and plan.greyChainAsk
    if ask and StaticPopup_Show and not greyAsked[ask.root] then
        greyAsked[ask.root] = true
        StaticPopup_Show("LEVELMATE_GREY_STORY", ask.name or "?", nil, ask.root)
    end

    if not pcall(UpdateBar, not plan.error and plan or nil) then pcall(UpdateBar, nil) end
    if plan.error then
        panel.zone:SetText(Levelmate.DB.Available() and "" or (L("Gebietshinweis: ") .. (Levelmate.Routes and Levelmate.Routes.GetHint(faction, UnitLevel("player") or 1) or "")))
        SetCard(plan.error, "", nil, nil, { 1, 0.38, 0.38 }, true)
        panel.previewText:SetText("")
        panel.nextText:SetText("")
        currentAction = nil
        Levelmate.Arrow.SetTarget(nil)
    else
        local okZ, zl = pcall(ZoneLine, plan)
        panel.zone:SetText(okZ and zl or "")
        local act = plan.actions[1]
        currentAction = act
        if act and Levelmate.Journal and Levelmate.Journal.Step and Levelmate.Planner.ActionKey then
            pcall(Levelmate.Journal.Step, act, Levelmate.Planner.ActionKey(act))
        end
        local okT, train = false, nil
        if Levelmate.Trainer and Levelmate.Trainer.Suggest then okT, train = pcall(Levelmate.Trainer.Suggest) end
        if not okT then train = nil end
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
            SetCardIcons(act, plan)
            local nxt = ShortAction(plan.actions[2])
            panel.nextText:SetText((nxt and CharDB().previewHidden) and (L("Danach: ") .. nxt) or "")
            -- Pfeil: Endziel + Zwischenziel (Uebergang / bekannter Weg). Das
            -- Zwischenziel wird laufend neu bestimmt, waehrend du dich bewegst.
            local finalTarget, finalName = act.target, act.targetName
            do
                -- Nummern auf der Weltkarte: echte Reihenfolge aus der Routenvorschau
                -- (ab dem aktuellen Schritt), sonst die bestbewerteten Schritte
                local steps = {}
                local pl = previewRoute.list
                local from
                if pl then
                    local key = Levelmate.Planner.ActionKey(act)
                    for i, e in ipairs(pl) do if Levelmate.Planner.ActionKey(e.act) == key then from = i; break end end
                end
                if from then
                    for i = from, math.min(#pl, from + 7) do
                        if pl[i].act and pl[i].act.target then steps[#steps + 1] = { target = pl[i].act.target } end
                    end
                else
                    for i = 1, 4 do
                        local a2 = plan.actions[i]
                        if not a2 then break end
                        steps[#steps + 1] = { target = a2.target }
                    end
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
                -- Aufgang (Rampe/Aufzug/Bruecke) zum Ziel bekannt? Dann ihm folgen.
                local awp, akind = Levelmate.Travel.AccessWaypoint and Levelmate.Travel.AccessWaypoint(here, finalTarget)
                if awp then
                    return awp, (akind == "start" and L("Zum Aufgang (") or L("Aufgang hinauf (")) .. (finalName or "?") .. ")", "trail"
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

    Levelmate.Perf.Time("rows", UpdateQuestRows, plan)
    Levelmate.CheckDungeonReady()

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
-- Gerade beschaeftigt (Kampf, Looten, kurz nach dem Kampf)? Dann keine schwere
-- Rechnung - genau dann fallen kleine Hänger am meisten auf.
function Levelmate.Busy()
    if Levelmate.InCombat() then return true end
    if LootFrame and LootFrame.IsShown and LootFrame:IsShown() then return true end
    local now = GetTime and GetTime() or 0
    if now - (Levelmate._combatEndAt or -100) < 4 then return true end
    return false
end
function Levelmate.RequestRefresh(now, delay)
    if not panel:IsShown() then return end
    -- Im Kampf gar nicht neu planen (jeder Treffer/Kill loest Updates aus und die
    -- Rechnung ruckelt genau dann). Nach dem Kampf einmal nachholen.
    if not now and Levelmate.InCombat() then
        Levelmate._combatRefresh = true
        return
    end
    if now or not (C_Timer and C_Timer.After) then Refresh(); return end
    if pending then return end
    pending = true
    local function Fire()
        pending = false
        if not panel:IsShown() then return end
        if Levelmate.InCombat() then Levelmate._combatRefresh = true; return end
        if Levelmate.Busy() then pending = true; C_Timer.After(0.5, Fire); return end
        Refresh()
    end
    C_Timer.After(delay or 0.3, Fire)
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
    -- Von dir zuerst gewaehlt (/lm zuerst oder Dungeon-Fenster): Spaeter/Ueberspringen hebt das auf
    local P = Levelmate.Planner
    if P.forceQuest and act and act.c and act.c.q and act.c.q.id == P.forceQuest then
        P.forceQuest, P.forceAccept = nil, nil
    end
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
        Levelmate.Smart.SetDeferred(act.c.q.id, true, perm, act.kind)
        table.insert(CharDB().skipStack, act.c.q.id)
        if perm then
            Print(L("Übersprungen: ") .. QuestName(act.c) .. L(" – kommt nicht mehr in die Route (der Pfeil holt sie zurück)."))
        else
            Print(L("Auf später verschoben: ") .. QuestName(act.c) .. L(" – kommt nach einem halben Level wieder (der Pfeil holt sie sofort zurück)."))
        end
    elseif act and act.group then
        -- "Jetzt hin" aus dem Dungeon-Fenster fuer diesen Dungeon aufheben, sonst bleibt er oben
        local go = CharDB().dungeonGo
        if go and act.group.area and Levelmate.DB.SameDungeon(go.area, act.group.area) then CharDB().dungeonGo = nil end
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
-- /lm bug: Fehlerbericht zum Kopieren (unter 2000 Zeichen fuer Discord).
-- Enthaelt keinen Charakter- oder Realmnamen.
---------------------------------------------------------------------------
local function BugMapName(map)
    local info = map and C_Map and C_Map.GetMapInfo and select(2, pcall(C_Map.GetMapInfo, map))
    return (type(info) == "table" and info.name) or tostring(map or "?")
end
local function BugPoint(p)
    if not p or not p.map then return "-" end
    return string.format("%s(%d) %.1f,%.1f", BugMapName(p.map), p.map, p.x or 0, p.y or 0)
end
function Levelmate.BugReport()
    local P = Levelmate.Planner
    local plan = P.Last()
    local lines = {}
    local function add(s) lines[#lines + 1] = s end
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    local build = GetBuildInfo and GetBuildInfo() or "?"
    local qdb = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("QuestieDB", "Version")
    add(string.format("Levelmate-Bug %s | WoW %s | %s | QuestieDB %s", Levelmate.version, tostring(build),
        GetLocale and GetLocale() or "?", Levelmate.DB.Available() and tostring(qdb or "?") or "-"))
    local xp, xpMax = UnitXP and UnitXP("player") or 0, UnitXPMax and UnitXPMax("player") or 1
    add(string.format("Char: L%d (%d%%) %s %s %s | Modus: %s", UnitLevel("player") or 0,
        math.floor(xp / math.max(1, xpMax) * 100), tostring(race), tostring(class),
        tostring(UnitFactionGroup("player")), tostring(CharDB().mode)))
    local here = P.PlayerPoint and P.PlayerPoint()
    local speed = P.WalkSpeed and P.WalkSpeed() or 0
    add(string.format("Ort: %s | Ruhestein: %s | Tempo %.1f%s", BugPoint(here),
        Levelmate.Travel.HearthName and Levelmate.Travel.HearthName() or "?", speed,
        (Levelmate.Flag(IsMounted, false)) and " (Reittier)" or ""))
    local live = Q.GetList()
    local ready = 0
    for _, lq in ipairs(live) do if lq.status == Q.STATUS_READY then ready = ready + 1 end end
    add(string.format("Questlog: %d (%d fertig) | Addons: TomTom %s, OpenMap %s", #live, ready,
        TomTom and "ja" or "nein", OpenMapAPI and "ja" or "nein"))
    if not plan or plan.error then
        add("Plan: " .. tostring(plan and plan.error or "noch keiner"))
    else
        add(string.format("Plan: %d Schritte, Ø %.0f XP/min", #plan.actions, plan.referenceXPPerMin or 0))
        for i = 1, math.min(5, #plan.actions) do
            local a = plan.actions[i]
            local id = a.c and a.c.q and a.c.q.id
            add(string.format("%d. %s%s -> %s | %.0fs %.0fXP/min s=%.3g%s", i, ShortAction(a) or "?",
                id and (" [" .. id .. "]") or "", BugPoint(a.target), a.seconds or 0, a.xpPerMin or 0,
                a.score or 0, a.pen and (" |" .. a.pen) or ""))
        end
        if plan.skipped and #plan.skipped > 0 then
            local sk = {}
            for i = 1, math.min(6, #plan.skipped) do
                local c = plan.skipped[i]
                if c.q then sk[#sk + 1] = string.format("[%d] %s", c.q.id, tostring(c.skipReason or "?")) end
            end
            add("Ausgelassen: " .. table.concat(sk, "; "))
        end
    end
    if Levelmate.Smart and Levelmate.Smart.DeferredList then
        local later, perm = Levelmate.Smart.DeferredList()
        local function ids(t) local o = {} for i = 1, math.min(12, #t) do o[i] = tostring(t[i]) end
            return table.concat(o, ",") .. (#t > 12 and ",…" or "") end
        if #later > 0 or #perm > 0 then
            add(string.format("Später: %s | Übersprungen: %s", #later > 0 and ids(later) or "-", #perm > 0 and ids(perm) or "-"))
        end
    end
    if P.lastPreviewError then add("Vorschau-Fehler: " .. P.lastPreviewError:sub(1, 200)) end
    if Levelmate.lastRefreshError then add("Anzeige-Fehler: " .. tostring(Levelmate.lastRefreshError):sub(1, 300)) end
    if P.PoolState then add("Pool: " .. P.PoolState() .. " | Fenster: " .. (panel:IsShown() and "an" or "aus")
        .. " | Karte: " .. tostring(panel.stepTitle and panel.stepTitle:GetText() or "?"):sub(1, 60)) end
    -- Questlog zuletzt: wird gekuerzt, damit alles unter 2000 Zeichen bleibt
    local head = table.concat(lines, "\n")
    local budget = 1900 - #head - 12
    local parts = {}
    for _, lq in ipairs(live) do
        local st = lq.status == Q.STATUS_READY and "+" or (lq.status == Q.STATUS_FAILED and "x" or "-")
        local open = ""
        if lq.status ~= Q.STATUS_READY then
            for _, o in ipairs(lq.objectives or {}) do
                if not o.done and o.need then open = open .. string.format(" %s/%s", tostring(o.have or 0), tostring(o.need)) end
            end
        end
        local item = string.format("%s%d%s", st, lq.questID, open)
        if budget - #item - 2 < 0 then parts[#parts + 1] = "…"; break end
        budget = budget - #item - 2
        parts[#parts + 1] = item
    end
    if #parts > 0 then head = head .. "\nLog: " .. table.concat(parts, ", ") end
    if #head > 1990 then head = head:sub(1, 1990) end
    return head
end

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
        Levelmate_DB.dungeonPos = nil; Levelmate_DB.dungeonSize = nil; if Levelmate.AnchorDungeonFrame then Levelmate.AnchorDungeonFrame() end
        panel:SetScale(1)
        AnchorPanel(); Levelmate.Arrow.Restore()
        Print(L("Übersprungene Quests und Fensterpositionen zurückgesetzt."))
        Refresh()
    elseif cmd == "gruppe" or cmd == "group" then
        local G = Levelmate.Group
        if not (IsInGroup and IsInGroup()) then
            Print(L("Gruppenmodus: Du bist in keiner Gruppe."))
        elseif not (G and G.Active and G.Active()) then
            Print(L("Gruppenmodus: Noch keine Daten von Mitspielern – haben sie Levelmate (ab 1.0.8)? Abgleich alle paar Sekunden."))
        else
            for name, m in pairs(G.members) do
                local n, shared = 0, 0
                local mine = {}
                for _, lq in ipairs(Levelmate.Quests.GetList() or {}) do mine[lq.questID] = true end
                for id in pairs(m.quests or {}) do n = n + 1; if mine[id] then shared = shared + 1 end end
                Print(string.format(L("Gruppenmodus: %s (Stufe %s) – %d Quests, %d gemeinsam mit dir"),
                    name, tostring(m.level or "?"), n, shared))
            end
        end
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
    elseif cmd:match("^zuerst") or cmd:match("^first") then
        local arg = (msg or ""):match("^%S+%s+(.+)$")
        local P = Levelmate.Planner
        if not arg then
            P.forceQuest, P.forceAccept = nil, nil
            Print(L("Normale Reihenfolge wiederhergestellt."))
        else
            local id = tonumber(arg)
            if not id then
                local needle = string.lower(arg)
                for _, lq in ipairs(Q.GetList()) do
                    if string.lower(lq.title or ""):find(needle, 1, true) then id = lq.questID; break end
                end
            end
            if id then
                P.forceQuest, P.forceAccept = id, nil
                local q = Levelmate.DB.Quest(id)
                Print(L("Zuerst: ") .. (q and q.name or tostring(id)) .. L(" – zurück mit /lm zuerst"))
            else
                Print(L("Keine passende Quest im Questlog. Beispiel: /lm zuerst Foliant"))
            end
        end
        Levelmate.RequestRefresh(true)
    elseif cmd == "aufgang" or cmd == "ascent" then
        local r, n = Levelmate.Travel.AccessRecord()
        if r == "start" then
            Print(L("Aufgang wird aufgezeichnet: Lauf jetzt den Weg nach oben bis zum Ziel und gib dort nochmal /lm aufgang ein."))
        elseif r == "saved" then
            Print(string.format(L("Aufgang gespeichert (%d Punkte). Ziele dort oben führt der Pfeil jetzt über diesen Weg. Mit /lm export kannst du ihn teilen."), n))
            Levelmate.RequestRefresh(true)
        elseif r == "short" then
            Print(L("Aufzeichnung verworfen – zu kurz. Unten starten, oben beenden."))
        else
            Print(L("Position unbekannt – hier kann nichts aufgezeichnet werden."))
        end
    elseif cmd == "aufgang löschen" or cmd == "aufgang loeschen" or cmd == "ascent delete" then
        local n = Levelmate.Travel.AccessDeleteNear()
        Print(string.format(L("%d Aufgang/Aufgänge in deiner Nähe gelöscht."), n))
        Levelmate.RequestRefresh(true)
    elseif cmd == "bug" or cmd == "fehler" or cmd == "report" then
        Levelmate.Export.ShowText(L("Fehlerbericht"), Levelmate.BugReport(),
            L("Mit Strg+C kopieren und zusammen mit einer kurzen Beschreibung (was ist passiert, was hättest du erwartet?) auf Discord schicken. Enthält keinen Charakternamen."))
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
        Print(L("Befehle: /lm | optionen | wege | export | import | aufgang | bug | hide | mode | arrow | tomtom | minimap | scale 0.8 | reset | smart | diag | lehrer | warum <Quest> | gruppe | sitzung | tipps"))
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, event in ipairs({
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "ZONE_CHANGED_NEW_AREA", "TAXIMAP_OPENED",
    "LEARNED_SPELL_IN_TAB", "TRAINER_CLOSED", "CHARACTER_POINTS_CHANGED", "PLAYER_CONTROL_GAINED",
}) do
    SafeRegister(events, event)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_CONTROL_GAINED" then
        -- Landung nach einem Flug: Route direkt fortsetzen
        if panel.onTaxi and C_Timer and C_Timer.After then
            C_Timer.After(0.5, function() if panel.onTaxi then Levelmate.RequestRefresh(true) end end)
        end
        return
    end
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
                -- gerade gelandet: sofort weiter
                if panel.onTaxi and not (Levelmate.Flag(UnitOnTaxi, false, "player")) then Refresh(); return end
                local fighting = Levelmate.InCombat()
                if fighting or Levelmate.Busy() then return end
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
        -- "Zuerst" aus dem Dungeon-Fenster galt nur dem Abholen: angenommen -> normal weiter
        local P = Levelmate.Planner
        if P.forceAccept and P.forceQuest == arg1 then P.forceQuest, P.forceAccept = nil, nil end
    elseif event == "QUEST_TURNED_IN" then
        Levelmate.Smart.OnQuestTurnedIn(arg1, arg2)
        Levelmate.Planner.MarkDone(arg1)
        if Levelmate.Planner.forceQuest == arg1 then Levelmate.Planner.forceQuest = nil end
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
    if (event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "ZONE_CHANGED_NEW_AREA")
       and Levelmate.Planner.InvalidateWaypoints then
        Levelmate.Planner.InvalidateWaypoints()
    end
    if event == "QUEST_LOG_UPDATE" then Levelmate.RequestRefresh(false, 2.0) else Levelmate.RequestRefresh() end
end)

AnchorPanel()
