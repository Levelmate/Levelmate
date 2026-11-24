-- Options.lua
-- Einstellungsfenster (Zahnrad oben rechts im Hauptfenster oder /lm optionen).
-- Aufbau (1.1.0): Seitenleiste links mit den Bereichen, rechts Kaesten mit
-- An/Aus-Schaltern und Reglern. Alle Einstellungen gelten fuer alle Charaktere.
Levelmate = Levelmate or {}
Levelmate.Options = Levelmate.Options or {}
local O = Levelmate.Options
local L = Levelmate.L

local WHITE = "Interface/Buttons/WHITE8X8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"   -- weisser Kreis
local GOLD = { 1, 0.82, 0 }
local BORDER = { 0.79, 0.60, 0.23 }
local SIDE_W, CONTENT_W = 138, 340
local CARD_W = CONTENT_W - 24

-- Texte, die beim Oeffnen in der gewaehlten Sprache neu gesetzt werden
local texts = {}
local function Txt(fs, raw) fs.raw = raw; fs:SetText(raw); texts[#texts + 1] = fs end

local function Refresh()
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
end

local function Tex(parent, layer, r, g, b, a, file)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(file or WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end

local function ShowTip(owner, text)
    if not text then return end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(L(text), 1, 1, 1, 1, true)
    GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------------
local frame = CreateFrame("Frame", "LevelmateOptionsFrame", UIParent, "BackdropTemplate")
frame:SetSize(SIDE_W + CONTENT_W, 460)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
frame:SetBackdropColor(0.035, 0.055, 0.12, 0.97)
frame:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.9)
frame:Hide()
frame:SetScript("OnHide", function() if O.ApplyPending then O.ApplyPending() end end)
if UISpecialFrames then table.insert(UISpecialFrames, "LevelmateOptionsFrame") end  -- ESC schliesst

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetSize(24, 24)
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)

-- Seitenleiste
local side = CreateFrame("Frame", nil, frame)
side:SetPoint("TOPLEFT", 1, -1)
side:SetPoint("BOTTOMLEFT", 1, 1)
side:SetWidth(SIDE_W)
local sideBg = Tex(side, "BACKGROUND", 0.016, 0.027, 0.07, 0.95)
sideBg:SetAllPoints()
local sideLine = Tex(side, "BORDER", BORDER[1], BORDER[2], BORDER[3], 0.35)
sideLine:SetPoint("TOPRIGHT"); sideLine:SetPoint("BOTTOMRIGHT"); sideLine:SetWidth(1)

local logo = side:CreateTexture(nil, "ARTWORK")
logo:SetTexture("Interface\\AddOns\\Levelmate\\Media\\Logo")
logo:SetSize(26, 26)
logo:SetPoint("TOPLEFT", 12, -12)
local brand = side:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
brand:SetPoint("TOPLEFT", logo, "TOPRIGHT", 6, 1)
brand:SetText("Levelmate")
brand:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
local ver = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
ver:SetPoint("TOPLEFT", brand, "BOTTOMLEFT", 0, -1)
ver:SetText("Version " .. tostring(Levelmate.version or ""))

---------------------------------------------------------------------------
-- Bereiche (Seiten) und Navigation
---------------------------------------------------------------------------
local pages, navs = {}, {}
local page, y
local function SelectPage(p)
    for _, x in ipairs(pages) do x:SetShown(x == p) end
    for _, n in ipairs(navs) do
        local on = n.page == p
        n.bg:SetShown(on); n.bar:SetShown(on)
        n.label:SetTextColor(on and GOLD[1] or 0.72, on and GOLD[2] or 0.72, on and GOLD[3] or 0.72)
        n.icon:SetDesaturated(not on)
        n.icon:SetAlpha(on and 1 or 0.7)
    end
    frame.current = p
end

