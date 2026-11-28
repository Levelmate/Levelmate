-- Levelmate: kleine Komfort-Helfer (alle abschaltbar, Standard: aus)
--  * Quests automatisch annehmen
--  * Fertige Quests automatisch abgeben (bei mehreren Belohnungen waehlst du selbst)
--  * Graue Gegenstaende beim Haendler verkaufen
--  * Beim Haendler automatisch reparieren
-- Shift gedrueckt halten: dieses eine Mal nichts automatisch machen.

Levelmate = Levelmate or {}
local L = Levelmate.L or function(s) return s end
local C = {}
Levelmate.Comfort = C

local function DB() return Levelmate_DB or {} end
local function On(key) return DB()[key] == true end
local function Held() return IsShiftKeyDown and IsShiftKeyDown() end
local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLevelmate|r: " .. msg) end
end

-- Uebersprungene Quests (dauerhaft) nicht automatisch annehmen
local function Unwanted(questID)
    return questID and Levelmate.Smart and Levelmate.Smart.IsPermanent and Levelmate.Smart.IsPermanent(questID)
end

-- Steht die Quest in Levelmates Route (oder ist sie nur nicht bewertet)?
-- Einstellung "autoAcceptAll": alle Quests annehmen statt nur die aus der Route.
local function InRoute(questID, title)
    if DB().autoAcceptAll then return true end
    local plan = Levelmate.Planner and Levelmate.Planner.Last and Levelmate.Planner.Last()
    local byId = plan and plan.byId
    if not byId then return false end
    local c = questID and byId[questID]
    if not c and title then
        for _, x in pairs(byId) do
            if x.q and x.q.name == title then c = x; break end
        end
    end
    return c ~= nil and not c.skipReason
end

-- Schutz gegen Endlosschleifen im Gespraechsfenster
local tried, triedAt = {}, 0
local function Once(key)
    local now = GetTime and GetTime() or 0
    if now - triedAt > 3 then tried = {} end
    triedAt = now
    if tried[key] then return false end
    tried[key] = true
    return true
end

---------------------------------------------------------------------------
-- Quests: Gespraech, Annehmen, Abgeben
---------------------------------------------------------------------------
local function GossipPick()
    local G = C_GossipInfo
    if not G then return false end
    if On("autoTurnIn") and G.GetActiveQuests then
        local ok, list = pcall(G.GetActiveQuests)
        for i, q in ipairs(ok and list or {}) do
            if q.isComplete and Once("a" .. tostring(q.questID or i)) then
                pcall(G.SelectActiveQuest, q.questID or i)
                return true
            end
        end
    end
    if On("autoAccept") and G.GetAvailableQuests then
        local ok, list = pcall(G.GetAvailableQuests)
        for i, q in ipairs(ok and list or {}) do
            if not Unwanted(q.questID) and InRoute(q.questID, q.title) and Once("v" .. tostring(q.questID or i)) then
                pcall(G.SelectAvailableQuest, q.questID or i)
                return true
            end
        end
    end
    return false
end

local function GreetingPick()
    if On("autoTurnIn") and GetNumActiveQuests then
        for i = 1, GetNumActiveQuests() do
            local title, done = GetActiveTitle(i)
            if done and Once("ga" .. tostring(title)) then SelectActiveQuest(i); return end
        end
    end
    if On("autoAccept") and GetNumAvailableQuests then
        for i = 1, GetNumAvailableQuests() do
            local title = GetAvailableTitle and GetAvailableTitle(i)
            if InRoute(nil, title) and Once("gv" .. tostring(title or i)) then SelectAvailableQuest(i); return end
        end
    end
end

