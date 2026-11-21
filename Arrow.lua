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
-- Route: Endziel + Funktion, die das aktuelle Zwischenziel liefert
local route = { final = nil, name = nil, resolve = nil, direct = false, key = nil, kind = nil, via = nil }

local function ClearTomTom()
    if tomtomUID and TomTom and TomTom.RemoveWaypoint then Call(TomTom.RemoveWaypoint, TomTom, tomtomUID) end
    tomtomUID = nil
end

-- target = {map, x, y} in Prozent; name = Anzeigename
local function SetTargetRaw(t, name)
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

local function RouteKey(t) return t and (tostring(t.map) .. ":" .. math.floor((t.x or 0) * 10) .. ":" .. math.floor((t.y or 0) * 10)) end

-- Zwischenziel neu bestimmen (beim Setzen und alle 1,5 s waehrend du laeufst)
local function UpdateRoute()
    if not route.final then return end
    local here = Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    local wp, wpName, kind
    if not route.direct and route.resolve then
        local ok, a, b, c = pcall(route.resolve, here)
        if ok then wp, wpName, kind = a, b, c end
    end
    route.kind, route.via = wp and kind or nil, wp
    local name = wp and wpName or route.name
    if route.direct then name = (route.name or "") .. L(" (direkt)") end
    target = wp or route.final
    label:SetText(name or "")
end

-- Endziel setzen; resolve(here) liefert optional ein Zwischenziel (wp, name, art)
function A.SetRoute(final, name, resolve)
    local key = RouteKey(final)
    if key ~= route.key then route.direct = false end   -- neues Ziel: wieder dem Weg folgen
    route.final, route.name, route.resolve, route.key = final, name, resolve, key
    SetTargetRaw(final, name)
    UpdateRoute()
end

-- Rechtsklick auf den Pfeil: fuer dieses Ziel Luftlinie statt Weg/Uebergang
function A.ToggleDirect()
    if not route.final then return end
    route.direct = not route.direct
    UpdateRoute()
    Levelmate.Print(route.direct and L("Pfeil zeigt jetzt direkt aufs Ziel (Rechtsklick: wieder dem Weg folgen).")
        or L("Pfeil folgt wieder dem geplanten Weg."))
end
function A.Route() return route end

-- Ziel ohne Zwischenziele (Lehrer usw.); beendet eine laufende Route
function A.SetTarget(t, name)
    route.final, route.resolve, route.key, route.via, route.kind = nil, nil, nil, nil, nil
    SetTargetRaw(t, name)
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

frame:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then A.ToggleDirect() end
end)
frame:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Levelmate")
    GameTooltip:AddLine(L("Linksklick ziehen: verschieben"), 1, 1, 1)
    GameTooltip:AddLine(route.direct and L("Rechtsklick: wieder dem Weg folgen") or L("Rechtsklick: direkt zum Ziel (Luftlinie)"), 1, 1, 1)
    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

local elapsed, routeTick = 0, 0
frame:SetScript("OnUpdate", function(_, dt)
    routeTick = routeTick + dt
    if routeTick >= 1.5 then
        routeTick = 0
        if Levelmate.Perf and Levelmate.Perf.Time then Levelmate.Perf.Time("arrow", UpdateRoute) else pcall(UpdateRoute) end
    end
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

-- ---------------------------------------------------------------------------
-- Route auf der Weltkarte: Linie von dir ueber Zwischenziele (Uebergang,
-- bekannter Weg) zum aktuellen Ziel, danach gestrichelt die naechsten Schritte.
-- Ein/aus: /lm karte
-- ---------------------------------------------------------------------------
local MAX_STEPS = 4
A.steps = {}          -- {target, name} der naechsten Schritte (setzt Core)
function A.SetSteps(list) A.steps = list or {} end

local mapOv, lines, marks, lineN, markN
local function T_lastPath() return Levelmate.Travel and Levelmate.Travel.lastTrailPath end
local function Canvas()
    return WorldMapFrame and WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child
end
-- OpenMap (nahtlose Weltkarte): eigene Umrechnung, sonst landet die Route
-- unter seiner Kartengrafik bzw. an der falschen Stelle.
local function OpenMapStitched()
    local OM = OpenMapAPI
    if OM and OM.major == 1 and (OM.version or 0) >= 2 and OM.IsStitched then
        local ok, on = pcall(OM.IsStitched)
        if ok and on then return OM end
    end
end
local function ToCanvas(cont, wx, wy, mapID, w, h)
    local OM = OpenMapStitched()
    if OM then
        local ok, x, y = pcall(OM.CanvasFromWorldPos, cont, wx, wy)
        if ok and x and y then return x * w, -y * h end
        return nil
    end
    if not (C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return nil end
    local ok, _, v = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(wx, wy), mapID)
    if not ok or not v then return nil end
    local x, y = v:GetXY()
    if x < -0.05 or x > 1.05 or y < -0.05 or y > 1.05 then return nil end
    return x * w, -y * h
end
local function GetLine()
    lineN = lineN + 1
    local l = lines[lineN]
    if not l then l = mapOv:CreateLine(nil, "OVERLAY"); lines[lineN] = l end
    l:Show()
    return l
end
local function GetMark()
    markN = markN + 1
    local m = marks[markN]
    if not m then
        m = CreateFrame("Frame", nil, mapOv)
        m:SetSize(18, 18)
        m.bg = m:CreateTexture(nil, "OVERLAY"); m.bg:SetAllPoints(); m.bg:SetColorTexture(0.05, 0.05, 0.1, 0.85)
        m.txt = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); m.txt:SetPoint("CENTER")
        marks[markN] = m
    end
    m:Show()
    return m