local function NewPage(key, label, icon, subtitle)
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_W + 1, 0)
    p:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    p:Hide()
    p.key = key
    pages[#pages + 1] = p
    local head = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 12, -14)
    head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    Txt(head, label)
    local sub = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -3)
    Txt(sub, subtitle)

    local n = CreateFrame("Button", nil, side)
    n:SetSize(SIDE_W - 1, 26)
    n:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -54 - (#pages - 1) * 28)
    n.bg = Tex(n, "BACKGROUND", BORDER[1], BORDER[2], BORDER[3], 0.16); n.bg:SetAllPoints()
    n.bar = Tex(n, "ARTWORK", GOLD[1], GOLD[2], GOLD[3], 1)
    n.bar:SetPoint("TOPLEFT"); n.bar:SetPoint("BOTTOMLEFT"); n.bar:SetWidth(2)
    local hl = Tex(n, "HIGHLIGHT", 1, 1, 1, 0.06); hl:SetAllPoints()
    n.icon = n:CreateTexture(nil, "ARTWORK")
    n.icon:SetTexture(icon)
    n.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    n.icon:SetSize(16, 16)
    n.icon:SetPoint("LEFT", 12, 0)
    n.label = n:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    n.label:SetPoint("LEFT", n.icon, "RIGHT", 8, 0)
    Txt(n.label, label)
    n.page = p
    n:SetScript("OnClick", function() SelectPage(p) end)
    navs[#navs + 1] = n

    page, y = p, -50
    return p
end

---------------------------------------------------------------------------
-- Bausteine: Kasten, Schalter, Regler, Knopf
---------------------------------------------------------------------------
local card
local function Card(title)
    local c = CreateFrame("Frame", nil, page, "BackdropTemplate")
    c:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    c:SetWidth(CARD_W)
    c:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    c:SetBackdropColor(0.08, 0.105, 0.19, 0.95)
    c:SetBackdropBorderColor(0.165, 0.19, 0.28, 1)
    local t = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", 10, -8)
    t:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    Txt(t, title)
    c.top, c.y = y, -24
    card = c
    return c
end
local function EndCard()
    local h = -card.y + 6
    card:SetHeight(h)
    y = card.top - h - 8
    card = nil
end

-- Pillen-Form aus zwei Kreisen und einem Rechteck
local function Pill(parent, w, h, layer)
    local parts = {}
    local l = parent:CreateTexture(nil, layer); l:SetTexture(ROUND); l:SetSize(h, h); l:SetPoint("LEFT")
    local r = parent:CreateTexture(nil, layer); r:SetTexture(ROUND); r:SetSize(h, h); r:SetPoint("RIGHT")
    local m = parent:CreateTexture(nil, layer); m:SetTexture(WHITE)
    m:SetPoint("TOPLEFT", h / 2, 0); m:SetPoint("BOTTOMRIGHT", -h / 2, 0)
    parts[1], parts[2], parts[3] = l, r, m
    return function(cr, cg, cb, ca) for _, p in ipairs(parts) do p:SetVertexColor(cr, cg, cb, ca or 1) end end
end

local toggles = {}
local function Toggle(label, hint, get, set)
    local row = CreateFrame("Button", nil, card)
    row:SetPoint("TOPLEFT", card, "TOPLEFT", 6, card.y)
    row:SetSize(CARD_W - 12, 24)
    local hl = Tex(row, "HIGHLIGHT", 1, 1, 1, 0.04); hl:SetAllPoints()
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", 4, 0)
    text:SetPoint("RIGHT", -40, 0)
    text:SetJustifyH("LEFT")
    Txt(text, label)
    row.info = false
    if hint then
        local i = CreateFrame("Frame", nil, row)
        i:SetSize(12, 12)
        local dot = i:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(ROUND); dot:SetAllPoints(); dot:SetVertexColor(0.35, 0.38, 0.5, 1)
        local q = i:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        q:SetPoint("CENTER", 0, 0); q:SetText("?")
        i:SetAlpha(0.55)
        i:SetPoint("LEFT", text, "LEFT", math.min(text:GetStringWidth() or 0, CARD_W - 70) + 4, 0)
        row.info = i
    end
    local sw = CreateFrame("Frame", nil, row)
    sw:SetSize(28, 14)
    sw:SetPoint("RIGHT", -4, 0)
    local paint = Pill(sw, 28, 14, "ARTWORK")
    local knob = sw:CreateTexture(nil, "OVERLAY")
    knob:SetTexture(ROUND)
    knob:SetSize(10, 10)
    row.enabled = true
    row.Paint = function()
        local on = row.value
        if on then paint(0.23, 0.54, 0.24, 1) else paint(0.23, 0.25, 0.31, 1) end
        knob:ClearAllPoints()
        knob:SetPoint(on and "RIGHT" or "LEFT", sw, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
        knob:SetVertexColor(0.95, 0.95, 0.95, 1)
        row:SetAlpha(row.enabled and 1 or 0.4)
    end
    row.Load = function() row.value = get() and true or false; row.Paint() end
    row.SetEnabled = function(self, e) self.enabled = e and true or false; self.Paint() end
    row:SetScript("OnClick", function(self)
        if not self.enabled then return end
        self.value = not self.value
        self.Paint()
        set(self.value)
        Refresh()
    end)
    row:SetScript("OnEnter", function(self)
        if self.info then self.info:SetAlpha(1) end
        ShowTip(self, hint)
    end)
    row:SetScript("OnLeave", function(self)
        if self.info then self.info:SetAlpha(0.55) end
        GameTooltip:Hide()
    end)
    -- Info-Symbol erst nach dem Sprachwechsel richtig platzieren
    row.Relayout = function()
        if row.info then
            row.info:ClearAllPoints()
            row.info:SetPoint("LEFT", text, "LEFT", math.min(text:GetStringWidth() or 0, CARD_W - 70) + 4, 0)
        end
    end
    card.y = card.y - 25
    toggles[#toggles + 1] = row
    return row
end

local function Slider(minV, maxV, step, hint)
    local label = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("TOPLEFT", card, "TOPLEFT", 10, card.y - 4)
    local val = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, card.y - 4)
    val:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local sl = CreateFrame("Slider", nil, card)
    sl:SetOrientation("HORIZONTAL")
    sl:SetSize(CARD_W - 24, 14)
    sl:SetPoint("TOPLEFT", card, "TOPLEFT", 12, card.y - 22)
    local track = Tex(sl, "BACKGROUND", 0.165, 0.19, 0.28, 1)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetHeight(4)
    local fill = Tex(sl, "BORDER", BORDER[1], BORDER[2], BORDER[3], 1)
    fill:SetPoint("LEFT"); fill:SetHeight(4)
    sl:SetThumbTexture(ROUND)
    local th = sl:GetThumbTexture()
    if th then th:SetSize(12, 12); th:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) end
    sl:SetMinMaxValues(minV, maxV)
    sl:SetValueStep(step)
    if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end
    sl.label, sl.val = label, val
    sl.UpdateFill = function(v)
        local w = (CARD_W - 24) * ((v - minV) / math.max(1, maxV - minV))
        fill:SetWidth(math.max(1, w))
    end
    if hint then
        local h = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", card, "TOPLEFT", 10, card.y - 40)
        h:SetWidth(CARD_W - 20)
        h:SetJustifyH("LEFT")
        Txt(h, hint)
        card.y = card.y - 26
    end
    card.y = card.y - 44
    return sl
end

-- Flacher Knopf mit Goldrand (selected = gefuellt)
local flatButtons = {}
local function FlatButton(parent, label, w, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.raw, b.tip, b.selected = label, false, false
    b.SetSelected = function(self, on)
        self.selected = on
        if on then
            self:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.95)
            self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
            self.text:SetTextColor(0.04, 0.06, 0.12)
        else
            self:SetBackdropColor(0, 0, 0, 0)
            self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.6)
            self.text:SetTextColor(0.85, 0.85, 0.85)
        end
    end
    b:SetScript("OnEnter", function(self) if not self.selected then self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.18) end; if self.tip then ShowTip(self, self.tip) end end)
    b:SetScript("OnLeave", function(self) if not self.selected then self:SetBackdropColor(0, 0, 0, 0) end; GameTooltip:Hide() end)
    b:SetScript("OnClick", onClick)
    b:SetSelected(false)
    flatButtons[#flatButtons + 1] = b
    return b
end
local function CardButton(label, w, onClick)
    local b = FlatButton(card, label, w, onClick)
    b:SetPoint("TOPLEFT", card, "TOPLEFT", 10, card.y - 2)
    card.y = card.y - 30
    return b
end

---------------------------------------------------------------------------
-- Allgemein
---------------------------------------------------------------------------
NewPage("general", "Allgemein", "Interface\\Icons\\INV_Misc_Gear_01", "Grundeinstellungen und Sprache")
Card("Klassenquests")
Toggle("|cffb070ffKlassenquests anzeigen|r", "lila markiert und bevorzugt eingeplant (Zauber, Begleiter)",
    function() return Levelmate_DB.classQuests ~= false end,
    function(v) Levelmate_DB.classQuests = v; if Levelmate.Planner.BuildPool then Levelmate.Planner.BuildPool(Refresh) end end)
Toggle("Hinweis im Chat bei neuer Klassenquest", nil,
    function() return Levelmate_DB.classNotify ~= false end,
    function(v) Levelmate_DB.classNotify = v end)
EndCard()
Card("Meldungen")
Toggle("Meldung beim Stufenaufstieg", "kurzes Fenster: neue Zauber, passende Gebiete",
    function() return Levelmate_DB.levelToast ~= false end,
    function(v) Levelmate_DB.levelToast = v and true or false end)
Toggle("Rückblick beim Einloggen", "Stufen, Quests und XP pro Stunde der letzten Sitzung",
    function() return Levelmate_DB.sessionSummary ~= false end,
    function(v) Levelmate_DB.sessionSummary = v and true or false end)
EndCard()
Card("Sprache")
local langButtons = {}
local LANGS = { { key = "auto", text = "Automatisch" }, { key = "de", text = "Deutsch" }, { key = "en", text = "English" } }
local function MarkLanguage()
    local cur = (Levelmate_DB and Levelmate_DB.language) or "auto"
    for _, b in ipairs(langButtons) do b:SetSelected(b.key == cur) end
end
local LW = math.floor((CARD_W - 20 - 12) / 3)
for i, lang in ipairs(LANGS) do
    local b = FlatButton(card, lang.text, LW, function()
        Levelmate_DB.language = lang.key
        O.Load()
        if Levelmate.OnLanguageChanged then Levelmate.OnLanguageChanged() end
    end)
    b:SetPoint("TOPLEFT", card, "TOPLEFT", 10 + (i - 1) * (LW + 6), card.y - 2)
    b.key = lang.key
    langButtons[#langButtons + 1] = b
end
card.y = card.y - 30
EndCard()
Card("Hilfe")
CardButton("Einführung nochmal zeigen", 190, function()
    frame:Hide(); if Levelmate.ShowTips then Levelmate.ShowTips(true) end
end)
EndCard()

---------------------------------------------------------------------------
-- Route
---------------------------------------------------------------------------
NewPage("route", "Route", "Interface\\Icons\\INV_Misc_Map_01", "Wie Levelmate deine Quests plant")
Card("Planung")
Toggle("Ruhestein einplanen", "wenn er bereit ist und viel Weg spart",
    function() return Levelmate_DB.useHearth ~= false end,
    function(v) Levelmate_DB.useHearth = v end)
Toggle("Lange Sammelquests auslassen", "Quests mit seltenen Drops und über 45 min Arbeit nicht vorschlagen",
    function() return Levelmate_DB.skipLongCollect end,
    function(v) Levelmate_DB.skipLongCollect = v and true or nil; if Levelmate.Refresh then Levelmate.Refresh() end end)
local tomtom = Toggle("TomTom-Wegpunkte setzen", "nur wenn das Addon TomTom installiert ist",
    function() return Levelmate_DB.useTomTom end,
    function(v) Levelmate_DB.useTomTom = v end)
EndCard()
Card("Schwierigkeit")
local danger = Slider(3, 12, 1, "Ziele in so hohen Gebieten werden nur noch zuletzt vorgeschlagen")
Txt(danger.label, "Gefährliches Gebiet ab")
local function DangerText(v)
    danger.val:SetText(string.format(L("+%d Stufen"), v))
    danger.UpdateFill(v)
end
danger:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    DangerText(v)
    if not frame.loading then O.SetPending("danger", v) end
end)
local maxAbove = Slider(0, 4, 1, "0 = nur Quests bis zu deiner Stufe, 2 = Standard (gelb/orange), 4 = mutig (rot)")
Txt(maxAbove.label, "Quests annehmen bis")
local function MaxText(v)
    maxAbove.val:SetText(string.format(L(v == 1 and "+%d Stufe" or "+%d Stufen"), v))
    maxAbove.UpdateFill(v)
end
maxAbove:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    MaxText(v)
    if not frame.loading then O.SetPending("maxAbove", v) end
end)
-- Diese beiden Regler planen die ganze Route neu. Damit das Ziehen nicht ruckelt,
-- gelten sie erst nach "Übernehmen" (oder beim Schliessen des Fensters).
local pending = {}
local applyBtn = CardButton("Übernehmen", 130, function() O.ApplyPending() end)
local applyState = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
applyState:SetPoint("LEFT", applyBtn, "RIGHT", 10, 0)
applyState:SetPoint("RIGHT", card, "RIGHT", -10, 0)
applyState:SetJustifyH("LEFT")
local function UpdateApply()
    local any = next(pending) ~= nil
    applyBtn:SetSelected(any)
    applyBtn:SetAlpha(any and 1 or 0.5)
    applyState:SetText(any and ("|cffff9933" .. L("Noch nicht übernommen") .. "|r") or "")
