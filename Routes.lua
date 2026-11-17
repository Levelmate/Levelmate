Levelmate = Levelmate or {}
local L = Levelmate.L
Levelmate.Routes = Levelmate.Routes or {}

-- These are broad leveling hints, not a verified quest-by-quest route.
-- Detailed quest coordinates will be added only after they are confirmed
-- for the Forever server.
local hints = {
    Horde = {
        { min = 1, max = 10, text = "Rassenstartgebiet / Durotar" },
        { min = 10, max = 20, text = "Nördliches Brachland / Silberwald" },
        { min = 20, max = 30, text = "Brachland / Steinkrallengebirge" },
        { min = 25, max = 35, text = "Tausend Nadeln / Ashenvale" },
        { min = 30, max = 40, text = "Schlingendorntal / Arathihochland" },
        { min = 40, max = 50, text = "Feralas / Tanaris / Hinterland" },
        { min = 50, max = 60, text = "Un'Goro / Teufelswald / Pestländer" },
    },
    Alliance = {
        { min = 1, max = 10, text = "Rassenstartgebiet" },
        { min = 10, max = 20, text = "Dunkelküste / Westfall / Loch Modan" },
        { min = 20, max = 30, text = "Rotkammgebirge / Dämmerwald / Eschental" },
        { min = 30, max = 40, text = "Desolace / Schlingendorntal / Arathihochland" },
        { min = 40, max = 50, text = "Feralas / Tanaris / Hinterland" },
        { min = 50, max = 60, text = "Un'Goro / Teufelswald / Pestländer" },
    }
}

function Levelmate.Routes.GetHint(faction, level)
    local list = hints[faction] or hints.Horde
    for _, entry in ipairs(list) do
        if level >= entry.min and level <= entry.max then
            return L(entry.text) .. " (Level " .. entry.min .. "–" .. entry.max .. ")"
        end
    end
    return L("Gebietshinweis nicht verfügbar.")
end
