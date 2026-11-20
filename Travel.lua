-- Travel.lua
local L = Levelmate.L
-- Reisezeiten mit Flugrouten.
-- Flugmeister kommen aus QuestieDB (NPC-Flag "Flugmeister", Fraktion).
-- Welche Flugpunkte dein Charakter kennt, merkt sich das Addon, sobald du
-- einen Flugmeister ansprichst (Flugkarte offen). Solange noch nichts
-- erfasst ist, nimmt es an, dass du alle Flugpunkte deiner Fraktion kennst.
Levelmate = Levelmate or {}
Levelmate.Travel = Levelmate.Travel or {}
local T = Levelmate.Travel

local CONFIG = {
    flightSpeed = 32,     -- Yards/s eines Flugtiers
    routeFactor = 1.3,    -- Flugrouten sind laenger als die Luftlinie
    overhead = 30,        -- Sekunden fuer Ansprechen, Start und Landung
    minSaving = 30,       -- Flug nur vorschlagen, wenn er mind. 30 s spart
    hearthSeconds = 40,   -- Ruhestein: 10 s Zaubern + Ladebildschirm
    hearthMinSaving = 120,-- Ruhestein nur vorschlagen, wenn er mind. 2 Minuten spart
    -- Zeppelin/Schiff: Abfahrt alle ca. 4-5 min (im Schnitt gut 2 min warten),
    -- dazu die Fahrt mit Ladebildschirm.
    shipSeconds = 300,
}
T.CONFIG = CONFIG

local fps = {}            -- { id, name, point }
local version = 0
T.ready = false

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
end

local function FlightFlag()
    local e = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
    return (e and e.FLIGHT_MASTER) or 8
end

local function HasFlag(flags, flag)
    return flags and flag and math.floor(flags / flag) % 2 == 1
end

local function FactionLetter()
    local f = UnitFactionGroup("player")
    return f == "Alliance" and "A" or f == "Horde" and "H" or nil
end

local function AddFP(id)
    local n = Levelmate.DB.Npc(id)
    if n and n.points and n.points[1] then
        table.insert(fps, { id = id, name = n.name, point = n.points[1] })
    end
end