end
function O.SetPending(key, v)
    local cur = key == "danger" and Levelmate.Planner.DangerLevels()
        or ((Levelmate.Planner.MaxLevelAbove and Levelmate.Planner.MaxLevelAbove()) or 2)
    if v == cur then pending[key] = nil else pending[key] = v end
    UpdateApply()
end
function O.ApplyPending()
    if not next(pending) then return end
    if pending.danger then Levelmate_DB.dangerLevels = pending.danger end
    local rebuild = pending.maxAbove ~= nil
    if rebuild then Levelmate_DB.maxLevelAbove = pending.maxAbove end
    pending = {}
    UpdateApply()
    if rebuild and Levelmate.Planner.BuildPool then
        Levelmate.Planner.BuildPool(function() if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end end)
    end
    Refresh()
end
O.ClearPending = function() pending = {}; UpdateApply() end
EndCard()

---------------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------------
NewPage("display", "Anzeige", "Interface\\Icons\\INV_Misc_Spyglass_03", "Wie Levelmate aussieht")
Card("Fenster")
Toggle("Fenster sperren", "Levelmate- und Dungeon-Fenster nicht verschieben (auch Schloss oben im Fenster)",
    function() return Levelmate_DB.locked end,
    function(v) Levelmate_DB.locked = v or nil; if Levelmate.UpdateHeaderButtons then Levelmate.UpdateHeaderButtons() end end)
