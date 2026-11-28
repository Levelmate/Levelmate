-- Smart.lua
local L = Levelmate.L
local MAX_SAMPLE_SECONDS = 7200   -- 2 Stunden
-- XP-pro-Minute-Messung und "Zurueckstellen" von Quests.
--
-- Messung ueber Events (Forever/Retail-Payload):
--   QUEST_ACCEPTED: questID            -> Startzeit merken
--   QUEST_TURNED_IN: questID, xpReward -> XP direkt vom Spiel, Dauer berechnen
-- Die Differenz von UnitXP wird nicht mehr benutzt (war bei Levelaufstieg falsch).
-- Die Zeit ist Echtzeit inkl. Laufwege/Pausen. AFK-Bereinigung folgt in Phase 5.
Levelmate = Levelmate or {}
Levelmate.Smart = Levelmate.Smart or {}

local DATA_VERSION = 2
local MAX_SAMPLES = 50
Levelmate.Smart.MIN_SAMPLES = 3   -- erst ab so vielen Messungen wird ein Wert angezeigt

local function Ensure()
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.smart = Levelmate_DB.smart or {}
    local s = Levelmate_DB.smart
    -- Migration aus 0.4-0.6: alte Eintraege hatten gemischte Formate
    -- (teils nur eine Zahl), was nach der Reparatur des Queststatus zu einem
    -- Lua-Fehler gefuehrt haette. Alte Messdaten waren ohnehin leer.
    -- Migration aus 0.4-0.6: Die alten Eintraege hatten gemischte Formate
    -- (teils nur eine Zahl), was nach der Reparatur des Queststatus zu einem
    -- Lua-Fehler gefuehrt haette. Messwerte gab es nie (samples war leer),
    -- und alte Startzeiten wuerden die erste Messung verfaelschen.
    if s.version ~= DATA_VERSION then
        s.started = {}
        s.samples = {}
        s.pending = nil
        s.version = DATA_VERSION
        Levelmate_DB.step = nil       -- Altlast aus frueheren Versionen
    end
    s.started = s.started or {}
    s.samples = s.samples or {}
    s.defer = nil  -- seit 0.8.0 pro Charakter in Levelmate_CharDB
end

---------------------------------------------------------------------------
-- Kalibrierung: echte Dauer / geschaetzte Dauer, getrennt nach Questart
-- ("kill" Gegner, "item" Gegenstaende sammeln, "object" Objekte, "travel" nur Laufen).
---------------------------------------------------------------------------
local function Calib()
    Levelmate_CharDB = Levelmate_CharDB or {}
    Levelmate_CharDB.calib = Levelmate_CharDB.calib or {}
    Levelmate_CharDB.estimates = Levelmate_CharDB.estimates or {}
    return Levelmate_CharDB.calib, Levelmate_CharDB.estimates
end

Levelmate.Smart.KIND_LABEL = { kill = "Gegner-Quests", item = "Sammelquests", object = "Objekt-Quests", travel = "Laufquests" }

-- Faktor, mit dem der Planer seine Zeitschaetzung fuer diese Questart multipliziert.
function Levelmate.Smart.Factor(kind)
    local cal = Calib()
    -- Begrenzt auf 0,67 bis 1,5: Die Messung (Annahme bis Abgabe) enthaelt oft
    -- Zeit, in der man andere Quests macht. Ohne Grenze wurden aus 1,5 Stunden
    -- schnell 4,5 Stunden geschaetzt.
    local function Clamp(f) return math.max(0.67, math.min(1.5, f)) end
    local e = cal[kind or "travel"]
    if e and e.n >= 2 then return Clamp(e.f) end
    local g = cal.all
    if g and g.n >= 3 then return Clamp(g.f) end
    return 1
end

local function Learn(key, ratio)
    local cal = Calib()
    local e = cal[key] or { n = 0, f = 1 }
    local n = math.min(e.n, 9)                 -- gleitender Mittelwert ueber ~10 Messungen
    e.f = (e.f * n + ratio) / (n + 1)
    e.n = e.n + 1
    cal[key] = e
end