-- Flugmeister suchen. Die Liste wird gespeichert, damit beim naechsten
-- Login nicht alle NPCs durchsucht werden muessen.
function T.Scan(onDone)
    if not Levelmate.DB.Available() then return end
    Levelmate_DB = Levelmate_DB or {}
    local letter = FactionLetter()
    local build = (C_AddOns and Call(C_AddOns.GetAddOnMetadata, "QuestieDB", "X-BUILD-COMMIT"))
        or (GetAddOnMetadata and Call(GetAddOnMetadata, "QuestieDB", "X-BUILD-COMMIT")) or "?"
    local cache = Levelmate_DB.fpCache
    local function Finish(ids)
        fps = {}
        for _, id in ipairs(ids) do
            local friendly = Call(NpcDB.friendlyToFaction, id)
            if letter and friendly and friendly:find(letter, 1, true) then AddFP(id) end
        end
        version = version + 1
        T.ready = true
        if onDone then onDone() end
    end
    if cache and cache.build == build and type(cache.ids) == "table" then
        Finish(cache.ids); return
    end
    local all = Call(NpcDB.GetAllIds) or {}
    local flag, found, i = FlightFlag(), {}, 1
    local function Step()
        local stop = math.min(#all, i + 600)
        for k = i, stop do
            local id = all[k]
            if HasFlag(Call(NpcDB.npcFlags, id), flag) then found[#found + 1] = id end
        end
        i = stop + 1
        if i <= #all then
            if C_Timer and C_Timer.After then C_Timer.After(0, Step) else Step() end
        else
            Levelmate_DB.fpCache = { build = build, ids = found }
            Finish(found)
        end
    end
    Step()
end

function T.List() return fps end

-- Gastwirte (fuer den Ruhestein-Ort), eigene Suche mit eigenem Speicher
local inns, auctioneers = {}, {}
local function InnFlag()
    local e = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
    return (e and e.INNKEEPER) or 65536
end
local function AuctionFlag()
    local e = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
    return (e and e.AUCTIONEER) or 2097152
end
function T.ScanInns()
    if not Levelmate.DB.Available() or not NpcDB then return end
    Levelmate_DB = Levelmate_DB or {}
    local letter = FactionLetter()
    local build = (C_AddOns and Call(C_AddOns.GetAddOnMetadata, "QuestieDB", "X-BUILD-COMMIT"))
        or (GetAddOnMetadata and Call(GetAddOnMetadata, "QuestieDB", "X-BUILD-COMMIT")) or "?"
    local function Collect(ids, into)
        for _, id in ipairs(ids) do
            local friendly = Call(NpcDB.friendlyToFaction, id)
            local n = Levelmate.DB.Npc(id)
            if letter and friendly and friendly:find(letter, 1, true) and n and n.points and n.points[1] then
                table.insert(into, { id = id, name = n.name, point = n.points[1] })
            end
        end
    end
    local function Finish(ids, ahIds)
        inns, auctioneers = {}, {}
        Collect(ids, inns)
        Collect(ahIds or {}, auctioneers)
    end
    local cache = Levelmate_DB.innCache
    if cache and cache.build == build and type(cache.ids) == "table" and type(cache.ahIds) == "table" then
        Finish(cache.ids, cache.ahIds); return
    end
    local all = Call(NpcDB.GetAllIds) or {}
    local flag, aflag, found, foundAH, i = InnFlag(), AuctionFlag(), {}, {}, 1
    local function Step()
        local stop = math.min(#all, i + 600)
        for k = i, stop do
            local id = all[k]
            local f = Call(NpcDB.npcFlags, id)
            if HasFlag(f, flag) then found[#found + 1] = id end
            if HasFlag(f, aflag) then foundAH[#foundAH + 1] = id end
        end
        i = stop + 1
        if i <= #all then
            if C_Timer and C_Timer.After then C_Timer.After(0, Step) else Step() end
        else
            Levelmate_DB.innCache = { build = build, ids = found, ahIds = foundAH }
            Finish(found, foundAH)
        end
    end
    Step()
end
function T.Inns() return inns end
function T.Auctioneers() return auctioneers end

-- Anzeigename eines Flugpunkts: Ort aus der Flugkarte ("Ratschet"), sonst Gebiet.
function T.PlaceName(fp)
    local names = Levelmate_DB and Levelmate_DB.fpNames
    local name = names and names[fp.id]
    local zone = Levelmate.Planner.MapName(fp.point.map)
    if name then
        local place = name:match("^([^,]+)") or name
        if place ~= zone then return place .. " (" .. zone .. ")" end
        return place
    end
    return L("Flugpunkt ") .. zone
end

local function Known(fp)
    local k = Levelmate_CharDB and Levelmate_CharDB.knownFP
    if not k then return true end       -- noch nicht erfasst: Annahme "bekannt"
    return k[fp.id] == true
end
T.Known = Known

function T.Captured() return Levelmate_CharDB and Levelmate_CharDB.knownFP ~= nil end

-- Naechster bekannter Flugpunkt zu einem Punkt (wird am Punkt zwischengespeichert).
local function NearestFP(p, Yards)
    if p._fpVer == version then return p._fp, p._fpYd end
    local best, bestYd
    for _, fp in ipairs(fps) do
        if Known(fp) then
            local yd = Yards(p, fp.point)
            if yd and (not bestYd or yd < bestYd) then best, bestYd = fp, yd end
        end
    end
    p._fpVer, p._fp, p._fpYd = version, best, bestYd
    return best, bestYd
end

-- Naechster bekannter Flugpunkt zu einem Punkt (fuer die Routenplanung).
function T.NearestFP(p, Yards)
    if not T.ready or #fps == 0 then return nil end
    return NearestFP(p, Yards)
end

-- Reisezeit von a nach b in Sekunden. Liefert zusaetzlich Abflug- und
-- Ziel-Flugpunkt, wenn ein Flug schneller ist als Laufen.
-- Zeppeline und Schiffe. Die Anleger werden ueber die NPCs dort aus der
-- Questdatenbank bestimmt (Zeppelinmeister bzw. Hafenmeister), nicht geraten.
-- a/b: NPC am Abfahrtsort / am Zielort (jede Linie faehrt in beide Richtungen).
local TRANSPORTS = {
    { kind = "Zeppelin", horde = true, a = 9564, an = "Orgrimmar",  b = 9566,  bn = "Unterstadt" },
    { kind = "Zeppelin", horde = true, a = 12136, an = "Orgrimmar", b = 3149,  bn = "Grom'gol" },
    { kind = "Zeppelin", horde = true, a = 3150, an = "Unterstadt", b = 12137, bn = "Grom'gol" },
    { kind = "Schiff",                 a = 3453, an = "Ratschet",   b = 4631,  bn = "Beutebucht" },
    -- Allianz: keine eindeutigen Anleger-NPCs in der Datenbank. Koordinaten aus
    -- "HandyNotes: TravelGuide (Classic)" v3.8 von Dathwada (siehe SOURCES.txt).
    { kind = "Schiff", alliance = true, a = { map = 1437, x = 5.02, y = 63.48 }, an = "Menethil",
                                        b = { map = 1445, x = 71.62, y = 56.48 }, bn = "Theramore" },
    { kind = "Schiff", alliance = true, a = { map = 1437, x = 4.63, y = 57.10 }, an = "Menethil",
                                        b = { map = 1439, x = 32.40, y = 43.80 }, bn = "Auberdine" },
    { kind = "Schiff", alliance = true, a = { map = 1439, x = 33.19, y = 40.06 }, an = "Auberdine",
                                        b = { map = 1438, x = 54.85, y = 96.80 }, bn = "Rut'theran" },
    { kind = "Tiefenbahn", alliance = true, seconds = 150,
                                        a = { map = 1453, x = 63.91, y = 8.17 }, an = "Sturmwind",
                                        b = { map = 1455, x = 76.98, y = 51.53 }, bn = "Eisenschmiede" },
}
local legs
local function Dock(ref)
    if type(ref) == "table" then return { map = ref.map, x = ref.x, y = ref.y }, nil end
    local n = Levelmate.DB and Levelmate.DB.Npc and Levelmate.DB.Npc(ref)
    return n and n.points and n.points[1], n and n.name
end
local function Legs()
    if legs then return legs end
    local list = {}
    local faction = UnitFactionGroup and select(1, Call(UnitFactionGroup, "player"))
    for _, t in ipairs(TRANSPORTS) do
        if (not t.horde or faction == "Horde") and (not t.alliance or faction == "Alliance") then
            local pa, ma = Dock(t.a)
            local pb, mb = Dock(t.b)
            if pa and pb and Levelmate.Planner.Yards(pa, pa) and Levelmate.Planner.Yards(pb, pb) then
                local sec = t.seconds or CONFIG.shipSeconds
                list[#list + 1] = { kind = t.kind, from = pa, to = pb, fromName = L(t.an), toName = L(t.bn),
                    master = ma or (L("Anleger ") .. L(t.an)), seconds = sec }
                list[#list + 1] = { kind = t.kind, from = pb, to = pa, fromName = L(t.bn), toName = L(t.an),
                    master = mb or (L("Anleger ") .. L(t.bn)), seconds = sec }
            end
        end
    end
    if Levelmate.DB and Levelmate.DB.Available and Levelmate.DB.Available() then legs = list end
    return list
end
T.TransportLegs = Legs
function T.ResetLegs() legs = nil end   -- z. B. nach Sprachwechsel (Ortsnamen)

-- Beste Verbindung ueber genau einen Zeppelin/ein Schiff.
-- Liefert Sekunden und die genutzte Linie (oder nil).
function T.ShipRoute(a, b, walkSpeed, Yards)
    if not a or not b then return nil end
    local best, bestLeg
    for _, l in ipairs(Legs()) do
        if l.from.cont == a.cont and l.to.cont == b.cont then
            local t1 = T.Route(a, l.from, walkSpeed, Yards)
            local t2 = t1 and T.Route(l.to, b, walkSpeed, Yards)
            if t1 and t2 then
                local t = t1 + (l.seconds or CONFIG.shipSeconds) + t2
                if not best or t < best then best, bestLeg = t, l end
            end
        end
    end
    return best, bestLeg
end

-- Fuer /lm warum: Woraus besteht die geschaetzte Reisezeit?
function T.RouteParts(a, b, walkSpeed, Yards)
    local r = { straight = Yards(a, b) }
    if not r.straight then return r end
    r.trail = T.TrailYards and T.TrailYards(a, b)
    r.gate = T.WalkYards(a, b)
    r.chain = T.ChainYards and T.ChainYards(a, b)
    r.used = r.trail and "gelaufene Wege" or r.gate and "Gebietsübergang" or r.chain and "Gebietskette" or "Luftlinie"
    r.walkYd = r.trail or r.gate or r.chain or r.straight
    r.walkSec = r.walkYd / walkSpeed
    if T.ready and #fps > 0 then
        local fa = NearestFP(a, Yards)
        local fb = NearestFP(b, Yards)
        r.fa, r.fb = fa, fb
    end
    return r
end

function T.Route(a, b, walkSpeed, Yards)
    local yd = Yards(a, b)
    if not yd then return nil end
    yd = (T.TrailYards and T.TrailYards(a, b)) or T.WalkYards(a, b)
         or (T.ChainYards and T.ChainYards(a, b)) or yd   -- Trampelpfade / Uebergaenge / Gebietskette
    local walk = yd / walkSpeed
    if not T.ready or #fps == 0 then return walk end
    local fa, ya = NearestFP(a, Yards)
    local fb, yb = NearestFP(b, Yards)
    if not fa or not fb or fa == fb then return walk end
    local fly = Yards(fa.point, fb.point)
    if not fly then return walk end
    ya = (T.TrailYards and T.TrailYards(a, fa.point)) or T.WalkYards(a, fa.point)
         or (T.ChainYards and T.ChainYards(a, fa.point)) or ya
    yb = T.WalkYards(fb.point, b) or yb
    local total = ya / walkSpeed + CONFIG.overhead + fly * CONFIG.routeFactor / CONFIG.flightSpeed + yb / walkSpeed
    if total + CONFIG.minSaving < walk then return total, fa, fb end
    return walk
end

-- Flugkarte offen: bekannte Flugpunkte erfassen.
function T.OnTaxiOpened()
    Levelmate_CharDB = Levelmate_CharDB or {}
    local known = Levelmate_CharDB.knownFP or {}
    local Yards = Levelmate.Planner.Yards
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.fpNames = Levelmate_DB.fpNames or {}
    local function MarkNear(point, maxYd, name)
        local best, bestYd
        for _, fp in ipairs(fps) do
            local yd = Yards(point, fp.point)
            if yd and (not bestYd or yd < bestYd) then best, bestYd = fp, yd end
        end
        if best and bestYd <= maxYd then
            known[best.id] = true
            -- Ortsname des Flugpunkts aus dem Spiel merken, z. B. "Ratschet, Brachland"
            if type(name) == "string" and name ~= "" then Levelmate_DB.fpNames[best.id] = name end
            return true
        end
    end
    local count = 0
    local here = Levelmate.Planner.PlayerPoint()
    if here and MarkNear(here, 80) then count = count + 1 end
    local mapID = GetTaxiMapID and Call(GetTaxiMapID)
    if mapID and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
        local nodes = Call(C_TaxiMap.GetAllTaxiNodes, mapID) or {}
        local unreachable = Enum and Enum.FlightPathState and Enum.FlightPathState.Unreachable or 2
        for _, node in ipairs(nodes) do
            if node.state ~= unreachable and node.position then
                local x, y = node.position:GetXY()
                if MarkNear({ map = mapID, x = x * 100, y = y * 100 }, 300, node.name) then count = count + 1 end
            end
        end
    elseif mapID and NumTaxiNodes then
        for i = 1, (Call(NumTaxiNodes) or 0) do
            local kind = Call(TaxiNodeGetType, i)
            if kind == "CURRENT" or kind == "REACHABLE" then
                local x, y = Call(TaxiNodePosition, i)
                if x and y and MarkNear({ map = mapID, x = x * 100, y = (1 - y) * 100 }, 300, Call(TaxiNodeName, i)) then count = count + 1 end
            end
        end
    end
    Levelmate_CharDB.knownFP = known
    version = version + 1
    return count
end


---------------------------------------------------------------------------
-- Zu Fuss begehbare Verbindungen zwischen Gebieten (uiMapID -> Nachbarn).
-- Daten aus LibTourist Classic Era (Odica, MIT-Lizenz), Gebietsnamen ueber
-- QuestieDB in Karten-IDs umgerechnet. Nur Verbindungen, keine Koordinaten.
---------------------------------------------------------------------------
local ZONE_LINKS = {
    [1411] = { 1413, 1454 },
    [1412] = { 1413, 1456 },
    [1413] = { 1411, 1412, 1440, 1441, 1442, 1445, 1454 },
    [1416] = { 1422, 1424 },
    [1417] = { 1424, 1437 },
    [1418] = { 1427, 1432 },
    [1419] = { 1435 },
    [1420] = { 1421, 1422, 1458 },
    [1421] = { 1420, 1424 },
    [1422] = { 1416, 1420, 1423, 1425 },
    [1423] = { 1422 },
    [1424] = { 1416, 1417, 1421, 1425 },
    [1425] = { 1422, 1424 },
    [1426] = { 1432, 1455 },
    [1427] = { 1418, 1432 },
    [1428] = { 1433 },
    [1429] = { 1431, 1433, 1436, 1453 },
    [1430] = { 1431, 1435 },
    [1431] = { 1429, 1430, 1433, 1434, 1436 },
    [1432] = { 1418, 1426, 1427, 1437 },
    [1433] = { 1428, 1429, 1431 },
    [1434] = { 1431 },
    [1435] = { 1419, 1430 },
    [1436] = { 1429, 1431 },
    [1437] = { 1417, 1432 },
    [1438] = { 1457 },
    [1439] = { 1440 },
    [1440] = { 1413, 1439, 1442, 1447, 1448 },
    [1441] = { 1413, 1444, 1446 },
    [1442] = { 1413, 1440, 1443 },
    [1443] = { 1442, 1444 },
    [1444] = { 1441, 1443 },
    [1445] = { 1413 },
    [1446] = { 1441, 1449 },
    [1447] = { 1440 },
    [1448] = { 1440, 1450, 1452 },
    [1449] = { 1446, 1451 },
    [1450] = { 1448 },
    [1451] = { 1449 },
    [1452] = { 1448 },
    [1453] = { 1429 },
    [1454] = { 1411, 1413 },
    [1455] = { 1426 },
    [1456] = { 1412 },
    [1457] = { 1438 },
    [1458] = { 1420 },
}

local function CDist(ax, ay, bx, by) local dx, dy = ax - bx, ay - by; return math.sqrt(dx * dx + dy * dy) end

-- Kette von Gebieten (kuerzeste Anzahl Wechsel) von Karte a nach Karte b
local chainCache = {}
local function ZoneChain(ma, mb)
    if ma == mb then return { ma } end
    local key = ma .. ">" .. mb
    if chainCache[key] ~= nil then return chainCache[key] or nil end
    if not ZONE_LINKS[ma] or not ZONE_LINKS[mb] then chainCache[key] = false; return nil end
    local prev, queue, head = { [ma] = ma }, { ma }, 1
    while queue[head] do
        local m = queue[head]; head = head + 1
        if m == mb then break end
        for _, n in ipairs(ZONE_LINKS[m] or {}) do
            if not prev[n] then prev[n] = m; queue[#queue + 1] = n end
        end
    end
    if not prev[mb] then chainCache[key] = false; return nil end
    local chain, m = {}, mb
    while m ~= ma do table.insert(chain, 1, m); m = prev[m] end
    table.insert(chain, 1, ma)
    chainCache[key] = chain
    return chain
end
T.ZoneChain = ZoneChain

-- Weg ueber die Gebietskette: Liegen zwischen Start- und Zielgebiet weitere
-- Gebiete (man kann also nicht direkt hinueber laufen), wird der Weg laenger
-- angesetzt: je Zwischengebiet 30 % mehr als die Luftlinie, hoechstens doppelt.
-- Grobe Schaetzung - die genauen Stellen liefern gelernte Uebergaenge und
-- Trampelpfade. nil = direkte Nachbarn oder unbekannt.
function T.ChainYards(a, b)
    if not a or not b or a.map == b.map or not a.wx or not b.wx or a.cont ~= b.cont then return nil end
    local chain = ZoneChain(a.map, b.map)
    if not chain then return nil end
    local straight = CDist(a.wx, a.wy, b.wx, b.wy)
    -- Direktes Nachbargebiet ohne gelernten Uebergang: Gebietsgrenzen sind fast
    -- immer Gebirge, der Weg fuehrt ueber einen Pass -> 60 % Aufschlag.
    if #chain == 2 then return straight * 1.6 end
    return straight * math.min(2, 1 + 0.3 * (#chain - 2))
end

---------------------------------------------------------------------------
-- Gebietsuebergaenge (Laufwege zwischen Gebieten)
-- Das Spiel liefert Addons keine Wege. Deshalb lernt das Addon die echten
-- Uebergaenge selbst: Laeufst (oder reitest) du von einem Gebiet ins
-- naechste, merkt es sich die Stelle. Fluege, Ruhestein, Portale und
-- Dungeons zaehlen nicht (Sprung in der Position). Ohne gelernten Uebergang
-- bleibt es bei der Luftlinie.
---------------------------------------------------------------------------
local GATE_MERGE = 80     -- Yards: naeher beieinander = derselbe Uebergang
local GATE_MAX = 8        -- hoechstens so viele Uebergaenge je Gebietspaar
local MAX_STEP = 60       -- Yards zwischen zwei Messungen (1 s), sonst Sprung

local gateList, gateDirty = nil, true
local fromGate = {}       -- Dijkstra-Ergebnisse je Start-Uebergang

local function GateStore()
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.gates = Levelmate_DB.gates or {}
    return Levelmate_DB.gates
end

local function PairKey(m1, m2)
    if m1 > m2 then m1, m2 = m2, m1 end
    return m1 .. "-" .. m2
end

-- Nur "richtige" Gebiete und Staedte, keine Hoehlen/Dungeons
local function IsZoneMap(map)
    if not (C_Map and C_Map.GetMapInfo) then return true end
    local info = Call(C_Map.GetMapInfo, map)
    if not info then return false end
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    return info.mapType == zoneType
end

local function Dist(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return math.sqrt(dx * dx + dy * dy)
end

-- Feste Gebietsuebergaenge (Paesse/Strassen), damit Levelmate die echten Wege
-- von Anfang an kennt - auch bevor du sie selbst gelaufen bist.
-- { Karte A, Karte B, Karte der Koordinate, x, y }  (Koordinaten wie auf der Karte)
-- Quellen: Leveling-Guides/Wikis (Classic/Forever) und Kartenauswertung; auf
-- etwa 50-100 Yards genau - fuer die Wegberechnung reicht das. Gelernte
-- Uebergaenge (selbst gelaufen oder geteilt) haben Vorrang.
local STATIC_GATES = {
    { 1411, 1413, 1413, 62.8, 19.6 },  -- Durotar <-> Brachland: Bruecke am Wachposten (Far Watch Post)
    { 1413, 1440, 1413, 48.2,  5.0 },  -- Brachland <-> Eschental: Mor'shan-Wall (Goldstrasse)
    { 1413, 1442, 1413, 35.0, 27.0 },  -- Brachland <-> Steinkrallengebirge: Strasse im Westen
    { 1413, 1445, 1445, 28.5, 47.3 },  -- Brachland <-> Duesterwald (Marschen): beim Gasthaus Zur Schattenruh
    { 1442, 1443, 1443, 55.3,  5.0 },  -- Steinkrallengebirge (Verbranntes Tal) <-> Desolace: Pass im Norden
    { 1443, 1444, 1443, 45.0, 98.5 },  -- Desolace <-> Feralas: Strasse im Sueden
    { 1441, 1444, 1444, 89.8, 46.0 },  -- Tausend Nadeln <-> Feralas: Strasse bei Thalanaar
    { 1440, 1442, 1442, 78.5, 43.0 },  -- Eschental <-> Steinkrallengebirge: Klauenpfad (Tunnel)
    -- 1.0.3: weitere Kalimdor-Uebergaenge (Guides + auf der Forever-Karte geprueft)
    { 1411, 1454, 1411, 45.5, 11.0 },  -- Durotar <-> Orgrimmar: Haupttor
    { 1412, 1413, 1412, 68.0, 61.5 },  -- Mulgore <-> Brachland: Pass im Osten (Richtung Camp Taurajo)
    { 1413, 1441, 1441, 32.2, 22.2 },  -- Brachland <-> Tausend Nadeln: Grosser Aufzug (unten)
    { 1441, 1446, 1441, 75.0, 95.0 },  -- Tausend Nadeln <-> Tanaris: Pass suedlich der Schimmernden Ebene
    { 1446, 1449, 1446, 27.0, 56.0 },  -- Tanaris <-> Un'Goro: Pfad im Distelstrauchtal
    { 1449, 1451, 1449, 29.0, 22.0 },  -- Un'Goro <-> Silithus: Rampe im Nordwesten
    { 1439, 1440, 1440, 29.0, 13.0 },  -- Dunkelkueste <-> Eschental: Strasse noerdlich von Maestras Posten
    { 1440, 1448, 1440, 55.3, 27.0 },  -- Eschental <-> Teufelswald: Abzweig nach Norden
    { 1440, 1447, 1440, 94.5, 47.5 },  -- Eschental <-> Azshara: Strasse ueber den Fluss
    { 1448, 1450, 1448, 65.1,  8.2 },  -- Teufelswald <-> Mondlichtung: Holzschlundfeste (Tunnel)
    { 1448, 1452, 1448, 65.1,  8.2 },  -- Teufelswald <-> Winterquell: Holzschlundfeste (Tunnel)
    -- 1.0.3: Oestliche Koenigreiche (Grenzen der Gebietskarten = Classic)
    { 1429, 1453, 1429, 32.0, 49.5 },  -- Elwynn <-> Sturmwind: Stadttor
    { 1426, 1455, 1426, 53.5, 35.0 },  -- Dun Morogh <-> Eisenschmiede: Stadttor
    { 1429, 1436, 1429, 21.5, 80.0 },  -- Elwynn <-> Westfall: Bruecke
    { 1429, 1431, 1431, 92.5,  9.0 },  -- Elwynn <-> Daemmerwald: Bruecke im Nordosten
    { 1429, 1433, 1433, 15.3, 71.5 },  -- Elwynn <-> Rotkamm: Drei Ecken
    { 1431, 1433, 1433, 15.3, 71.5 },  -- Daemmerwald <-> Rotkamm: Drei Ecken
    { 1431, 1436, 1431,  8.0, 62.0 },  -- Daemmerwald <-> Westfall: Bruecke im Westen
    { 1431, 1434, 1431, 44.0, 90.0 },  -- Daemmerwald <-> Schlingendorn: Strasse nach Sueden
    { 1430, 1431, 1431, 88.0, 40.0 },  -- Daemmerwald <-> Gebirgspass: oestlich von Dunkelhain
    { 1430, 1435, 1435,  5.0, 51.5 },  -- Gebirgspass <-> Suempfe des Elends
    { 1419, 1435, 1435, 33.0, 75.0 },  -- Suempfe <-> Verwuestete Lande: Strasse nach Sueden
    { 1428, 1433, 1433, 41.5,  6.0 },  -- Rotkamm <-> Brennende Steppe: Strasse nach Norden
    { 1418, 1427, 1418,  5.8, 60.4 },  -- Oedland <-> Sengende Schlucht: Pass im Westen
    { 1418, 1432, 1432, 46.0, 85.0 },  -- Loch Modan <-> Oedland: Pass bei Uldaman
    { 1426, 1432, 1432, 19.3, 62.0 },  -- Dun Morogh <-> Loch Modan: Tunnel (Suedtor)
    { 1432, 1437, 1437, 54.0, 71.0 },  -- Loch Modan <-> Sumpfland: Dun Algaz
    { 1417, 1437, 1437, 51.0,  9.0 },  -- Sumpfland <-> Arathi: Thandoluebergang
    { 1417, 1424, 1424, 81.0, 55.0 },  -- Arathi <-> Hillsbrad: Thoradinswall
    { 1424, 1425, 1424, 89.5, 42.0 },  -- Hillsbrad <-> Hinterland: Bergpfad noerdlich Durnholde
    { 1416, 1424, 1424, 54.5,  8.0 },  -- Hillsbrad <-> Alterac: Strasse noerdlich von Tarrens Muehle
    { 1421, 1424, 1424,  8.0, 46.0 },  -- Silberwald <-> Hillsbrad: Strasse im Westen
    { 1420, 1421, 1421, 66.0,  6.0 },  -- Tirisfal <-> Silberwald: Strasse im Norden
    { 1420, 1422, 1420, 85.5, 68.5 },  -- Tirisfal <-> Westliche Pestlaender: Bollwerk
    { 1422, 1423, 1422, 69.5, 50.0 },  -- Westliche <-> Oestliche Pestlaender: Bruecke am Thondroril
}
local trailGates = {}   -- aus gelaufenen Wegen abgeleitete Uebergaenge (siehe unten)
local staticCache
local function StaticGates()
    if staticCache then return staticCache end
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return {} end
    staticCache = {}
    for _, s in ipairs(STATIC_GATES) do
        local cont, vec = Call(C_Map.GetWorldPosFromMapPos, s[3], CreateVector2D(s[4] / 100, s[5] / 100))
        if cont and vec then
            local wx, wy = vec:GetXY()
            staticCache[#staticCache + 1] = { m1 = s[1], m2 = s[2], cont = cont, wx = wx, wy = wy, static = true,
                pts = { [tostring(s[3])] = { s[4], s[5] } } }
        end
    end
    return staticCache
end

-- Alle Uebergaenge als Liste (fuer die Wegsuche)
local function Gates()
    if not gateDirty and gateList then return gateList end
    gateList, fromGate, gateDirty = {}, {}, false
    for key, list in pairs(GateStore()) do
        local m1, m2 = key:match("^(%d+)%-(%d+)$")
        m1, m2 = tonumber(m1), tonumber(m2)
        if m1 and m2 then
            for _, g in ipairs(list) do
                table.insert(gateList, { m1 = m1, m2 = m2, cont = g.cont, wx = g.wx, wy = g.wy, pts = g.pts })
            end
        end
    end
    -- feste und aus Wegen abgeleitete Uebergaenge dazu, wenn kein gelernter in der Naehe liegt
    local extra = {}
    for _, sg in ipairs(StaticGates()) do extra[#extra + 1] = sg end
    for _, tg in ipairs(trailGates) do extra[#extra + 1] = tg end
    for _, sg in ipairs(extra) do
        local dup = false
        for _, g in ipairs(gateList) do
            if g.cont == sg.cont and ((g.m1 == sg.m1 and g.m2 == sg.m2) or (g.m1 == sg.m2 and g.m2 == sg.m1))
               and Dist(g.wx, g.wy, sg.wx, sg.wy) < 200 then dup = true; break end
        end
        if not dup then table.insert(gateList, sg) end
    end
    if not staticCache then gateDirty = true end   -- Karten-API noch nicht bereit: spaeter nochmal
    return gateList
end
T.StaticGateCount = function() return #STATIC_GATES end

local function Touches(g, map) return g.m1 == map or g.m2 == map end

-- Kuerzeste Wege von Uebergang i zu allen anderen (Dijkstra, Kanten nur
-- zwischen Uebergaengen, die ein gemeinsames Gebiet haben).
local function DistancesFrom(i)
    if fromGate[i] then return fromGate[i] end
    local list = Gates()
    local dist, done = {}, {}
    dist[i] = 0
    while true do
        local u, best
        for k, d in pairs(dist) do
            if not done[k] and (not best or d < best) then u, best = k, d end
        end
        if not u then break end
        done[u] = true
        local gu = list[u]
        for v, gv in ipairs(list) do
            if not done[v] and gv.cont == gu.cont
               and (Touches(gv, gu.m1) or Touches(gv, gu.m2)) then
                local nd = best + Dist(gu.wx, gu.wy, gv.wx, gv.wy)
                if not dist[v] or nd < dist[v] then dist[v] = nd end
            end
        end
    end
    fromGate[i] = dist
    return dist
end

-- Laufweg in Yards von a nach b ueber gelernte Uebergaenge.
-- nil = unbekannt (dann gilt die Luftlinie). Zweiter Rueckgabewert: der
-- erste Uebergang auf dem Weg (fuer den Pfeil).
function T.WalkYards(a, b)
    if not a or not b or a.map == b.map or not a.wx or not b.wx or a.cont ~= b.cont then return nil end
    local list = Gates()
    if #list == 0 then return nil end
    -- Zwischenergebnis je Startpunkt und Zielgebiet merken: fuer jeden
    -- Uebergang h am Zielgebiet der kuerzeste Weg a -> h (und der erste Uebergang)
    if a._walkVer ~= list then a._walkVer, a._walkMaps = list, {} end
    local ends = a._walkMaps[b.map]
    if not ends then
        ends = {}
        for i, g in ipairs(list) do
            if g.cont == a.cont and Touches(g, a.map) then
                local d0 = Dist(a.wx, a.wy, g.wx, g.wy)
                for j, d in pairs(DistancesFrom(i)) do
                    local h = list[j]
                    if Touches(h, b.map) and (not ends[j] or d0 + d < ends[j].base) then
                        ends[j] = { h = h, base = d0 + d, first = g }
                    end
                end
            end
        end
        a._walkMaps[b.map] = ends
    end
    local best, bestGate
    for _, e in pairs(ends) do
        local total = e.base + Dist(e.h.wx, e.h.wy, b.wx, b.wy)
        if not best or total < best then best, bestGate = total, e.first end
    end
    return best, bestGate
end

-- Wegpunkt fuer den Pfeil: der naechste Uebergang, falls das Ziel in einem
-- anderen Gebiet liegt und ein Weg bekannt ist.
function T.NextWaypoint(a, b)
    local _, g = T.WalkYards(a, b)
    if not g or not g.pts then return nil end
    local p = g.pts[tostring(a.map)]
    if not p then return nil end
    local other = (g.m1 == a.map) and g.m2 or g.m1
    return { map = a.map, x = p[1], y = p[2] }, other
end

local function RecordGate(last, now)
    local store = GateStore()
    local key = PairKey(last.map, now.map)
    local list = store[key] or {}
    store[key] = list
    local wx, wy = (last.wx + now.wx) / 2, (last.wy + now.wy) / 2
    for _, g in ipairs(list) do
        if g.cont == now.cont and Dist(g.wx, g.wy, wx, wy) < GATE_MERGE then
            g.n = (g.n or 1) + 1
            return false
        end
    end
    if #list >= GATE_MAX then return false end
    local entry = {
        cont = now.cont, wx = wx, wy = wy, n = 1,
        pts = { [tostring(last.map)] = { last.x, last.y }, [tostring(now.map)] = { now.x, now.y } },
    }
    table.insert(list, entry)
    gateDirty = true
    if T.OnGateLearned then pcall(T.OnGateLearned, last.map, now.map, entry) end
    return true
end

-- Uebergang von einem Gruppenmitglied uebernehmen
function T.AddSharedGate(m1, m2, entry)
    local store = GateStore()
    local key = PairKey(m1, m2)
    local list = store[key] or {}
    store[key] = list
    for _, g in ipairs(list) do
        if g.cont == entry.cont and Dist(g.wx, g.wy, entry.wx, entry.wy) < GATE_MERGE then return false end
    end
    if #list >= GATE_MAX then return false end
    table.insert(list, entry)
    gateDirty = true
    return true
end
function T.AllGates()
    local out = {}
    for key, list in pairs(GateStore()) do
        local m1, m2 = key:match("^(%d+)%-(%d+)$")
        for _, g in ipairs(list) do out[#out + 1] = { m1 = tonumber(m1), m2 = tonumber(m2), g = g } end
    end
    return out
end

local lastSample
function T.SampleGate()
    if UnitOnTaxi and UnitOnTaxi("player") then lastSample = nil; return end
    local p = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    if not p or not p.wx or not IsZoneMap(p.map) then lastSample = nil; return end
    local t = GetTime and GetTime() or 0
    local last = lastSample
    lastSample = { map = p.map, x = p.x, y = p.y, wx = p.wx, wy = p.wy, cont = p.cont, t = t }
    if last and last.map ~= p.map and last.cont == p.cont and (t - last.t) <= 3
       and Dist(last.wx, last.wy, p.wx, p.wy) <= MAX_STEP then
        if RecordGate(last, lastSample) and Levelmate.RequestRefresh then Levelmate.RequestRefresh() end
    end
end

function T.GateCount()
    local n, pairsN = 0, 0
    for _, list in pairs(GateStore()) do pairsN = pairsN + 1; n = n + #list end
    return n, pairsN
end

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(1, function() pcall(T.SampleGate) end)
end


---------------------------------------------------------------------------
-- Ruhestein
-- Der Ort wird gemerkt, wenn du dich an einem Gasthaus bindest oder den
-- Ruhestein benutzt (Position nach der Landung). Abklingzeit fragt das Addon
-- das Spiel.
---------------------------------------------------------------------------
local HEARTHSTONE_ITEM, HEARTHSTONE_SPELL = 6948, 8690

local function CharStore()
    Levelmate_CharDB = Levelmate_CharDB or {}
    return Levelmate_CharDB
end

local function HearthCooldownLeft()
    local start, duration
    if C_Container and C_Container.GetItemCooldown then
        start, duration = Call(C_Container.GetItemCooldown, HEARTHSTONE_ITEM)
    elseif GetItemCooldown then
        start, duration = Call(GetItemCooldown, HEARTHSTONE_ITEM)
    end
    if not start or start == 0 or not duration then return 0 end
    local now = GetTime and GetTime() or 0
    return math.max(0, start + duration - now)
end

local function HasHearthstone()
    local n = (C_Item and C_Item.GetItemCount and Call(C_Item.GetItemCount, HEARTHSTONE_ITEM))
           or (GetItemCount and Call(GetItemCount, HEARTHSTONE_ITEM)) or 0
    return n > 0
end

-- Ziel des Ruhesteins, falls bekannt und sofort benutzbar; sonst nil.
-- Ruhestein-Ort schaetzen, solange er noch nicht gemessen ist: Gastwirt,
-- dessen Gebiet oder naechster Flugpunkt so heisst wie dein Bindungsort
-- (z. B. "Orgrimmar" oder "Das Wegekreuz").
local guess = {}
local function GuessHearth()
    local bind = GetBindLocation and Call(GetBindLocation)
    if type(bind) ~= "string" or bind == "" or #inns == 0 then return nil end
    if guess.bind == bind then return guess.point end
    local names = Levelmate_DB and Levelmate_DB.fpNames or {}
    local Yards = Levelmate.Planner.Yards
    local found
    for _, inn in ipairs(inns) do
        if Levelmate.Planner.MapName(inn.point.map) == bind then found = inn.point; break end
        for _, fp in ipairs(fps) do
            local nm = names[fp.id]
            local place = nm and (nm:match("^([^,]+)") or nm)
            if place == bind then
                local yd = Yards(inn.point, fp.point)
                if yd and yd < 400 then found = inn.point; break end
            end
        end
        if found then break end
    end
    guess = { bind = bind, point = found and { map = found.map, x = found.x, y = found.y } or nil }
    return guess.point
end
function T.HearthGuessed() return CharStore().hearth == nil and guess.point ~= nil end

function T.HearthOption()
    local h = CharStore().hearth
    local bind = GetBindLocation and Call(GetBindLocation)
    if h and h.bind and bind and h.bind ~= bind then h = nil end   -- neu gebunden
    if not h or not h.map then h = GuessHearth() end
    if not h or not h.map then return nil end
    if Levelmate_DB and Levelmate_DB.useHearth == false then return nil end
    if not HasHearthstone() or HearthCooldownLeft() > 0 then return nil end
    T._hearthPoint = T._hearthPoint and T._hearthPoint.map == h.map and T._hearthPoint.x == h.x and T._hearthPoint
        or { map = h.map, x = h.x, y = h.y }
    return T._hearthPoint
end

function T.HearthName()
    local name = GetBindLocation and Call(GetBindLocation)
    if type(name) == "string" and name ~= "" then return name end
    local h = CharStore().hearth
    return h and Levelmate.Planner.MapName(h.map) or "?"
end

function T.HearthKnown() return CharStore().hearth ~= nil end

local hearthPending, hearthFrom
local function RememberHere(why)
    local p = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    if not p then return false end
    if why == "landed" and hearthFrom then
        -- Erst merken, wenn du wirklich woanders bist (Teleport abgeschlossen)
        local yd = Levelmate.Planner.Yards(hearthFrom, p)
        if yd and yd < 200 then return false end
    end
    CharStore().hearth = { map = p.map, x = p.x, y = p.y, bind = GetBindLocation and Call(GetBindLocation) }
    T._hearthPoint = nil
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
    return true
end

local hf = CreateFrame("Frame")
pcall(hf.RegisterEvent, hf, "HEARTHSTONE_BOUND")
if hf.RegisterUnitEvent then pcall(hf.RegisterUnitEvent, hf, "UNIT_SPELLCAST_SUCCEEDED", "player")
else pcall(hf.RegisterEvent, hf, "UNIT_SPELLCAST_SUCCEEDED") end
pcall(hf.RegisterEvent, hf, "PLAYER_ENTERING_WORLD")
hf:SetScript("OnEvent", function(_, event, unit, _, spellID)
    if event == "HEARTHSTONE_BOUND" then
        RememberHere("bind")
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" and unit == "player" and spellID == HEARTHSTONE_SPELL then
        hearthPending = GetTime and GetTime() or 0
        hearthFrom = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    elseif event == "PLAYER_ENTERING_WORLD" and hearthPending then
        -- nach dem Ladebildschirm kurz warten, bis die Position stimmt
        if C_Timer and C_Timer.After then
            C_Timer.After(2, function() if RememberHere("landed") then hearthPending = nil end end)
        end
    end
end)
-- Ruhestein ohne Ladebildschirm (gleicher Kontinent): Landung beim naechsten Messen
local oldSample = T.SampleGate
function T.SampleGate()
    if hearthPending and GetTime then
        local dt = GetTime() - hearthPending
        if dt > 120 then hearthPending = nil
        elseif dt > 1 and RememberHere("landed") then hearthPending = nil end
    end
    return oldSample()
end


---------------------------------------------------------------------------
-- Trampelpfade: Wo du laeufst oder reitest, merkt sich das Addon die Stelle
-- (Raster von 50 Yards, fuer alle Charaktere). Daraus entsteht mit der Zeit
-- eine Karte echter Wege. Die Wegberechnung ab deiner Position nutzt diese
-- Wege, wenn sie einen Umweg zeigen, den die Luftlinie nicht kennt (Berge,
-- Mauern, Hoehlenausgaenge). Unbekannt = weiter Luftlinie / Uebergaenge.
---------------------------------------------------------------------------
local CELL = 50            -- Yards je Rasterfeld
local START_R = 150        -- so nah muss ein bekanntes Wegfeld am Start/Ziel liegen
local FIELD_MAX = 4000     -- Yards: so weit reicht die Wegsuche ab deiner Position
local MAX_CELLS = 80000    -- Obergrenze je Kontinent

local function TrailStore(cont)
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.trails = Levelmate_DB.trails or {}
    local t = Levelmate_DB.trails[cont]
    if not t then t = { n = 0, c = {} }; Levelmate_DB.trails[cont] = t end
    return t
end

local trailVersion = 0
local function CellKey(cx, cy) return cx .. "," .. cy end

-- Feld als begangen markieren; true, wenn neu
function T.AddTrailCell(cont, cx, cy)
    local t = TrailStore(cont)
    local k = CellKey(cx, cy)
    if t.c[k] or t.n >= MAX_CELLS then return false end
    t.c[k] = 1
    t.n = t.n + 1
    trailVersion = trailVersion + 1
    return true
end

local function MarkLine(cont, ax, ay, bx, by, newCells)
    local d = Dist(ax, ay, bx, by)
    local steps = math.max(1, math.ceil(d / (CELL / 2)))
    for i = 0, steps do
        local x = ax + (bx - ax) * i / steps
        local y = ay + (by - ay) * i / steps
        local cx, cy = math.floor(x / CELL), math.floor(y / CELL)
        if T.AddTrailCell(cont, cx, cy) and newCells then newCells[#newCells + 1] = { cx, cy } end
    end
end

local lastTrail
function T.SampleTrail()
    if UnitOnTaxi and UnitOnTaxi("player") then lastTrail = nil; return end
    if IsInInstance and IsInInstance() then lastTrail = nil; return end
    local p = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    if not p or not p.wx or not p.cont then lastTrail = nil; return end
    local new = {}
    if lastTrail and lastTrail.cont == p.cont and Dist(lastTrail.wx, lastTrail.wy, p.wx, p.wy) <= 60 then
        MarkLine(p.cont, lastTrail.wx, lastTrail.wy, p.wx, p.wy, new)
    else
        local cx, cy = math.floor(p.wx / CELL), math.floor(p.wy / CELL)
        if T.AddTrailCell(p.cont, cx, cy) then new[1] = { cx, cy } end
    end
    lastTrail = { wx = p.wx, wy = p.wy, cont = p.cont }
    if #new > 0 and T.OnTrailLearned then pcall(T.OnTrailLearned, p.cont, new) end
end

function T.TrailCount()
    local n = 0
    for _, t in pairs((Levelmate_DB and Levelmate_DB.trails) or {}) do n = n + (t.n or 0) end
    return n
end

---------------------------------------------------------------------------
-- Uebergaenge aus gelaufenen Wegen ableiten
-- Jeder gelaufene Weg (eigene Trampelpfade und das mitgelieferte Startwissen)
-- wird auf die Gebietskarten gelegt: Wo zwei benachbarte Wegfelder in
-- verschiedenen Gebieten liegen, ist ein begehbarer Uebergang. Das Spiel
-- sagt dafuer selbst, zu welchem Gebiet eine Stelle gehoert (echte
-- Gebietsgrenzen, nicht nur Rechtecke). Laeuft in kleinen Portionen im
-- Hintergrund, damit es nicht ruckelt.
---------------------------------------------------------------------------
local CONT_MAP = { [0] = 1415, [1] = 1414 }
local zoneAt = {}           -- ["cont:cx,cy"] = Karten-ID oder false
local deriveVer = -1
local deriving = false

local function ZoneAtCell(cont, cx, cy)
    local key = cont .. ":" .. cx .. "," .. cy
    local z = zoneAt[key]
    if z ~= nil then return z or nil end
    z = false
    local cm = CONT_MAP[cont]
    if cm and C_Map and C_Map.GetMapPosFromWorldPos and C_Map.GetMapInfoAtPosition and CreateVector2D then
        local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, CreateVector2D(cx * CELL + CELL / 2, cy * CELL + CELL / 2), cm)
        if ok and pos then
            local px, py = pos:GetXY()
            local ok2, info = pcall(C_Map.GetMapInfoAtPosition, cm, px, py)
            if ok2 and info and info.mapID and info.mapID ~= cm and IsZoneMap(info.mapID) then z = info.mapID end
        end
    end
    zoneAt[key] = z
    return z or nil
end

local NEIGHBORS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }
function T.DeriveTrailGates(onDone)
    if deriving or deriveVer == trailVersion then return end
    if not (C_Map and C_Map.GetMapInfoAtPosition and C_Timer and C_Timer.After) then return end
    deriving = true
    local startVer = trailVersion
    local cells = {}
    for cont, t in pairs((Levelmate_DB and Levelmate_DB.trails) or {}) do
        if CONT_MAP[cont] then
            for k in pairs(t.c or {}) do
                local cx, cy = k:match("^(-?%d+),(-?%d+)$")
                if cx then cells[#cells + 1] = { cont, tonumber(cx), tonumber(cy), t.c } end
            end
        end
    end
    local found, i = {}, 1
    local function Add(cont, m1, m2, wx, wy)
        for _, g in ipairs(found) do
            if g.cont == cont and ((g.m1 == m1 and g.m2 == m2) or (g.m1 == m2 and g.m2 == m1))
               and Dist(g.wx, g.wy, wx, wy) < 150 then return end
        end
        found[#found + 1] = { m1 = m1, m2 = m2, cont = cont, wx = wx, wy = wy, derived = true }
    end
    local function Step()
        local stop = math.min(#cells, i + 299)
        for j = i, stop do
            local cont, cx, cy, map = cells[j][1], cells[j][2], cells[j][3], cells[j][4]
            local za
            for _, d in ipairs(NEIGHBORS) do
                local nx, ny = cx + d[1], cy + d[2]
                if map[nx .. "," .. ny] then
                    za = za or ZoneAtCell(cont, cx, cy)
                    local zb = za and ZoneAtCell(cont, nx, ny)
                    if za and zb and za ~= zb then
                        Add(cont, za, zb, (cx + nx + 1) * CELL / 2, (cy + ny + 1) * CELL / 2)
                    end
                end
            end
        end
        i = stop + 1
        if i <= #cells then
            C_Timer.After(0.05, Step)
        else
            trailGates = found
            gateDirty = true
            deriveVer, deriving = startVer, false
            if onDone then pcall(onDone, #found) end
        end
    end
    Step()
end
function T.TrailGateCount() return #trailGates end

-- Nach dem Einloggen und danach alle 10 Minuten (falls neue Wege dazukamen)
if C_Timer and C_Timer.After and C_Timer.NewTicker then
    C_Timer.After(15, function()
        pcall(T.DeriveTrailGates, function() if Levelmate.RequestRefresh then Levelmate.RequestRefresh() end end)
    end)
    C_Timer.NewTicker(600, function() pcall(T.DeriveTrailGates) end)
end

-- Kleiner Binaer-Heap fuer die Wegsuche
local function HeapPush(h, k, d)
    h.n = h.n + 1
    local i = h.n
    h.k[i], h.d[i] = k, d
    while i > 1 do
        local p = math.floor(i / 2)
        if h.d[p] <= h.d[i] then break end
        h.k[p], h.k[i] = h.k[i], h.k[p]
        h.d[p], h.d[i] = h.d[i], h.d[p]
        i = p
    end
end
local function HeapPop(h)
    if h.n == 0 then return nil end
    local k, d = h.k[1], h.d[1]
    h.k[1], h.d[1] = h.k[h.n], h.d[h.n]
    h.k[h.n], h.d[h.n] = nil, nil
    h.n = h.n - 1
    local i = 1
    while true do
        local l, r, m = 2 * i, 2 * i + 1, i
        if l <= h.n and h.d[l] < h.d[m] then m = l end
        if r <= h.n and h.d[r] < h.d[m] then m = r end
        if m == i then break end
        h.k[m], h.k[i] = h.k[i], h.k[m]
        h.d[m], h.d[i] = h.d[i], h.d[m]
        i = m
    end
    return k, d
end

-- Wegsuche ab einem Punkt ueber alle begangenen Felder (einmal je Position)
local field
local NEIGH = {}
for dx = -1, 1 do for dy = -1, 1 do
    if dx ~= 0 or dy ~= 0 then NEIGH[#NEIGH + 1] = { dx, dy, math.sqrt(dx * dx + dy * dy) * CELL } end
end end

local function BuildField(origin)
    local t = Levelmate_DB and Levelmate_DB.trails and Levelmate_DB.trails[origin.cont]
    if not t or (t.n or 0) < 20 then return nil end
    local cells = t.c
    local ox, oy = math.floor(origin.wx / CELL), math.floor(origin.wy / CELL)
    local dist, h = {}, { n = 0, k = {}, d = {} }
    local r = math.ceil(START_R / CELL)
    for dx = -r, r do for dy = -r, r do
        local cx, cy = ox + dx, oy + dy
        local k = CellKey(cx, cy)
        if cells[k] then
            local d = Dist(origin.wx, origin.wy, (cx + 0.5) * CELL, (cy + 0.5) * CELL)
            if d <= START_R and (not dist[k] or d < dist[k]) then dist[k] = d; HeapPush(h, k, d) end
        end
    end end
    if h.n == 0 then return nil end
    local done, expanded = {}, 0
    while true do
        local k, d = HeapPop(h)
        if not k then break end
        if not done[k] then
            done[k] = true
            expanded = expanded + 1
            if expanded > 12000 or d > FIELD_MAX then break end
            local cx, cy = k:match("^(-?%d+),(-?%d+)$")
            cx, cy = tonumber(cx), tonumber(cy)
            for _, nb in ipairs(NEIGH) do
                local nk = CellKey(cx + nb[1], cy + nb[2])
                if cells[nk] and not done[nk] then
                    local nd = d + nb[3]
                    if not dist[nk] or nd < dist[nk] then dist[nk] = nd; HeapPush(h, nk, nd) end
                end
            end
        end
    end
    return { cont = origin.cont, ox = ox, oy = oy, dist = dist, version = trailVersion }
end

-- Planer: Startpunkt fuer diese Planung setzen (nur echte Position, keine Vorschau)
function T.SetTrailOrigin(p)
    T._trailOrigin = p
    if not p or not p.wx or not p.cont then return end
    local ox, oy = math.floor(p.wx / CELL), math.floor(p.wy / CELL)
    if field and field.cont == p.cont and math.abs(field.ox - ox) <= 6 and math.abs(field.oy - oy) <= 6
       and trailVersion - field.version < 200 then
        return
    end
    field = BuildField(p)
end

-- Laufweg in Yards ueber bekannte Wege; nil = unbekannt
function T.TrailYards(a, b)
    if not field or a ~= T._trailOrigin or not b or not b.wx or b.cont ~= field.cont then return nil end
    local straight = Dist(a.wx, a.wy, b.wx, b.wy)
    if straight < 300 then return nil end
    local bx, by = math.floor(b.wx / CELL), math.floor(b.wy / CELL)
    local r = math.ceil(START_R / CELL)
    local best
    for dx = -r, r do for dy = -r, r do
        local d = field.dist[CellKey(bx + dx, by + dy)]
        if d then
            local tail = Dist((bx + dx + 0.5) * CELL, (by + dy + 0.5) * CELL, b.wx, b.wy)
            if tail <= START_R and (not best or d + tail < best) then best = d + tail end
        end
    end end
    if not best then return nil end
    -- Nur echte Umwege uebernehmen; viel laengere Wege heissen meist nur,
    -- dass der direkte Weg noch nicht begangen wurde.
    if best < straight * 1.15 or best > straight * 3 then return nil end
    return best
end

-- Pfeil entlang bekannter Wege: Fuehrt der kuerzeste bekannte Weg deutlich um
-- etwas herum (Serpentinen, Rampe auf ein Plateau), zeigt der Pfeil auf einen
-- Punkt ca. 100 Yards voraus auf diesem Weg statt per Luftlinie zum Ziel.
-- Liefert {map, x, y, cont, wx, wy} oder nil (dann Luftlinie).
local lastFieldRebuild = 0
function T.TrailWaypoint(a, b)
    if not a or not b or not a.wx or not b.wx then return nil end
    -- Das Wegfeld wurde vom Planungsstartpunkt aus berechnet. Bist du inzwischen
    -- woanders (z. B. anderen Weg genommen), wuerde der Pfeil zurueck zum alten
    -- Startpunkt fuehren -> Feld von deiner Position neu aufbauen (hoechstens alle 5 s).
    local px0, py0 = math.floor(a.wx / CELL), math.floor(a.wy / CELL)
    if not field or field.cont ~= a.cont or math.abs(field.ox - px0) > 6 or math.abs(field.oy - py0) > 6 then
        local now = GetTime and GetTime() or 0
        if now - lastFieldRebuild < 5 then return nil end
        lastFieldRebuild = now
        field = BuildField(a)
        T._trailOrigin = a
    end
    if not field or a.cont ~= field.cont or b.cont ~= field.cont then return nil end
    local straight = Dist(a.wx, a.wy, b.wx, b.wy)
    if straight < 150 then return nil end
    local r = math.ceil(START_R / CELL)
    -- Ende des Weges: bestes bekanntes Feld nahe am Ziel
    local bx, by = math.floor(b.wx / CELL), math.floor(b.wy / CELL)
    local best, ex, ey
    for dx = -r, r do for dy = -r, r do
        local d = field.dist[CellKey(bx + dx, by + dy)]
        if d then
            local tail = Dist((bx + dx + 0.5) * CELL, (by + dy + 0.5) * CELL, b.wx, b.wy)
            if tail <= START_R and (not best or d + tail < best) then best, ex, ey = d + tail, bx + dx, by + dy end
        end
    end end
    if not best then return nil end
    -- Nur bei echtem Umweg (wie bei der Zeitberechnung)
    if best < straight * 1.15 or best > straight * 3 then return nil end
    -- Wo stehst du auf dem Wegenetz?
    local px, py = math.floor(a.wx / CELL), math.floor(a.wy / CELL)
    local dp, near
    for dx = -r, r do for dy = -r, r do
        local d = field.dist[CellKey(px + dx, py + dy)]
        if d then
            local g = Dist((px + dx + 0.5) * CELL, (py + dy + 0.5) * CELL, a.wx, a.wy)
            if g <= START_R and (not near or g < near) then near, dp = g, d end
        end
    end end
    if not dp then return nil end
    -- Vom Ziel aus "bergab" zum Startpunkt, bis ca. 100 Yards vor dir
    local cx, cy = ex, ey
    local wx, wy   -- letzter Wegpunkt, der noch mind. 60 Yards vor dir liegt
    local path, step = { { wx = b.wx, wy = b.wy } }, 0   -- fuer die Weltkarte (vom Ziel zu dir)
    for _ = 1, 3000 do
        local cwx, cwy = (cx + 0.5) * CELL, (cy + 0.5) * CELL
        if Dist(a.wx, a.wy, cwx, cwy) >= 60 then wx, wy = cwx, cwy end
        step = step + 1
        if step % 3 == 0 then path[#path + 1] = { wx = cwx, wy = cwy } end
        local d = field.dist[CellKey(cx, cy)]
        if not d or d <= dp + 100 then break end
        local nx, ny, nd
        for _, nb in ipairs(NEIGH) do
            local k = CellKey(cx + nb[1], cy + nb[2])
            local v = field.dist[k]
            -- Vorgaenger auf dem kuerzesten Weg: v + Schrittlaenge = d
            if v and v < d and (not nd or v + nb[3] < nd) then nx, ny, nd = cx + nb[1], cy + nb[2], v + nb[3] end
        end
        if not nx then break end
        cx, cy = nx, ny
    end
    if not wx then return nil end
    -- Schutz: Ein Zwischenziel ca. 100 Yards voraus kann dich hoechstens wenig vom
    -- Ziel wegfuehren (Serpentine). Weiter weg = Feld passt nicht -> Luftlinie.
    if Dist(wx, wy, b.wx, b.wy) > straight + 150 then return nil end
    path[#path + 1] = { wx = a.wx, wy = a.wy }
    T.lastTrailPath = { cont = a.cont, pts = path }
    local p = { map = a.map, cont = a.cont, wx = wx, wy = wy, x = a.x, y = a.y }
    if C_Map and C_Map.GetMapPosFromWorldPos and CreateVector2D then
        local ok, _, v = pcall(C_Map.GetMapPosFromWorldPos, a.cont, CreateVector2D(wx, wy), a.map)
        if ok and v then local x, y = v:GetXY(); p.x, p.y = x * 100, y * 100 end
    end
    return p
end

-- Messung: Gebietsuebergaenge, Ruhestein (oben) und Trampelpfade
local prevSample = T.SampleGate
function T.SampleGate()
    pcall(T.SampleTrail)
    return prevSample()
end

---------------------------------------------------------------------------
-- Austausch in der Gruppe: Die Addons schicken sich gelernte Uebergaenge und
-- Wege (nur an Gruppenmitglieder mit diesem Addon).
---------------------------------------------------------------------------
local PREFIX = "Levelmate1"
local outQueue, pendingCells = {}, {}
if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end

local function InGroup()
    return (IsInGroup and IsInGroup()) and true or false
end
local function Channel()
    if IsInRaid and IsInRaid() then return "RAID" end
    return "PARTY"
end
local function Queue(msg) if InGroup() then outQueue[#outQueue + 1] = msg end end

local function GateMsg(m1, m2, g)
    local p1, p2 = g.pts and g.pts[tostring(m1)], g.pts and g.pts[tostring(m2)]
    if not (p1 and p2) then return nil end
    return string.format("G|%d|%d|%d|%.1f|%.1f|%.2f|%.2f|%.2f|%.2f", m1, m2, g.cont, g.wx, g.wy, p1[1], p1[2], p2[1], p2[2])
end

function T.OnGateLearned(m1, m2, g)
    local msg = GateMsg(m1, m2, g)
    if msg then Queue(msg) end
end

function T.OnTrailLearned(cont, cells)
    if not InGroup() then return end
    pendingCells[cont] = pendingCells[cont] or {}
    for _, c in ipairs(cells) do table.insert(pendingCells[cont], c) end
end

local function FlushCells()
    for cont, list in pairs(pendingCells) do
        while #list > 0 do
            local parts, len = {}, 0
            while #list > 0 and len < 200 do
                local c = table.remove(list)
                local s = c[1] .. "," .. c[2]
                parts[#parts + 1] = s
                len = len + #s + 1
            end
            Queue("T|" .. cont .. "|" .. table.concat(parts, ";"))
        end
        pendingCells[cont] = nil
    end
end

T.shared = { gates = 0, cells = 0 }
local function OnMessage(msg, sender)
    local kind = msg:sub(1, 1)
    if kind == "G" then
        local m1, m2, cont, wx, wy, x1, y1, x2, y2 = msg:match("^G|(%d+)|(%d+)|(%d+)|([%-%d%.]+)|([%-%d%.]+)|([%d%.]+)|([%d%.]+)|([%d%.]+)|([%d%.]+)$")
        if m1 then
            m1, m2 = tonumber(m1), tonumber(m2)
            local entry = { cont = tonumber(cont), wx = tonumber(wx), wy = tonumber(wy), n = 1, shared = true,
                pts = { [tostring(m1)] = { tonumber(x1), tonumber(y1) }, [tostring(m2)] = { tonumber(x2), tonumber(y2) } } }
            if T.AddSharedGate(m1, m2, entry) then T.shared.gates = T.shared.gates + 1 end
        end
    elseif kind == "T" then
        local cont, rest = msg:match("^T|(%d+)|(.+)$")
        cont = tonumber(cont)
        if cont and rest then
            for cx, cy in rest:gmatch("(-?%d+),(-?%d+)") do
                if T.AddTrailCell(cont, tonumber(cx), tonumber(cy)) then T.shared.cells = T.shared.cells + 1 end
            end
        end
    elseif kind == "H" then
        -- Neues Gruppenmitglied mit Addon: unsere Uebergaenge schicken
        for _, e in ipairs(T.AllGates()) do
            if not e.g.shared then local m = GateMsg(e.m1, e.m2, e.g); if m then Queue(m) end end
        end
    end
end

T._OnMessage = OnMessage   -- fuer Tests
local cf = CreateFrame("Frame")
pcall(cf.RegisterEvent, cf, "CHAT_MSG_ADDON")
pcall(cf.RegisterEvent, cf, "GROUP_ROSTER_UPDATE")
local wasInGroup = false
cf:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
    if event == "CHAT_MSG_ADDON" then
        if prefix ~= PREFIX or not msg then return end
        local me = UnitName and UnitName("player")
        if sender and me and (sender == me or sender:match("^([^%-]+)") == me) then return end
        pcall(OnMessage, msg, sender)
    elseif event == "GROUP_ROSTER_UPDATE" then
        local now = InGroup()
        if now and not wasInGroup then
            Queue("H")
            for _, e in ipairs(T.AllGates()) do
                if not e.g.shared then local m = GateMsg(e.m1, e.m2, e.g); if m then Queue(m) end end
            end
        end
        wasInGroup = now
    end
end)

-- Senden gedrosselt: hoechstens 2 Nachrichten pro Sekunde
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(0.5, function()
        if not InGroup() then outQueue = {}; pendingCells = {}; return end
        FlushCells()
        local msg = table.remove(outQueue, 1)
        if msg and C_ChatInfo and C_ChatInfo.SendAddonMessage then
            pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, Channel())
        end
    end)
end

---------------------------------------------------------------------------
-- Export / Import als Text (/lm export, /lm import) und Startwissen.
-- Gleiches Format wie der Austausch in der Gruppe: G|... (Uebergang),
-- T|Kontinent|x,y;x,y;... (Wegfelder).
---------------------------------------------------------------------------
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local DIRCH = "abcdefgh"
-- "P"-Zeile (kompakter Export) in normale "T"-Zeilen umwandeln
local function ExpandP(line)
    local cont, body = line:match("^P|(%d+)|(.*)$")
    if not cont then return {} end
    local out, cur = {}, {}
    for seg in body:gmatch("[^;]+") do
        local x, y, dirs = seg:match("^(-?%d+),(-?%d+):([a-h]*)$")
        if x then
            x, y = tonumber(x), tonumber(y)
            cur[#cur + 1] = x .. "," .. y
            for i = 1, #dirs do
                local v = DIRS[DIRCH:find(dirs:sub(i, i), 1, true)]
                x, y = x + v[1], y + v[2]
                cur[#cur + 1] = x .. "," .. y
                if #cur >= 40 then out[#out + 1] = "T|" .. cont .. "|" .. table.concat(cur, ";"); cur = {} end
            end
            if #cur >= 40 then out[#out + 1] = "T|" .. cont .. "|" .. table.concat(cur, ";"); cur = {} end
        end
    end
    if #cur > 0 then out[#out + 1] = "T|" .. cont .. "|" .. table.concat(cur, ";") end
    return out
end

function T.ExportText()
    local lines, gates, cells = { "Levelmate-Export 1" }, 0, 0
    for _, e in ipairs(T.AllGates()) do
        local m = GateMsg(e.m1, e.m2, e.g)
        if m then lines[#lines + 1] = m; gates = gates + 1 end
    end
    -- Wegfelder kompakt: zusammenhaengende Felder als Kette von Richtungen
    -- ("P|kont|x,y:abc...;x,y:..."), ca. 1 Zeichen je Feld statt ~10.
    for cont, t in pairs((Levelmate_DB and Levelmate_DB.trails) or {}) do
        local left, keys = {}, {}
        for k in pairs(t.c or {}) do
            local x, y = k:match("^(-?%d+),(-?%d+)$")
            if x then left[k] = true; keys[#keys + 1] = k; cells = cells + 1 end
        end
        table.sort(keys)
        local segs, len = {}, 0
        local function Flush()
            if #segs > 0 then lines[#lines + 1] = "P|" .. cont .. "|" .. table.concat(segs, ";") end
            segs, len = {}, 0
        end
        for _, k in ipairs(keys) do
            if left[k] then
                left[k] = nil
                local x, y = k:match("^(-?%d+),(-?%d+)$")
                x, y = tonumber(x), tonumber(y)
                local dirs = {}
                while true do
                    local moved = false
                    for d, v in ipairs(DIRS) do
                        local nk = (x + v[1]) .. "," .. (y + v[2])
                        if left[nk] then
                            left[nk] = nil; x, y = x + v[1], y + v[2]
                            dirs[#dirs + 1] = DIRCH:sub(d, d); moved = true
                            break
                        end
                    end
                    if not moved then break end
                end
                local seg = k .. ":" .. table.concat(dirs)
                segs[#segs + 1] = seg; len = len + #seg + 1
                if len > 880 then Flush() end
            end
        end
        Flush()
    end
    return table.concat(lines, "\n"), gates, cells
end

-- Liefert die Anzahl neu uebernommener Uebergaenge und Wegfelder
function T.ImportText(text)
    local g0, c0 = T.shared.gates, T.shared.cells
    for line in tostring(text or ""):gmatch("[^\r\n]+") do
        line = (line:gsub("^%s+", ""):gsub("%s+$", ""))
        if line:match("^[GT]|") then pcall(OnMessage, line)
        elseif line:match("^P|") then
            for _, tl in ipairs(ExpandP(line)) do pcall(OnMessage, tl) end
        end
    end
    local g, c = T.shared.gates - g0, T.shared.cells - c0
    T.shared.gates, T.shared.cells = g0, c0
    if Levelmate.Planner and Levelmate.Planner.InvalidateCostCache then pcall(Levelmate.Planner.InvalidateCostCache) end
    return g, c
end

-- Startwissen (Seed.lua) einmal je Version uebernehmen
function T.ApplySeed()
    local seed = Levelmate.SeedData
    if not seed or not seed.text then return end
    Levelmate_DB = Levelmate_DB or {}
    if (Levelmate_DB.seedVersion or 0) >= (seed.version or 1) then return end
    T.ImportText(seed.text)
    Levelmate_DB.seedVersion = seed.version or 1
end