Toggle("Nächste Schritte nach Gebiet ordnen", "mit Symbolen statt \"Annehmen:/Abgeben:\"",
    function() return not Levelmate_DB.classicList end,
    function(v) Levelmate_DB.classicList = (not v) or nil; if Levelmate.Refresh then Levelmate.Refresh() end end)
Toggle("Fortschrittsbalken auf der Karte", "z. B. 7/12 bei \"Erledigen\"",
    function() return Levelmate_DB.cardProgress ~= false end,
    function(v) Levelmate_DB.cardProgress = v and true or false; if Levelmate.Refresh then Levelmate.Refresh() end end)
Toggle("Questgegenstände im Questlog zeigen", "Symbol bei der Quest im Levelmate-Fenster, anklicken zum Benutzen",
    function() return Levelmate_DB.itemButton ~= false end,
    function(v) Levelmate_DB.itemButton = v and true or false; if Levelmate.Refresh then Levelmate.Refresh() end end)
EndCard()
Card("Karte und Hilfen")
Toggle("Zielpfeil anzeigen", nil,
    function() return not Levelmate_DB.arrowHidden end,
    function(v) if v == (Levelmate_DB.arrowHidden and true or false) then Levelmate.Arrow.Toggle() end end)
Toggle("Route auf der Weltkarte zeigen", "Linie zum Ziel und nummerierte nächste Schritte (auch /lm karte)",
    function() return Levelmate_DB.mapRoute ~= false end,
    function(v) Levelmate_DB.mapRoute = v and true or false; if Levelmate.Arrow.RefreshMap then Levelmate.Arrow.RefreshMap() end end)
