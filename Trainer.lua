-- Trainer.lua
local L = Levelmate.L
-- Klassenlehrer: Wie viele neue Zauber kannst du gerade lernen, was kostet
-- das, und ist ein Lehrer in der Naehe? Der Lehrer-Schritt erscheint nur,
-- wenn sich der Weg lohnt: Lehrer hoechstens ~250 Yards entfernt oder du
-- bist in einer Hauptstadt, in der dein Klassenlehrer steht.
--
-- Zauberliste: Ist "What's Training?" installiert, kommen die Daten von dort
-- (beruecksichtigt auch Rabatte und ignorierte Zauber). Sonst nutzt Levelmate
-- die mitgelieferte Liste aus TrainerData.lua.
Levelmate = Levelmate or {}
Levelmate.Trainer = Levelmate.Trainer or {}
local T = Levelmate.Trainer

local NEAR_YARDS = 250
-- Hauptstaedte: Karten-IDs (Classic und neuere Clients) und Namen (de/en)
local CAPITALS = { [1453] = true, [1454] = true, [1455] = true, [1456] = true, [1457] = true, [1458] = true,
    [84] = true, [85] = true, [87] = true, [88] = true, [89] = true, [90] = true }
local CAPITAL_NAMES = { ["orgrimmar"] = true, ["donnerfels"] = true, ["thunder bluff"] = true,
    ["unterstadt"] = true, ["undercity"] = true, ["sturmwind"] = true, ["stormwind"] = true,
    ["eisenschmiede"] = true, ["ironforge"] = true, ["darnassus"] = true }
local function MapName(map)
    return (Levelmate.Planner and Levelmate.Planner.MapName and Levelmate.Planner.MapName(map)) or ""
end
local function IsCapital(map)
    return CAPITALS[map] or CAPITAL_NAMES[MapName(map):lower()] or false
end
-- Bist du in der Hauptstadt, in der dieser Lehrer steht?
local function InSameCapital(here, point)
    if not IsCapital(point.map) then return false end
    if here.map == point.map then return true end
    local zone = (GetRealZoneText and Call(GetRealZoneText)) or (GetZoneText and Call(GetZoneText)) or ""
    return zone ~= "" and zone:lower() == MapName(point.map):lower()
end
local CLASS_EN = { DRUID = "druid", HUNTER = "hunter", MAGE = "mage", PALADIN = "paladin", PRIEST = "priest",
    ROGUE = "rogue", SHAMAN = "shaman", WARLOCK = "warlock", WARRIOR = "warrior" }

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end

---------------------------------------------------------------------------
-- Lernbare Zauber
---------------------------------------------------------------------------
local function Known(id)
    if not id then return false end
    if IsSpellKnown and Call(IsSpellKnown, id) then return true end
    if IsPlayerSpell and Call(IsPlayerSpell, id) then return true end
    return false
end

local cache = { t = -100 }
function T.Invalidate() cache.t = -100 end

local function FromWhatsTraining()
    if type(WT_API) ~= "table" or not WT_API.IsReady or not Call(WT_API.IsReady) then return nil end
    local spells = Call(WT_API.GetSpells)
    local avail = WT_API.Status and WT_API.Status.AVAILABLE
    if type(spells) ~= "table" or not avail then return nil end
    local count, cost, cheapest = 0, 0, nil
    for _, s in ipairs(spells) do
        if s.status == avail and not s.quest and not s.isItem then
            count = count + 1
            local c = tonumber(s.cost) or 0
            cost = cost + c
            if not cheapest or c < cheapest then cheapest = c end
        end
    end
    return count, cost, cheapest
end

