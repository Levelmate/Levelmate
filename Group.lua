-- Levelmate – Gruppenmodus (Teil 1): Questlogs in der Gruppe abgleichen.
-- Die Levelmate-Addons in einer Gruppe schicken sich unsichtbar eine kurze Liste:
-- welche Quests im Log sind und wie weit (nur Quest-IDs und Fortschritt, sonst nichts).
-- Daraus: "Gemeinsam mit X" auf der Karte, ein Symbol im Questlog-Bereich und
-- gemeinsame Quests werden etwas vorgezogen.
Levelmate = Levelmate or {}
local G = {}
Levelmate.Group = G
G.members = {}          -- [Name] = { quests = { [id] = { s = "A"/"R", p = 0..9 } }, level, map, at }

local L = Levelmate.L or function(s) return s end
local function Now() return GetTime and GetTime() or 0 end
local function Short(name) return name and name:match("^([^%-]+)") or name end
local function InGroup() return (IsInGroup and IsInGroup()) and true or false end

-- Ist der Name (noch) in meiner Gruppe?
local function InMyGroup(name)
    if not InGroup() then return false end
    if UnitInParty and UnitInParty(name) then return true end
    if UnitInRaid and UnitInRaid(name) then return true end
    return false
end

---------------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------------
local dirty, lastSent, stamp = true, -100, 0

local function Encode()
    local Q = Levelmate.Quests
    local items = {}
    for _, lq in ipairs((Q and Q.GetList and Q.GetList()) or {}) do
        local s, p = "A", 0
        if lq.status == Q.STATUS_READY then s, p = "R", 9
        elseif lq.objectives and #lq.objectives > 0 then
            local done = 0
            for _, o in ipairs(lq.objectives) do if o.done then done = done + 1 end end
            p = math.floor(9 * done / #lq.objectives)
        end
        items[#items + 1] = lq.questID .. "." .. s .. p
    end
    return items
end

function G.Broadcast()
    local T = Levelmate.Travel
    if not (InGroup() and T and T.QueueFront) then return end
    stamp = (stamp % 999) + 1
    local items = Encode()
    local chunks, cur, len = {}, {}, 0
    for _, it in ipairs(items) do
        if len + #it + 1 > 200 then chunks[#chunks + 1] = cur; cur, len = {}, 0 end
        cur[#cur + 1] = it; len = len + #it + 1
    end
    chunks[#chunks + 1] = cur
    -- Stufe und Gebiet (fuer spaeter: "Warte auf X")
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
    local msgs = { string.format("P|%d|%d", UnitLevel and UnitLevel("player") or 0, map or 0) }
    for i, c in ipairs(chunks) do
        msgs[#msgs + 1] = string.format("Q|%d/%d|%d|%s", i, #chunks, stamp, table.concat(c, ";"))
    end
    -- in umgekehrter Reihenfolge vorne einreihen, damit sie in Reihenfolge rausgehen
    for i = #msgs, 1, -1 do T.QueueFront(msgs[i]) end
    dirty, lastSent = false, Now()
end

function G.MarkDirty() dirty = true end

---------------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------------
local partial = {}      -- [Name] = { stamp, n, parts = {} }

local function Member(name)
    local m = G.members[name]
    if not m then m = { quests = {} }; G.members[name] = m end
    return m
end

local function Changed()
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(false, 1.0) end
end

function G.OnMessage(kind, msg, sender)
    local name = Short(sender)
    if not name then return false end
    if kind == "P" then
        local lv, map = msg:match("^P|(%d+)|(%d+)$")
        if lv then
            local m = Member(name)
            m.level, m.map, m.at = tonumber(lv), tonumber(map), Now()
        end
        return true
    elseif kind == "Q" then
        local i, n, st, body = msg:match("^Q|(%d+)/(%d+)|(%d+)|(.*)$")
        i, n, st = tonumber(i), tonumber(n), tonumber(st)
        if not (i and n and st) then return true end
        local pa = partial[name]
        if not pa or pa.stamp ~= st then pa = { stamp = st, n = n, parts = {}, got = 0 }; partial[name] = pa end
        if not pa.parts[i] then pa.parts[i] = body or ""; pa.got = pa.got + 1 end
        if pa.got >= pa.n then
            local quests = {}
            for k = 1, pa.n do
                for id, s, p in (pa.parts[k] or ""):gmatch("(%d+)%.([AR])(%d)") do
                    quests[tonumber(id)] = { s = s, p = tonumber(p) }
                end
            end
            local m = Member(name)
            m.quests, m.at = quests, Now()
            partial[name] = nil
            Changed()
        end
        return true
    elseif kind == "H" then
        -- neues Gruppenmitglied mit Levelmate: unseren Stand gleich schicken
        dirty = true
        return false   -- Travel verarbeitet "H" ebenfalls (Wege)
    end
    return false
end

---------------------------------------------------------------------------
-- Abfragen fuer Planer und Anzeige
---------------------------------------------------------------------------
-- Namen der Gruppenmitglieder (mit Levelmate), die diese Quest im Log haben.
-- open = true: nur, wenn sie bei ihnen noch nicht fertig ist.
function G.Who(questID, open)
    local out
    for name, m in pairs(G.members) do
        local q = m.quests and m.quests[questID]
        if q and (not open or q.s ~= "R") then
            out = out or {}
            out[#out + 1] = name
        end
    end
    if out then table.sort(out) end
    return out
end

function G.Active()
    for _ in pairs(G.members) do return true end
    return false
end

function G.Count()
    local n = 0
    for _ in pairs(G.members) do n = n + 1 end
    return n
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN",
                      "GROUP_ROSTER_UPDATE", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event) pcall(function()
    if event == "GROUP_ROSTER_UPDATE" then
        local changed = false
        for name in pairs(G.members) do
            if not InMyGroup(name) then G.members[name] = nil; changed = true end
        end
        if changed then Changed() end
    end
    dirty = true
end) end)

-- Hoechstens alle 5 s senden, wenn sich etwas geaendert hat; sonst jede Minute
-- einmal zur Sicherheit. Alte Daten (Spieler weg, 5 min nichts gehoert) verwerfen.
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(5, function() pcall(function()
        if not InGroup() then
            if next(G.members) then G.members = {}; Changed() end
            return
        end
        local now = Now()
        if (dirty and now - lastSent >= 5) or now - lastSent >= 60 then G.Broadcast() end
        for name, m in pairs(G.members) do
            if now - (m.at or 0) > 300 then G.members[name] = nil end
        end
    end) end)
end