end
local function Segment(cont, a, b, mapID, w, h, r, g, bl, alpha, thick, dashed)
    local x1, y1 = ToCanvas(cont, a.wx, a.wy, mapID, w, h)
    local x2, y2 = ToCanvas(cont, b.wx, b.wy, mapID, w, h)
    if not x1 or not x2 then return end
    if dashed then
        local dx, dy = x2 - x1, y2 - y1
        local len = math.sqrt(dx * dx + dy * dy)
        -- Anzahl Striche begrenzen: beim Hineinzoomen wurden das sonst Hunderte
        -- Linien je Abschnitt (Ruckler bei offener Karte)
        local n = math.max(1, math.min(40, math.floor(len / (thick * 4))))
        for i = 0, n - 1, 2 do
            local l = GetLine()
            l:SetThickness(thick); l:SetColorTexture(r, g, bl, alpha)
            l:SetStartPoint("TOPLEFT", mapOv, x1 + dx * i / n, y1 + dy * i / n)
            l:SetEndPoint("TOPLEFT", mapOv, x1 + dx * math.min(n, i + 1) / n, y1 + dy * math.min(n, i + 1) / n)
        end
    else
        local l = GetLine()
        l:SetThickness(thick); l:SetColorTexture(r, g, bl, alpha)
        l:SetStartPoint("TOPLEFT", mapOv, x1, y1)
        l:SetEndPoint("TOPLEFT", mapOv, x2, y2)
    end
end

local DrawMapRouteInner
local function DrawMapRoute()
    if Levelmate.Perf and Levelmate.Perf.Time then
        local ok, err = Levelmate.Perf.Time("map", DrawMapRouteInner)
        if not ok then error(err, 0) end
        return
    end
    return DrawMapRouteInner()
