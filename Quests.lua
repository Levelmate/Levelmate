-- Quests.lua
local L = Levelmate.L
-- Gemeinsame Questdatenquelle fuer Questliste, Guide und XP/min-Messung.
--
-- WoW Forever (Client 1.60.x, Interface 16001) basiert auf der modernen
-- Retail-Technik. Die alten Classic-Funktionen GetQuestLogTitle und
-- GetNumQuestLogEntries existieren dort NICHT (im Spiel geprueft:
-- beide liefern false). Ausserdem enthaelt C_QuestLog.GetInfo() KEIN Feld
-- "isComplete" - genau das war die Ursache des Fehlers bis 0.6.3.
--
-- Der Abschlussstatus wird deshalb so gelesen wie im Blizzard-Questtracker:
--   C_QuestLog.ReadyForTurnIn(questID) / C_QuestLog.IsComplete(questID)
-- Im Spiel geprueft (Quest 233): GetInfo().isComplete = nil,
-- IsComplete = true, ReadyForTurnIn = true.

Levelmate = Levelmate or {}
Levelmate.Quests = Levelmate.Quests or {}
local Q = Levelmate.Quests

-- Statuswerte. Jede Quest hat genau EINEN Status, dadurch kann sie nie
-- gleichzeitig "abgeschlossen" und "in Arbeit" sein.
Q.STATUS_ACTIVE    = "ACTIVE"     -- im Questlog, noch nicht fertig
Q.STATUS_READY     = "READY"      -- im Questlog, alle Ziele erfuellt
Q.STATUS_FAILED    = "FAILED"     -- im Questlog, fehlgeschlagen
Q.STATUS_TURNEDIN  = "TURNEDIN"   -- nicht im Questlog, vom Server als abgegeben markiert
Q.STATUS_NOTINLOG  = "NOTINLOG"   -- nicht im Questlog, nicht abgegeben

local snapshot = { list = {}, byID = {}, byTitle = {}, time = 0 }

-- Sicherer Aufruf: liefert nil, wenn die Funktion fehlt oder einen Fehler wirft.
local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end
Q.Call = Call

local CQL = C_QuestLog