---------------------------------------------------------------------------
-- Ausloggen ausserhalb eines Gasthauses: Hinweis auf das naechste Gasthaus
-- (Das Spiel zaehlt dann 20 Sekunden herunter. Im Gasthaus oder mit Schlafsack
-- bist du "ausgeruht" und loggst sofort aus - dann kommt kein Hinweis.)
---------------------------------------------------------------------------
local function RestHint()
    if DB().restHint == false then return end
    if (UnitLevel("player") or 60) >= 60 then return end
    if IsResting and IsResting() then return end
    local P, T = Levelmate.Planner, Levelmate.Travel
    local here = P and P.PlayerPoint and P.PlayerPoint()
    local inns = T and T.Inns and T.Inns() or {}
    local best, bestYd
    for _, inn in ipairs(inns) do
        local yd = here and P.Yards and P.Yards(here, inn.point)
        if yd and (not bestYd or yd < bestYd) then best, bestYd = inn, yd end
    end
    if best then
        local mins = math.max(1, math.floor(bestYd / 7 / 60 + 0.5))
        local zone = P.MapName and P.MapName(best.point.map) or "?"
        Print(string.format(L("Tipp: Im Gasthaus ausloggen gibt Ruhe-Bonus (doppelte XP für Gegner). Nächstes Gasthaus: %s, %s (ca. %d min zu Fuß)."),
            best.name or "?", zone, mins))
    else
        Print(L("Tipp: Im Gasthaus ausloggen gibt Ruhe-Bonus (doppelte XP für Gegner)."))
    end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
                      "QUEST_COMPLETE", "MERCHANT_SHOW", "PLAYER_CAMPING", "PLAYER_QUITING" }) do
    pcall(f.RegisterEvent, f, ev)
end

local function SellGrey()
    local CC = C_Container
    local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
    if not numSlots then return end
    local total, n = 0, 0
    for bag = 0, 4 do
        for slot = 1, (numSlots(bag) or 0) do
            local quality, count, noValue, itemID
            if CC and CC.GetContainerItemInfo then
                local info = CC.GetContainerItemInfo(bag, slot)
                if info then quality, count, noValue, itemID = info.quality, info.stackCount, info.hasNoValue, info.itemID end
            elseif GetContainerItemInfo then
                local _, c, _, q, _, _, _, _, nv, id = GetContainerItemInfo(bag, slot)
                quality, count, noValue, itemID = q, c, nv, id
            end
            if quality == 0 and not noValue and itemID then
                local price = select(11, GetItemInfo(itemID)) or 0
                if price > 0 then
                    total = total + price * (count or 1); n = n + 1
                    if CC and CC.UseContainerItem then CC.UseContainerItem(bag, slot) else UseContainerItem(bag, slot) end
                end
            end
        end
    end
    if n > 0 then
        local money = GetCoinTextureString and GetCoinTextureString(total) or tostring(total)
        Print(string.format(L("%d graue Gegenstände verkauft für %s."), n, money))
    end
end

local function Repair()
    if not (CanMerchantRepair and CanMerchantRepair()) then return end
    local cost, can = GetRepairAllCost()
    if not cost or cost <= 0 or not can then return end
    if (GetMoney and GetMoney() or 0) < cost then
        Print(L("Nicht genug Gold zum Reparieren."))
        return
    end
    RepairAllItems()
    local money = GetCoinTextureString and GetCoinTextureString(cost) or tostring(cost)
    Print(string.format(L("Ausrüstung repariert für %s."), money))
end

f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_CAMPING" or event == "PLAYER_QUITING" then pcall(RestHint); return end
    if Held() then return end
    if event == "GOSSIP_SHOW" then
        if On("autoAccept") or On("autoTurnIn") then GossipPick() end
    elseif event == "QUEST_GREETING" then
        if On("autoAccept") or On("autoTurnIn") then GreetingPick() end
    elseif event == "QUEST_DETAIL" then
        if On("autoAccept") then
            local id = GetQuestID and GetQuestID()
            local title = GetTitleText and GetTitleText()
            if not Unwanted(id) and InRoute(id, title) then
                if QuestGetAutoAccept and QuestGetAutoAccept() then
                    if CloseQuest then CloseQuest() end   -- schon angenommen (vom Spiel)
                else
                    AcceptQuest()
                end
            end
        end
    elseif event == "QUEST_PROGRESS" then
        if On("autoTurnIn") and IsQuestCompletable and IsQuestCompletable() then CompleteQuest() end
    elseif event == "QUEST_COMPLETE" then
        if On("autoTurnIn") then
            local n = GetNumQuestChoices and GetNumQuestChoices() or 0
            if n <= 1 then
                GetQuestReward(n == 1 and 1 or 0)
            else
                Print(L("Mehrere Belohnungen – bitte selbst wählen."))
            end
        end
    elseif event == "MERCHANT_SHOW" then
        if On("autoSellGrey") then pcall(SellGrey) end
        if On("autoRepair") then pcall(Repair) end
    end
end)
