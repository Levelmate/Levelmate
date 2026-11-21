-- Arrow.lua
local L = Levelmate.L
-- Richtungspfeil zum aktuellen Ziel (wie bei RestedXP/TomTom).
-- Optional zusaetzlich ein TomTom-Wegpunkt, wenn TomTom installiert ist.
Levelmate = Levelmate or {}
Levelmate.Arrow = Levelmate.Arrow or {}
local A = Levelmate.Arrow

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local frame = CreateFrame("Frame", "LevelmateArrowFrame", UIParent)
frame:SetSize(120, 92)
frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, rel, x, y = self:GetPoint()
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.arrowPos = { point, rel, x, y }
end)
frame:SetClampedToScreen(true)

local tex = frame:CreateTexture(nil, "ARTWORK")
tex:SetSize(48, 48)
tex:SetPoint("TOP", frame, "TOP", 0, 0)
tex:SetTexture("Interface\\Minimap\\MinimapArrow")
tex:SetVertexColor(1, 0.82, 0)

local dist = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
dist:SetPoint("TOP", tex, "BOTTOM", 0, -2)
local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("TOP", dist, "BOTTOM", 0, -2)
label:SetWidth(160)
frame:Hide()

local target, tomtomUID

local function ClearTomTom()
    if tomtomUID and TomTom and TomTom.RemoveWaypoint then Call(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
    tomtomUID = nil
end

-- target = {map, x, y} in Prozent; name = Anzeigename
function A.SetTarget(t, name)
    local same = t and target and t.map == target.map and t.x == target.x and t.y == target.y
    target = t
    label:SetText(name or "")
    if not same and Levelmate_DB and Levelmate_DB.useTomTom and TomTom and TomTom.AddWaypoint then
        ClearTomTom()
        if t then
            tomtomUID = Call(TomTom.AddWaypoint, TomTom, t.map, t.x / 100, t.y / 100,
                { title = name or "Levelmate", persistent = false, minimap = true, world = true, crazy = true })
        end
    end
    if t and not (Levelmate_DB and Levelmate_DB.arrowHidden) then frame:Show() else frame:Hide() end
end

function A.Restore()
    local p = Levelmate_DB and Levelmate_DB.arrowPos
    if p then frame:ClearAllPoints(); frame:SetPoint(p[1], UIParent, p[2] or p[1], p[3], p[4]) end
end

function A.Toggle()
    Levelmate_DB.arrowHidden = not Levelmate_DB.arrowHidden
    if Levelmate_DB.arrowHidden then frame:Hide() elseif target then frame:Show() end
    return not Levelmate_DB.arrowHidden
end

-- Entfernung (Yards) und Richtung (Radiant, gegen den Uhrzeigersinn ab Norden).
function A.Compute()
    if not target or not C_Map then return nil end
    local here = Levelmate.Planner.PlayerPoint()
    if not here then return nil end
    local yards = Levelmate.Planner.Yards(here, target)
    if not yards then return nil end
    -- Ziel in die Karte des Spielers umrechnen, dann Richtung bestimmen.
    local _, mapPos = Call(C_Map.GetMapPosFromWorldPos, target.cont, CreateVector2D(target.wx, target.wy), here.map)
    local w, h = Call(C_Map.GetMapWorldSize, here.map)
    if not mapPos or not w or w == 0 then return yards, nil end
    local tx, ty = mapPos:GetXY()
    local east = (tx - here.x / 100) * w
    local north = -(ty - here.y / 100) * h
    local bearing = math.atan2(-east, north)
    return yards, bearing
end

local elapsed = 0
frame:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed < 0.05 then return end
    elapsed = 0
    local yards, bearing = A.Compute()
    if not yards then
        dist:SetText(L("|cffaaaaaaanderer Kontinent|r"))
        tex:SetRotation(0)
        return
    end
    local meters = yards * 0.9144
    if yards < 8 then
        dist:SetText(L("|cff00ff00Ziel erreicht|r"))
        tex:SetVertexColor(0, 1, 0)
    else
        dist:SetText(string.format("%d m", math.floor(meters)))
        tex:SetVertexColor(1, 0.82, 0)
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    if bearing and facing then
        tex:SetRotation(bearing - facing)
    end
end)