function Levelmate.Smart.OnQuestAccepted(questID)
    Ensure()
    questID = tonumber(questID)
    if not questID then return end
    Levelmate_DB.smart.started[questID] = time()
    Levelmate_DB.smart.turnins = Levelmate_DB.smart.turnins or 0
    Levelmate_DB.smart.startedAt = Levelmate_DB.smart.startedAt or {}
    Levelmate_DB.smart.startedAt[questID] = Levelmate_DB.smart.turnins
    -- Schaetzung des Planers zum Zeitpunkt der Annahme merken
    local est = Levelmate.Planner and Levelmate.Planner.EstimateFor and Levelmate.Planner.EstimateFor(questID)
    if est then
        local _, estimates = Calib()
        estimates[questID] = est
    end
end

function Levelmate.Smart.OnQuestTurnedIn(questID, xpReward)
    Ensure()
    questID = tonumber(questID)
    if not questID then return end
    local s = Levelmate_DB.smart
    local started = s.started[questID]
    s.started[questID] = nil
    -- Wurden zwischendurch andere Quests abgegeben, hast du die Zeit geteilt:
    -- dann taugt sie nicht als Messung fuer diese eine Quest.
    s.turnins = (s.turnins or 0) + 1
    local before = s.startedAt and s.startedAt[questID]
    if s.startedAt then s.startedAt[questID] = nil end
    local shared = before and (s.turnins - before) > 1
    -- Abgleich mit der Schaetzung (Ausreisser durch AFK/Ausloggen ignorieren)
    local _, estimates = Calib()
    local est = estimates[questID]
    estimates[questID] = nil
    if started and est and est.seconds and est.seconds > 0 then
        local actual = time() - started
        local ratio = actual / est.seconds
        if not shared and actual < 7200 and ratio > 0.2 and ratio < 5 then
            Learn(est.kind or "travel", ratio)
            Learn("all", ratio)
        end
    end
    local xp = tonumber(xpReward) or 0
    if Levelmate.DB and Levelmate.DB.LearnXP then pcall(Levelmate.DB.LearnXP, questID, xp, UnitLevel and UnitLevel("player")) end
    if not started or xp <= 0 then return end  -- ohne Startzeit/XP keine Messung
    local seconds = math.max(1, time() - started)
    -- Ueber 2 Stunden zwischen Annahme und Abgabe (z. B. ueber Nacht ausgeloggt)
    -- ist keine echte Questzeit: nicht als Messung verwenden.
    if seconds > MAX_SAMPLE_SECONDS then return end
    local title = C_QuestLog and Levelmate.Quests.Call(C_QuestLog.GetTitleForQuestID, questID)
    table.insert(s.samples, {
        questID = questID, title = title, xp = xp, seconds = seconds,
        xpPerMinute = xp / (seconds / 60), level = UnitLevel and UnitLevel("player") or 0,
        at = time(),
    })
    while #s.samples > MAX_SAMPLES do table.remove(s.samples, 1) end
end

