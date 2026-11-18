-- Planner.lua
local L, LT = Levelmate.L, Levelmate.LT
-- Berechnet den naechsten sinnvollen Schritt (RestedXP-Prinzip), komplett aus
-- Daten: Volk/Klasse/Fraktion/Stufe des Charakters, Questlog, erledigte Quests
-- und die Forever-Questdatenbank (QuestieDB).
--
-- Grundidee:
--   Wert   = Quest-XP (auf deine Stufe umgerechnet) + Anteil der XP von
--            Folgequests, die diese Quest freischaltet (Vorquests fuer
--            Questketten und - im Dungeon-Modus - Dungeonquests).
--   Kosten = geschaetzte Zeit: Laufwege + Kills/Drops/Objekte + Abgabe.
--   Effizienz = Wert / Kosten  (XP pro Minute, geschaetzt)
-- Quests deutlich unter dem Durchschnitt ihrer Umgebung werden uebersprungen
-- (z. B. seltene Gegner, niedrige Dropchance). Der naechste Schritt ist die
-- Aktion (Annehmen / Erledigen / Abgeben / Dungeon) mit dem besten Verhaeltnis
-- von XP zu Zeit ab deiner aktuellen Position.
--
-- WICHTIG: Alle Zeiten sind Schaetzwerte (siehe CONFIG). Sie werden spaeter mit
-- den echten XP/min-Messungen aus Smart.lua kalibriert.
Levelmate = Levelmate or {}
Levelmate.Planner = Levelmate.Planner or {}
local P = Levelmate.Planner
local DB = Levelmate.DB

P.MODES = {
    quests   = { label = "Nur Quests",        threshold = 0.35, dungeons = false },
    dungeons = { label = "Quests + Dungeons", threshold = 0.35, dungeons = true  },
}
-- "Schnellster Weg" gibt es seit 0.9.62 nicht mehr (alte Einstellung -> Nur Quests)
P.MODES.fastest = P.MODES.quests

local CONFIG = {
    speedLow = 7.0,          -- Laufgeschwindigkeit in Yards/s ohne Reittier
    speedMount = 10.5,       -- ab Stufe 40 (Reittier angenommen)
    crossContinent = 1500,   -- Sekunden-Aufschlag fuer Kontinentwechsel (Schiff/Zeppelin)
    maxLevelAbove = 2,       -- Quests mehr als 2 Stufen ueber dir: zu gefaehrlich
    riskPerLevel = 0.2,      -- je Stufe ueber dir 20 % Abschlag (Todesrisiko)
    talk = 15,               -- Sekunden je Annahme/Abgabe
    objectSeconds = 15,      -- je Objekt (Kiste, Pflanze ...)
    defaultDrop = 0.35,      -- angenommene Dropchance ohne Daten
    rareSpawnWait = 90,      -- Aufschlag je Einheit bei < 3 Spawnpunkten
    unknownObjective = 300,  -- Aufschlag fuer nicht bewertbare Ziele
    eliteFactor = 3,         -- Elite-Gegner dauern deutlich laenger
    maxLogSize = 20,         -- Ersatzwert; normalerweise fragt das Addon den Client (Forever: 40)
    dungeonRun = 1800,       -- Sekunden fuer einen Dungeonlauf inkl. Gruppensuche
    followUpShare = 0.6,     -- Anteil der Folgequest-XP als Bonus
    nearbyPickup = 30,       -- Quests in <30 s Laufweg zuerst alle mitnehmen
    nearbyBoost = 20,        -- so stark werden nahe Annahmen/Abgaben bevorzugt
    optionalFactor = 0.4,
    classValue = 1.5,
    mobXPShare = 0.5,        -- Gegner-XP nur zur Haelfte: Kill-Quests leicht bevorzugen, nicht dominieren
    classMaxBoostEffort = 2700, -- Sekunden: laengere Klassenquests nicht vorziehen
    dungeonNear = 60,        -- Sekunden: so nah am Dungeoneingang = "du stehst davor"
    zoneStickNear = 120,     -- Sekunden: so nahe Ziele gelten nie als "anderes Gebiet"
    sharedTripShare = 0.8,
    sharedTripRadius = 300,  -- Yards: so nah an einem Ort, zu dem du ohnehin gehst   -- so viel vom Hinweg gilt als "schon bezahlt", wenn eine andere Quest auch dorthin fuehrt
    buyItem = 300,           -- Sekunden: Gegenstand im Auktionshaus besorgen (inkl. Suchen)
    onTheWayMin = 30,        -- Sekunden: erst ab so weitem Weg nach Zwischenstopps suchen
    onTheWayDetour = 1.15,   -- hoechstens 15 % Umweg fuer einen Zwischenstopp
    dungeonWaitLevels = 2,   -- Dungeon zurueckstellen, wenn in so vielen Stufen mehr Quests dafuer kommen
    dungeonPickupMax = 900,  -- Sekunden: so weit darf eine weitere Dungeonquest entfernt sein, um vorher annehmen zu lohnen
    dungeonPickupBoost = 3,  -- Annahme einer weiteren Dungeonquest bevorzugen
    laterZone = 0.05,        -- Schritte in einem Gebiet, das laut Gebietsplan erst spaeter dran ist
    laterZoneTravel = 300,
    dangerLevels = 7,        -- Gebiet gilt als gefaehrlich ab so vielen Stufen ueber dir (Einstellungen)
    dangerFactor = 0.02,     -- gefaehrliche Ziele ganz nach hinten   -- ... nur wenn der Weg dorthin laenger als 5 Minuten ist        -- Klassenquests gelten als 1,5x so lohnend wie der Durchschnitt    -- optionale Quests (Begleitquests) nach hinten schieben
    stickiness = 1.6,        -- neuer Schritt muss 60 % besser sein, um den bisherigen abzuloesen
    hubRadius = 150,         -- Yards: Questgeber in diesem Umkreis gelten als ein Lager
    returnShare = 0.3,       -- Anteil des Rueckwegs, den eine offene Quest allein traegt
    returnRadius = 1200,     -- Yards: Ziele in diesem Umkreis eines Lagers = "du kommst eh vorbei"
    comeBackMin = 120,       -- Sekunden: nur bei weiter entfernten Lagern lohnt das Aufschieben
    closerShare = 0.5,
    localWork = 60,          -- Sekunden: so nah gilt ein offenes Ziel als "direkt hier"
    localWorkSlack = 30,     -- ... wenn die Abgabe nicht mehr als 30 s naeher ist       -- Ziel gilt als "deutlich naeher", wenn < 60 % des Wegs zur Abgabe
    waitFactor = 0.1,        -- Abgabe zurueckstellen, solange Ziele in der Naehe offen sind
    leaveMargin = 120,       -- Sekunden: so viel weiter weg als das Abgabe-Lager gilt als "Gebiet verlassen"
    leavePenalty = 0.05,     -- Abwertung fuer das Verlassen, solange Abgaben offen sind
    zoneStick = 0.1,         -- Abwertung fuer andere Gebiete, solange hier noch Arbeit ist
    clusterCell = 150,       -- Yards: Rastergroesse fuer die Dichte von Questzielen
    clusterOther = 0.7,      -- Gewicht von Zielen ANDERER Quests im selben Gebiet
    clusterTravel = 150,     -- Sekunden: so stark mindert der Weg die Dichte-Bewertung
}
P.CONFIG = CONFIG

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok then return a, b, c, d end
end

---------------------------------------------------------------------------
-- Charakter
---------------------------------------------------------------------------
local player = {}
local function UpdatePlayer()
    player.level = UnitLevel("player") or 1
    player.raceID = select(3, UnitRace("player")) or 0
    player.classID = select(3, UnitClass("player")) or 0
    player.faction = UnitFactionGroup("player")
end
P.player = player

-- specialFlags: 1 = wiederholbar, 2 = Begleitung/Erkundung/Skript (normale Quest!),
-- 4 und hoeher = monatlich/sonstige Sonderfaelle.
local function SpecialExcluded(flags)
    flags = flags or 0
    if flags % 2 == 1 then return true end      -- wiederholbar
    if flags >= 4 then return true end           -- monatlich u. a.
    return false
end

-- Ist ein Datenbankwert wirklich gesetzt? Im echten Client kommen "leere"
-- Felder als 0, {0, 0} oder {} zurueck - das bedeutet "keine Anforderung".
local function IsSet(v)
    if v == nil or v == false then return false end
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "table" then
        for _, x in pairs(v) do
            if IsSet(x) then return true end
        end
        return false
    end
    return true
end

-- Welche Anforderung (Beruf, Ruf, Zauber) blockiert die Quest? nil = keine.
local function RequirementBlock(q)
    if IsSet(q.requiredSkill) then return "Beruf" end
    if IsSet(q.requiredSpecialization) then return "Berufs-Spezialisierung" end
    if IsSet(q.requiredRanks) then return "Berufsrang" end
    if IsSet(q.requiredSpell) then return "Zauber" end
    if IsSet(q.requiredMinRep) then return "Ruf (mindestens)" end
    if IsSet(q.requiredMaxRep) then return "Ruf (höchstens)" end
    return nil
end

local function HasBit(mask, index)
    if not mask or mask == 0 or not index or index < 1 then return true end
    return math.floor(mask / 2 ^ (index - 1)) % 2 == 1
end

-- Klassenquest = Quest, die nur fuer 1-3 Klassen gilt (laut QuestieDB requiredClasses).
local function ClassMaskSpecific(mask)
    if type(mask) ~= "number" or mask <= 0 then return false end
    local bits, m = 0, math.floor(mask)
    while m > 0 do bits = bits + m % 2; m = math.floor(m / 2) end
    return bits <= 3
end
P.ClassMaskSpecific = ClassMaskSpecific

-- Einstellung "Klassenquests anzeigen" (Standard: an)
function P.ClassQuestsOn()
    return not (Levelmate_DB and Levelmate_DB.classQuests == false)
end

-- Ab welcher Questlevel eine Quest grau ist (Classic-Regel).
local function GreyLevel(level)
    if level <= 5 then return 0 end
    if level <= 39 then return level - 5 - math.floor(level / 10) end
    if level <= 59 then return level - 1 - math.floor(level / 5) end
    return level - 9
end

-- XP-Reduktion fuer Quests unter deiner Stufe (Classic-Regel).
local function ScaledXP(baseXP, questLevel, level)
    if not baseXP then return 0 end
    if level >= 60 then return 0 end
    local diff = level - (questLevel or level)
    local f = 1
    if diff >= 10 then f = 0.1 elseif diff == 9 then f = 0.2 elseif diff == 8 then f = 0.4
    elseif diff == 7 then f = 0.6 elseif diff == 6 then f = 0.8 end
    return baseXP * f
end

-- Gegner-XP (Classic-Regel): Grundwert Stufe*5+45, mehr fuer hoehere Gegner
-- (bis +4 Stufen), weniger fuer niedrigere, nichts fuer graue.
local function ZeroDiff(level)
    if level <= 7 then return 5 elseif level <= 9 then return 6 elseif level <= 11 then return 7
    elseif level <= 15 then return 8 elseif level <= 19 then return 9 elseif level <= 29 then return 11
    elseif level <= 39 then return 12 elseif level <= 44 then return 13 elseif level <= 49 then return 14
    elseif level <= 54 then return 15 else return 16 end
end
local function MobXP(mobLevel, level)
    if not mobLevel or not level or level >= 60 then return 0 end
    local ml = math.floor(mobLevel + 0.5)
    if ml <= GreyLevel(level) then return 0 end
    local base = level * 5 + 45
    if ml >= level then return base * (1 + 0.05 * math.min(4, ml - level)) end
    return math.max(0, base * (1 - (level - ml) / ZeroDiff(level)))
end
P.MobXP = MobXP

---------------------------------------------------------------------------
-- Erledigte Quests
---------------------------------------------------------------------------
local completed = {}
local completedFull = false   -- komplette Liste vom Spiel geladen?
local notDone = {}            -- schon gefragt: nicht erledigt (bis zur naechsten Abgabe)
local function LoadCompleted()
    completed, notDone = {}, {}
    local list = C_QuestLog and Call(C_QuestLog.GetAllCompletedQuestIDs)
    if type(list) == "table" and #list > 0 then
        for _, id in ipairs(list) do completed[id] = true end
        completedFull = true
    end
end
P.LoadCompleted = LoadCompleted
local virtualDone = nil   -- nur waehrend der Routenvorschau gesetzt
local virtualItems = nil  -- in der Vorschau "geholte" Schluessel
local function HasKey(itemId)
    if virtualItems and virtualItems[itemId] then return true end
    return DB.HasItem(itemId)
end
-- Erledigt? Fragt das Spiel nur einmal je Quest (vorher bei jeder Planung
-- hunderte Male - eine Hauptursache fuer Ruckler).
local function Done(id)
    if completed[id] then return true end
    if virtualDone and virtualDone[id] then return true end
    if completedFull or notDone[id] then return false end
    if C_QuestLog and Call(C_QuestLog.IsQuestFlaggedCompleted, id) == true then
        completed[id] = true; return true
    end
    notDone[id] = true
    return false
end
P.Done = Done
function P.MarkDone(id) if id then completed[id] = true; notDone[id] = nil end end

---------------------------------------------------------------------------
-- Geometrie (Weltkoordinaten in Yards)
---------------------------------------------------------------------------
local function World(point)
    if point.cont == nil then
        point.cont = false
        if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local cont, vec = Call(C_Map.GetWorldPosFromMapPos, point.map, CreateVector2D(point.x / 100, point.y / 100))
            if cont and vec then
                point.cont = cont
                point.wx, point.wy = vec:GetXY()
            end
        end
    end
    return point.cont
end

