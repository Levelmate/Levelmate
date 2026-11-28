-- Levelmate: optionale Anbindung an AtlasLoot (Beutetabellen der Dungeonbosse)
-- Levelmate enthaelt selbst keine AtlasLoot-Daten. Ist AtlasLoot installiert,
-- liest Levelmate die Tabellen zur Laufzeit aus dem geladenen AtlasLoot-Modul.
-- Das Modul wird erst geladen, wenn der Beute-Reiter geoeffnet wird.

Levelmate = Levelmate or {}
local A = {}
Levelmate.Atlas = A

local MODULES = {
    "AtlasLootContinued_DungeonsAndRaids",
    "AtlasLootClassic_DungeonsAndRaids",
    "AtlasLoot_DungeonsAndRaids",
}

local function IsLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded(name) end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end
local function Exists(name)
    local ok, n, _, _, loadable, reason
    if C_AddOns and C_AddOns.GetAddOnInfo then
        ok, n, _, _, loadable, reason = pcall(C_AddOns.GetAddOnInfo, name)
    elseif GetAddOnInfo then
        ok, n, _, _, loadable, reason = pcall(GetAddOnInfo, name)
    end
    if not ok or not n then return false end
    if reason == "MISSING" then return false end
    return true, loadable, reason
end
local function Load(name)
    if C_AddOns and C_AddOns.LoadAddOn then return pcall(C_AddOns.LoadAddOn, name) end
    if LoadAddOn then return pcall(LoadAddOn, name) end
end

local function Core()
    local AL = rawget(_G, "AtlasLoot")
    if type(AL) == "table" and type(AL.ItemDB) == "table" and type(AL.ItemDB.Storage) == "table" then return AL end
end

-- Zustand: nil = nicht geprueft, "ok", "missing", "combat", "off"
local state, module

--- Ist AtlasLoot (Kern) da? Dann lohnt sich der Hinweis bzw. der Ladeversuch.
function A.Installed()
    return Core() ~= nil
end

--- Modul mit den Dungeon-Tabellen laden (falls noetig). Gibt den Zustand zurueck.
function A.Ensure()
    if state == "ok" then return state end
    if not Core() then state = "missing"; return state end
    for _, m in ipairs(MODULES) do
        if IsLoaded(m) and Core().ItemDB.Storage[m] then module = m; state = "ok"; return state end
    end
    if InCombatLockdown and InCombatLockdown() then return "combat" end
    local found = false
    for _, m in ipairs(MODULES) do
        local ex = Exists(m)
        if ex then
            found = true
            if not IsLoaded(m) then Load(m) end
            if IsLoaded(m) and Core().ItemDB.Storage[m] then module = m; state = "ok"; return state end
        end
    end
    state = found and "off" or "missing"
    return state
end

---------------------------------------------------------------------------
-- Index aufbauen: Inhalte je Gebiet (MapID) und Name, Bosse je NPC
---------------------------------------------------------------------------
local byArea, byName, byNpc, contents

local function Norm(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):lower()
    s = s:gsub("^the ", ""):gsub("^die ", ""):gsub("^der ", ""):gsub("^das ", "")
    s = s:gsub("[%s%p]", "")
    return s
end