-- Liefert nil, wenn keine Messung vorliegt. Sonst: letzte Messung und
-- Durchschnitt (Summe XP / Summe Zeit) der letzten bis zu 5 Quests.
function Levelmate.Smart.GetSummary()
    Ensure()
    local all = Levelmate_DB.smart.samples
    -- Nur plausible Messungen (aeltere Daten koennen Ausreisser enthalten)
    local samples = {}
    for _, sm in ipairs(all) do
        if sm.seconds and sm.seconds > 0 and sm.seconds <= MAX_SAMPLE_SECONDS and sm.xp then samples[#samples + 1] = sm end
    end
    if #samples == 0 then return nil end
    local last = samples[#samples]
    local xp, sec, n = 0, 0, 0
    for i = #samples, math.max(1, #samples - 4), -1 do
        xp = xp + samples[i].xp; sec = sec + samples[i].seconds; n = n + 1
    end
    return { last = last, avg = xp / (sec / 60), count = n, total = #samples,
             enough = #samples >= Levelmate.Smart.MIN_SAMPLES }
end

function Levelmate.Smart.CalibrationText()
    local cal = Calib()
    local parts = {}
    for _, kind in ipairs({ "kill", "item", "object", "travel" }) do
        local e = cal[kind]
        if e and e.n > 0 then
            table.insert(parts, string.format(L(e.n == 1 and "%s ×%.2f (%d Messung%s)" or "%s ×%.2f (%d Messungen%s)"),
                L(Levelmate.Smart.KIND_LABEL[kind]), e.f, e.n, e.n < 2 and L(", noch nicht aktiv") or ""))
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " · ")
end

-- Uebersprungene Quests gelten pro Charakter (Levelmate_CharDB).
local function Deferred()
    Levelmate_CharDB = Levelmate_CharDB or {}
    Levelmate_CharDB.defer = Levelmate_CharDB.defer or {}
    return Levelmate_CharDB.defer
end

-- Uebersprungen = "spaeter": Die Quest kommt automatisch wieder, sobald du
-- eine halbe Stufe weiter bist (skaliert mit der Stufe: auf Stufe 50 sind das
-- mehr XP als auf Stufe 10, aber ungefaehr gleich viel Spielzeit).
-- Gespeichert wird der Fortschritt beim Ueberspringen, z. B. 33.4 = Stufe 33, 40 %.
local function MyLevel() return (UnitLevel and UnitLevel("player")) or 1 end
local function Progress()
    local lvl = MyLevel()
    local xp = UnitXP and UnitXP("player") or 0
    local max = UnitXPMax and UnitXPMax("player") or 0
    if max and max > 0 then return lvl + xp / max end
    return lvl
end
Levelmate.Smart.DEFER_LEVELS = 0.5
-- perm = true: "Ueberspringen" - die Quest kommt nicht von selbst wieder
-- (nur ueber den Zurueck-Pfeil oder /lm ausgelassen leeren).
-- kind: Art des Schritts beim Zurueckstellen (z. B. "DO", "TURNIN")
function Levelmate.Smart.SetDeferred(questID, state, perm, kind)
    if questID then Deferred()[questID] = state and { p = Progress(), perm = perm or nil, kind = kind } or nil end
end

-- "Später" beim Erledigen gedrueckt, Quest inzwischen trotzdem fertig:
-- die Abgabe nicht mit zurueckstellen.
function Levelmate.Smart.ReleaseIfReady(questID, ready)
    local v = questID and Deferred()[questID]
    if ready and type(v) == "table" and not v.perm and v.kind and v.kind ~= "TURNIN" then
        Deferred()[questID] = nil
        return true
    end
    return false
end

-- Fuer den Fehlerbericht: zurueckgestellte und uebersprungene Quests
function Levelmate.Smart.DeferredList()
    local later, perm = {}, {}
    for id, v in pairs(Deferred()) do
        if type(v) == "table" and v.perm then perm[#perm + 1] = id else later[#later + 1] = id end
    end
    table.sort(later); table.sort(perm)
    return later, perm
end

function Levelmate.Smart.IsPermanent(questID)
    local v = questID and Deferred()[questID]
    return type(v) == "table" and v.perm == true
end

-- Dauerhaft uebersprungene Quests: Anzahl bzw. alle wieder freigeben
function Levelmate.Smart.PermanentCount()
    local n = 0
    for _, v in pairs(Deferred()) do if type(v) == "table" and v.perm then n = n + 1 end end
    return n
end
function Levelmate.Smart.ClearPermanent()
    local d, n = Deferred(), 0
    for id, v in pairs(d) do if type(v) == "table" and v.perm then d[id] = nil; n = n + 1 end end
    return n
end

-- Uebersprungenes wieder freigeben, wenn genug XP dazugekommen sind; gibt die IDs zurueck
function Levelmate.Smart.ReleaseDeferred()
    local d, lvl, prog, back = Deferred(), MyLevel(), Progress(), {}
    for id, v in pairs(d) do
        if v == true then d[id] = { p = prog }                    -- sehr alte Eintraege
        elseif type(v) == "number" then                             -- Eintraege vor 0.9.61: Stufe
            if v < lvl then d[id] = nil; back[#back + 1] = id end
        elseif type(v) == "table" and v.p and not v.perm and prog >= v.p + Levelmate.Smart.DEFER_LEVELS then
            d[id] = nil; back[#back + 1] = id
        end
    end
    return back
end

function Levelmate.Smart.ClearDeferred()
    Levelmate_CharDB = Levelmate_CharDB or {}
    Levelmate_CharDB.defer = {}
end

function Levelmate.Smart.ToggleDefer(q)
    local id = q and q.questID
    if not id then return false end
    local d = Deferred()
    if d[id] then d[id] = nil else d[id] = { p = Progress() } end
    return d[id] ~= nil
end

function Levelmate.Smart.IsDeferred(q)
    local id = q and q.questID
    return id ~= nil and Deferred()[id] ~= nil
end

Levelmate.QuestChains = Levelmate.QuestChains or {}

---------------------------------------------------------------------------
-- Fahrtenbuch und Kartendaten (zur Auswertung/Verbesserung des Addons)
-- Speichert pro Charakter, welcher Schritt vorgeschlagen wurde, was wirklich
-- passiert ist (Annahmen, Abgaben, Stufen, Fluege) und alle 15 s die Position.
-- Alles bleibt lokal in den SavedVariables (Levelmate_DB.journal).
---------------------------------------------------------------------------
Levelmate.Journal = Levelmate.Journal or {}
local J = Levelmate.Journal
local MAX_LINES = 30000

local function CharKey()
    local n = UnitName and UnitName("player") or "?"
    local r = GetRealmName and GetRealmName() or "?"
    return n .. "-" .. r
end

local function Book()
    Levelmate_DB = Levelmate_DB or {}
    -- Standard: aus. Einschalten mit /lm fahrtenbuch (nur fuer Tests/Entwicklung).
    if not Levelmate_DB.journalOn then return nil end
    Levelmate_DB.journal = Levelmate_DB.journal or {}
    local key = CharKey()
    local b = Levelmate_DB.journal[key]
    if not b then
        local _, class = UnitClass and UnitClass("player")
        local _, race = UnitRace and UnitRace("player")
        b = { class = class, race = race, faction = UnitFactionGroup and UnitFactionGroup("player"), lines = {} }
        Levelmate_DB.journal[key] = b
    end
    return b
end

local function Pos()
    local p = Levelmate.Planner and Levelmate.Planner.PlayerPoint and Levelmate.Planner.PlayerPoint()
    if not p then return "-|-|-" end
    return string.format("%d|%.1f|%.1f", p.map, p.x, p.y)
end

local function Write(kind, ...)
    local b = Book()
    if not b then return end
    local parts = { tostring(math.floor(time and time() or 0)), kind,
        tostring(UnitLevel and UnitLevel("player") or 0), Pos() }
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    local lines = b.lines
    lines[#lines + 1] = table.concat(parts, "|")
    if #lines > MAX_LINES then
        local keep = {}
        for i = #lines - MAX_LINES + 5000, #lines do keep[#keep + 1] = lines[i] end
        b.lines = keep
    end
end
J.Write = Write

-- Vom Hauptfenster: neuer vorgeschlagener Schritt
local lastStepKey
function J.Step(act, key)
    if not act or key == lastStepKey then return end
    lastStepKey = key
    local t = act.target
    Write("S", act.kind or "?", act.c and act.c.q and act.c.q.id or (act.group and act.group.area) or "-",
        t and t.map or "-", t and string.format("%.1f", t.x) or "-", t and string.format("%.1f", t.y) or "-",
        math.floor(act.stepSeconds or act.seconds or 0), act.pen and act.pen:gsub("|", "/") or "")
end

local jf = CreateFrame("Frame")
for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP", "QUEST_REMOVED" }) do
    pcall(jf.RegisterEvent, jf, ev)
end
jf:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "QUEST_ACCEPTED" then
        local qid = (type(a2) == "number" and a2) or a1
        Write("A", qid)
    elseif event == "QUEST_TURNED_IN" then
        Write("T", a1, a2 or 0)
    elseif event == "QUEST_REMOVED" then
        Write("R", a1)
    elseif event == "PLAYER_LEVEL_UP" then
        Write("L", a1)
    end
end)

-- Position alle 15 s (nur wenn du dich bewegt hast) und Fluege
local lastPos, onTaxi
if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(15, function()
        local taxi = Levelmate.Flag(UnitOnTaxi, false, "player") or false
        if taxi ~= onTaxi then onTaxi = taxi; Write(taxi and "F" or "f") end
        if taxi then return end
        local p = Pos()
        if p ~= lastPos then lastPos = p; Write("P") end
    end)
end

-- Kartendaten: Groesse und Lage aller Gebiete (einmal je Spielversion)
function J.DumpMaps(force)
    if not (C_Map and C_Map.GetMapInfo and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
    Levelmate_DB = Levelmate_DB or {}
    if not Levelmate_DB.journalOn and not force then return end
    local build = GetBuildInfo and select(2, GetBuildInfo()) or "?"
    if not force and Levelmate_DB.mapDump and Levelmate_DB.mapDump.build == build then return end
    local out = { build = build, maps = {} }
    local id, last = 1, 3000
    local function Step()
        local stop = math.min(last, id + 200)
        for m = id, stop do
            local ok, info = pcall(C_Map.GetMapInfo, m)
            if ok and info and info.mapType and info.mapType >= 2 and info.mapType <= 5 then
                local ok1, c0, v0 = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(0, 0))
                local ok2, c1, v1 = pcall(C_Map.GetWorldPosFromMapPos, m, CreateVector2D(1, 1))
                if ok1 and ok2 and v0 and v1 then
                    local x0, y0 = v0:GetXY()
                    local x1, y1 = v1:GetXY()
                    out.maps[m] = string.format("%s|%d|%d|%d|%.1f|%.1f|%.1f|%.1f",
                        (info.name or "?"):gsub("|", "/"), info.mapType, info.parentMapID or 0, c0 or 0, x0, y0, x1, y1)
                end
            end
        end
        id = stop + 1
        if id <= last then C_Timer.After(0, Step) else Levelmate_DB.mapDump = out end
    end
    Step()
end

---------------------------------------------------------------------------
-- Leveltempo: echte XP pro Spielminute dieses Charakters, gleitend ueber die
-- letzten 60 aktiven Minuten. Gezaehlt wird jede XP (Quests, Gegner,
-- Entdecken); Zeit nur, solange du eingeloggt und nicht AFK bist.
---------------------------------------------------------------------------
local PACE_CHUNKS = 60       -- Minuten im gleitenden Fenster
local PACE_MIN_SECONDS = 600 -- erst ab 10 Minuten Spielzeit verlaesslich
local paceXP, paceSec = 0, 0
local lastXP, lastMax, lastLevel

local function PaceStore()
    Levelmate_CharDB = Levelmate_CharDB or {}
    Levelmate_CharDB.pace = Levelmate_CharDB.pace or {}
    return Levelmate_CharDB.pace
end

local function OnXP()
    local xp, max, lvl = UnitXP("player") or 0, UnitXPMax("player") or 0, UnitLevel("player") or 0
    if lastXP then
        local gained
        if lvl > lastLevel then gained = (lastMax - lastXP) + xp else gained = xp - lastXP end
        if gained > 0 and gained < 1000000 then paceXP = paceXP + gained end
    end
    lastXP, lastMax, lastLevel = xp, max, lvl
end

local pf = CreateFrame("Frame")
pcall(pf.RegisterEvent, pf, "PLAYER_XP_UPDATE")
pcall(pf.RegisterEvent, pf, "PLAYER_ENTERING_WORLD")
pf:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" and lastXP then return end
    OnXP()
end)

if C_Timer and C_Timer.NewTicker then
    C_Timer.NewTicker(15, function()
        local afk = Levelmate.Flag(UnitIsAFK, false, "player")
        if not afk and (UnitLevel("player") or 60) < 60 then paceSec = paceSec + 15 end
        if paceSec >= 60 then
            local p = PaceStore()
            p[#p + 1] = { s = paceSec, x = paceXP }
            while #p > PACE_CHUNKS do table.remove(p, 1) end
            paceXP, paceSec = 0, 0
        end
    end)
end

-- XP pro Minute aus der Spielzeit, oder nil, solange zu wenig gemessen wurde
function Levelmate.Smart.Pace()
    local sec, xp = paceSec, paceXP
    for _, c in ipairs(PaceStore()) do sec = sec + (c.s or 0); xp = xp + (c.x or 0) end
    if sec < PACE_MIN_SECONDS or xp <= 0 then return nil, sec end
    return xp / (sec / 60), sec
end