Toggle("Levelmate im Tooltip von NPCs", "zeigt, wenn ein NPC in deiner Route vorkommt",
    function() return Levelmate_DB.npcTooltip ~= false end,
    function(v) Levelmate_DB.npcTooltip = v and true or false end)
Toggle("Minimap-Knopf anzeigen", nil,
    function() return not Levelmate_DB.minimapHidden end,
    function(v) Levelmate_DB.minimapHidden = not v; if Levelmate.Minimap then Levelmate.Minimap.Update() end end)
EndCard()
Card("Aussehen")
local scale = Slider(50, 150, 5)
Txt(scale.label, "Fenstergröße")
local function ScaleText(v) scale.val:SetText(v .. " %"); scale.UpdateFill(v) end
scale:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 5 + 0.5) * 5
    ScaleText(v)
    if not frame.loading then
        Levelmate_DB.scale = v / 100
        if LevelmateQuestPanel then LevelmateQuestPanel:SetScale(Levelmate_DB.scale) end
    end
end)
local alpha = Slider(30, 100, 5)
Txt(alpha.label, "Hintergrund")
local function AlphaText(v) alpha.val:SetText(v .. " %"); alpha.UpdateFill(v) end
alpha:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 5 + 0.5) * 5
    AlphaText(v)
    if not frame.loading then
        Levelmate_DB.bgAlpha = v / 100
        if Levelmate.ApplyBackground then Levelmate.ApplyBackground() end
    end