local function NpcList(v)
    if type(v) == "number" then return { v } end
    if type(v) == "table" then
        local t = {}
        for _, x in ipairs(v) do if type(x) == "number" then t[#t + 1] = x end end
        return t
    end
    return {}
end

local function ItemsOf(AL, key, content, i)
    local storage = AL.ItemDB.Storage[module]
    local diff = content.LoadDifficulty
    if not diff and storage.GetDifficultyByName then
        local ok, d = pcall(storage.GetDifficultyByName, storage, "NORMAL")
        if ok then diff = d end
    end
    diff = diff or 1
    local ok, tab = pcall(AL.ItemDB.GetItemTable, AL.ItemDB, module, key, i, diff)
    if not ok or type(tab) ~= "table" then
        local b = content.items[i]
        tab = type(b) == "table" and type(b[diff]) == "table" and b[diff] or nil
    end
    if not tab then return nil end
    local out, seen = {}, {}
    for _, e in ipairs(tab) do
        if type(e) == "table" then
            local id = e[2]
            if type(id) == "string" then id = tonumber(id:match("^i?(%d+)$")) end
            if type(id) == "number" and id > 0 and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    return out
end

local function BuildIndex()
    if contents then return end
    local AL = Core()
    if not (AL and module) then return end
    local storage = AL.ItemDB.Storage[module]
    local forever = AL.FOREVER_VERSION_NUM
    local cur = rawget(AL, "CurrentGameVersion") or (AL.GetGameVersion and select(2, pcall(AL.GetGameVersion, AL)))
    contents, byArea, byName, byNpc = {}, {}, {}, {}
    local list = {}
    for key, c in pairs(storage) do
        if type(key) == "string" and key:sub(1, 2) ~= "__" and type(c) == "table" and type(c.items) == "table" then
            local own = (forever and c.gameVersion == forever) or (cur and c.gameVersion == cur)
            list[#list + 1] = { key = key, c = c, own = own and true or false }
        end
    end
    -- eigene Spielversion zuerst; danach nach Stufe und Schluessel
    table.sort(list, function(x, y)
        if x.own ~= y.own then return x.own end
        local lx = x.c.LevelRange and x.c.LevelRange[2] or 999
        local ly = y.c.LevelRange and y.c.LevelRange[2] or 999
        if lx ~= ly then return lx < ly end
        return x.key < y.key
    end)
    local areaOwn = {}
    for _, it in ipairs(list) do
        local c = it.c
        local okN, name = pcall(c.GetName, c, true)
        if not okN then name = c.name end
        local entry = { key = it.key, c = c, name = name, own = it.own }
        contents[#contents + 1] = entry
        local area = c.MapID or c.AreaID
        if area then
            -- Gebiet: nur Inhalte der eigenen Spielversion, sonst Klassik als Ersatz
            if it.own then
                areaOwn[area] = true
                byArea[area] = byArea[area] or {}
                table.insert(byArea[area], entry)
            elseif not areaOwn[area] then
                byArea[area] = byArea[area] or {}
                table.insert(byArea[area], entry)
            end
        end
        local n = Norm(name)
        if n and not byName[n] then byName[n] = entry end
        for i, b in ipairs(c.items) do
            if type(b) == "table" then
                for _, npc in ipairs(NpcList(b.npcID)) do
                    if not byNpc[npc] then byNpc[npc] = { entry = entry, index = i } end
                end
            end
        end
    end
end

--- Bosse eines Inhalts mit ihrer Beute
local cache = {}
local function Bosses(entry)
    if cache[entry.key] then return cache[entry.key] end
    local AL = Core()
    local c = entry.c
    local out = {}
    local DR = AL.Data and AL.Data.Droprate
    for i, b in ipairs(c.items) do
        if type(b) == "table" and not b.ExtraList then
            local items = ItemsOf(AL, entry.key, c, i) or {}
            if #items > 0 then
                local okN, bname = pcall(c.GetNameForItemTable, c, i, true)
                if not okN or not bname then bname = b.name or "?" end
                local npcs = NpcList(b.npcID)
                local list = {}
                for _, id in ipairs(items) do
                    local rate
                    if DR and DR.GetData then
                        for _, npc in ipairs(npcs) do
                            local ok, r = pcall(DR.GetData, DR, npc, id)
                            if ok and r then rate = r; break end
                        end
                    end
                    list[#list + 1] = { id = id, rate = rate }
                end
                out[#out + 1] = { name = bname, npcs = npcs, items = list }
            end
        end
    end
    cache[entry.key] = out
    return out
end

--- Beute fuer einen Dungeon: Liste von Abschnitten { title, bosses = { {name, npcs, items} } }
-- area: Gebiets-ID (wie Questie/AtlasLoot MapID), name: angezeigter Name, npcs: bekannte Boss-IDs
function A.ForDungeon(area, name, npcs, atlasKey)
    if A.Ensure() ~= "ok" then return nil end
    BuildIndex()
    if not contents then return nil end
    local entries = area and byArea[area]
    if not entries and atlasKey then
        for _, e in ipairs(contents) do if e.key == atlasKey then entries = { e }; break end end
    end
    if not entries then
        local e = byName[Norm(name) or ""]
        if e then entries = { e } end
    end
    if not entries and npcs then
        -- ueber bekannte Boss-IDs suchen
        local seen = {}
        for _, npc in ipairs(npcs) do
            local hit = byNpc[npc]
            if hit and not seen[hit.entry.key] then
                seen[hit.entry.key] = true
                entries = entries or {}
                entries[#entries + 1] = hit.entry
            end
        end
    end
    if not entries then return nil end
    local out = {}
    for _, e in ipairs(entries) do
        local b = Bosses(e)
        if #b > 0 then out[#out + 1] = { title = e.name, bosses = b } end
    end
    return #out > 0 and out or nil
end

--- Ist diese NPC-ID ein Boss mit AtlasLoot-Tabelle? (nur wenn schon geladen)
function A.IsBoss(npc)
    if state ~= "ok" then return false end
    BuildIndex()
    return byNpc and byNpc[npc] ~= nil or false
end

--- Kampf vorbei: Ladeversuch kann wiederholt werden
local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function()
    if A.waiting then
        A.waiting = nil
        if Levelmate.DungeonFrame and Levelmate.DungeonFrame:IsShown() and Levelmate.DungeonLayout then
            pcall(Levelmate.DungeonLayout)
        end
    end
end)
