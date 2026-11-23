-- Options.lua
-- Einstellungsfenster (Zahnrad oben rechts im Hauptfenster oder /lm optionen).
-- Alle Einstellungen gelten fuer alle Charaktere (Levelmate_DB).
Levelmate = Levelmate or {}
Levelmate.Options = Levelmate.Options or {}
local O = Levelmate.Options
local L = Levelmate.L

-- Texte, die beim Oeffnen in der gewaehlten Sprache neu gesetzt werden
local texts = {}
local function Txt(fs, raw) fs.raw = raw; fs:SetText(raw); texts[#texts + 1] = fs end

local frame = CreateFrame("Frame", "LevelmateOptionsFrame", UIParent, "BackdropTemplate")
frame:SetSize(330, 330)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:SetClampedToScreen(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 }
})
frame:SetBackdropColor(0.025, 0.035, 0.055, 0.97)
frame:Hide()
if UISpecialFrames then table.insert(UISpecialFrames, "LevelmateOptionsFrame") end  -- ESC schliesst

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -12)
Txt(title, "Einstellungen")

local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

local function Refresh()
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
end

---------------------------------------------------------------------------
-- Haken
---------------------------------------------------------------------------
local checks = {}
local y = -42
local function Check(label, hint, get, set)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, y)
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetWidth(270)
    text:SetJustifyH("LEFT")
    Txt(text, label)
    if hint then
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        h:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -2)
        h:SetWidth(270)
        h:SetJustifyH("LEFT")
        Txt(h, hint)
        y = y - 14
    end
    y = y - 30
    cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false); Refresh() end)
    cb.Load = function() cb:SetChecked(get() and true or false) end
    table.insert(checks, cb)
    return cb
end

Check("|cffb070ffKlassenquests anzeigen|r",
    "lila markiert und bevorzugt eingeplant (Zauber, Begleiter)",
    function() return Levelmate_DB.classQuests ~= false end,
    function(v) Levelmate_DB.classQuests = v; if Levelmate.Planner.BuildPool then Levelmate.Planner.BuildPool(Refresh) end end)
Check("Hinweis im Chat bei neuer Klassenquest", nil,
    function() return Levelmate_DB.classNotify ~= false end,
    function(v) Levelmate_DB.classNotify = v end)
Check("Zielpfeil anzeigen", nil,
    function() return not Levelmate_DB.arrowHidden end,
    function(v) if v == (Levelmate_DB.arrowHidden and true or false) then Levelmate.Arrow.Toggle() end end)
Check("Route auf der Weltkarte zeigen", "Linie zum Ziel und nächste Schritte (auch /lm karte)",
    function() return Levelmate_DB.mapRoute ~= false end,
    function(v) Levelmate_DB.mapRoute = v and true or false; if Levelmate.Arrow.RefreshMap then Levelmate.Arrow.RefreshMap() end end)
Check("Questgegenstände im Questlog zeigen", "Symbol bei der Quest im Levelmate-Fenster, anklicken zum Benutzen",
    function() return Levelmate_DB.itemButton ~= false end,
    function(v) Levelmate_DB.itemButton = v and true or false; if Levelmate.Refresh then Levelmate.Refresh() end end)
Check("Lange Sammelquests auslassen", "Quests mit seltenen Drops und über 45 min Arbeit nicht vorschlagen",
    function() return Levelmate_DB.skipLongCollect end,
    function(v) Levelmate_DB.skipLongCollect = v and true or nil; if Levelmate.Refresh then Levelmate.Refresh() end end)
local tomtom = Check("TomTom-Wegpunkte setzen", "nur wenn das Addon TomTom installiert ist",
    function() return Levelmate_DB.useTomTom end,
    function(v) Levelmate_DB.useTomTom = v end)
Check("Ruhestein einplanen", "wenn er bereit ist und viel Weg spart",
    function() return Levelmate_DB.useHearth ~= false end,
    function(v) Levelmate_DB.useHearth = v end)
Check("Minimap-Knopf anzeigen", nil,
    function() return not Levelmate_DB.minimapHidden end,
    function(v) Levelmate_DB.minimapHidden = not v; if Levelmate.Minimap then Levelmate.Minimap.Update() end end)

---------------------------------------------------------------------------
-- Fenstergroesse
---------------------------------------------------------------------------
y = y - 6
local scaleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
y = y - 20
local scale = CreateFrame("Slider", nil, frame, "BackdropTemplate")
scale:SetOrientation("HORIZONTAL")
scale:SetSize(280, 12)
scale:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, y)
scale:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
scale:SetBackdropColor(1, 1, 1, 0.12)
scale:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
scale:SetMinMaxValues(50, 150)
scale:SetValueStep(5)
if scale.SetObeyStepOnDrag then scale:SetObeyStepOnDrag(true) end
local function ScaleText(v) scaleLabel:SetText(string.format(L("Fenstergröße: %d %%"), v)) end
scale:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v / 5 + 0.5) * 5
    ScaleText(v)
    if not frame.loading then
        Levelmate_DB.scale = v / 100
        if LevelmateQuestPanel then LevelmateQuestPanel:SetScale(Levelmate_DB.scale) end
    end
end)
y = y - 30