end)
EndCard()

---------------------------------------------------------------------------
-- Gruppe
---------------------------------------------------------------------------
NewPage("group", "Gruppe", "Interface\\Icons\\Ability_Warrior_BattleShout", "Zusammen mit Freunden leveln")
Card("Gruppenmodus")
Toggle("Gruppenmodus", "Questlogs mit Mitspielern abgleichen, die auch Levelmate haben; gemeinsame Quests zuerst",
    function() return not Levelmate_DB.groupOff end,
    function(v) Levelmate_DB.groupOff = (not v) or nil
        if not v and Levelmate.Group then Levelmate.Group.members = {} end
        if Levelmate.Refresh then Levelmate.Refresh() end end)
local groupHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
groupHint:SetPoint("TOPLEFT", card, "TOPLEFT", 10, card.y - 4)
groupHint:SetWidth(CARD_W - 20)
groupHint:SetJustifyH("LEFT")
Txt(groupHint, "Es werden nur Quest-Nummern und Fortschritt ausgetauscht – sonst nichts. Alle in der Gruppe brauchen Levelmate 1.0.8 oder neuer.")
card.y = card.y - 40
CardButton("Gruppenfenster öffnen", 190, function()
    frame:Hide(); if Levelmate.ToggleGroupFrame then Levelmate.ToggleGroupFrame() end
end)
EndCard()

---------------------------------------------------------------------------
-- Knoepfe unten in der Seitenleiste
---------------------------------------------------------------------------
local resetBtn = FlatButton(side, "Zurücksetzen", SIDE_W - 24, function()
    SlashCmdList.LEVELMATE("reset")
    O.Load()
end)
resetBtn:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 12, 12)
resetBtn.tip = "Übersprungene Quests, Fensterpositionen\nund Fenstergröße zurücksetzen."
local modeBtn = FlatButton(side, "Modus wählen …", SIDE_W - 24, function()
    frame:Hide(); if Levelmate.ShowModeDialog then Levelmate.ShowModeDialog() end
end)
modeBtn:SetPoint("BOTTOMLEFT", resetBtn, "TOPLEFT", 0, 6)

-- Hoehe nach dem laengsten Bereich
local lowest = -300
for _, p in ipairs(pages) do
    local minY = 0
    for _, c in ipairs({ p:GetChildren() }) do
        local _, _, _, _, cy = c:GetPoint(1)
        local h = c:GetHeight() or 0
        if cy and (cy - h) < minY then minY = cy - h end
    end
    if minY < lowest then lowest = minY end
end
frame:SetHeight(math.max(360, -lowest + 14))

---------------------------------------------------------------------------
function O.Load()
    Levelmate_DB = Levelmate_DB or {}
    frame.loading = true
    for _, fs in ipairs(texts) do fs:SetText(L(fs.raw)) end
    for _, b in ipairs(flatButtons) do b.text:SetText(L(b.raw)) end
    MarkLanguage()
    SelectPage(frame.current or pages[1])
    for _, t in ipairs(toggles) do t.Load(); t.Relayout() end
    tomtom:SetEnabled(TomTom ~= nil)
    local v = math.floor((Levelmate_DB.scale or 1) * 100 + 0.5)
    scale:SetValue(v); ScaleText(v)
    local d = Levelmate.Planner.DangerLevels()
    danger:SetValue(d); DangerText(d)
    local m = (Levelmate.Planner.MaxLevelAbove and Levelmate.Planner.MaxLevelAbove()) or 2
    maxAbove:SetValue(m); MaxText(m)
    local av = math.floor((Levelmate_DB.bgAlpha or 0.72) * 100 + 0.5)
    alpha:SetValue(av); AlphaText(av)
    if O.ClearPending then O.ClearPending() end
    frame.loading = false
end

function O.Toggle()
    if frame:IsShown() then frame:Hide() else O.Load(); frame:Show() end
end
O.SelectPage = function(key)
    for _, p in ipairs(pages) do if p.key == key then SelectPage(p) end end
end
