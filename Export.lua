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
        hint:SetText(L("Text einfügen (Strg+V) und auf \"Importieren\" klicken. Bei mehreren Teilen: jeden Teil einzeln importieren oder alle auf einmal einfügen."))
        edit:SetText("")
        importBtn:Show()
        if E.HideParts then E.HideParts() end
    else
        local text, gates, cells = Levelmate.Travel.ExportText()
        title:SetText(L("Wege exportieren"))
        -- Discord erlaubt nur 2000 Zeichen je Nachricht -> in Teile aufteilen.
        -- Jede Zeile ist fuer sich gueltig, darum geht der Import Teil fuer Teil
        -- (oder alle Teile auf einmal eingefuegt).
        E.parts = E.Split(text, E.PART_CHARS)
        E.part = 1
        E.info = string.format(L("%d Gebietsübergänge, %d Wegfelder."), gates, cells)
        E.ShowPart()
        importBtn:Hide()
    end
    f:Show()
    edit:SetFocus()
    if mode ~= "import" then edit:HighlightText() end
end

E.PART_CHARS = 1900
function E.Split(text, max)
    local parts, cur, n = {}, {}, 0
    local header = "Levelmate-Export 1"
    for line in tostring(text):gmatch("[^\n]+") do
        if line ~= header then
            if n + #line + 1 > max - #header - 12 and #cur > 0 then
                parts[#parts + 1] = cur; cur, n = {}, 0
            end
            cur[#cur + 1] = line; n = n + #line + 1
        end
    end
    if #cur > 0 or #parts == 0 then parts[#parts + 1] = cur end
    for i, lines in ipairs(parts) do
        parts[i] = header .. " (" .. i .. "/" .. #parts .. ")\n" .. table.concat(lines, "\n")
    end
    return parts
end

local prevBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
prevBtn:SetSize(28, 22)
prevBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
prevBtn:SetText("<")
local nextBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
nextBtn:SetSize(28, 22)
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 96, 0)
nextBtn:SetText(">")
local partLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
partLabel:SetPoint("LEFT", prevBtn, "RIGHT", 6, 0)
partLabel:SetWidth(84)

function E.ShowPart()
    local n = #(E.parts or {})
    local i = math.max(1, math.min(E.part or 1, n))
    E.part = i
    edit:SetText(E.parts[i] or "")
    partLabel:SetText(string.format(L("Teil %d/%d"), i, n))
    hint:SetText(E.info .. " " .. (n > 1
        and string.format(L("Discord erlaubt 2000 Zeichen je Nachricht: Teil für Teil kopieren (Strg+C) und schicken, mit > zum nächsten Teil."))
        or L("Mit Strg+C kopieren und z. B. per Discord schicken.")))
    prevBtn:SetShown(n > 1); nextBtn:SetShown(n > 1); partLabel:SetShown(n > 1)
    edit:SetFocus(); edit:HighlightText()
end
prevBtn:SetScript("OnClick", function() E.part = (E.part or 1) - 1; E.ShowPart() end)
nextBtn:SetScript("OnClick", function() E.part = (E.part or 1) + 1; E.ShowPart() end)
prevBtn:Hide(); nextBtn:Hide(); partLabel:Hide()

function E.HideParts() prevBtn:Hide(); nextBtn:Hide(); partLabel:Hide() end