local function FromBundledData()
    local _, token = UnitClass("player")
    local data = Levelmate.TrainerData and Levelmate.TrainerData[token or ""]
    if not data then return 0, 0 end
    local level = UnitLevel("player") or 1
    local faction = UnitFactionGroup("player")
    local raceID = select(3, UnitRace("player"))
    -- Bei manchen Zaubern bleibt nur der hoechste Rang im Zauberbuch:
    -- ein niedriger Rang gilt als bekannt, wenn ein hoeherer bekannt ist.
    local higher = {}
    for _, grp in ipairs(data.groups or {}) do
        for i, id in ipairs(grp) do
            local list = {}
            for k = i + 1, #grp do list[#list + 1] = grp[k] end
            higher[id] = list
        end
    end
    local function IsKnown(id)
        if Known(id) then return true end
        for _, h in ipairs(higher[id] or {}) do if Known(h) then return true end end
        return false
    end
    local levels = {}
    for lvl in pairs(data.spells) do if lvl <= level then levels[#levels + 1] = lvl end end
    table.sort(levels)
    local willKnow, count, cost, cheapest = {}, 0, 0, nil
    for _, lvl in ipairs(levels) do
        for _, s in ipairs(data.spells[lvl]) do
            local okRace = (not s.race and not s.races) or s.race == raceID
                or (s.races and (s.races[1] == raceID or s.races[2] == raceID))
            local okFaction = not s.faction or s.faction == faction
            if okRace and okFaction and not IsKnown(s.id) and (not s.talent or IsKnown(s.talent)) then
                local reqOk = true
                for _, r in ipairs(s.req or {}) do
                    if not IsKnown(r) and not willKnow[r] then reqOk = false; break end
                end
                if reqOk then
                    willKnow[s.id] = true
                    count = count + 1
                    cost = cost + (s.cost or 0)
                    if not cheapest or (s.cost or 0) < cheapest then cheapest = s.cost or 0 end
                end
            end
        end
    end
    return count, cost, cheapest
end

-- Anzahl lernbarer Zauber und Gesamtpreis in Kupfer (kurz zwischengespeichert)
function T.Learnable()
    local now = GetTime and GetTime() or 0
    if now - cache.t < 5 then return cache.count, cache.cost, cache.source, cache.cheapest end
    local count, cost, cheapest = FromWhatsTraining()
    local source = "wt"
    if not count then count, cost, cheapest = FromBundledData(); source = "levelmate" end
    cache = { t = now, count = count or 0, cost = cost or 0, source = source, cheapest = cheapest or 0 }
    return cache.count, cache.cost, cache.source, cache.cheapest
end

---------------------------------------------------------------------------
-- Klassenlehrer aus QuestieDB (Titel wie "Warlock Trainer"/"Hexenmeisterlehrer")
---------------------------------------------------------------------------
local trainers = {}
local scanning = false

-- Deutsche Wortstaemme (passen fuer "Hexenmeisterlehrer" und "-lehrerin")
-- (Magier-Lehrer heissen im deutschen Client "Magielehrer"/"Magielehrerin")
local CLASS_DE = { DRUID = "druide", HUNTER = "jäger", MAGE = "magie", PALADIN = "paladin", PRIEST = "priester",
    ROGUE = "schurke", SHAMAN = "schamane", WARLOCK = "hexenmeister", WARRIOR = "krieger" }
-- Gespeicherte Suchergebnisse aelterer Suchregeln werden verworfen
local SCAN_VERSION = 2
local function ClassWords(token)
    local words = {}
    local function Add(w) if type(w) == "string" and w ~= "" then words[#words + 1] = w:lower() end end
    Add(CLASS_EN[token or ""])
    Add(CLASS_DE[token or ""])
    if LOCALIZED_CLASS_NAMES_MALE then Add(LOCALIZED_CLASS_NAMES_MALE[token or ""]) end
    if LOCALIZED_CLASS_NAMES_FEMALE then Add(LOCALIZED_CLASS_NAMES_FEMALE[token or ""]) end
    Add((UnitClass("player")))
    return words
end
-- Klassenlehrer: Titel enthaelt den Klassennamen und ist als Lehrer erkennbar,
-- entweder am Wort ("Trainer", "Lehrer") oder - fuer andere Sprachen - am
-- Lehrer-Kennzeichen des NPCs in der Datenbank.
local function IsMyTrainer(sub, words, id)
    sub = (type(sub) == "string" and sub or ""):lower()
    if sub == "" then return false end
    local hasClass = false
    for _, w in ipairs(words) do
        if sub:find(w, 1, true) then hasClass = true; break end
    end
    if not hasClass then return false end
    if sub:find("trainer", 1, true) or sub:find("lehrer", 1, true) then return true end
    if id and NpcDB then
        local e = LibQuestieDB and LibQuestieDB.Enum and LibQuestieDB.Enum.npcFlags
        local flag = (e and e.TRAINER) or 16
        local f = tonumber(Call(NpcDB.npcFlags, id)) or 0
        return math.floor(f / flag) % 2 == 1
    end
    return false
end

-- Positionen eines NPCs. Erst ueber DB.Npc; liefert das nichts, direkt aus
-- den Spawn-Daten (Gebiets-ID -> Karte), ohne die Dungeon-Pruefung.
function T.PointsOf(id)
    local n = Levelmate.DB.Npc(id)
    if n and n.points and #n.points > 0 then return n.points end
    local out = {}
    local spawns = Call(NpcDB.spawns, id)
    if type(spawns) == "table" then
        for areaId, list in pairs(spawns) do
            local map = Levelmate.DB.AreaToUiMap and Levelmate.DB.AreaToUiMap(areaId)
            if map and type(list) == "table" then
                for _, p in ipairs(list) do
                    if type(p) == "table" and tonumber(p[1]) and tonumber(p[2]) and p[1] >= 0 and p[2] >= 0 then
                        out[#out + 1] = { map = map, x = p[1], y = p[2], area = areaId }
                    end
                end
            end
        end
    end
    return out
end

function T.Scan(force, onDone)
    if scanning or not (Levelmate.DB and Levelmate.DB.Available and Levelmate.DB.Available()) or not NpcDB then return end
    Levelmate_DB = Levelmate_DB or {}
    local _, token = UnitClass("player")
    local f = UnitFactionGroup("player")
    local letter = f == "Alliance" and "A" or f == "Horde" and "H" or nil
    if not token or not letter then return end
    local build = (C_AddOns and Call(C_AddOns.GetAddOnMetadata, "QuestieDB", "X-BUILD-COMMIT"))
        or (GetAddOnMetadata and Call(GetAddOnMetadata, "QuestieDB", "X-BUILD-COMMIT")) or "?"
    local function Finish(ids)
        trainers = {}
        local info = { ids = #ids, friendly = 0, withPoints = 0 }
        for _, id in ipairs(ids) do
            local friendly = tostring(Call(NpcDB.friendlyToFaction, id) or "")
            if friendly:find(letter, 1, true) then
                info.friendly = info.friendly + 1
                local points = T.PointsOf(id)
                if #points > 0 then info.withPoints = info.withPoints + 1 end
                local name = Call(NpcDB.name, id) or (L("NPC ") .. id)
                for _, p in ipairs(points) do
                    trainers[#trainers + 1] = { id = id, name = name, point = p }
                end
            end
        end
        T.finishInfo = info
    end
    Levelmate_DB.trainerCache = Levelmate_DB.trainerCache or {}
    local c = Levelmate_DB.trainerCache[token]
    if not force and c and c.build == build and c.v == SCAN_VERSION and type(c.ids) == "table" and #c.ids > 0 then
        Finish(c.ids)
        if #trainers > 0 then
            if onDone then onDone() end
            return
        end
        -- Gespeichertes Ergebnis taugt nicht: neu suchen
    end
    local all = Call(NpcDB.GetAllIds) or {}
    local found, i = {}, 1
    local words = ClassWords(token)
    scanning = true
    T.scanInfo = { total = #all, done = 0 }
    local function Step()
        local ok, err = pcall(function()
            local stop = math.min(#all, i + 600)
            for k = i, stop do
                local id = all[k]
                if IsMyTrainer(Call(NpcDB.subName, id), words, id) then found[#found + 1] = id end
            end
            i = stop + 1
            T.scanInfo.done = math.min(#all, i - 1)
            if i <= #all then
                if C_Timer and C_Timer.After then C_Timer.After(0, Step) else Step() end
            else
                scanning = false
                Levelmate_DB.trainerCache[token] = { build = build, v = SCAN_VERSION, ids = found }
                T.scanInfo.matched = #found
                Finish(found)
                if onDone then onDone() end
            end
        end)
        if not ok then scanning = false; T.lastError = tostring(err) end
    end
    Step()
end

---------------------------------------------------------------------------
-- Vorschlag fuer den aktuellen Schritt
---------------------------------------------------------------------------
local function Money(copper)
    copper = math.floor(copper or 0)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|cffffd700g|r" end
    if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. L("|cffeda55fk|r") end
    return table.concat(parts, " ")
end
T.Money = Money

function T.Suggest()
    if Levelmate_DB and Levelmate_DB.trainerOff then return nil end
    local level = UnitLevel("player") or 1
    local cdb = Levelmate_CharDB
    if cdb and cdb.trainSkipLevel == level then return nil end
    if IsInInstance and Call(IsInInstance) then return nil end
    if #trainers == 0 then return nil end
    local here = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    if not here then return nil end
    local count, cost, source, cheapest = T.Learnable()
    if not count or count <= 0 then return nil end
    -- Nur wenn du dir mindestens einen Zauber leisten kannst (z. B. nicht gleich zu
    -- Beginn im Startgebiet ohne Geld - erst die ersten Quests machen).
    local money = GetMoney and Call(GetMoney)
    if money and cheapest and money < cheapest then return nil end
    local best, bestD
    for _, t in ipairs(trainers) do
        local d = Levelmate.Planner.Yards(here, t.point)
        if d and (not bestD or d < bestD) then best, bestD = t, d end
    end
    if not best then return nil end
    local inCity = bestD <= 1500 and InSameCapital(here, best.point)
    if bestD > NEAR_YARDS and not inCity then return nil end
    return { kind = "TRAIN", target = best.point, targetName = best.name, count = count, cost = cost,
        yards = bestD, source = source }
end

function T.Detail(t)
    local money = GetMoney and Call(GetMoney) or nil
    local lack = (money and t.cost > money) and L("  |cffff6060(dein Gold reicht nicht für alle)|r") or ""
    local word = t.count == 1 and L("neuer Zauber") or L("neue Zauber")
    return string.format(L("%d %s · %s%s\n%s (%.1f, %.1f) · ca. %d m entfernt"),
        t.count, word, Money(t.cost), lack, t.targetName or "?", t.target.x, t.target.y,
        math.floor((t.yards or 0) * 0.9144 + 0.5))
end

-- Naechster Klassenlehrer, egal wie weit (fuer den Tooltip oben im Fenster)
function T.Nearest()
    local here = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    if not here then return nil end
    local best, bestD
    for _, t in ipairs(trainers) do
        local d = Levelmate.Planner.Yards(here, t.point)
        if d and (not bestD or d < bestD) then best, bestD = t, d end
    end
    return best, bestD
end

-- /lm lehrer: zeigt, was Levelmate ueber Lehrer und Zauber weiss, und
-- startet eine frische Suche, deren Ergebnis danach im Chat erscheint.
function T.Debug(out)
    local count, cost, source = T.Learnable()
    local here = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    out(string.format(L("Zauber: %d lernbar (%s, %s) · Du: Karte %s (%s)"), count or 0, Money(cost or 0),
        source == "wt" and L("What's Training") or L("Levelmate-Liste"), tostring(here and here.map), here and MapName(here.map) or "?"))
    local _, token = UnitClass("player")
    out(L("Suchwörter für deine Klasse: ") .. table.concat(ClassWords(token), ", "))
    local fi = T.finishInfo
    out(string.format(L("Lehrer bekannt: %d · letzte Auswertung: %s IDs / %s Fraktion / %s mit Position%s"),
        #trainers, fi and tostring(fi.ids) or "-", fi and tostring(fi.friendly) or "-", fi and tostring(fi.withPoints) or "-",
        T.lastError and (L(" · Fehler: ") .. T.lastError) or ""))
    if scanning then out(L("Suche läuft gerade …")); return end
    T.lastError = nil
    out(L("Starte frische Suche …"))
    local ok, err = pcall(T.Scan, true, function()
        local si, t = T.scanInfo or {}, T.Nearest and select(1, T.Nearest())
        local _, d = T.Nearest()
        out(string.format(L("Suche fertig: %s NPCs durchsucht, %s Treffer, %d Lehrer mit Position."),
            tostring(si.done or "?"), tostring(si.matched or "?"), #trainers))
        if t then out(string.format(L("Nächster: %s · %d Yards · Lehrer-Schritt: %s"), t.name or "?", math.floor(d or 0),
            T.Suggest() and L("wird angezeigt") or L("nicht angezeigt"))) end
        if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
    end)
    if not ok then out(L("Fehler bei der Suche: ") .. tostring(err)) end
    if T.lastError then out(L("Fehler bei der Suche: ") .. T.lastError) end
end
