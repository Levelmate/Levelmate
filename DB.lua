-- DB.lua
local L = Levelmate.L
-- Zugriff auf die Forever-Questdatenbank von QuestieDB (separates Addon).
-- QuestieDB stellt dafuer eine oeffentliche Schnittstelle bereit
-- (QuestDB, NpcDB, ObjectDB, ItemDB und LibQuestieDB.Support).
-- Alle Aufrufe sind abgesichert; fehlt QuestieDB, meldet DB.Available() false.
Levelmate = Levelmate or {}
Levelmate.DB = Levelmate.DB or {}
local DB = Levelmate.DB

local xpTable

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    return nil
end

function DB.Available()
    return type(QuestDB) == "table" and type(NpcDB) == "table" and type(LibQuestieDB) == "table"
end

local function Support(name)
    local s = LibQuestieDB and LibQuestieDB.Support
    return s and Call(s.Get, name)
end

-- Tabellen, die QuestieDB als Lua-Text speichert, einmalig laden.
local function LoadStringTable(text)
    if type(text) == "table" then return text end
    if type(text) ~= "string" then return nil end
    local loader = loadstring or load
    local fn = loader(text)
    if not fn then return nil end
    local ok, t = pcall(fn)
    return ok and type(t) == "table" and t or nil
end

---------------------------------------------------------------------------
-- Zonen
---------------------------------------------------------------------------
local areaToMap, dungeons
local function ZoneTables()
    if areaToMap then return end
    areaToMap = {}
    local zdb = Support("ZoneDB")
    local priv = zdb and zdb.private or {}
    local base = LoadStringTable(priv.areaIdToUiMapId) or {}
    local override = LoadStringTable(priv.areaIdToUiMapIdOverride) or {}
    for k, v in pairs(base) do areaToMap[k] = v end
    for k, v in pairs(override) do areaToMap[k] = v end
    dungeons = {}
    if type(priv.dungeons) == "table" then for k, v in pairs(priv.dungeons) do dungeons[k] = v end end
    -- Neue Forever-Dungeons, die QuestieDB (noch) nicht als Dungeon fuehrt
    if DB.ForeverDungeons then
        for id, f in pairs(DB.ForeverDungeons) do
            if not dungeons[id] then dungeons[id] = { f.en, nil, nil, { { f.zone, f.x, f.y } } } end
        end
    end
    -- Alternative Area-IDs eines Dungeons auf den Haupteintrag zeigen lassen.
    local alias = {}
    for id, d in pairs(dungeons) do
        if type(d[2]) == "table" then for _, alt in ipairs(d[2]) do alias[alt] = id end end
    end
    for alt, id in pairs(alias) do if not dungeons[alt] then dungeons[alt] = dungeons[id] end end
end

-- Instanz-ID des Spiels (GetInstanceInfo, 8. Wert) -> Area-ID des Dungeons
function DB.InstanceArea(instanceID)
    if not instanceID then return nil end
    local zdb = Support("ZoneDB")
    local t = zdb and zdb.instanceIdToAreaId
    return type(t) == "table" and t[instanceID] or nil
end

-- Gehoeren zwei Area-IDs zum selben Dungeon (inkl. alternativer IDs)?
function DB.SameDungeon(a, b)
    if not a or not b then return false end
    if a == b then return true end
    ZoneTables()
    return dungeons[a] ~= nil and dungeons[a] == dungeons[b]
end