function Q.NormalizeTitle(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return string.lower(s)
end

local function ReadObjectives(questID)
    local result = {}
    local list = CQL and Call(CQL.GetQuestObjectives, questID)
    if type(list) ~= "table" then return result end
    for _, o in ipairs(list) do
        if type(o) == "table" then
            table.insert(result, {
                text = o.text or "",
                done = o.finished == true,
                have = tonumber(o.numFulfilled),
                need = tonumber(o.numRequired),
                type = o.type,
            })
        end
    end
    return result
end

local function ReadStatus(questID, objectives)
    if not CQL then return Q.STATUS_ACTIVE end
    if Call(CQL.IsFailed, questID) == true then return Q.STATUS_FAILED end
    if Call(CQL.ReadyForTurnIn, questID) == true then return Q.STATUS_READY end
    if Call(CQL.IsComplete, questID) == true then return Q.STATUS_READY end
    -- Letzte Absicherung: alle gemeldeten Ziele erledigt.
    if #objectives > 0 then
        local all = true
        for _, o in ipairs(objectives) do if not o.done then all = false end end
        if all then return Q.STATUS_READY end
    end
    return Q.STATUS_ACTIVE
end

-- Liest das komplette Questlog neu ein und speichert das Ergebnis.
function Q.Rebuild()
    local list, byID, byTitle = {}, {}, {}
    if CQL and CQL.GetNumQuestLogEntries and CQL.GetInfo then
        local n = Call(CQL.GetNumQuestLogEntries) or 0
        for i = 1, n do
            local info = Call(CQL.GetInfo, i)
            if type(info) == "table" and not info.isHeader and not info.isHidden
               and info.title and info.questID and info.questID > 0 then
                local objectives = ReadObjectives(info.questID)
                local q = {
                    questID = info.questID,
                    title = info.title,
                    level = info.level or 0,
                    logIndex = i,
                    objectives = objectives,
                    status = ReadStatus(info.questID, objectives),
                }
                q.complete = (q.status == Q.STATUS_READY)
                table.insert(list, q)
                byID[q.questID] = q
                byTitle[Q.NormalizeTitle(q.title)] = q
            end
        end
    end
    snapshot = { list = list, byID = byID, byTitle = byTitle, time = GetTime and GetTime() or 0 }
    return list
end

-- Anzeigetext eines Questziels. Rufziele kommen vom Spiel als
-- "Gelkisklan: Feindselig / Freundlich" (jetzt / Ziel) - das liest sich wie
-- "erledigt". Darum: "Gelkisklan: Feindselig (Ziel: Freundlich)".
function Q.ShowText(o)
    local t = o and o.text or ""
    if o and o.type == "reputation" and not o.done then
        local name, now, goal = t:match("^(.-):%s*(.-)%s*/%s*(.-)$")
        if name and now ~= "" and goal ~= "" then
            return name .. ": " .. now .. " (" .. Levelmate.L("Ziel") .. ": " .. goal .. ")"
        end
    end
    return t
end

-- Liefert die zuletzt eingelesene Liste (gleiche Tabelle fuer alle Anzeigen).
function Q.GetList() return snapshot.list end

-- Sucht eine Quest im aktuellen Questlog: zuerst per Quest-ID, sonst per Titel.
function Q.Find(questID, title)
    if questID and snapshot.byID[questID] then return snapshot.byID[questID] end
    if title then return snapshot.byTitle[Q.NormalizeTitle(title)] end
    return nil
end

-- Status einer beliebigen Quest, auch wenn sie nicht (mehr) im Questlog ist.
function Q.GetStatus(questID, title)
    local q = Q.Find(questID, title)
    if q then return q.status, q end
    if questID and CQL and Call(CQL.IsQuestFlaggedCompleted, questID) == true then
        return Q.STATUS_TURNEDIN, nil
    end
    return Q.STATUS_NOTINLOG, nil
end

Q.Labels = {
    ACTIVE   = "|cffffff00In Arbeit|r",
    READY    = "|cff00ff00Abgabebereit|r",
    FAILED   = "|cffff4040Fehlgeschlagen|r",
    TURNEDIN = "|cff00ff00Bereits abgegeben|r",
    NOTINLOG = "|cffaaaaaaNoch nicht angenommen|r",
}

-- Symbole als Spieltexturen. Textzeichen wie "○" fehlen in der
-- Spielschrift und erscheinen als leeres Kaestchen (im Spiel gesehen, 0.7.0).
Q.ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t"
Q.ICON_OPEN = "|TInterface\\COMMON\\Indicator-Gray:12:12|t"
Q.ICON_FAIL = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12|t"

function Q.Icon(status)
    if status == Q.STATUS_READY or status == Q.STATUS_TURNEDIN then return Q.ICON_DONE end
    if status == Q.STATUS_FAILED then return Q.ICON_FAIL end
    return Q.ICON_OPEN
end

-- Diagnose: gibt Rohdaten der Client-API im Chat aus.
function Q.Diagnose(print)
    print(L("--- Levelmate Diagnose ---"))
    local apis = { "GetNumQuestLogEntries", "GetInfo", "GetQuestObjectives", "IsComplete",
                   "ReadyForTurnIn", "IsFailed", "IsQuestFlaggedCompleted" }
    local missing = {}
    for _, name in ipairs(apis) do
        if not (CQL and type(CQL[name]) == "function") then table.insert(missing, name) end
    end
    print(#missing == 0 and L("C_QuestLog: alle benoetigten Funktionen vorhanden.")
        or (L("|cffff4040Fehlende C_QuestLog-Funktionen:|r ") .. table.concat(missing, ", ")))
    local list = Q.Rebuild()
    print(string.format(L("%d Quests im Questlog:"), #list))
    for _, q in ipairs(list) do
        local id = q.questID
        print(string.format(L("%s [%d] %s  Status=%s  IsComplete=%s ReadyForTurnIn=%s IsFailed=%s"),
            Q.Icon(q.status), id, q.title, q.status,
            tostring(Call(CQL.IsComplete, id)), tostring(Call(CQL.ReadyForTurnIn, id)),
            tostring(Call(CQL.IsFailed, id))))
        if #q.objectives == 0 then
            print(L("     (keine Questziele - z. B. Liefer- oder Gespraechsquest)"))
        end
        for _, o in ipairs(q.objectives) do
            print(string.format(L("     %s %s  (%s/%s, erledigt=%s)"), o.done and "+" or "-",
                o.text, tostring(o.have), tostring(o.need), tostring(o.done)))
        end
    end
end
