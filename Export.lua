-- Export.lua
-- /lm export: gelernte Uebergaenge und Wege als Text zum Kopieren (z. B. um sie
-- dem Entwickler zu schicken). /lm import: solchen Text wieder einfuegen.
Levelmate = Levelmate or {}
Levelmate.Export = Levelmate.Export or {}
local E = Levelmate.Export
local L = Levelmate.L

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLevelmate|r: " .. tostring(msg))
end

local f = CreateFrame("Frame", "LevelmateExportFrame", UIParent, "BackdropTemplate")
f:SetSize(480, 340)
f:SetPoint("CENTER")
f:SetFrameStrata("DIALOG")
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
f:SetBackdropColor(0.035, 0.055, 0.12, 0.95)
f:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
f:Hide()
if UISpecialFrames then table.insert(UISpecialFrames, "LevelmateExportFrame") end

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -12)
local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
hint:SetWidth(440)

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

local scroll = CreateFrame("ScrollFrame", "LevelmateExportScroll", f, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -62)
scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -34, 46)
local bg = f:CreateTexture(nil, "BACKGROUND")
bg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -4, 4)
bg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 4, -4)
bg:SetColorTexture(0, 0, 0, 0.35)

local edit = CreateFrame("EditBox", nil, scroll)
edit:SetMultiLine(true)
edit:SetAutoFocus(false)
edit:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
edit:SetWidth(420)
if edit.SetMaxLetters then edit:SetMaxLetters(0) end
edit:SetScript("OnEscapePressed", function() f:Hide() end)
scroll:SetScrollChild(edit)

local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
importBtn:SetSize(140, 22)
importBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
importBtn:SetScript("OnClick", function()
    local g, c = Levelmate.Travel.ImportText(edit:GetText())
    Print(string.format(L("Importiert: %d neue Gebietsübergänge, %d neue Wegfelder."), g, c))
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
    f:Hide()
end)

local closeBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
closeBtn:SetSize(120, 22)
closeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
closeBtn:SetScript("OnClick", function() f:Hide() end)

function E.Show(mode)
    closeBtn:SetText(L("Schließen"))
    importBtn:SetText(L("Importieren"))
    if mode == "import" then
        title:SetText(L("Wege importieren"))
        hint:SetText(L("Text einfügen (Strg+V) und auf \"Importieren\" klicken."))
        edit:SetText("")
        importBtn:Show()
    else
        local text, gates, cells = Levelmate.Travel.ExportText()
        title:SetText(L("Wege exportieren"))
        hint:SetText(string.format(L("%d Gebietsübergänge, %d Wegfelder. Mit Strg+C kopieren und z. B. per Discord schicken."),
            gates, cells))
        edit:SetText(text)
        importBtn:Hide()
    end
    f:Show()
    edit:SetFocus()
    if mode ~= "import" then edit:HighlightText() end
end