end
DrawMapRouteInner = function()
    if not mapOv then return end
    lineN, markN = 0, 0
    -- ueber der Kartengrafik von OpenMap bleiben
    do
        local OM = OpenMapStitched()
        local top = OM and OM.ArtTopLevel and select(2, pcall(OM.ArtTopLevel))
        local child = Canvas()
        local want = math.max((child and child:GetFrameLevel() or 1) + 20, (type(top) == "number" and top or 0) + 10)
        if mapOv:GetFrameLevel() ~= want then mapOv:SetFrameLevel(want) end
    end
    if not (Levelmate_DB and Levelmate_DB.mapRoute == false) and WorldMapFrame and WorldMapFrame:IsShown() then
        local mapID = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
        local w, h = mapOv:GetWidth(), mapOv:GetHeight()
        local cs = WorldMapFrame.ScrollContainer.GetCanvasScale and WorldMapFrame.ScrollContainer:GetCanvasScale() or 1
        local thick = 4 / math.max(cs, 0.2)
        local here = Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
        if mapID and w > 0 and here and here.wx and route.final and route.final.wx then
            local final = route.final
            -- 1) aktueller Schritt: du -> Zwischenziel(e) -> Ziel (gelb)
            local tp = T_lastPath and T_lastPath()
            if route.kind == "trail" and tp and tp.cont == here.cont then
                local pts = tp.pts
                local prev = here
                -- Punkte ausduennen: hoechstens ~60 Abschnitte (Weg in 8-Yard-Schritten)
                local step = math.max(1, math.ceil(#pts / 60))
                for i = #pts, 1, -1 do
                    if i == 1 or (#pts - i) % step == 0 then
                        Segment(here.cont, prev, pts[i], mapID, w, h, 1, 0.82, 0, 0.95, thick)
                        prev = pts[i]
                    end
                end
            elseif route.via and route.via.wx then
                Segment(here.cont, here, route.via, mapID, w, h, 1, 0.82, 0, 0.95, thick)
                if (final.cont or here.cont) == here.cont then
                    Segment(here.cont, route.via, final, mapID, w, h, 1, 0.82, 0, 0.6, thick, true)
                end
            elseif (final.cont or here.cont) == here.cont then
                Segment(here.cont, here, final, mapID, w, h, 1, 0.82, 0, 0.95, thick)
            end
            -- 2) die naechsten Schritte gestrichelt (grau-blau) mit Nummern
            local prev = final
            for i, st in ipairs(A.steps) do
                if i > MAX_STEPS then break end
                local t = st.target
                if t and t.wx and t.cont == here.cont then
                    if i > 1 and prev and prev.wx and prev.cont == t.cont then
                        Segment(t.cont, prev, t, mapID, w, h, 0.55, 0.75, 1, 0.75, thick * 0.7, true)
                    end
                    local x, y = ToCanvas(t.cont, t.wx, t.wy, mapID, w, h)
                    if x then
                        local m = GetMark()
                        local sc = 1 / math.max(cs, 0.2)
                        m:SetScale(sc)
                        m:ClearAllPoints()
                        -- Offsets gelten im (skalierten) Koordinatensystem der Marke
                        m:SetPoint("CENTER", mapOv, "TOPLEFT", x / sc, y / sc)
                        m.txt:SetText(i)
                        m.txt:SetTextColor(i == 1 and 1 or 0.7, i == 1 and 0.82 or 0.85, i == 1 and 0 or 1)
                    end
                    prev = t
                end
            end
        end
    end
    for i = lineN + 1, #lines do lines[i]:Hide() end
    for i = markN + 1, #marks do marks[i]:Hide() end
end

local function InitMapRoute()
    local child = Canvas()
    if mapOv or not child then return end
    mapOv = CreateFrame("Frame", nil, child)
    mapOv:SetAllPoints(child)
    mapOv:SetFrameLevel((child:GetFrameLevel() or 1) + 20)
    lines, marks, lineN, markN = {}, {}, 0, 0
    local acc, lastSig = 0, nil
    -- Beim Zoomen/Verschieben sofort neu zeichnen (sonst haengt die Linie
    -- kurz an der falschen Stelle, z. B. oben rechts), sonst alle 0,5 s.
    local function ViewSig()
        local sc = WorldMapFrame.ScrollContainer
        local cs = sc and sc.GetCanvasScale and sc:GetCanvasScale() or 1
        local id = WorldMapFrame.GetMapID and WorldMapFrame:GetMapID() or 0
        local sig = tostring(id) .. ":" .. string.format("%.4f", cs) .. ":" .. math.floor(mapOv:GetWidth() or 0)
        if sc and sc.GetNormalizedHorizontalScroll then
            local ok, hx = pcall(sc.GetNormalizedHorizontalScroll, sc)
            local ok2, vy = pcall(sc.GetNormalizedVerticalScroll, sc)
            if ok and ok2 then sig = sig .. string.format(":%.4f:%.4f", hx or 0, vy or 0) end
        end
        local OM = OpenMapStitched()
        if OM and OM.GetView then
            local ok, u, v, z = pcall(OM.GetView)
            if ok and u then sig = sig .. string.format(":%.4f:%.4f:%.4f", u, v or 0, z or 0) end
        end
        return sig
    end
    local sinceDraw = 1
    mapOv:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        sinceDraw = sinceDraw + dt
        local ok, sig = pcall(ViewSig)
        -- beim Zoomen/Verschieben hoechstens ~30-mal pro Sekunde neu zeichnen
        if ok and sig ~= lastSig and sinceDraw >= 0.033 then
            lastSig = sig; acc = 0; sinceDraw = 0
            pcall(DrawMapRoute)
            return
        end
        if acc < 0.5 then return end
        acc = 0; sinceDraw = 0
        pcall(DrawMapRoute)
    end)
    local OM = OpenMapAPI
    if OM and OM.RegisterCallback then
        pcall(OM.RegisterCallback, A, "OpenMap_ViewChanged", function() pcall(DrawMapRoute) end)
        pcall(OM.RegisterCallback, A, "OpenMap_StitchedChanged", function() pcall(DrawMapRoute) end)
    end
end
A.RefreshMap = function() pcall(DrawMapRoute) end

local initF = CreateFrame("Frame")
initF:RegisterEvent("PLAYER_LOGIN")
initF:SetScript("OnEvent", function()
    if WorldMapFrame then
        pcall(InitMapRoute)
        if WorldMapFrame.HookScript then WorldMapFrame:HookScript("OnShow", function() pcall(InitMapRoute); pcall(DrawMapRoute) end) end
    end
end)
