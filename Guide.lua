-- Guide.lua
-- Guide-Schritte. Der Status kommt ausschliesslich aus Levelmate.Quests, also aus
-- derselben Datenquelle wie die Questliste.
--
-- Quest-IDs und Titel unten sind im Spiel per Diagnose bestaetigt
-- (233 = "Postbeförderung im Coldridgetal", 3361 = "Dilemma eines Flüchtlings").
-- Die Steps sind weiterhin nur ein Test-Ablauf, KEINE vollstaendige
-- Level-1-bis-10-Route (die folgt in Phase 4).
Levelmate = Levelmate or {}
Levelmate.Guide = Levelmate.Guide or {}

local steps = {
    {
        title = "Postbeförderung im Coldridgetal",
        questID = 233,
        quest = "Postbeförderung im Coldridgetal",
        instruction = "Bringe die Post zum Empfänger und gib die Quest dort ab.",
        kind = "turnin",
    },
    {
        title = "Dilemma eines Flüchtlings",
        questID = 3361,
        quest = "Dilemma eines Flüchtlings",
        instruction = "Erledige die drei Aufgaben im Questlog (Felix' Kasten, Truhe, Felix' Bolzenheimer). Kehre danach zum Questgeber zurück.",
        kind = "quest",
    },
}
Levelmate.Guide.steps = steps

local function Ensure()
    Levelmate_DB = Levelmate_DB or {}
    Levelmate_DB.guide = Levelmate_DB.guide or {}
    if not Levelmate_DB.guide.index then Levelmate_DB.guide.index = 1 end
end

function Levelmate.Guide.GetCurrent()
    Ensure()
    local i = math.max(1, math.min(#steps, tonumber(Levelmate_DB.guide.index) or 1))
    Levelmate_DB.guide.index = i
    return steps[i], i, #steps
end

function Levelmate.Guide.Next()
    Ensure()
    Levelmate_DB.guide.index = math.min(#steps, (tonumber(Levelmate_DB.guide.index) or 1) + 1)
end

function Levelmate.Guide.Previous()
    Ensure()
    Levelmate_DB.guide.index = math.max(1, (tonumber(Levelmate_DB.guide.index) or 1) - 1)
end

-- Liefert: Statuscode, Anzeigetext, Questeintrag (falls im Questlog)
function Levelmate.Guide.GetStepStatus(step)
    if not step then return nil, "Nicht verfügbar", nil end
    local Q = Levelmate.Quests
    local status, q = Q.GetStatus(step.questID, step.quest)
    local text = Q.Icon(status) .. " " .. (Q.Labels[status] or status)
    if q and status == Q.STATUS_ACTIVE and #q.objectives > 0 then
        local done = 0
        for _, o in ipairs(q.objectives) do if o.done then done = done + 1 end end
        text = text .. string.format(" (%d/%d Ziele)", done, #q.objectives)
    end
    if status == Q.STATUS_TURNEDIN then
        text = text .. " – mit „Weiter“ zum nächsten Schritt"
    end
    return status, text, q
end

-- Kompatibilitaet zu 0.6.x: frueher wurde GetStatus(step, rows) aufgerufen.
function Levelmate.Guide.GetStatus(step)
    local _, text = Levelmate.Guide.GetStepStatus(step)
    return text
end
