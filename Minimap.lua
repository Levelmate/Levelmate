-- Minimap.lua
local L = Levelmate.L
-- Runder Knopf am Rand der Minimap (wie bei Details oder GearQuest).
--   Linksklick:          Fenster ein-/ausblenden
--   Rechtsklick:         Modus wählen
--   Umschalt+Linksklick: Pfeil ein-/ausblenden
--   Ziehen:              Knopf am Kartenrand verschieben
-- Zusaetzlich Eintrag im Addon-Sammelmenue der Minimap, falls der Client es hat.
Levelmate = Levelmate or {}
Levelmate.Minimap = Levelmate.Minimap or {}
local MM = Levelmate.Minimap

local ICON = "Interface\\AddOns\\Levelmate\\Media\\MinimapIcon"

local button = CreateFrame("Button", "LevelmateMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local overlay = button:CreateTexture(nil, "OVERLAY")
overlay:SetSize(53, 53)
overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
overlay:SetPoint("TOPLEFT")
local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", 7, -5)
local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20)
icon:SetTexture(ICON)
icon:SetPoint("TOPLEFT", 6, -5)

-- Position auf dem Kartenrand aus einem Winkel (Grad) berechnen.
local function Place()
    local angle = math.rad((Levelmate_DB and Levelmate_DB.minimapAngle) or 220)
    local x, y = math.cos(angle), math.sin(angle)
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local r = (Minimap:GetWidth() / 2) + 5
    if shape == "SQUARE" then
        -- Bei eckiger Minimap auf den Rand des Quadrats schieben.
        local m = math.max(math.abs(x), math.abs(y))
        x, y = x / m, y / m
        r = (Minimap:GetWidth() / 2) + 2
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * r, y * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    Levelmate_DB.minimapAngle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    Place()
end

button:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", OnDragUpdate)
end)
button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
end)

local function OnClick(mouse)
    if mouse == "RightButton" then
        Levelmate.ShowModeDialog()
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        Levelmate.Arrow.Toggle()
    else
        Levelmate.TogglePanel()
    end
end
button:SetScript("OnClick", function(_, mouse) OnClick(mouse) end)

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:AddLine("Levelmate " .. (Levelmate.version or ""))
    local title, detail = Levelmate.CurrentStepText()
    if title then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(title, 1, 1, 1, true)
        if detail and detail ~= "" then GameTooltip:AddLine(detail, 0.8, 0.8, 0.8, true) end
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L("|cffffd100Linksklick:|r Fenster ein/aus"), 1, 1, 1)
    GameTooltip:AddLine(L("|cffffd100Rechtsklick:|r Modus wählen"), 1, 1, 1)
    GameTooltip:AddLine(L("|cffffd100Umschalt+Linksklick:|r Pfeil ein/aus"), 1, 1, 1)
    GameTooltip:AddLine(L("|cffffd100Ziehen:|r Knopf verschieben"), 1, 1, 1)
    GameTooltip:Show()
end
button:SetScript("OnEnter", ShowTooltip)
button:SetScript("OnLeave", function() GameTooltip:Hide() end)

function MM.Update()
    if Levelmate_DB and Levelmate_DB.minimapHidden then button:Hide() else button:Show(); Place() end
end

local registered = false
function MM.Init()
    MM.Update()
    -- Addon-Sammelmenue an der Minimap (moderner Client), falls vorhanden.
    if not registered and AddonCompartmentFrame and AddonCompartmentFrame.RegisterAddon then
        registered = pcall(AddonCompartmentFrame.RegisterAddon, AddonCompartmentFrame, {
            text = "Levelmate",
            icon = ICON,
            notCheckable = true,
            func = function() Levelmate.TogglePanel() end,
            funcOnEnter = function(b) ShowTooltip(b) end,
            funcOnLeave = function() GameTooltip:Hide() end,
        })
    end
end