-- Ab wie vielen Stufen ueber dir ein Gebiet als gefaehrlich gilt
local dangerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
dangerLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
local dangerHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dangerHint:SetPoint("TOPLEFT", dangerLabel, "BOTTOMLEFT", 0, -2)
dangerHint:SetWidth(290)
dangerHint:SetJustifyH("LEFT")
Txt(dangerHint, "Ziele in so hohen Gebieten werden nur noch zuletzt vorgeschlagen")
y = y - 34
local danger = CreateFrame("Slider", nil, frame, "BackdropTemplate")
danger:SetOrientation("HORIZONTAL")
danger:SetSize(280, 12)
danger:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, y)
danger:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
danger:SetBackdropColor(1, 1, 1, 0.12)
danger:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
danger:SetMinMaxValues(3, 12)
danger:SetValueStep(1)
if danger.SetObeyStepOnDrag then danger:SetObeyStepOnDrag(true) end
local function DangerText(v) dangerLabel:SetText(string.format(L("Gefährliches Gebiet ab: %d Stufen über dir"), v)) end
danger:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    DangerText(v)
    if not frame.loading then Levelmate_DB.dangerLevels = v; Refresh() end
end)
y = y - 30

-- Hoechstes Questlevel beim Annehmen
local maxLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
maxLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
local maxHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
maxHint:SetPoint("TOPLEFT", maxLabel, "BOTTOMLEFT", 0, -2)
maxHint:SetWidth(290)
maxHint:SetJustifyH("LEFT")
Txt(maxHint, "0 = nur Quests bis zu deiner Stufe, 2 = Standard (gelb/orange), 4 = mutig (rot)")
y = y - 34
local maxAbove = CreateFrame("Slider", nil, frame, "BackdropTemplate")
maxAbove:SetOrientation("HORIZONTAL")
maxAbove:SetSize(280, 12)
maxAbove:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, y)
maxAbove:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8" })
maxAbove:SetBackdropColor(1, 1, 1, 0.12)
maxAbove:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
maxAbove:SetMinMaxValues(0, 4)
maxAbove:SetValueStep(1)
if maxAbove.SetObeyStepOnDrag then maxAbove:SetObeyStepOnDrag(true) end
local function MaxText(v)
    maxLabel:SetText(string.format(L(v == 1 and "Quests annehmen bis: %d Stufe über dir" or "Quests annehmen bis: %d Stufen über dir"), v))
end
maxAbove:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    MaxText(v)
    if not frame.loading then
        Levelmate_DB.maxLevelAbove = v
        if Levelmate.Planner.BuildPool then Levelmate.Planner.BuildPool(function() if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end end) end
        Refresh()
    end
end)
y = y - 30

---------------------------------------------------------------------------
-- Sprache: Automatisch (Spielsprache) / Deutsch / English
---------------------------------------------------------------------------
local langLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
langLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, y)
Txt(langLabel, "Sprache")
y = y - 20
local langButtons = {}
local LANGS = { { key = "auto", text = "Automatisch" }, { key = "de", text = "Deutsch" }, { key = "en", text = "English" } }
local function MarkLanguage()
    local cur = (Levelmate_DB and Levelmate_DB.language) or "auto"
    for _, b in ipairs(langButtons) do
        b:SetText((b.key == cur and "|cff7fd67f" or "") .. L(b.label) .. (b.key == cur and "|r" or ""))
    end
end
for i, lang in ipairs(LANGS) do
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(94, 22)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (i - 1) * 100, y)
    b.key, b.label = lang.key, lang.text
    b:SetScript("OnClick", function()
        Levelmate_DB.language = lang.key
        O.Load()
        if Levelmate.OnLanguageChanged then Levelmate.OnLanguageChanged() end
    end)
    langButtons[#langButtons + 1] = b
end
y = y - 34

---------------------------------------------------------------------------
-- Knoepfe
---------------------------------------------------------------------------
local modeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
modeBtn:SetSize(140, 22)
modeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
modeBtn.raw = "Modus wählen …"
modeBtn:SetScript("OnClick", function() frame:Hide(); if Levelmate.ShowModeDialog then Levelmate.ShowModeDialog() end end)

local resetBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 22)
resetBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
resetBtn.raw = "Zurücksetzen"
resetBtn:SetScript("OnClick", function()
    SlashCmdList.LEVELMATE("reset")
    O.Load()
end)
resetBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L("Übersprungene Quests, Fensterpositionen\nund Fenstergröße zurücksetzen."))
    GameTooltip:Show()
end)
resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

frame:SetHeight(-y + 50)

---------------------------------------------------------------------------
function O.Load()
    Levelmate_DB = Levelmate_DB or {}
    frame.loading = true
    for _, fs in ipairs(texts) do fs:SetText(L(fs.raw)) end
    modeBtn:SetText(L(modeBtn.raw))
    resetBtn:SetText(L(resetBtn.raw))
    MarkLanguage()
    for _, cb in ipairs(checks) do cb.Load() end
    if tomtom.SetEnabled then tomtom:SetEnabled(TomTom ~= nil) end
    local v = math.floor((Levelmate_DB.scale or 1) * 100 + 0.5)
    scale:SetValue(v)
    ScaleText(v)
    local d = Levelmate.Planner.DangerLevels()
    danger:SetValue(d)
    local m = (Levelmate.Planner.MaxLevelAbove and Levelmate.Planner.MaxLevelAbove()) or 2
    MaxText(m)
    maxAbove:SetValue(m)
    DangerText(d)
    frame.loading = false
end

function O.Toggle()
    if frame:IsShown() then frame:Hide() else O.Load(); frame:Show() end
end