function P.PlayerPoint()
    if not (C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = Call(C_Map.GetBestMapForUnit, "player")
    if not map then return nil end
    local pos = Call(C_Map.GetPlayerMapPosition, map, "player")
    if not pos then return nil end
    local x, y = pos:GetXY()
    local p = { map = map, x = x * 100, y = y * 100 }
    World(p)
    return p
end

-- Entfernung in Yards; nil bei unterschiedlichen Kontinenten/unbekannt.
local function Yards(a, b)
    if not a or not b then return nil end
    if not World(a) or not World(b) or a.cont ~= b.cont then return nil end
    local dx, dy = a.wx - b.wx, a.wy - b.wy
    return math.sqrt(dx * dx + dy * dy)
end
P.Yards = Yards

local function WalkSpeed()
    return (player.level or 1) >= 40 and CONFIG.speedMount or CONFIG.speedLow
end

-- Reisezeit inkl. Flugrouten; liefert ggf. Abflug- und Ziel-Flugpunkt.
-- Zwischenspeicher je Planung: Dieselben Wege werden sonst hundertfach
-- neu berechnet (Hauptursache fuer Ruckler beim Annehmen von Quests).
local travelCache = setmetatable({}, { __mode = "k" })
-- Aufwand ab Questgeber je Quest (siehe Plan, Abschnitt 2)
local costCache = {}
function P.InvalidateCostCache() costCache = {} end
local hearthMemo, hearthMemoSet = nil, false   -- Ruhestein-Ziel, einmal je Planung abgefragt
local function ResetTravelCache()
    travelCache = setmetatable({}, { __mode = "k" })
    hearthMemo, hearthMemoSet = nil, false
end
local function PlanHearth()
    if not hearthMemoSet then
        hearthMemoSet = true
        hearthMemo = Levelmate.Travel and Levelmate.Travel.HearthOption and Levelmate.Travel.HearthOption() or nil
    end
    return hearthMemo
end
local TravelSecondsRaw
local function TravelSecondsBase(a, b)
    if not a or not b then return 0 end
    local row = travelCache[a]
    local hit = row and row[b]
    if hit then return hit[1], hit[2], hit[3], hit[4], hit[5] end
    local t, fa, fb, h, leg = TravelSecondsRaw(a, b)
    if not row then row = setmetatable({}, { __mode = "k" }); travelCache[a] = row end
    row[b] = { t, fa, fb, h, leg }
    return t, fa, fb, h, leg
end
TravelSecondsRaw = function(a, b)
    if Levelmate.Travel then
        local t, fa, fb = Levelmate.Travel.Route(a, b, WalkSpeed(), Yards)
        -- Zeppelin/Schiff: anderer Kontinent, oder auf demselben Kontinent
        -- schneller (z. B. Unterstadt - Grom'gol)
        if Levelmate.Travel.ShipRoute and World(a) and World(b) and (a.cont ~= b.cont or (Yards(a, b) or 0) > 1500) then
            local ts, leg = Levelmate.Travel.ShipRoute(a, b, WalkSpeed(), Yards)
            if ts and (not t or ts + 60 < t) then return ts, nil, nil, nil, leg end
        end
        if t then return t, fa, fb end
        return CONFIG.crossContinent
    end
    local yd = Yards(a, b)
    if not yd then return CONFIG.crossContinent end
    return yd / WalkSpeed()
end

-- Ruhestein: nur ab deiner aktuellen Position und nur einmal je Planung.
local hearthFrom
local function TravelSeconds(a, b)
    local t, fa, fb, _, leg = TravelSecondsBase(a, b)
    if hearthFrom and a == hearthFrom and Levelmate.Travel and Levelmate.Travel.HearthOption then
        local h = PlanHearth()
        if h and World(h) then
            local th = Levelmate.Travel.CONFIG.hearthSeconds + TravelSecondsBase(h, b)
            if th + Levelmate.Travel.CONFIG.hearthMinSaving < t then return th, nil, nil, h end
        end
    end
    return t, fa, fb, nil, leg
end
P.TravelSeconds = TravelSeconds

-- Naechster Punkt, bevorzugt im aktuellen Gebiet (gleiche Karte).
local function NearestSameMap(from, points)
    if from and points then
        local local_ = {}
        for _, p in ipairs(points) do if p.map == from.map then local_[#local_ + 1] = p end end
        if #local_ > 0 then points = local_ end
    end
    return points
end

-- Dichte-Raster: Wie viele Questziele liegen um einen Punkt herum?
-- So fuehrt der Pfeil ins grosse Lager mit vielen Zielen statt zum
-- naechstgelegenen Einzelgegner.
local function CellKey(p, dx, dy)
    local size = CONFIG.clusterCell
    return p.cont .. ":" .. (math.floor(p.wx / size) + dx) .. ":" .. (math.floor(p.wy / size) + dy)
end

local function BuildDensity(targetLists)
    local grid = {}
    for tag, points in pairs(targetLists) do
        for _, p in ipairs(points) do
            if World(p) then
                local k = CellKey(p, 0, 0)
                local cell = grid[k]
                if not cell then cell = { total = 0, by = {} }; grid[k] = cell end
                cell.total = cell.total + 1
                cell.by[tag] = (cell.by[tag] or 0) + 1
            end
        end
    end
    return grid
end

local function DensityAt(grid, p, tag)
    if not grid or not World(p) then return 1 end
    local own, other = 0, 0
    for dx = -1, 1 do
        for dy = -1, 1 do
            local cell = grid[CellKey(p, dx, dy)]
            if cell then
                local mine = cell.by[tag] or 0
                own = own + mine
                other = other + (cell.total - mine)
            end
        end
    end
    return own + CONFIG.clusterOther * other
end

-- Bester Punkt fuer ein Ziel: viele Ziele in der Naehe, nicht zu weit weg.
local function BestClusterPoint(here, points, grid, tag)
    if not points or #points == 0 then return nil, 0 end
    -- Kandidaten: die 40 naechsten Punkte (Luftlinie)
    local list = {}
    for _, p in ipairs(points) do
        local yd = Yards(here, p)
        if yd then list[#list + 1] = { p = p, yd = yd } end
    end
    if #list == 0 then return points[1], TravelSeconds(here, points[1]) end
    table.sort(list, function(a, b) return a.yd < b.yd end)
    local best, bestScore, bestT
    for i = 1, math.min(40, #list) do
        local p = list[i].p
        local t = TravelSeconds(here, p)
        local score = DensityAt(grid, p, tag) / (1 + t / CONFIG.clusterTravel)
        if not bestScore or score > bestScore then best, bestScore, bestT = p, score, t end
    end
    return best, bestT
end

-- Naechster Punkt (Luftlinie), Zeit dorthin inkl. Flug.
local function Nearest(from, points)
    local best, bestYd
    for _, p in ipairs(points or {}) do
        local yd = Yards(from, p)
        if yd and (not bestYd or yd < bestYd) then best, bestYd = p, yd end
    end
    if not best then
        best = points and points[1]
        if not best then return nil, 0 end
    end
    return best, TravelSeconds(from, best)
end

---------------------------------------------------------------------------
-- Statische Questanalyse (wird je Quest einmal berechnet)
---------------------------------------------------------------------------
local analysis = {}

local function Numbers(text)
    local nums = {}
    for n in tostring(text or ""):gmatch("(%d+)") do
        local v = tonumber(n)
        if v and v > 0 and v <= 40 then table.insert(nums, v) end
    end
    return nums
end

-- Durchschnittliche Stufe eines Gegners (fuer die Gegner-XP), sonst nil
local function MobLevel(npc)
    if not npc then return nil end
    local lo, hi = npc.minLevel or 0, npc.maxLevel or 0
    if hi <= 0 then return nil end
    if lo <= 0 then lo = hi end
    return (lo + hi) / 2
end

local function KillSeconds(npc)
    local lvl = (npc and npc.maxLevel and npc.maxLevel > 0) and npc.maxLevel or (player.level or 1)
    local t = 18 + lvl * 0.4
    if npc and (npc.rank or 0) >= 1 then t = t * CONFIG.eliteFactor end
    return t
end

local function AddPoints(target, points)
    for _, p in ipairs(points or {}) do table.insert(target, p) end
end

local function Analyze(q)
    local a = analysis[q.id]
    if a then return a end
    a = { givers = {}, finishers = {}, targets = {}, effort = 0, elite = false }
    local sb, fb = q.startedBy or {}, q.finishedBy or {}
    for _, id in ipairs(sb[1] or {}) do
        local n = DB.Npc(id)
        if n then AddPoints(a.givers, n.points); a.giverName = a.giverName or n.name end
    end
    for _, id in ipairs(sb[2] or {}) do
        local o = DB.Object(id)
        if o then AddPoints(a.givers, o.points); a.giverName = a.giverName or o.name end
    end
    a.itemStart = (sb[3] and #sb[3] > 0) and #a.givers == 0
    for _, id in ipairs(fb[1] or {}) do
        local n = DB.Npc(id)
        if n then AddPoints(a.finishers, n.points); a.finisherName = a.finisherName or n.name end
    end
    for _, id in ipairs(fb[2] or {}) do
        local o = DB.Object(id)
        if o then AddPoints(a.finishers, o.points); a.finisherName = a.finisherName or o.name end
    end

    local obj = q.objectives or {}
    local nums = Numbers(type(q.objectivesText) == "table" and table.concat(q.objectivesText, " ") or q.objectivesText)
    local idx = 0
    local function need(default)
        idx = idx + 1
        -- Ohne Zahl im Questtext ("Bringt den Kopf von ...") ist es fast immer 1 Stueck.
        if #nums == 0 then return 1 end
        return nums[idx] or nums[1] or default
    end
    local function AddTarget(t)
        if #t.points < 3 and #t.points > 0 then t.perUnit = t.perUnit + CONFIG.rareSpawnWait end
        if #t.points == 0 and not t.dungeonArea then t.perUnit = t.perUnit + CONFIG.unknownObjective end
        t.effort = t.need * t.perUnit
        a.effort = a.effort + t.effort
        -- Nur Dungeonquest, wenn das Ziel ausschliesslich im Dungeon zu finden ist.
        if t.dungeonArea and #t.points == 0 then a.dungeonArea = a.dungeonArea or t.dungeonArea end
        table.insert(a.targets, t)
    end
    -- 1: Gegner toeten
    for _, e in ipairs(obj[1] or {}) do
        local n = DB.Npc(type(e) == "table" and e[1] or e)
        if n then
            if (n.rank or 0) >= 1 then a.elite = true end
            local t = { kind = "kill", name = n.name, points = n.points, dungeonArea = n.dungeonArea,
                        need = need(8), perUnit = KillSeconds(n) }
            if (n.rank or 0) < 1 then t.mobLevel, t.killsPerUnit = MobLevel(n), 1 end
            AddTarget(t)
        end
    end
    -- 2: Objekte benutzen
    for _, e in ipairs(obj[2] or {}) do
        local o = DB.Object(type(e) == "table" and e[1] or e)
        if o then
            AddTarget({ kind = "object", name = o.name, points = o.points, dungeonArea = o.dungeonArea,
                        need = need(1), perUnit = CONFIG.objectSeconds })
        end
    end
    -- 3: Gegenstaende sammeln (Drops oder Objekte)
    for _, e in ipairs(obj[3] or {}) do
        local itemId = type(e) == "table" and e[1] or e
        local t = { kind = "item", itemId = itemId, name = DB.ItemName(itemId), points = {}, need = need(6), perUnit = 0 }
        local best = nil
        local anyNormal, anyElite = false, false
        local friendlyOnly, friendlyName = true, nil
        local letter = player.faction == "Alliance" and "A" or player.faction == "Horde" and "H" or "?"
        for _, src in ipairs(DB.ItemSources(itemId)) do
            if src.kind == "npc" then
                local n = DB.Npc(src.id)
                if n then
                    AddPoints(t.points, n.points)
                    t.dungeonArea = t.dungeonArea or n.dungeonArea
                    local chance = (src.chance and src.chance > 0) and math.min(1, src.chance / 100) or CONFIG.defaultDrop
                    local per = KillSeconds(n) / math.max(0.05, chance)
                    if (n.rank or 0) >= 1 then anyElite = true else anyNormal = true end
                    -- Freundliche NPCs "droppen" nichts: Gegenstand per Tausch/Herstellung.
                    if n.friendly and n.friendly:find(letter, 1, true)
                       and not (n.friendly == "AH" and not n.service) then
                        friendlyName = friendlyName or n.name
                    else
                        friendlyOnly = false
                    end
                    if not best or per < best then
                        best = per
                        if (n.rank or 0) < 1 then t.mobLevel, t.killsPerUnit = MobLevel(n), 1 / math.max(0.05, chance)
                        else t.mobLevel, t.killsPerUnit = nil, nil end
                    end
                    t.source = t.source or n.name
                end
            else
                local o = DB.Object(src.id)
                if o then
                    anyNormal = true
                    friendlyOnly = false
                    AddPoints(t.points, o.points)
                    t.dungeonArea = t.dungeonArea or o.dungeonArea
                    if not best or CONFIG.objectSeconds < best then
                        best = CONFIG.objectSeconds
                        t.mobLevel, t.killsPerUnit = nil, nil   -- aus Objekten, keine Kills
                    end
                    t.source = t.source or o.name
                end
            end
        end
        t.perUnit = best or CONFIG.unknownObjective
        if not best and #t.points == 0 then
            -- Keine Beute-Quelle bekannt: Haendler? Sonst Auktionshaus/Herstellen.
            local vendors = DB.ItemVendors(itemId)
            for _, vid in ipairs(vendors) do
                local n = DB.Npc(vid)
                if n and n.points and (not n.friendly or n.friendly:find(letter, 1, true)) then
                    AddPoints(t.points, n.points)
                    t.source = t.source or n.name
                end
            end
            if #t.points > 0 then
                t.buy = "vendor"
                t.perUnit = 30 / math.max(1, t.need)
            else
                t.buy = "ah"
                t.perUnit = CONFIG.buyItem / math.max(1, t.need)
            end
        end
        if anyElite and not anyNormal then a.elite = true end
        if friendlyName and friendlyOnly then
            t.trade = friendlyName          -- nur per Tausch/Beruf/Handel erhaeltlich
            t.tradePoints = t.points        -- Ort des NPCs, bei dem getauscht wird
            t.points = {}                   -- kein Ort zum "Farmen"
            t.perUnit = 60 / math.max(1, t.need)  -- Tauschen selbst geht schnell
        end
        AddTarget(t)
    end
    -- 5: Kill-Credit (z. B. "Gegner X besiegt")
    for _, e in ipairs(obj[5] or {}) do
        local t = { kind = "kill", points = {}, need = need(1), perUnit = 0 }
        for _, id in ipairs(type(e) == "table" and type(e[1]) == "table" and e[1] or {}) do
            local n = DB.Npc(id)
            if n then
                AddPoints(t.points, n.points); t.name = t.name or n.name
                t.dungeonArea = t.dungeonArea or n.dungeonArea
                t.perUnit = math.max(t.perUnit, KillSeconds(n))
                -- Keine Gegner-XP: "Kill-Credit" heisst oft zaehmen, benutzen,
                -- ansprechen oder begleiten (z. B. Kodozusammentrieb) - kein Kill.
            end
        end
        if t.perUnit == 0 then t.perUnit = CONFIG.unknownObjective end
        AddTarget(t)
    end
    -- Begleitung / Erkundung: Zielort steht in triggerEnd = {Text, Spawns}
    if type(q.triggerEnd) == "table" and q.triggerEnd[1] then
        local text = tostring(q.triggerEnd[1])
        local points, dungeonArea = DB.ConvertSpawns(q.triggerEnd[2])
        local low = text:lower()
        local explore = low:find("xplore", 1, true) or low:find("erkund", 1, true) or low:find("locate", 1, true)
                     or low:find("find ", 1, true) or low:find("finde", 1, true) or low:find("visit", 1, true)
        -- Alles andere (Eskorte, "Besiege X" nach einem Skript) dauert einige Minuten
        local escort = not explore
        local t = { kind = escort and "escort" or "explore", name = text, points = points,
                    dungeonArea = (#points == 0) and dungeonArea or nil, need = 1,
                    perUnit = escort and 300 or 20 }
        -- Begleitquest: Start beim Questgeber, dort beginnt die Eskorte
        if escort and #a.givers > 0 then t.points = a.givers; t.source = a.giverName end
        if escort then a.optional = true end   -- NPC ist oft unterwegs (andere Spieler)
        AddTarget(t)
    end
    -- 4/6: Ruf / Zauber -> nicht bewertbar
    if (obj[4] and #obj[4] > 0) or (obj[6] and #obj[6] > 0) then
        a.effort = a.effort + CONFIG.unknownObjective
    end
    -- Questgeber oder Abgabe im Dungeon -> Dungeonquest
    if not a.dungeonArea and #a.finishers == 0 then
        for _, id in ipairs(fb[1] or {}) do
            local n = DB.Npc(id); if n and n.dungeonArea then a.dungeonArea = n.dungeonArea end
        end
    end
    if a.dungeonArea then
        a.dungeonName, a.dungeonEntrance = DB.Dungeon(a.dungeonArea)
    end
    -- Alle Zielpunkte (fuer Routen)
    -- Benoetigte Gegenstaende (z. B. Schluessel fuer Kugeln/Kaefige): erst holen,
    -- dann die Objekt-Ziele. Gleiche Anzahl -> Schluessel i oeffnet Objekt i.
    local objectTargets = {}
    for _, t in ipairs(a.targets) do if t.kind == "object" then objectTargets[#objectTargets + 1] = t end end
    local keys = {}
    for _, itemId in ipairs(q.requiredSourceItems or {}) do
      if itemId ~= 0 then
        local t = { kind = "key", itemId = itemId, name = DB.ItemName(itemId), points = {}, need = 1, perUnit = 0 }
        local best
        for _, src in ipairs(DB.ItemSources(itemId)) do
            if src.kind == "npc" then
                local n = DB.Npc(src.id)
                if n then
                    AddPoints(t.points, n.points)
                    local chance = (src.chance and src.chance > 0) and math.min(1, src.chance / 100) or 0.5
                    local per = KillSeconds(n) / math.max(0.05, chance)
                    if not best or per < best then best = per end
                    t.source = t.source or n.name
                end
            else
                local o = DB.Object(src.id)
                if o then
                    AddPoints(t.points, o.points)
                    if not best or CONFIG.objectSeconds < best then best = CONFIG.objectSeconds end
                    t.source = t.source or o.name
                end
            end
        end
        if best then
            t.perUnit = best
            AddTarget(t)
            keys[#keys + 1] = t
        end
      end
    end
    if #keys > 0 then
        for i, ot in ipairs(objectTargets) do
            ot.needsKeys = (#keys == #objectTargets) and { keys[i] } or keys
        end
    end
    a.keys = keys

    -- Hauptart (fuer die Kalibrierung): Ziel mit dem groessten Aufwand
    local mainEffort = 0
    a.kind = "travel"
    for _, t in ipairs(a.targets) do
        if t.kind ~= "key" and t.effort > mainEffort then mainEffort = t.effort; a.kind = t.kind end
    end
    a.objectivePoints = {}
    for _, t in ipairs(a.targets) do AddPoints(a.objectivePoints, t.points) end
    analysis[q.id] = a
    return a
end
P.Analyze = Analyze

---------------------------------------------------------------------------
-- Verfuegbarkeit
---------------------------------------------------------------------------
local inLog = {}

local function RaceClassOK(q)
    return HasBit(q.requiredRaces, player.raceID) and HasBit(q.requiredClasses, player.classID)
end

-- Schlachtfeld-Quests (Alteractal, Warsongschlucht, Arathibecken) und PvP-Sortierung
-- sowie Fest-/Eventquests und Berufsquests (Beruf unbekannt) ausschliessen.
local PVP_ZONES = { [2597] = true, [3277] = true, [3358] = true, [-25] = true,
    -- Feste und Events: Saisonal, Sonnenwendfest, Geissel-Invasion, AQ-Kriegsanstrengung u. a.
    [-22] = true, [-364] = true, [-365] = true, [-366] = true, [-367] = true, [-368] = true,
    [-369] = true, [-370] = true, [-374] = true, [-375] = true, [-376] = true,
    [-1001] = true, [-1002] = true, [-1003] = true,
    -- Berufe: Kraeuterkunde, Angeln, Schmiedekunst, Alchemie, Lederverarbeitung,
    -- Ingenieurskunst, Schneiderei, Kochen, Erste Hilfe
    [-24] = true, [-101] = true, [-121] = true, [-181] = true, [-182] = true,
    [-201] = true, [-264] = true, [-304] = true, [-324] = true }

-- Questgegenstand ohne Beute-/Haendlerquelle, den es nur als Belohnung einer
-- anderen Quest gibt (z. B. die Kapitel fuer "The Green Hills of Stranglethorn"):
-- erst verfuegbar, wenn eine dieser Quests erledigt ist oder der Gegenstand im Rucksack liegt.
-- Liefert die erste Belohnungs-Quest-ID oder nil.
local RewardItemBlock
local rewardBlockCache = {}
local function RewardItemQuests(q)
    local c = rewardBlockCache[q.id]
    if c == nil then
        c = {}
        for _, e in ipairs((q.objectives or {})[3] or {}) do
            local itemId = type(e) == "table" and e[1] or e
            if type(itemId) == "number" and #DB.ItemSources(itemId) == 0 and #DB.ItemVendors(itemId) == 0 then
                local rq = DB.ItemRewardQuests(itemId)
                local self = false
                for _, id in ipairs(rq) do if id == q.id then self = true end end
                if #rq > 0 and not self then c[#c + 1] = { item = itemId, quests = rq } end
            end
        end
        rewardBlockCache[q.id] = c
    end
    return c
end
P.RewardItemQuests = RewardItemQuests
RewardItemBlock = function(q)
    for _, r in ipairs(RewardItemQuests(q)) do
        if not HasKey(r.item) then
            local any = false
            for _, id in ipairs(r.quests) do if Done(id) then any = true; break end end
            if not any then return r.quests[1] end
        end
    end
    return nil
end

-- Quests, die sich gegenseitig ausschliessen, aber in QuestieDB nicht so markiert
-- sind. Desolace: Wer mit den Magram verbuendet ist, wird bei den Gelkis feindselig
-- (und umgekehrt) - die zweite Allianz kostet dann Stunden.
local EXCLUSIVE = {
    [1367] = { 1368 },   -- Allianz mit den Magram  <-> Allianz mit den Gelkis
    [1368] = { 1367 },
}
-- Gegenstueck, das schon abgeschlossen oder abgabebereit ist (oder nil)
local function ExclusiveDone(id)
    for _, other in ipairs(EXCLUSIVE[id] or {}) do
        if Done(other) then return other end
        local e = Levelmate.Quests.Find(other)
        if e and e.status == Levelmate.Quests.STATUS_READY then return other end
    end
    return nil
end

-- Liefert nil, wenn die Quest annehmbar ist, sonst den Grund (fuer /lm warum).
local function NotAvailableReason(q)
    if Done(q.id) then return "schon abgeschlossen" end
    if inLog[q.id] then return "steht schon im Questlog" end
    if q.zoneOrSort and PVP_ZONES[q.zoneOrSort] then return "PvP-, Fest- oder Berufsquest" end
    if q.noLevel then return "Sonderquest ohne Stufenangabe" end
    if (q.requiredLevel or 1) > player.level then return "erst ab Stufe " .. q.requiredLevel end
    if (q.questLevel or 1) > player.level + P.MaxLevelAbove() then return "Questlevel " .. q.questLevel .. " zu hoch (Todesrisiko)" end
    if q.requiredMaxLevel and q.requiredMaxLevel > 0 and player.level > q.requiredMaxLevel then return "nur bis Stufe " .. q.requiredMaxLevel end
    if not RaceClassOK(q) then return "nicht für dein Volk/deine Klasse" end
    if SpecialExcluded(q.specialFlags) then return "wiederholbar/monatlich" end
    local block = RequirementBlock(q)
    if block then return "braucht " .. block end
    for _, itemId in ipairs(q.requiredSourceItems or {}) do
        if itemId ~= 0 and #DB.ItemSources(itemId) == 0 then return "braucht Gegenstand " .. itemId .. " ohne bekannte Quelle" end
    end
    for _, id in ipairs(q.preQuestGroup or {}) do if id ~= 0 and not Done(id) then return "Vorquest " .. id .. " fehlt" end end
    local rq = RewardItemBlock(q)
    if rq then return "Gegenstand kommt erst aus Quest " .. rq end
    if IsSet(q.preQuestSingle) then
        local any = false
        for _, id in ipairs(q.preQuestSingle) do if id ~= 0 and Done(id) then any = true; break end end
        if not any then return "Vorquest " .. table.concat(q.preQuestSingle, "/") .. " fehlt" end
    end
    for _, id in ipairs(q.exclusiveTo or {}) do if id ~= 0 and (Done(id) or inLog[id]) then return "schließt sich mit Quest " .. id .. " aus" end end
    for _, id in ipairs(EXCLUSIVE[q.id] or {}) do if Done(id) or inLog[id] then return "schließt sich mit Quest " .. id .. " aus" end end
    if q.parentQuest and q.parentQuest > 0 and not inLog[q.parentQuest] then return "Hauptquest " .. q.parentQuest .. " nicht im Log" end
    if q.availableUntilCompleted and q.availableUntilCompleted > 0 and Done(q.availableUntilCompleted) then return "nicht mehr verfügbar" end
    if q.availableStartingWith and q.availableStartingWith > 0
       and not (inLog[q.availableStartingWith] or Done(q.availableStartingWith)) then return "erst ab Quest " .. q.availableStartingWith end
    if q.disabledByQuest and q.disabledByQuest > 0 and inLog[q.disabledByQuest] then return "gesperrt durch Quest " .. q.disabledByQuest end
    if q.breadcrumbForQuestId and q.breadcrumbForQuestId > 0
       and (Done(q.breadcrumbForQuestId) or inLog[q.breadcrumbForQuestId]) then return "Hinführungsquest, Ziel schon erreicht" end
    return nil
end

local function Available(q)
    return NotAvailableReason(q) == nil
end

---------------------------------------------------------------------------
-- Vorauswahl (Pool): einmal je Stufe, in kleinen Paketen ohne Ruckler
---------------------------------------------------------------------------
local pool, poolLevel, poolBuilding = {}, nil, false
local unlocks, unlocksFor = {}, nil

-- Rueckwaerts-Index aus den Vorquest-Angaben: unlocks[vorquest] = {folgequests}
local function BuildUnlocks()
    if unlocksFor == pool then return end
    unlocks = {}
    for _, id in ipairs(pool) do
        local q = DB.Quest(id)
        if q then
            for _, pre in ipairs(q.preQuestSingle or {}) do
                unlocks[pre] = unlocks[pre] or {}; table.insert(unlocks[pre], id)
            end
            for _, pre in ipairs(q.preQuestGroup or {}) do
                unlocks[pre] = unlocks[pre] or {}; table.insert(unlocks[pre], id)
            end
            for _, r in ipairs(RewardItemQuests(q)) do
                for _, pre in ipairs(r.quests) do
                    unlocks[pre] = unlocks[pre] or {}; table.insert(unlocks[pre], id)
                end
            end
        end
    end
    unlocksFor = pool
end
P.poolReady = false

-- Einstiegsstufe je Gebiet (unteres Viertel der Questlevel), einmal je Sitzung
-- berechnet. Das untere Viertel statt des Mittelwerts, weil Gebiete wie das
-- Brachland von 10 bis 25 reichen und man schon am unteren Ende hin kann.
local zoneLevels, zoneLists
local function MedianOf(list)
    table.sort(list)
    return list[math.max(1, math.floor(#list / 4 + 0.5))]
end
function P.ZoneLevel(map)
    return zoneLevels and zoneLevels[map]
end
-- Hoechstens so viele Stufen ueber dir darf eine Quest beim Annehmen sein (Einstellungen)
function P.MaxLevelAbove()
    local v = Levelmate_DB and tonumber(Levelmate_DB.maxLevelAbove)
    if v then return math.max(0, math.min(4, v)) end
    return CONFIG.maxLevelAbove
end
function P.DangerLevels()
    return (Levelmate_DB and tonumber(Levelmate_DB.dangerLevels)) or CONFIG.dangerLevels
end

function P.BuildPool(onDone)
    costCache = {}
    LoadCompleted()   -- einmal je Stufe komplett neu einlesen
    if poolBuilding or not DB.Available() then return end
    UpdatePlayer()
    poolBuilding = true
    local ids = DB.AllQuestIDs()
    local newPool, i, level = {}, 1, player.level
    local minLevel, maxReq = GreyLevel(level) - 2, level + 10
    if not zoneLevels then zoneLists = {} end
    local function Step()
        local stop = math.min(#ids, i + 400)
        for k = i, stop do
            local id = ids[k]
            local ql, rl, races, classes = DB.QuestBasics(id)
            if zoneLists and ql and ql > 0 then
                local area = DB.QuestZone and DB.QuestZone(id)
                local map = area and DB.AreaToUiMap(area)
                if map then
                    zoneLists[map] = zoneLists[map] or {}
                    table.insert(zoneLists[map], ql)
                end
            end
            local classQ = ClassMaskSpecific(classes)
            if ((ql or 0) >= minLevel or classQ) and (rl or 1) <= maxReq and (ql or 0) <= level + 12
               and HasBit(races, player.raceID) and HasBit(classes, player.classID) then
                newPool[#newPool + 1] = id
            end
        end
        i = stop + 1
        if i <= #ids then
            if C_Timer and C_Timer.After then C_Timer.After(0, Step) else Step() end
        else
            if zoneLists then
                zoneLevels = {}
                for map, list in pairs(zoneLists) do
                    if #list >= 5 then zoneLevels[map] = MedianOf(list) end
                end
                zoneLists = nil
            end
            pool, poolLevel, poolBuilding, P.poolReady = newPool, level, false, true
            if onDone then onDone() end
        end
    end
    Step()
end

---------------------------------------------------------------------------
-- Bewertung
---------------------------------------------------------------------------
local function QuestXP(q)
    return ScaledXP(q.baseXP, q.questLevel, player.level)
end

-- Fuer Quests, die QuestieDB nicht (vollstaendig) kennt - z. B. Forever-eigene
-- Quests: XP und Abgabeort direkt vom Spiel holen.
local function ClientXP(questID)
    local xp = Call(GetQuestLogRewardXP, questID)
    if type(xp) == "number" and xp > 0 then return xp end
    return 0
end

local function ClientWaypoint(questID)
    local CQ = C_QuestLog
    if not CQ then return nil end
    if CQ.GetNextWaypoint then
        local ok, map, x, y = pcall(CQ.GetNextWaypoint, questID)
        if ok and map and x and y and (x > 0 or y > 0) then
            local name
            if CQ.GetNextWaypointText then
                local ok2, txt = pcall(CQ.GetNextWaypointText, questID)
                if ok2 and type(txt) == "string" and txt ~= "" then name = txt end
            end
            return { map = map, x = x * 100, y = y * 100 }, name
        end
    end
    if CQ.GetQuestsOnMap and C_Map and C_Map.GetBestMapForUnit then
        local map = Call(C_Map.GetBestMapForUnit, "player")
        local list = map and Call(CQ.GetQuestsOnMap, map)
        if type(list) == "table" then
            for _, e in ipairs(list) do
                if e.questID == questID and e.x and e.y then
                    return { map = map, x = e.x * 100, y = e.y * 100 }, nil
                end
            end
        end
    end
    return nil
end

-- XP der Folgequests als Bonus (Vorquest-Wert), im Dungeon-Modus inkl. Dungeonquests.
local function FollowUpBonus(q, mode, depth)
    depth = depth or 1
    if depth > 2 then return 0, false end
    local parts, leadsToDungeon = {}, false
    local ids = {}
    if q.nextQuestInChain and q.nextQuestInChain > 0 then ids[#ids + 1] = q.nextQuestInChain end
    for _, id in ipairs(q.childQuests or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(unlocks[q.id] or {}) do ids[#ids + 1] = id end
    local seen = {}
    for _, id in ipairs(ids) do
      if not seen[id] then
        seen[id] = true
        local f = DB.Quest(id)
        local blocked = f and (RequirementBlock(f) or SpecialExcluded(f.specialFlags))
        if f and not blocked and not Done(id) and RaceClassOK(f) then
            local fa = Analyze(f)
            local isDungeon = fa.dungeonArea ~= nil
            if not isDungeon or mode.dungeons then
                local share = CONFIG.followUpShare / depth
                local b2, d2 = FollowUpBonus(f, mode, depth + 1)
                table.insert(parts, share * QuestXP(f) + b2)
                if isDungeon or d2 then leadsToDungeon = true end
            end
        end
      end
    end
    -- Viele Folgequests schliessen sich gegenseitig aus (z. B. Berufsquests):
    -- nur die drei wertvollsten zaehlen.
    table.sort(parts, function(x, y) return x > y end)
    local bonus = 0
    for i = 1, math.min(3, #parts) do bonus = bonus + parts[i] end
    return bonus, leadsToDungeon
end

-- Passendes Questlog-Ziel zu einem Datenbank-Ziel finden: zuerst ueber den
-- Namen im Zieltext ("Troll-Gluecksbringer: 0/8"), sonst ueber die Position.
local function MatchObjective(live, t, index)
    if not live or not live.objectives then return nil end
    if t.name and t.name ~= "" then
        local found, count = nil, 0
        for _, o in ipairs(live.objectives) do
            if o.text and o.text:find(t.name, 1, true) then found = found or o; count = count + 1 end
        end
        -- Eindeutiger Name -> dieses Ziel; gleich benannte Ziele -> ueber die Position
        if count == 1 then return found end
        if count > 1 and live.objectives[index] then return live.objectives[index] end
    end
    return live.objectives[index]
end
P.MatchObjective = MatchObjective

-- Anteil der noch offenen Ziele einer aktiven Quest (aus dem Questlog).
local function RemainingFraction(live)
    if not live or #live.objectives == 0 then return 1 end
    local need, have = 0, 0
    for _, o in ipairs(live.objectives) do
        local n = (o.need and o.need > 0) and o.need or 1
        local h = o.done and n or math.min(n, o.have or 0)
        need, have = need + n, have + h
    end
    if need == 0 then return 0 end
    return (need - have) / need
end

---------------------------------------------------------------------------
-- Planung
---------------------------------------------------------------------------
local lastPlan
local committed   -- Schluessel des zuletzt angezeigten Schritts
local committedMap -- Karte des zuletzt angezeigten Ziels
local function ActionKey(act)
    if act.kind == "DUNGEON" then return "DUNGEON:" .. tostring(act.group and act.group.area) end
    if act.kind == "SHIP" then return "SHIP:" .. tostring(act.leg and act.leg.fromName) .. ">" .. tostring(act.leg and act.leg.toName) end
    return act.kind .. ":" .. tostring(act.c and act.c.q.id) .. ":" .. tostring(act.objIndex or "")
end
P.ActionKey = ActionKey
local TradeMissing
local UnlocksAvailable

local function MaxLogSize()
    local n = C_QuestLog and Call(C_QuestLog.GetMaxNumQuestsCanAccept)
    if not n and GetMaxNumQuestsCanAccept then n = Call(GetMaxNumQuestsCanAccept) end
    return tonumber(n) or CONFIG.maxLogSize
end

-- Liefert den NPC-Namen, wenn ein Ziel nur per Tausch erhaeltlich und noch offen ist.
TradeMissing = function(c)
    for ti, t in ipairs(c.a.targets) do
        if t.trade then
            local lo = c.live and MatchObjective(c.live, t, ti)
            if not (lo and lo.done) then return t.trade end
        end
    end
    return nil
end

-- Wird nach Abgabe dieser Quest sofort eine Folgequest verfuegbar?
UnlocksAvailable = function(q)
    local ids = {}
    if q.nextQuestInChain and q.nextQuestInChain > 0 then ids[#ids + 1] = q.nextQuestInChain end
    for _, id in ipairs(q.childQuests or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(unlocks[q.id] or {}) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local f = DB.Quest(id)
        if f and not Done(id) and RaceClassOK(f) and (f.requiredLevel or 1) <= player.level
           and (f.questLevel or 1) <= player.level + P.MaxLevelAbove() then
            return true
        end
    end
    return false
end

local function Median(list)
    if #list == 0 then return nil end
    table.sort(list)
    return list[math.ceil(#list / 2)]
end

local function MapName(map)
    local info = C_Map and Call(C_Map.GetMapInfo, map)
    return info and info.name or (L("Karte ") .. tostring(map))
end
P.MapName = MapName

local laterMaps, recMap = {}, nil
-- Zeitmessung je Abschnitt (fuer /lm leistung)
local markT, markName, markAcc
local function Mark(name)
    if not markAcc or not debugprofilestop then return end
    local t = debugprofilestop()
    if markName then markAcc[markName] = (markAcc[markName] or 0) + (t - markT) end
    markT, markName = t, name
end
function P.Plan(modeKey, state)
    local measure = not state and debugprofilestop
    if measure then markAcc, markName, markT = {}, "Start", debugprofilestop() else markAcc = nil end
    ResetTravelCache()
    UpdatePlayer()
    if state then player.level = state.level end
    local mode = P.MODES[modeKey] or P.MODES.quests
    local result = { mode = mode, modeKey = modeKey, actions = {}, entries = {}, skipped = {}, byId = {} }
    if not DB.Available() then
        result.error = L("QuestieDB ist nicht aktiv. Der Routenplaner braucht QuestieDB.")
        lastPlan = result; return result
    end
    if not P.poolReady then
        result.error = L("Questdaten werden geladen …")
        lastPlan = result; return result
    end
    if not state and poolLevel ~= player.level then P.BuildPool(function() if Levelmate.RequestRefresh then Levelmate.RequestRefresh() end end) end

    BuildUnlocks()
    local here = state and state.here or P.PlayerPoint()
    hearthFrom = (not (state and state.hearthUsed)) and here or nil
    if not state and Levelmate.Travel and Levelmate.Travel.SetTrailOrigin then
        if here then World(here) end
        Levelmate.Travel.SetTrailOrigin(here)
    end
    local live = state and state.live or Levelmate.Quests.GetList()
    inLog = {}
    for _, lq in ipairs(live) do inLog[lq.questID] = lq end

    Mark("Kandidaten")
    -- 1) Kandidaten sammeln: aktive Quests + verfuegbare Quests
    local cands = {}
    for _, lq in ipairs(live) do
        local q = DB.Quest(lq.questID)
        if q then table.insert(cands, { q = q, live = lq }) end
    end
    local grey = GreyLevel(player.level)
    for _, id in ipairs(pool) do
        local q = DB.Quest(id)
        if q and not inLog[id] and Available(q) then
            local a = Analyze(q)
            local classQ = ClassMaskSpecific(q.requiredClasses)
            if classQ and not P.ClassQuestsOn() then
                -- Einstellung: Klassenquests ausgeblendet
            elseif not a.itemStart and #a.givers > 0 and ((q.questLevel or 0) > grey or classQ) then
                table.insert(cands, { q = q })
            end
        end
    end

    Mark("Bewertung")
    -- 2) Wert, Aufwand und Effizienz je Quest
    local effs = {}
    for _, c in ipairs(cands) do
        local q, a = c.q, Analyze(c.q)
        c.a = a
        c.xp = QuestXP(q)
        if c.live and c.xp == 0 then c.xp = ClientXP(q.id) end
        local bonus, toDungeon = FollowUpBonus(q, mode)
        -- Gegner-XP: Kills fuer die Quest (bei Drops: erwartete Kills) bringen
        -- nebenbei XP. Nur der noch offene Teil, nicht im Dungeon.
        local mob = 0
        for ti, t in ipairs(a.targets) do
            if t.mobLevel and t.killsPerUnit and not (t.dungeonArea and #t.points == 0) then
                local left = t.need or 1
                if c.live then
                    local lo = MatchObjective(c.live, t, ti)
                    if lo and lo.done then left = 0
                    elseif lo and lo.need and lo.need > 0 then left = math.max(0, lo.need - (lo.have or 0)) end
                end
                mob = mob + left * t.killsPerUnit * MobXP(t.mobLevel, player.level)
            end
        end
        c.mobXP = mob * CONFIG.mobXPShare
        c.value = c.xp + bonus + c.mobXP
        c.leadsToDungeon = toDungeon
        c.classQuest = ClassMaskSpecific(q.requiredClasses)
        c.isDungeon = a.dungeonArea ~= nil
        local frac = c.live and RemainingFraction(c.live) or 1
        if c.live and c.live.status == Levelmate.Quests.STATUS_READY then frac = 0 end
        c.factor = Levelmate.Smart and Levelmate.Smart.Factor and Levelmate.Smart.Factor(a.kind) or 1
        c.effort = a.effort * frac * c.factor
        -- Aufwand ab Questgeber (unabhaengig von deiner Position) -> "lohnt sich?"
        local g = Nearest(here, a.givers)
        -- Der Teil ab dem Questgeber haengt nicht von deiner Position ab:
        -- je Questgeber zwischenspeichern (spart viel Rechenzeit).
        local o, tGO, tOF
        local cc = g and costCache[q.id]
        if cc and cc.g == g and cc.speed == WalkSpeed() then
            o, tGO, tOF = cc.o, cc.tGO, cc.tOF
        else
            o, tGO = Nearest(g or here, a.objectivePoints)
            local _
            _, tOF = Nearest(o or g or here, a.finishers)
            if g then costCache[q.id] = { g = g, o = o, tGO = tGO, tOF = tOF, speed = WalkSpeed() } end
        end
        local base = c.effort + (#a.objectivePoints > 0 and tGO or 0) + tOF + CONFIG.talk * 2
        if c.isDungeon then base = base + CONFIG.dungeonRun / 3 end
        c.zoneCost = math.max(30, base)
        c.eff = c.value / c.zoneCost
        -- fuer "gemeinsamer Weg": wohin fuehrt die Quest, und wie weit ist der Hinweg?
        c.tripSeconds = (#a.objectivePoints > 0 and tGO) or tOF or 0
        local dest = o or Nearest(g or here, a.finishers)
        c.destMap = dest and dest.map or nil
        c.destPoint = dest
        c.giverMap = g and g.map or nil
        local above = (q.questLevel or 1) - player.level
        if above > 0 then c.eff = c.eff * math.max(0.2, 1 - CONFIG.riskPerLevel * above) end
        c.xpPerMin = math.min(999, (c.xp + c.mobXP) / c.zoneCost * 60)
        if not c.isDungeon then table.insert(effs, c.eff) end
    end
    local ref = Median(effs) or 0
    result.referenceXPPerMin = ref * 60
    -- Klassenquests: Die Belohnung (Zauber, Begleiter) zaehlt mehr als die XP.
    -- Sie werden darum wie eine ueberdurchschnittlich lohnende Quest eingeplant.
    local classOn = P.ClassQuestsOn()
    for _, c in ipairs(cands) do
        -- Sehr lange Klassenquests (ueber 45 min) nicht ganz nach vorne holen:
        -- Sie bleiben eingeplant und werden erledigt, wenn du ohnehin dort bist.
        if c.classQuest and classOn and ref > 0 and c.effort <= CONFIG.classMaxBoostEffort then
            c.classBoost = math.min(50, math.max(1, ref * CONFIG.classValue / math.max(c.eff, 1e-6)))
        end
    end

    Mark("Auswahl")
    -- 3) Auswahl: zu langsame Quests ueberspringen, Dungeonquests je nach Modus
    local kept = {}
    for _, c in ipairs(cands) do
        local skipReason
        if Levelmate.Smart and Levelmate.Smart.IsDeferred({ questID = c.q.id }) then
            skipReason = "von dir übersprungen"
        elseif c.live and c.live.status ~= Levelmate.Quests.STATUS_READY and ExclusiveDone(c.q.id) then
            -- Gegenstueck schon erledigt (z. B. Magram-Allianz abgegeben -> Gelkis-Allianz)
            skipReason = "schließt sich mit Quest " .. ExclusiveDone(c.q.id) .. " aus"
        elseif c.isDungeon and not mode.dungeons then
            skipReason = "Dungeonquest (" .. (c.a.dungeonName or "Dungeon") .. ")"
        elseif c.a.elite and not mode.dungeons then
            skipReason = "Elite-Gegner (Gruppe nötig)"
        elseif not c.live and TradeMissing(c) then
            skipReason = "braucht Gegenstand von " .. TradeMissing(c) .. " (Tausch/Beruf/Handel)"
        elseif not c.isDungeon and ref > 0 and c.eff < ref * mode.threshold and not c.classBoost
               and not (c.classQuest and classOn)
               and not (c.live and c.live.status == Levelmate.Quests.STATUS_READY) then
            skipReason = string.format("lohnt sich nicht (≈%d XP/min, Ø %d)", math.floor(c.xpPerMin), math.floor(ref * 60))
        end
        c.skipReason = skipReason
        if skipReason then
            if c.live then table.insert(result.skipped, c) end
        else
            table.insert(kept, c)
        end
        if c.live then result.entries[c.q.id] = c end
        result.byId[c.q.id] = c
    end

    Mark("GemeinsamerWeg")
    -- 3b) Gemeinsamer Weg: Fuehrt schon eine eingeplante Quest in ein anderes
    -- Gebiet (z. B. vom Wegekreuz nach Desolace), dann ist der Hinweg fuer
    -- weitere Quests dorthin schon "bezahlt". Solche Quests werden neu bewertet
    -- und mitgenommen, wenn sie ohne den Hinweg lohnen.
    local tripTo = {}
    for _, c in ipairs(kept) do
        if c.destMap and c.giverMap and c.destMap ~= c.giverMap and not c.isDungeon then
            tripTo[c.destMap] = true
        end
    end
    -- Orte, zu denen du wegen eingeplanter Quests ohnehin gehst (Annahme, Ziele, Abgabe)
    -- Raster mit Zellen von der Groesse des Radius: Pruefen geht dann ueber
    -- die 9 Nachbarzellen statt ueber alle (oft tausende) Punkte.
    local R = CONFIG.sharedTripRadius
    local visitGrid = {}
    local function GKey(cont, cx, cy) return cont .. ":" .. cx .. ":" .. cy end
    for _, c in ipairs(kept) do
        if not c.isDungeon then
            local a = c.a
            for _, list in ipairs({ c.live and {} or a.givers, a.finishers, c.live and a.objectivePoints or {} }) do
                for _, p in ipairs(list) do
                    if World(p) then
                        local k = GKey(p.cont, math.floor(p.wx / R), math.floor(p.wy / R))
                        local cell = visitGrid[k]
                        if not cell then cell = {}; visitGrid[k] = cell end
                        cell[#cell + 1] = p
                    end
                end
            end
        end
    end
    local function VisitedAnyway(p)
        if not p or not World(p) then return false end
        local cx, cy = math.floor(p.wx / R), math.floor(p.wy / R)
        for dx = -1, 1 do for dy = -1, 1 do
            local cell = visitGrid[GKey(p.cont, cx + dx, cy + dy)]
            if cell then
                for _, v in ipairs(cell) do
                    local yd = Yards(p, v)
                    if yd and yd <= R then return true end
                end
            end
        end end
        return false
    end
    for _, c in ipairs(cands) do
        local sameZone = c.destMap and tripTo[c.destMap] and c.giverMap and c.destMap ~= c.giverMap
        if c.skipReason and c.skipReason:find("^lohnt sich nicht")
           and (sameZone or VisitedAnyway(c.destPoint)) then
            -- Nur der Hinweg ist "bezahlt" - die Arbeit vor Ort und der Weg zur
            -- Abgabe bleiben. Darum nie unter den eigentlichen Aufwand.
            local cost = math.max(30, (c.effort or 0) + CONFIG.talk * 2,
                c.zoneCost - CONFIG.sharedTripShare * (c.tripSeconds or 0))
            local eff = c.value / cost
            local above = (c.q.questLevel or 1) - player.level
            if above > 0 then eff = eff * math.max(0.2, 1 - CONFIG.riskPerLevel * above) end
            if eff >= ref * mode.threshold then
                c.skipReason, c.sharedTrip = nil, true
                c.eff, c.xpPerMin = eff, math.min(999, (c.xp + (c.mobXP or 0)) / cost * 60)
                table.insert(kept, c)
                if c.live then
                    for i, sc in ipairs(result.skipped) do
                        if sc == c then table.remove(result.skipped, i); break end
                    end
                end
            end
        end
    end

    Mark("Aktionen")
    -- 4) Aktionen ab der aktuellen Position bewerten
    local actions = result.actions
    local dungeonGroups = {}
    -- Dichte aller offenen Ziele aktiver, lohnender Quests
    local targetLists = {}
    for _, c in ipairs(kept) do
        if c.live and c.live.status ~= Levelmate.Quests.STATUS_READY and not c.isDungeon then
            for ti, t in ipairs(c.a.targets) do
                local lo = (t.kind ~= "key") and MatchObjective(c.live, t, ti) or nil
                if t.kind == "key" and HasKey(t.itemId) then lo = { done = true } end
                if not (lo and lo.done) and #t.points > 0 then
                    targetLists[c.q.id .. ":" .. ti] = NearestSameMap(here, t.points)
                end
            end
        end
    end
    local grid = BuildDensity(targetLists)
    for _, c in ipairs(kept) do
        local a, q = c.a, c.q
        if c.live and c.live.status == Levelmate.Quests.STATUS_READY then
            local f, t = Nearest(here, a.finishers)
            local fname = a.finisherName
            local clientWp = false
            if not f then
                -- Abgabeort unbekannt (z. B. Forever-eigene Quest): das Spiel fragen
                local wp, wname = ClientWaypoint(c.q.id)
                if wp and World(wp) then
                    f, t, fname = wp, TravelSeconds(here, wp), wname or L("Abgabeort laut Spiel")
                    clientWp = true
                end
            end
            if f then
                table.insert(actions, { kind = "TURNIN", c = c, target = f, targetName = fname, clientWaypoint = clientWp,
                    seconds = t + CONFIG.talk, stepSeconds = t + CONFIG.talk, value = math.max(c.value, 1) })
            end
        elseif c.live then
            if c.isDungeon then
                local g = dungeonGroups[a.dungeonArea] or { list = {}, value = 0, area = a.dungeonArea,
                    name = a.dungeonName, entrance = a.dungeonEntrance }
                table.insert(g.list, c); g.value = g.value + c.value
                dungeonGroups[a.dungeonArea] = g
            else
                -- Jedes offene Questziel ist ein eigener Schritt mit eigenem Ort.
                local added = false
                for ti, t in ipairs(a.targets) do
                    local lo = (t.kind ~= "key") and MatchObjective(c.live, t, ti) or nil
                    local blocked = false
                    if t.kind == "key" then
                        -- Schluessel schon im Rucksack, oder die zugehoerigen Ziele sind erledigt?
                        local needed = false
                        for oi, ot in ipairs(a.targets) do
                            if ot.needsKeys then
                                for _, k in ipairs(ot.needsKeys) do
                                    if k == t then
                                        local olo = MatchObjective(c.live, ot, oi)
                                        if not (olo and olo.done) then needed = true end
                                    end
                                end
                            end
                        end
                        if HasKey(t.itemId) or not needed then lo = { done = true } end
                    elseif t.needsKeys then
                        for _, k in ipairs(t.needsKeys) do if not HasKey(k.itemId) then blocked = true end end
                    end
                    if blocked then
                        -- erst den Schluessel holen
                    elseif t.buy == "ah" and not (lo and lo.done) and not HasKey(t.itemId) then
                        -- Kaufen im Auktionshaus (oder selbst herstellen)
                        local ahs = Levelmate.Travel.Auctioneers and Levelmate.Travel.Auctioneers() or {}
                        local pts = {}
                        for _, ah in ipairs(ahs) do pts[#pts + 1] = ah.point end
                        local o, tPO = Nearest(here, pts)
                        local ahName
                        for _, ah in ipairs(ahs) do if ah.point == o then ahName = ah.name end end
                        if not o then o, tPO = Nearest(here, a.finishers) end
                        if o then
                            table.insert(actions, { kind = "DO", c = c, obj = t, objIndex = ti, liveObj = lo, buy = "ah",
                                target = o, targetName = ahName, finisher = Nearest(o, a.finishers),
                                seconds = tPO + CONFIG.buyItem, stepSeconds = tPO + CONFIG.buyItem,
                                objEffort = CONFIG.buyItem, value = c.value * 0.5 })
                            added = true
                        end
                    elseif t.trade and not (lo and lo.done) and t.tradePoints and #t.tradePoints > 0 then
                        local o, tPO = Nearest(here, NearestSameMap(here, t.tradePoints))
                        table.insert(actions, { kind = "DO", c = c, obj = t, objIndex = ti, liveObj = lo, trade = true,
                            target = o, targetName = t.trade, finisher = Nearest(o, a.finishers),
                            seconds = tPO + 60, stepSeconds = tPO + 60, objEffort = 60, value = c.value * 0.25 })
                        added = true
                    elseif not (lo and lo.done) and #t.points > 0 then
                        local frac = 1
                        if lo and lo.need and lo.need > 0 then frac = math.max(0, (lo.need - (lo.have or 0)) / lo.need) end
                        local effort = t.effort * frac * (Levelmate.Smart.Factor and Levelmate.Smart.Factor(t.kind) or 1)
                        local o, tPO = BestClusterPoint(here, NearestSameMap(here, t.points), grid, c.q.id .. ":" .. ti)
                        local fin, tOF = Nearest(o or here, a.finishers)
                        local share = (a.effort > 0) and (t.effort / a.effort) or 1
                        -- Den Rueckweg teilen sich alle Quests desselben Lagers -> nur anteilig.
                        table.insert(actions, { kind = "DO", c = c, obj = t, objIndex = ti, liveObj = lo, key = (t.kind == "key"),
                            target = o, targetName = t.source or t.name, finisher = fin,
                            seconds = tPO + effort + tOF * CONFIG.returnShare, stepSeconds = tPO + effort,
                            objEffort = effort, value = c.value * share })
                        added = true
                    end
                end
                if not added then
                    -- Ziele ohne bekannte Orte: zur Abgabe bzw. Questgeber leiten.
                    local f, tf = Nearest(here, a.finishers)
                    if f then
                        table.insert(actions, { kind = "DO", c = c, target = f, targetName = a.finisherName, finisher = f,
                            seconds = tf + c.effort, stepSeconds = tf + c.effort, objEffort = c.effort, value = c.value })
                    end
                end
            end
        else
            local g, tPG = Nearest(here, a.givers)
            if g and #live < MaxLogSize() and (not c.isDungeon or (q.questLevel or 0) <= player.level + 2) then
                local secs = tPG + c.zoneCost
                local act = { kind = "ACCEPT", c = c, target = g, targetName = a.giverName,
                              seconds = secs, stepSeconds = tPG + CONFIG.talk, value = c.value,
                              pickup = tPG < CONFIG.nearbyPickup }
                table.insert(actions, act)
            end
        end
    end
    -- Weitere Quests fuer denselben Dungeon, die man noch annehmen kann:
    -- erst annehmen, dann einmal rein (statt zweimal in den Dungeon).
    for _, act in ipairs(actions) do
        if act.kind == "ACCEPT" and act.c and act.target then
            local a = act.c.a
            local area = a.dungeonArea
            if not area then for _, t in ipairs(a.targets) do area = area or t.dungeonArea end end
            if area then
                for _, g in pairs(dungeonGroups) do
                    if DB.SameDungeon(area, g.area) and TravelSeconds(here, act.target) <= CONFIG.dungeonPickupMax then
                        g.pickups = g.pickups or {}
                        table.insert(g.pickups, act)
                        act.dungeonPickup = g.name
                    end
                end
            end
        end
    end
    -- Bald verfuegbare Quests fuer denselben Dungeon (jetzt noch zu hoch):
    -- Lohnt es sich, mit dem Dungeon noch zu warten?
    if next(dungeonGroups) then
        local inLog = {}
        for _, lq in ipairs(live) do inLog[lq.questID] = true end
        for _, id in ipairs(pool) do
            local q = DB.Quest(id)
            local ql = q and q.questLevel or 0
            if q and not inLog[id] and not Done(id) and ql > player.level + P.MaxLevelAbove()
               and ql <= player.level + P.MaxLevelAbove() + CONFIG.dungeonWaitLevels then
                local a = Analyze(q)
                local area = a.dungeonArea
                if not area then for _, t in ipairs(a.targets) do area = area or t.dungeonArea end end
                if area and #a.givers > 0 then
                    for _, g in pairs(dungeonGroups) do
                        if DB.SameDungeon(area, g.area) then
                            g.upcoming = g.upcoming or {}
                            table.insert(g.upcoming, q)
                            local from = ql - CONFIG.maxLevelAbove
                            if not g.upcomingLevel or from > g.upcomingLevel then g.upcomingLevel = from end
                        end
                    end
                end
            end
        end
    end
    for _, g in pairs(dungeonGroups) do
        local e = g.entrance
        local t = e and TravelSeconds(here, e) or CONFIG.crossContinent
        -- Wert eines Laufs: Quest-XP + Gegner-XP im Dungeon (etwa so viel wie
        -- normales Questen in derselben Zeit).
        local killXP = ref * CONFIG.dungeonRun
        -- Gegner unter deiner Stufe geben weniger XP, graue gar keine.
        -- Dungeonstufe ~ hoechste Questlevel der Dungeonquests.
        local dl = 0
        for _, c in ipairs(g.list) do dl = math.max(dl, c.q.questLevel or 0) end
        if dl > 0 and dl < player.level then
            local grey = GreyLevel(player.level)
            local f = (dl <= grey) and 0 or (1 - (player.level - dl) / (player.level - grey + 1))
            killXP = killXP * math.max(0, f)
        end
        table.insert(actions, { kind = "DUNGEON", group = g, target = e, targetName = g.name,
            seconds = t + CONFIG.dungeonRun, stepSeconds = t + CONFIG.dungeonRun,
            value = g.value + killXP, questXP = g.value, pickups = g.pickups,
            upcoming = (g.upcoming and #g.list < 3) and g.upcoming or nil, upcomingLevel = g.upcomingLevel })
    end
    -- Abgaben buendeln: Wert aller fertigen Quests im selben Lager zusammenzaehlen,
    -- und Abgabe zurueckstellen, solange Quests desselben Lagers Ziele naeher
    -- als das Lager haben (erst alles erledigen, dann zusammen abgeben).
    for _, act in ipairs(actions) do
        if act.kind == "DO" and not act.tObj then act.tObj = TravelSeconds(here, act.target) end
    end
    -- Kuenftige Arbeit: Ziele aktiver Quests und Ziele der Folgequests, die
    -- durch Quests im Log freigeschaltet werden. Liegt davon etwas nahe an einem
    -- Abgabe-Lager, kommst du dort ohnehin noch einmal vorbei.
    local futurePoints = {}
    for _, act in ipairs(actions) do
        if act.kind == "DO" and act.target then futurePoints[#futurePoints + 1] = act.target end
    end
    for _, c in ipairs(kept) do
        if c.live then
            local ids = {}
            if c.q.nextQuestInChain and c.q.nextQuestInChain > 0 then ids[#ids + 1] = c.q.nextQuestInChain end
            for _, id in ipairs(c.q.childQuests or {}) do ids[#ids + 1] = id end
            for _, id in ipairs(unlocks[c.q.id] or {}) do ids[#ids + 1] = id end
            for _, id in ipairs(ids) do
                local f = DB.Quest(id)
                if f and not Done(id) and RaceClassOK(f) and (f.questLevel or 1) <= player.level + P.MaxLevelAbove() then
                    local fa = Analyze(f)
                    if not fa.dungeonArea then
                        for _, p in ipairs(NearestSameMap(here, fa.objectivePoints)) do futurePoints[#futurePoints + 1] = p end
                    end
                end
            end
        end
    end
    local function ComeBackLater(hub)
        -- Flugpunkt direkt am Lager? Ziele, die man ueber diesen Flugpunkt erreicht,
        -- bringen dich ebenfalls wieder hierher.
        local hubFP, hubFPyd = Levelmate.Travel.NearestFP(hub, Yards)
        if hubFPyd and hubFPyd > 300 then hubFP = nil end
        for _, p in ipairs(futurePoints) do
            local yd = Yards(p, hub) or 1e9
            if yd < CONFIG.returnRadius then return true end
            if hubFP and yd < CONFIG.returnRadius * 2 then
                local pFP = Levelmate.Travel.NearestFP(p, Yards)
                if pFP == hubFP then return true end
            end
        end
        return false
    end
    for _, act in ipairs(actions) do
        if act.kind == "TURNIN" then
            local hubValue, waiting = 0, 0
            local localWait = false
            local waitFor = {}   -- fuer /lm warum: worauf diese Abgabe wartet
            local function WaitOn(o, why)
                waiting = waiting + 1
                waitFor[#waitFor + 1] = { name = o.c and o.c.q and o.c.q.name or o.targetName or "?", why = why, act = o }
            end
            local tHub = TravelSeconds(here, act.target)
            -- Schaltet eine Abgabe in diesem Lager eine Folgequest frei? Dann lieber
            -- gleich abgeben und die neue Quest mitnehmen.
            local unlocksSomething = false
            for _, o in ipairs(actions) do
                if o.kind == "TURNIN" and (Yards(o.target, act.target) or 1e9) < CONFIG.hubRadius
                   and UnlocksAvailable(o.c.q) then
                    unlocksSomething = true
                end
            end
            for _, o in ipairs(actions) do
                if o.kind == "TURNIN" and (Yards(o.target, act.target) or 1e9) < CONFIG.hubRadius then
                    hubValue = hubValue + o.value
                elseif o.kind == "DO" and o.tObj then
                    if tHub > CONFIG.nearbyPickup and o.tObj < tHub * CONFIG.closerShare then
                        -- Ein offenes Ziel liegt deutlich naeher als diese Abgabe -> erst das Ziel.
                        WaitOn(o, "naeher")
                    elseif o.tObj <= CONFIG.localWork and o.tObj <= tHub + CONFIG.localWorkSlack then
                        -- Ein offenes Ziel ist direkt hier (z. B. im selben Gebaeude/Lager):
                        -- erst hier fertig machen, dann abgeben. Die Luftlinie kennt keine
                        -- Mauern - "erst raus und wieder rein" ist im Spiel meist laenger.
                        WaitOn(o, "hier")
                        localWait = true
                    elseif tHub > CONFIG.nearbyPickup and not unlocksSomething and o.finisher
                           and (Yards(o.finisher, act.target) or 1e9) < CONFIG.hubRadius then
                        -- Diese offene Quest wird im selben Lager abgegeben: erst erledigen,
                        -- dann alles zusammen abgeben (spart einen Weg zum Lager).
                        WaitOn(o, "lager")
                    end
                end
            end
            -- Spaeter kommst du ohnehin in die Naehe dieses Lagers -> dann abgeben.
            if waiting == 0 and tHub > CONFIG.comeBackMin and not unlocksSomething and ComeBackLater(act.target) then
                waiting = 1
                act.comeBack = true
            end
            act.hubValue, act.waiting, act.localWait = hubValue, waiting, localWait
            act.waitFor = waitFor
            act.travel = TravelSeconds(here, act.target)
        end
    end
    -- Nicht weggehen, solange fertige Quests in der Naehe abgegeben werden koennen:
    -- Aktionen, die deutlich weiter weg fuehren als das naechste Abgabe-Lager,
    -- werden abgewertet.
    local nearestTurnin
    for _, act in ipairs(actions) do
        -- Abgaben, die auf andere Quests desselben Lagers warten, zaehlen hier nicht.
        if act.kind == "TURNIN" and (act.waiting or 0) == 0
           and (not nearestTurnin or act.travel < nearestTurnin) then nearestTurnin = act.travel end
    end
    -- Offene Ziele der Reihe nach abarbeiten (wie ein Guide): Unter den lohnenden
    -- Quests kommt immer das naechstgelegene Ziel zuerst. Die Effizienz hat schon
    -- entschieden, OB eine Quest gemacht wird; hier geht es nur um die Reihenfolge.
    local bestDO, minDO = nil, nil
    for _, act in ipairs(actions) do
        if act.kind == "DO" then
            act.tObj = TravelSeconds(here, act.target)
            local s = act.value / math.max(10, act.seconds)
            -- Sehr lange Ziele (ueber 45 min Arbeit) nicht als "naechstes Ziel"
            -- bevorzugen - sie werden nach ihrem eigenen Wert bewertet.
            act.longDO = (act.objEffort or 0) > CONFIG.classMaxBoostEffort
            if not act.longDO then
                if not bestDO or s > bestDO then bestDO = s end
                if not minDO or act.tObj < minDO then minDO = act.tObj end
            end
        end
    end
    -- Erst das aktuelle Gebiet fertig machen: Gibt es hier noch Ziele oder Abgaben,
    -- werden Schritte in anderen Gebieten stark abgewertet.
    local hereMap = here and here.map
    local workHere = false
    for _, act in ipairs(actions) do
        if (act.kind == "DO" or act.kind == "TURNIN") and act.target and act.target.map == hereMap then
            workHere = true; break
        end
    end
    -- Nur "festhalten", wenn du hier schon gearbeitet hast - nicht beim Durchreisen
    -- (z. B. Landung in Orgrimmar auf dem Weg ins Steinkrallengebirge).
    if not state and committedMap and committedMap ~= hereMap then workHere = false end
    -- Gebiete, die laut Gebietsplan erst spaeter dran sind (z. B. Desolace 33-38,
    -- waehrend du mit 30 noch Tausend Nadeln machst). Einzelne Abgaben/Annahmen
    -- dort warten, bis du ohnehin hinkommst - statt extra hinzufliegen.
    if not state then
        laterMaps = {}
        local zp = P.ZonePlan and P.ZonePlan(4)
        recMap = zp and zp[1] and zp[1].map or nil
        if zp and zp[1] then
            for _, z in ipairs(zp) do
                if z.lo > player.level and z.map ~= zp[1].map then laterMaps[z.map] = true end
            end
        end
    end
    for _, act in ipairs(actions) do
      if act.kind ~= "ABANDON" then
        act.score = (act.hubValue or act.value) / math.max(10, act.seconds)
        if act.kind == "DO" and bestDO and not act.longDO then
            act.score = bestDO * (minDO + 60) / (act.tObj + 60)
        end
        -- Wie RestedXP: am selben Ort erst alles abgeben und annehmen, dann losgehen.
        local near = act.target and here and (TravelSeconds(here, act.target) < CONFIG.nearbyPickup)
        if near and (act.kind == "ACCEPT" or (act.kind == "TURNIN" and not act.localWait)) then
            act.score = act.score * CONFIG.nearbyBoost
            if act.kind == "TURNIN" then act.score = act.score * 2 end  -- Abgabe vor Annahme (Folgequests)
        elseif act.kind == "TURNIN" and (act.waiting or 0) > 0 then
            act.score = act.score * CONFIG.waitFactor; act.pen = (act.pen or "") .. " warten"
        end
        if nearestTurnin and act.target
           and TravelSeconds(here, act.target) > nearestTurnin + CONFIG.leaveMargin then
            act.score = act.score * CONFIG.leavePenalty; act.pen = (act.pen or "") .. " weit-weg"
        end
        -- Andere Karte, aber direkt nebenan (z. B. Wegpunkt des Spiels auf einer
        -- Nachbar-/Instanzkarte): nicht wie "anderes Gebiet" behandeln.
        if workHere and act.target and act.target.map ~= hereMap
           and not (act.clientWaypoint and TravelSeconds(here, act.target) <= CONFIG.zoneStickNear) then
            act.score = act.score * CONFIG.zoneStick; act.pen = (act.pen or "") .. " anderes-Gebiet"
        end
        -- "Spaeteres Gebiet": laut Gebietsplan spaeter dran ODER Einstiegsstufe
        -- ueber deiner Stufe (und nicht das empfohlene Gebiet).
        local tmap = act.target and act.target.map
        local zlv = tmap and zoneLevels and zoneLevels[tmap]
        local tooHigh = tmap and zlv and zlv >= player.level + 2 and tmap ~= recMap
        local later = tmap and (tooHigh or laterMaps[tmap])
        -- Gebiet ueber deiner Stufe: immer zurueckstellen (auch wenn ein Flug es
        -- nah erscheinen laesst), ausser du bist schon dort.
        if later and tmap ~= hereMap
           and (tooHigh or TravelSeconds(here, act.target) > CONFIG.laterZoneTravel) then
            act.score = act.score * CONFIG.laterZone; act.pen = (act.pen or "") .. " spaeteres-Gebiet"
            act.laterZone = true
        end
        if act.target and act.target.map ~= hereMap then
            local zl = zoneLevels and zoneLevels[act.target.map]
            if zl and zl - player.level >= P.DangerLevels() then
                act.score = act.score * CONFIG.dangerFactor; act.pen = (act.pen or "") .. " gefaehrlich"
                act.danger = zl
            end
        end
        if act.c and act.c.classBoost and not act.danger then act.score = act.score * act.c.classBoost end
        if act.kind == "DUNGEON" and act.upcoming then
            act.score = act.score * CONFIG.laterZone; act.pen = (act.pen or "") .. " spaeter-mehr-Dungeonquests"
        elseif act.kind == "DUNGEON" and act.pickups and #act.pickups > 0 then
            act.score = act.score * CONFIG.waitFactor; act.pen = (act.pen or "") .. " erst-Dungeonquests-annehmen"
        elseif act.kind == "ACCEPT" and act.dungeonPickup then
            act.score = act.score * CONFIG.dungeonPickupBoost
        end
        -- Du stehst vor dem Dungeon (z. B. mit deiner Gruppe): dann jetzt rein.
        -- ... aber nur mit Gruppe und wenn sich der Dungeon jetzt schon lohnt
        -- (nicht, nur weil du zufaellig am Eingang vorbeikommst).
        local grouped = (IsInGroup and IsInGroup()) or (state and state.grouped)
        if act.kind == "DUNGEON" and act.target and grouped and not act.upcoming
           and TravelSeconds(here, act.target) < CONFIG.dungeonNear then
            act.score = act.score * 1000
            act.atEntrance = true
        end
        act.xpPerMin = act.value / math.max(10, act.seconds) * 60
      end
    end
    -- Volles Questlog: unrentable Quests zum Abbrechen vorschlagen (wie RestedXP).
    if #live >= MaxLogSize() - 2 then
        local worst
        for _, c in ipairs(result.skipped) do
            if c.live and c.live.status ~= Levelmate.Quests.STATUS_READY and (not worst or c.xpPerMin < worst.xpPerMin) then
                worst = c
            end
        end
        if worst then
            table.insert(actions, { kind = "ABANDON", c = worst, seconds = 5, value = 0, score = math.huge, xpPerMin = 0 })
        end
    end
    for _, act in ipairs(actions) do
        if act.c and act.c.a and act.c.a.optional and act.score ~= math.huge then
            act.score = act.score * CONFIG.optionalFactor; act.pen = (act.pen or "") .. " optional"
        end
    end
    table.sort(actions, function(x, y) return x.score > y.score end)
    -- Abgabe wartet auf naehere Ziele - aber Schritt 1 ist gar keins davon (z. B. eine
    -- weit entfernte Annahme)? Dann ist das Warten sinnlos: Liegt die Abgabe naeher
    -- als Schritt 1, wird sie normal bewertet (erst abgeben, dann weiter).
    do
        local top = actions[1]
        if top and top.kind ~= "TURNIN" and top.score ~= math.huge and top.target and here then
            local tTop = TravelSeconds(here, top.target)
            local changed = false
            for _, act in ipairs(actions) do
                if act.kind == "TURNIN" and (act.waiting or 0) > 0 and not act.comeBack and not act.localWait
                   and act.travel and act.travel < tTop then
                    local blocks = false
                    for _, w in ipairs(act.waitFor or {}) do if w.act == top then blocks = true; break end end
                    if not blocks then
                        act.score = act.score / CONFIG.waitFactor
                        act.pen = (act.pen or ""):gsub(" warten", "")
                        if act.pen == "" then act.pen = nil end
                        act.waitIgnored = true
                        changed = true
                    end
                end
            end
            if changed then table.sort(actions, function(x, y) return x.score > y.score end) end
        end
    end
    -- Auf dem Weg: Liegt eine Abgabe (oder Annahme) fast genau auf dem Weg zum
    -- besten Schritt, wird sie vorher erledigt - z. B. am Grossen Aufzug auf
    -- dem Weg nach Tausend Nadeln. Umweg hoechstens 15 % (+30 s).
    local first = actions[1]
    if first and first.target and first.score ~= math.huge and first.kind ~= "HEARTH" then
        local tFirst = TravelSeconds(here, first.target)
        if tFirst > CONFIG.onTheWayMin then
            local best, bestT, bestI
            for i = 2, #actions do
                local x = actions[i]
                -- Kurze Wege (< 90 s): nur Abgaben einschieben (fertige Quest direkt
                -- daneben), keine neuen Annahmen - die verlaengern sonst die Route.
                local ok = (x.kind == "TURNIN")
                    or (x.kind == "ACCEPT" and x.c and not x.c.skipReason and tFirst > 90)
                if ok and x.target and x.score ~= 0 then
                    local t1 = TravelSeconds(here, x.target)
                    if t1 < tFirst then
                        local t2 = TravelSeconds(x.target, first.target)
                        if t1 + t2 <= tFirst * CONFIG.onTheWayDetour + math.min(30, tFirst * 0.25) and (not bestT or t1 < bestT) then
                            best, bestT, bestI = x, t1, i
                        end
                    end
                end
            end
            if best then
                table.remove(actions, bestI)
                table.insert(actions, 1, best)
                best.onTheWay = true
            end
        end
    end
    -- Ruhige Route: Den bisherigen Schritt beibehalten, solange er noch gilt und
    -- der neue beste Schritt nicht deutlich besser ist. Verhindert staendiges
    -- Hin- und Herspringen, z. B. bei Zwischenlandungen oder beim Durchqueren
    -- einer Stadt.
    -- Ein Zwischenstopp "auf dem Weg" darf den Schritt nur abloesen, wenn er
    -- direkt neben dir liegt (< 30 s). Sonst wuerde beim Laufen alle paar Meter
    -- ein anderer Stopp "auf dem Weg" liegen und die Anzeige springen.
    if not state and committed and actions[1] and ActionKey(actions[1]) ~= committed then
        local top = actions[1]
        local topNear = top.target and here and (top.kind == "TURNIN" or top.kind == "ACCEPT")
            and TravelSeconds(here, top.target) < CONFIG.nearbyPickup
        for i, act in ipairs(actions) do
            if ActionKey(act) == committed and i > 1 then
                local keep
                -- Fertige Abgabe, die viel naeher liegt als der gemerkte Schritt
                -- (ohne Ruhestein gerechnet): sofort umschwenken. Der Ruhestein
                -- laeuft ja nicht weg.
                local topCloser = top.kind == "TURNIN" and top.target and act.target and here
                    and TravelSeconds(here, top.target) < 0.5 * TravelSecondsBase(here, act.target)
                if top.score == math.huge then keep = false
                elseif topNear or topCloser then keep = false
                elseif top.onTheWay then keep = true
                else keep = top.score < act.score * CONFIG.stickiness end
                if keep then
                    table.remove(actions, i)
                    table.insert(actions, 1, act)
                end
                break
            end
        end
    end
    if not state then
        committed = actions[1] and ActionKey(actions[1]) or nil
        committedMap = actions[1] and actions[1].target and actions[1].target.map or nil
    end

    Mark("Gebiet")
    -- 5) Empfohlenes Gebiet: Summe der lohnenden Quests je Karte
    local zoneValue, zoneNear = {}, {}
    for _, c in ipairs(kept) do
        local pts = c.live and c.a.objectivePoints or c.a.givers
        local p, t = Nearest(here, pts)
        if not p then p, t = Nearest(here, c.a.finishers) end
        if p and not c.isDungeon then
            zoneValue[p.map] = (zoneValue[p.map] or 0) + c.value
            if not zoneNear[p.map] or t < zoneNear[p.map] then zoneNear[p.map] = t end
        end
    end
    local bestMap, bestScore
    for map, v in pairs(zoneValue) do
        local score = v / (1 + (zoneNear[map] or 0) / 900)   -- weite Anreise mindert den Wert
        if not bestScore or score > bestScore then bestMap, bestScore = map, score end
    end
    if bestMap then
        result.zone = { map = bestMap, name = MapName(bestMap), value = bestScore }
    end
    Mark("Flug")
    -- 6) Lohnt sich ein Flug zum Ziel des besten Schritts? Dann zuerst fliegen.
    local top = actions[1]
    if top and top.target and here then
        local tTop, fa, fb, hearth, leg = TravelSeconds(here, top.target)
        if leg and not hearth then
            -- Erst zum Anleger: dorthin ggf. fliegen, sonst direkt hin.
            local tDock, da, db = TravelSecondsBase(here, leg.from)
            local atDock = (Yards(here, leg.from) or 1e9) < 60
            if da and db and not atDock then
                local flyYd = Yards(da.point, db.point) or 0
                local tc = Levelmate.Travel.CONFIG
                local flight = tc.overhead + flyYd * tc.routeFactor / tc.flightSpeed
                local ship = { kind = "SHIP", leg = leg, target = leg.from, targetName = leg.master,
                    next = top, value = top.value, seconds = tDock, score = math.huge, xpPerMin = top.xpPerMin }
                table.insert(actions, 1, { kind = "FLY", from = da, to = db, target = da.point,
                    targetName = da.name, atFP = (Yards(here, da.point) or 1e9) < 40, next = ship, value = top.value,
                    seconds = TravelSeconds(here, da.point), stepSeconds = TravelSeconds(here, da.point) + flight,
                    score = math.huge, xpPerMin = top.xpPerMin })
            else
                table.insert(actions, 1, { kind = "SHIP", leg = leg, target = leg.from, targetName = leg.master,
                    atDock = atDock, next = top, value = top.value,
                    seconds = tDock, stepSeconds = tDock + (leg.seconds or Levelmate.Travel.CONFIG.shipSeconds),
                    score = math.huge, xpPerMin = top.xpPerMin })
            end
        elseif hearth then
            table.insert(actions, 1, { kind = "HEARTH", to = hearth, next = top, value = top.value,
                seconds = Levelmate.Travel.CONFIG.hearthSeconds, stepSeconds = Levelmate.Travel.CONFIG.hearthSeconds,
                saves = TravelSecondsBase(here, top.target) - tTop,
                score = math.huge, xpPerMin = top.xpPerMin })
        elseif fa and fb then
            local atFP = (Yards(here, fa.point) or 1e9) < 40
            local flyYd = Yards(fa.point, fb.point) or 0
            local tc = Levelmate.Travel.CONFIG
            local flight = tc.overhead + flyYd * tc.routeFactor / tc.flightSpeed
            table.insert(actions, 1, { kind = "FLY", from = fa, to = fb, target = fa.point,
                targetName = fa.name, atFP = atFP, next = top, value = top.value,
                seconds = TravelSeconds(here, fa.point), stepSeconds = TravelSeconds(here, fa.point) + flight,
                score = math.huge, xpPerMin = top.xpPerMin })
        end
    end
    result.here = here
    if measure then Mark(nil); P.lastSections = markAcc; markAcc = nil end
    if not state then lastPlan = result end
    return result
end

function P.Last() return lastPlan end

-- /lm warum <Name oder ID>: erklaert, warum eine Quest (nicht) vorgeschlagen wird.
function P.Explain(query, print)
    if not DB.Available() then print("QuestieDB nicht aktiv."); return end
    UpdatePlayer()
    query = tostring(query or ""):lower()
    local wanted = tonumber(query)
    local found = {}
    local function consider(id)
        local q = DB.Quest(id)
        if q and (id == wanted or (not wanted and q.name and q.name:lower():find(query, 1, true))) then found[#found + 1] = q end
    end
    if wanted then consider(wanted) else
        for _, id in ipairs(DB.AllQuestIDs()) do
            if #found >= 5 then break end
            local name = QuestDB and QuestDB.name and select(2, pcall(QuestDB.name, id))
            if type(name) == "string" and name:lower():find(query, 1, true) then consider(id) end
        end
    end
    if #found == 0 then print(L("Keine Quest gefunden zu: ") .. query); return end
    -- Bei gleichen Namen zuerst die Quest aus deinem Log und die zu deinem Volk/deiner Klasse passende
    do
        local log = {}
        for _, e in ipairs(Levelmate.Quests.GetList and Levelmate.Quests.GetList() or {}) do log[e.questID] = true end
        local function rank(q) return (log[q.id] and 2 or 0) + (RaceClassOK(q) and 1 or 0) end
        table.sort(found, function(x, y) return rank(x) > rank(y) end)
    end
    local inPool = {}
    for _, id in ipairs(pool) do inPool[id] = true end
    for _, q in ipairs(found) do
        print(string.format(L("|cffffd100%s|r (ID %d, Questlevel %s, ab Stufe %s)"), q.name or "?", q.id, tostring(q.questLevel), tostring(q.requiredLevel)))
        local reason = NotAvailableReason(q)
        if inLog[q.id] then reason = nil end
        if not inPool[q.id] and not inLog[q.id] then
            print(L("  - nicht in der Vorauswahl (Stufenbereich oder Volk/Klasse passt nicht)"))
        end
        if reason then print(L("  - nicht annehmbar: ") .. LT(reason)) else print(L("  - annehmbar bzw. im Questlog")) end
        local a = Analyze(q)
        print(string.format(L("  - Questgeber-Orte: %d, Ziele: %d, geschätzter Aufwand: %d s%s%s"), #a.givers, #a.targets,
            math.floor(a.effort), a.elite and L(", Elite") or "", a.dungeonName and (L(", Dungeon ") .. a.dungeonName) or ""))
        local c = lastPlan and lastPlan.byId and lastPlan.byId[q.id]
        if c then
            if (c.mobXP or 0) >= 1 then print(string.format(L("  - Gegner-XP nebenbei: ≈%d"), math.floor(c.mobXP))) end
            print(string.format(L("  - Bewertung: ≈%d XP, ~%d XP/min%s"), math.floor(c.xp), math.floor(c.xpPerMin),
                c.skipReason and (L(", übersprungen: ") .. LT(c.skipReason)) or L(", wird eingeplant")))
            for i, act in ipairs(lastPlan.actions) do
                if act.c == c then
                    print(string.format(L("  - steht als Schritt %d in der Liste (%s)"), i, act.kind))
                    local tg = act.target
                    -- seconds = ganze Quest ab hier (Hinweg + Aufwand + Abgabe),
                    -- stepSeconds = nur dieser Schritt (Hinweg + Ansprechen)
                    local work = (act.kind == "DO") and (act.objEffort or 0) or 0
                    local way = math.max(0, (act.stepSeconds or act.seconds or 0) - work)
                    print(string.format(L("  - Ziel: Karte %s (%.1f, %.1f) %s, Hinweg ~%d s%s, ganze Quest ab hier ~%d s, Abzüge:%s"),
                        tostring(tg and tg.map), tg and tg.x or 0, tg and tg.y or 0,
                        act.clientWaypoint and L("(Wegpunkt des Spiels)") or "",
                        math.floor(way), work > 0 and string.format(L(", Arbeit vor Ort ~%d min"), math.floor(work / 60 + 0.5)) or "",
                        math.floor(act.seconds or 0), act.pen and act.pen:gsub("%S+", L) or L(" keine")))
                    if act.kind == "TURNIN" then
                        if act.comeBack then
                            print(L("  - Abgabe wartet: du kommst später ohnehin wieder in die Nähe"))
                        end
                        local seen, n = {}, 0
                        for _, w in ipairs(act.waitFor or {}) do
                            local key = w.name .. w.why
                            if not seen[key] and n < 5 then
                                seen[key], n = true, n + 1
                                local why = (w.why == "naeher" and L("Ziel liegt deutlich näher"))
                                    or (w.why == "hier" and L("Ziel direkt hier"))
                                    or L("wird im selben Lager abgegeben")
                                print(L("  - Abgabe wartet auf: ") .. w.name .. " (" .. why .. ")")
                            end
                        end
                    end
                    if c.factor and math.abs(c.factor - 1) > 0.05 then
                        print(string.format(L("  - gelernter Zeitfaktor für diese Questart: ×%.2f"), c.factor))
                    end
                    if i > 1 and lastPlan.actions[1] then
                        local top = lastPlan.actions[1]
                        print(string.format(L("  - Schritt 1 ist gerade: %s (Bewertung %.2f, diese Quest %.2f)"),
                            top.kind .. " " .. (top.c and top.c.q.name or top.targetName or "?"), top.score or 0, act.score or 0))
                    end
                    -- Aufschluesselung der Wegzeit
                    local here = lastPlan.here
                    if tg and here and Levelmate.Travel and Levelmate.Travel.RouteParts then
                        local r = Levelmate.Travel.RouteParts(here, tg, WalkSpeed(), Yards)
                        if r.straight then
                            local parts = { string.format(L("Luftlinie %d yd"), math.floor(r.straight)) }
                            if r.used ~= "Luftlinie" then
                                parts[#parts + 1] = string.format(L("laut %s %d yd"), L(r.used), math.floor(r.walkYd))
                            end
                            parts[#parts + 1] = string.format(L("zu Fuß ~%d s (%.1f yd/s)"), math.floor(r.walkSec), WalkSpeed())
                            if r.fa and r.fb and r.fa ~= r.fb then
                                parts[#parts + 1] = L("Flug ") .. Levelmate.Travel.PlaceName(r.fa) .. " > " .. Levelmate.Travel.PlaceName(r.fb)
                            end
                            local tB, fa, fb, _, leg = TravelSecondsBase(here, tg)
                            if leg then parts[#parts + 1] = L(leg.kind) .. " " .. leg.fromName .. " > " .. leg.toName
                            elseif fa and fb then parts[#parts + 1] = L("gewählt: mit Flug ~") .. math.floor(tB) .. " s"
                            else parts[#parts + 1] = L("gewählt: ~") .. math.floor(tB) .. " s" end
                            print(L("    Weg: ") .. table.concat(parts, " · "))
                        else
                            print(L("    Weg: anderer Kontinent"))
                        end
                    end
                    local tm = tg and tg.map
                    print(string.format(L("  - Gebiet %s: Einstieg ca. Stufe %s · empfohlen: %s · später-Liste: %s"),
                        tm and MapName(tm) or "?", tostring(tm and zoneLevels and zoneLevels[tm] or "?"),
                        recMap and MapName(recMap) or "?", tostring(tm and laterMaps[tm] or false)))
                    break
                end
            end
        else
            print(L("  - nicht unter den aktuellen Kandidaten"))
        end
    end
end

-- Geschaetzte Gesamtdauer einer Quest (fuer die Kalibrierung bei der Annahme).
-- Ohne Kalibrierungsfaktor, damit der Abgleich immer gegen die Grundschaetzung laeuft.
function P.EstimateFor(questID)
    local c = lastPlan and lastPlan.byId and lastPlan.byId[questID]
    local q = DB.Available() and DB.Quest(questID)
    if not q then return nil end
    local a = Analyze(q)
    local base = (c and c.zoneCost and c.factor and c.factor > 0) and (c.zoneCost - c.effort + c.effort / c.factor) or (a.effort + 2 * CONFIG.talk + 120)
    return { seconds = math.max(60, base), kind = a.kind }
end

---------------------------------------------------------------------------
-- Routenvorschau: die naechsten Schritte virtuell durchspielen
---------------------------------------------------------------------------
-- XP bis zur naechsten Stufe (Classic-Werte; fuer die aktuelle Stufe nimmt
-- das Addon den echten Wert vom Spiel).
local XP_TO_LEVEL = { 400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600, 8800, 10100, 11400,
    12900, 14400, 16000, 17700, 19400, 21300, 23200, 25200, 27300, 29400, 31700, 34000, 36400,
    38900, 41400, 44300, 47400, 50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700,
    90700, 95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500, 153900,
    160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800 }

local function PreviewRun(modeKey, steps, yieldEach)
    if not lastPlan or lastPlan.error or not P.poolReady then return nil end
    local Qs = Levelmate.Quests
    local state = { level = UnitLevel("player") or 1, here = P.PlayerPoint(), live = {} }
    for _, lq in ipairs(Qs.GetList()) do
        local objs = {}
        for _, o in ipairs(lq.objectives) do
            objs[#objs + 1] = { text = o.text, done = o.done, have = o.have, need = o.need }
        end
        table.insert(state.live, { questID = lq.questID, title = lq.title, status = lq.status, objectives = objs })
    end
    local xp = (UnitXP and Call(UnitXP, "player")) or 0
    local xpMax = (UnitXPMax and Call(UnitXPMax, "player")) or XP_TO_LEVEL[state.level] or 1
    local function Gain(amount)
        xp = xp + (amount or 0)
        while state.level < 60 and xp >= xpMax do
            xp = xp - xpMax
            state.level = state.level + 1
            xpMax = XP_TO_LEVEL[state.level] or xpMax
        end
    end
    local function Find(id)
        for k, e in ipairs(state.live) do if e.questID == id then return k, e end end
    end
    virtualDone = {}
    virtualItems = {}
    local out, total = {}, 0
    local ok, err = true, nil
    local function Step()
            local plan = P.Plan(modeKey, state)
            local act = plan.actions[1]
            if not act then return false end
            total = total + (act.stepSeconds or act.seconds or 0)
            table.insert(out, { act = act, zone = act.target and MapName(act.target.map), seconds = total, level = state.level })
            local id = act.c and act.c.q.id
            if act.kind == "ACCEPT" then
                local ready = #act.c.a.targets == 0
                local objs = {}
                for _, t in ipairs(act.c.a.targets) do
                    objs[#objs + 1] = { text = (t.name or "?") .. ": 0/" .. (t.need or 1), done = false, have = 0, need = t.need }
                end
                table.insert(state.live, { questID = id, title = act.c.q.name,
                    status = ready and Qs.STATUS_READY or Qs.STATUS_ACTIVE, objectives = objs })
            elseif act.kind == "DO" and act.key then
                virtualItems[act.obj.itemId] = true
            elseif act.kind == "DO" then
                local _, e = Find(id)
                if e then
                    local o = act.obj and MatchObjective(e, act.obj, act.objIndex)
                    if o then o.done = true; o.have = o.need else
                        for _, x in ipairs(e.objectives) do x.done = true end
                    end
                    local all = true
                    for _, x in ipairs(e.objectives) do if not x.done then all = false end end
                    if all then e.status = Qs.STATUS_READY end
                end
                Gain(math.floor((act.objEffort or act.c.effort or 0) / 25) * (45 + 5 * state.level))  -- grobe Gegner-XP
            elseif act.kind == "TURNIN" then
                local k = Find(id); if k then table.remove(state.live, k) end
                virtualDone[id] = true
                Gain(act.c.xp)
            elseif act.kind == "ABANDON" then
                local k = Find(id); if k then table.remove(state.live, k) end
            elseif act.kind == "DUNGEON" then
                for _, dc in ipairs(act.group.list) do
                    local _, e = Find(dc.q.id); if e then e.status = Qs.STATUS_READY end
                end
                Gain((act.value or 0) - (act.questXP or 0))
            end
            if act.kind == "HEARTH" then
                state.here = act.to
                state.hearthUsed = true
            elseif act.kind == "FLY" then
                state.here = act.to.point
            elseif act.kind == "SHIP" then
                state.here = act.leg.to
            elseif act.target then
                state.here = act.target
            end
            return true
    end
    for _ = 1, steps do
        local okStep, more = pcall(Step)
        if not okStep then ok, err = false, more; break end
        if not more then break end
        if yieldEach then
            -- Zwischen den Schritten anderen Code laufen lassen: die "gedachten"
            -- Erledigungen duerfen die echte Planung nicht beeinflussen.
            local vd, vi = virtualDone, virtualItems
            virtualDone, virtualItems = nil, nil
            coroutine.yield()
            virtualDone, virtualItems = vd, vi
        end
    end
    virtualDone = nil
    virtualItems = nil
    if not ok then return nil, err end
    return out
end

function P.Preview(modeKey, steps)
    return PreviewRun(modeKey, steps, false)
end

-- Vorschau in kleinen Portionen (ein Schritt je Bild), damit das Spiel nicht
-- ruckelt. onDone(list) wird am Ende aufgerufen. Laeuft schon eine Berechnung,
-- wird nur der Rueckruf ersetzt.
local asyncJob
function P.PreviewAsync(modeKey, steps, onDone)
    if not (C_Timer and C_Timer.After) then onDone(PreviewRun(modeKey, steps, false)); return end
    if asyncJob then asyncJob.onDone = onDone; return end
    local job = { onDone = onDone }
    job.co = coroutine.create(function() return PreviewRun(modeKey, steps, true) end)
    asyncJob = job
    local function Resume()
        local t0 = debugprofilestop and debugprofilestop()
        local ok, res = coroutine.resume(job.co)
        if t0 and Levelmate.Perf then Levelmate.Perf.Add("preview", debugprofilestop() - t0) end
        if not ok or coroutine.status(job.co) == "dead" then
            virtualDone, virtualItems = nil, nil
            asyncJob = nil
            job.onDone(ok and res or nil)
        else
            C_Timer.After(0.25, Resume)
        end
    end
    Resume()
end

---------------------------------------------------------------------------
-- Gebietsplan: bestes Gebiet je Stufenbereich (3 Stufen), grobe Schaetzung
---------------------------------------------------------------------------
local zonePlanCache
function P.ZonePlan(bands)
    if not P.poolReady then return nil end
    UpdatePlayer()
    local here = P.PlayerPoint()
    local key = player.level .. ":" .. #pool .. ":" .. tostring(here and here.map) .. ":"
        .. tostring(lastPlan and lastPlan.zone and lastPlan.zone.map)
    if zonePlanCache and zonePlanCache.key == key then return zonePlanCache.list end
    local list = {}
    for b = 0, (bands or 4) - 1 do
        local lo = player.level + b * 3
        local hi = math.min(60, lo + 2)
        if lo > 60 then break end
        local sums, counts, near = {}, {}, {}
        for _, id in ipairs(pool) do
            local q = DB.Quest(id)
            local ql = q and q.questLevel or 0
            if q and not Done(id) and RaceClassOK(q) and ql >= lo - 1 and ql <= hi + 2
               and (q.requiredLevel or 1) <= hi and not RequirementBlock(q) and not SpecialExcluded(q.specialFlags) then
                local a = Analyze(q)
                local g = a.givers[1]
                if g and not a.dungeonArea and not a.elite then
                    sums[g.map] = (sums[g.map] or 0) + (q.baseXP or 0)
                    counts[g.map] = (counts[g.map] or 0) + 1
                    if not near[g.map] then near[g.map] = TravelSeconds(here, g) end
                end
            end
        end
        local bestMap, bestXP
        for map, v in pairs(sums) do
            -- weite Anreise mindert den Wert; Gebiete mit sehr wenigen Quests zaehlen nicht
            local score = v / (1 + (near[map] or 0) / 1800)
            if (counts[map] or 0) >= 4 and (not bestXP or score > bestXP) then bestMap, bestXP = map, score end
        end
        if b == 0 and lastPlan and lastPlan.zone then bestMap = lastPlan.zone.map end
        if bestMap then
            local last = list[#list]
            if last and last.map == bestMap then
                last.hi = hi
            else
                table.insert(list, { lo = lo, hi = hi, map = bestMap, name = MapName(bestMap) })
            end
        end
    end
    zonePlanCache = { key = key, list = list }
    return list
end

function P.OnLogin()
    UpdatePlayer()
    LoadCompleted()
end