-- Alle bekannten Dungeon-Area-IDs (Haupteintraege)
function DB.AllDungeonAreas()
    ZoneTables()
    local out = {}
    for id in pairs(dungeons) do out[#out + 1] = id end
    table.sort(out)
    return out
end

function DB.AreaToUiMap(areaId)
    ZoneTables()
    local m = areaToMap[areaId]
    if m and m > 0 then return m end
    return nil
end

-- Liefert Name und Eingangskoordinaten {uiMap, x, y}, falls areaId ein Dungeon ist.
-- Dungeon-Namen in der Sprache des Spiels (QuestieDB liefert nur Englisch).
-- Die englischen Namen bleiben intern fuer die Stufentabelle erreichbar.
local dungeonLoc, dungeonEn = {}, {}
function DB.DungeonEnglish(name) return name and dungeonEn[name] or name end
function DB.Dungeon(areaId)
    ZoneTables()
    local d = dungeons[areaId]
    if not d then return nil end
    local name = dungeonLoc[areaId]
    local fd = DB.ForeverDungeons and DB.ForeverDungeons[areaId]
    if not name and fd then
        local loc = GetLocale and GetLocale() or "enUS"
        name = (fd.names and fd.names[loc]) or fd.en
        dungeonLoc[areaId] = name
        dungeonEn[name] = fd.en
    end
    if not name then
        name = d[1]
        if C_Map and C_Map.GetAreaInfo then
            local ok, n = pcall(C_Map.GetAreaInfo, areaId)
            if ok and type(n) == "string" and n ~= "" then name = n end
        end
        dungeonLoc[areaId] = name
        if d[1] then dungeonEn[name] = d[1] end
    end
    local entrance
    local loc = type(d[4]) == "table" and d[4][1]
    if loc then
        local map = DB.AreaToUiMap(loc[1])
        if map then entrance = { map = map, x = loc[2], y = loc[3] } end
    end
    return name, entrance
end

-- Neue Forever-Dungeons kennt QuestieDB nicht als Dungeon. Eigene Eintraege mit
-- erfundener (negativer) Area-ID, Eingang (Area-ID der Zone, x, y in Prozent)
-- und den Quest-IDs, die dazugehoeren.
DB.ForeverDungeons = {
    [-1001] = { en = "The Drowned City", names = { deDE = "Die Versunkene Stadt" }, atlas = "TheDrownedCity",
                zone = 33, x = 21.4, y = 27.9,
                quests = { 95775, 95776, 95787, 95788, 95789, 95791, 96774 } },
    [-1002] = { en = "Krol'dok Stronghold", atlas = "KroldokStronghold",
                zone = 16591, x = 37.5, y = 37.2,
                quests = { 94968, 94982, 94972, 94984, 94975, 94983, 96771 } },
    [-1003] = { en = "Alcaz Prison", atlas = "AlcazPrison",
                zone = 15, x = 75.3, y = 14.1,
                quests = { 95309, 95454, 96369, 95483, 96334, 96332, 96772 } },
    [-1004] = { en = "Blackmaw Hold", atlas = "BlackmawHold",
                zone = 16, x = 38.7, y = 33.4,
                quests = { 92343, 92344, 97173, 97198, 92066, 92069, 92070, 97327, 92065 } },
    [-1005] = { en = "The Shaper's Terrace", atlas = "ShapersTerrace",
                zone = 490, x = 48.1, y = 6.1,
                quests = { 95928, 97049, 95926, 95924, 95925, 95790 } },
}
local foreverQuest
function DB.ForeverQuestArea(questID)
    if not foreverQuest then
        foreverQuest = {}
        for id, f in pairs(DB.ForeverDungeons) do
            for _, q in ipairs(f.quests or {}) do foreverQuest[q] = id end
        end
    end
    return questID and foreverQuest[questID]
end
-- Forever-Dungeon ueber seinen Namen (z. B. Kopf im Questlog)
function DB.ForeverDungeonByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local n = name:lower()
    for id, f in pairs(DB.ForeverDungeons) do
        if f.en:lower() == n then return id end
        for _, v in pairs(f.names or {}) do if v:lower() == n then return id end end
    end
end
function DB.ForeverDungeonEntrance(name)
    local id = DB.ForeverDungeonByName(name)
    if not id then return nil end
    local _, entrance = DB.Dungeon(id)
    return entrance
end

---------------------------------------------------------------------------
-- Spawns: {[areaId] = {{x, y}, ...}} -> Liste von Punkten
---------------------------------------------------------------------------
local function ConvertSpawns(spawns)
    local points, dungeonArea = {}, nil
    if type(spawns) ~= "table" then return points, nil end
    for areaId, list in pairs(spawns) do
        if DB.Dungeon(areaId) then
            dungeonArea = dungeonArea or areaId
        else
            local map = DB.AreaToUiMap(areaId)
            if map and type(list) == "table" then
                for _, p in ipairs(list) do
                    if type(p) == "table" and p[1] and p[1] >= 0 and p[2] and p[2] >= 0 then
                        table.insert(points, { map = map, x = p[1], y = p[2], area = areaId })
                    end
                end
            end
        end
    end
    return points, dungeonArea
end

DB.ConvertSpawns = function(s) return ConvertSpawns(s) end

local npcCache, objCache = {}, {}
function DB.Npc(id)
    if not id then return nil end
    local c = npcCache[id]
    if c ~= nil then return c or nil end
    if not NpcDB or not Call(NpcDB.Exists, id) then npcCache[id] = false; return nil end
    local points, dungeonArea = ConvertSpawns(Call(NpcDB.spawns, id))
    c = {
        id = id,
        name = Call(NpcDB.name, id) or (L("NPC ") .. id),
        rank = Call(NpcDB.rank, id) or 0,
        minLevel = Call(NpcDB.minLevel, id) or 0,
        maxLevel = Call(NpcDB.maxLevel, id) or 0,
        friendly = Call(NpcDB.friendlyToFaction, id),   -- "A", "H" oder "AH"
        -- Dienste (Haendler, Gespraech, Quests ...) oder Titel: echter freundlicher NPC.
        -- Ohne beides ist "AH" meist ein neutrales Tier (gelb), das man angreifen kann.
        service = ((tonumber(Call(NpcDB.npcFlags, id)) or 0) ~= 0)
            or ((Call(NpcDB.subName, id) or "") ~= ""),
        points = points,
        dungeonArea = dungeonArea,
    }
    npcCache[id] = c
    return c
end

function DB.Object(id)
    if not id then return nil end
    local c = objCache[id]
    if c ~= nil then return c or nil end
    if not ObjectDB or not Call(ObjectDB.Exists, id) then objCache[id] = false; return nil end
    local points, dungeonArea = ConvertSpawns(Call(ObjectDB.spawns, id))
    c = { id = id, name = Call(ObjectDB.name, id) or (L("Objekt ") .. id), points = points, dungeonArea = dungeonArea }
    objCache[id] = c
    return c
end

-- Hat der Spieler den Gegenstand (Rucksack)?
function DB.HasItem(itemId)
    local n = (C_Item and Call(C_Item.GetItemCount, itemId)) or (GetItemCount and Call(GetItemCount, itemId))
    return (tonumber(n) or 0) > 0
end

function DB.ItemName(id)
    return (ItemDB and Call(ItemDB.name, id)) or (L("Gegenstand ") .. tostring(id))
end

-- Quellen eines Questgegenstands: NPCs (mit Dropchance in %) und Objekte.
local dropTable
function DB.ItemSources(itemId)
    if not dropTable then
        local m = Support("QuestieClassicItemDrops")
        dropTable = (m and LoadStringTable(m.wowheadData)) or {}
    end
    local npcs = ItemDB and Call(ItemDB.npcDrops, itemId) or {}
    local objects = ItemDB and Call(ItemDB.objectDrops, itemId) or {}
    local chances = dropTable[itemId] or {}
    local result = {}
    for _, npcId in ipairs(npcs or {}) do
        table.insert(result, { kind = "npc", id = npcId, chance = tonumber(chances[npcId]) })
    end
    for _, objId in ipairs(objects or {}) do
        table.insert(result, { kind = "object", id = objId })
    end
    return result
end

-- Quests, die den Gegenstand als Belohnung geben (z. B. Kapitel-Seiten)
function DB.ItemRewardQuests(itemId)
    local v = ItemDB and ItemDB.questRewards and Call(ItemDB.questRewards, itemId)
    if type(v) ~= "table" then return {} end
    local out = {}
    for _, id in ipairs(v) do if type(id) == "number" and id > 0 then out[#out + 1] = id end end
    return out
end

-- Haendler, die den Gegenstand verkaufen (NPC-IDs)
function DB.ItemVendors(itemId)
    local v = ItemDB and ItemDB.vendors and Call(ItemDB.vendors, itemId)
    if type(v) ~= "table" then return {} end
    local out = {}
    for _, id in ipairs(v) do if type(id) == "number" and id > 0 then out[#out + 1] = id end end
    return out
end

---------------------------------------------------------------------------
-- Quests
---------------------------------------------------------------------------
local QUEST_FIELDS = { "name", "startedBy", "finishedBy", "requiredLevel", "questLevel",
    "requiredRaces", "requiredClasses", "objectivesText", "triggerEnd", "objectives", "preQuestGroup",
    "preQuestSingle", "childQuests", "exclusiveTo", "zoneOrSort", "requiredSkill",
    "requiredMinRep", "requiredMaxRep", "requiredSourceItems", "nextQuestInChain",
    "specialFlags", "parentQuest", "breadcrumbForQuestId", "requiredSpell",
    "requiredSpecialization", "requiredMaxLevel", "availableUntilCompleted",
    "availableStartingWith", "requiredRanks", "disabledByQuest" }

local questCache = {}
-- Typische XP einer Quest der Stufe L (Median aller Quests dieser Stufe in QuestXP)
local xpByLevel
function DB.EstimateXP(level)
    level = tonumber(level)
    if not level or level < 1 then return nil end
    if not xpByLevel then
        if not xpTable then
            local m = Support("QuestXP")
            xpTable = (m and m.db) or {}
        end
        local lists = {}
        for _, e in pairs(xpTable) do
            local l, x = type(e) == "table" and tonumber(e[1]), type(e) == "table" and tonumber(e[2])
            if l and x and x > 0 then
                lists[l] = lists[l] or {}
                table.insert(lists[l], x)
            end
        end
        xpByLevel = {}
        for l, list in pairs(lists) do
            if #list >= 5 then
                table.sort(list)
                xpByLevel[l] = list[math.floor((#list + 1) / 2)]
            end
        end
    end
    return xpByLevel[level]
end

-- Beim Abgeben gemessene XP merken (nur wenn die Quest nicht grau/abgewertet war)
function DB.LearnXP(id, xp, playerLevel)
    local q = DB.Quest(id)
    if not q or not xp or xp <= 0 or q.xpSource == nil then return end
    if playerLevel and q.questLevel and playerLevel - q.questLevel > 5 then return end
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.learnedXP = Levelmate_DB.learnedXP or {}
    Levelmate_DB.learnedXP[id] = xp
    q.baseXP, q.xpSource = xp, "gemessen"
end

function DB.Quest(id)
    local c = questCache[id]
    if c ~= nil then return c or nil end
    if not QuestDB or not Call(QuestDB.Exists, id) then questCache[id] = false; return nil end
    local q = { id = id }
    for _, field in ipairs(QUEST_FIELDS) do
        local fn = QuestDB[field]
        if fn then q[field] = Call(fn, id) end
    end
    if not xpTable then
        local m = Support("QuestXP")
        xpTable = (m and m.db) or {}
    end
    local xp = xpTable[id]
    q.baseXP = type(xp) == "table" and tonumber(xp[2]) or nil
    -- Ohne jede Stufenangabe (z. B. Belohnungs-/Promo-Quests wie "A Special Gift"):
    -- markieren, damit der Planer sie nicht quer durch die Welt ansteuert.
    if not (q.questLevel and q.questLevel > 0) and not (type(xp) == "table" and xp[1])
       and not (q.requiredLevel and q.requiredLevel > 0) then q.noLevel = true end
    -- Ohne Namen ist der Datensatz unvollstaendig (z. B. Quest 7790 bei "Fallen
    -- Skyborne"): nicht vorschlagen, sonst steht "?" als Schritt da.
    if not q.name or q.name == "" then q.noLevel = true end
    q.questLevel = q.questLevel or (type(xp) == "table" and xp[1]) or 1
    if not q.baseXP then
        -- Keine XP in QuestieDB (z. B. neue Forever-Quests): zuerst gemessene XP
        -- (beim Abgeben gelernt), sonst Schaetzung aus Quests gleicher Stufe.
        local learned = Levelmate_DB and Levelmate_DB.learnedXP and Levelmate_DB.learnedXP[id]
        if learned then q.baseXP, q.xpSource = learned, "gemessen"
        else
            local est = DB.EstimateXP(q.questLevel)
            if est then q.baseXP, q.xpSource = est, "geschätzt" end
        end
    end
    q.requiredLevel = q.requiredLevel or 1
    questCache[id] = q
    return q
end

-- Nur die Felder fuer die Vorauswahl (schnell, ohne Tabellenfelder).
function DB.QuestBasics(id)
    if not QuestDB then return nil end
    local ql = Call(QuestDB.questLevel, id)
    if not ql then
        if not xpTable then local m = Support("QuestXP"); xpTable = (m and m.db) or {} end
        local xp = xpTable[id]
        ql = type(xp) == "table" and xp[1] or nil
    end
    return ql, Call(QuestDB.requiredLevel, id),
           Call(QuestDB.requiredRaces, id), Call(QuestDB.requiredClasses, id)
end

-- Gebiet (areaId) einer Quest laut QuestieDB; negative Werte = Kategorie
function DB.QuestZone(id)
    if not QuestDB then return nil end
    local z = Call(QuestDB.zoneOrSort, id)
    if type(z) == "number" and z > 0 then return z end
    return nil
end

function DB.AllQuestIDs()
    return (QuestDB and Call(QuestDB.GetAllIds)) or {}
end
