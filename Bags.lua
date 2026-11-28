-- Levelmate: Quest-Gegenstaende in den Taschen, die du nicht mehr brauchst
-- Ein Quest-Gegenstand gilt als "kann weg", wenn ihn keine Quest in deinem Log
-- braucht, er keine Quest startet, die du noch machen kannst, und alle Quests,
-- zu denen er gehoert, erledigt sind (oder nicht fuer deine Klasse/dein Volk).
-- Fehlen Daten (z. B. neue Forever-Quests), sagt Levelmate lieber nichts.

Levelmate = Levelmate or {}
local L = Levelmate.L or function(s) return s end
local B = {}
Levelmate.Bags = B

local function Print(msg)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLevelmate|r: " .. msg) end
end

local function Done(id)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok, v = pcall(C_QuestLog.IsQuestFlaggedCompleted, id)
        if ok then return v == true end
    end
    return false
end

local function Band(a, b)
    if bit and bit.band then return bit.band(a, b) end
    local r, p = 0, 1
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then r = r + p end
        a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
    end
    return r
end
-- Kann dein Charakter die Quest ueberhaupt bekommen?
local function ForMe(id)
    local DB = Levelmate.DB
    local q = DB.Quest and DB.Quest(id)
    if not q then return false end
    local _, _, raceID = UnitRace("player")
    local _, _, classID = UnitClass("player")
    local races, classes = q.requiredRaces, q.requiredClasses
    if races and races > 0 and raceID and Band(races, 2 ^ (raceID - 1)) == 0 then return false end
    if classes and classes > 0 and classID and Band(classes, 2 ^ (classID - 1)) == 0 then return false end
    return true
end

local function InLog()
    local set = {}
    local Q = Levelmate.Quests
    for _, lq in ipairs(Q and Q.GetList and Q.GetList() or {}) do set[lq.questID] = true end
    return set
end

--- Zustand eines Gegenstands: "need" (mit Quest), "starts", "maybe", "junk" oder nil (kein Quest-Gegenstand / unbekannt)
function B.Status(itemID, log)
    if not itemID then return nil end
    local DB = Levelmate.DB
    if not (DB and DB.Available and DB.Available() and DB.ItemQuests) then return nil end
    local _, _, _, _, _, classID = (C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant)(itemID)
    if DB.ItemIndexReady and not DB.ItemIndexReady() then
        DB.BuildItemIndex(function()
            if B.SoonBags then B.SoonBags() end
            if B.RefreshBaganator then B.RefreshBaganator() end
        end)
        return nil
    end
    local related, start, known = DB.ItemQuests(itemID)
    if not known then return nil end
    -- nur echte Quest-Gegenstaende (z. B. kein Wasser, das auch fuer eine Quest zaehlt)
    if classID ~= 12 and not start then return nil end
    log = log or InLog()
    for _, id in ipairs(related) do
        if log[id] then return "need", id end
    end
    if start and log[start] then return "need", start end
    if start and not Done(start) and ForMe(start) then return "starts", start end
    if #related == 0 and not start then return nil end      -- keine Daten: lieber nichts sagen
    for _, id in ipairs(related) do
        if not Done(id) and ForMe(id) then return "maybe", id end
    end
    return "junk"
end

--- Alle Gegenstaende in den Taschen, die weg koennen: { {itemID, bag, slot, link} }
function B.Junk()
    local CC = C_Container
    local numSlots = (CC and CC.GetContainerNumSlots) or GetContainerNumSlots
    local out, seen, log = {}, {}, InLog()
    if not numSlots then return out end
    for bag = 0, 4 do
        for slot = 1, (numSlots(bag) or 0) do
            local id, link
            if CC and CC.GetContainerItemInfo then
                local info = CC.GetContainerItemInfo(bag, slot)
                if info then id, link = info.itemID, info.hyperlink end
            elseif GetContainerItemID then
                id = GetContainerItemID(bag, slot); link = GetContainerItemLink and GetContainerItemLink(bag, slot)
            end
            if id and not seen[id] then
                seen[id] = true
                local ok, st = pcall(B.Status, id, log)
                if ok and st == "junk" then out[#out + 1] = { itemID = id, bag = bag, slot = slot, link = link } end
            end
        end
    end
    return out
end

function B.Command()
    local list = B.Junk()
    if #list == 0 then
        Print(L("Keine überflüssigen Quest-Gegenstände in deinen Taschen."))
        return
    end
    local links = {}
    for _, e in ipairs(list) do links[#links + 1] = e.link or ("item:" .. e.itemID) end
    Print(string.format(L("Diese Quest-Gegenstände brauchst du nicht mehr (kann weg): %s"), table.concat(links, ", ")))
end

---------------------------------------------------------------------------
-- Tooltip: eine Zeile bei Quest-Gegenstaenden
---------------------------------------------------------------------------
local LINES = {
    need = "|cff40ff40Levelmate: wird für eine Quest in deinem Log gebraucht|r",
    junk = "|cff9d9d9dLevelmate: wird für keine Quest mehr gebraucht – kann weg|r",
    starts = "|cffffd100Levelmate: startet eine Quest – behalten|r",
    maybe = "|cffaaaaaaLevelmate: gehört zu einer Quest, die du noch machen kannst|r",
}
local function OnItem(tt)
    if Levelmate_DB and Levelmate_DB.bagHint == false then return end
    local _, link = tt:GetItem()
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return end
    local ok, st = pcall(B.Status, id)
    if ok and st and LINES[st] then tt:AddLine(L(LINES[st])) end
end
-- Neuere Clients: TooltipDataProcessor; aeltere: OnTooltipSetItem (nur eins von beiden)
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt)
        if tt == GameTooltip then OnItem(tt) end
    end)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", OnItem)
end

---------------------------------------------------------------------------
-- Nach dem Abgeben: kurzer Hinweis, wenn ein Gegenstand uebrig bleibt
---------------------------------------------------------------------------
local told = {}
local f = CreateFrame("Frame")
pcall(f.RegisterEvent, f, "QUEST_TURNED_IN")
f:SetScript("OnEvent", function()
    if Levelmate_DB and Levelmate_DB.bagHint == false then return end
    local function Check()
        local new = {}
        for _, e in ipairs(B.Junk()) do
            if not told[e.itemID] then told[e.itemID] = true; new[#new + 1] = e.link or ("item:" .. e.itemID) end
        end
        if #new > 0 then
            Print(string.format(L("Wird nicht mehr gebraucht (kann weg): %s"), table.concat(new, ", ")))
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(2, function() pcall(Check) end) else pcall(Check) end
end)

---------------------------------------------------------------------------
-- Markierung direkt in den Taschen (Blizzard-Taschen)
--   kann weg:            graues X oben links
--   startet Quest:       gelbes Ausrufezeichen
--   fuer Quest im Log:   gruener Haken
--   Quest noch offen:    graues Fragezeichen
---------------------------------------------------------------------------
local ICONS = {
    junk = { tex = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", size = 14 },
    starts = { tex = "Interface\\GossipFrame\\AvailableQuestIcon", size = 14 },
    need = { tex = "Interface\\RAIDFRAME\\ReadyCheck-Ready", size = 12 },
    maybe = { tex = "Interface\\GossipFrame\\ActiveQuestIcon", size = 12, grey = true },
}
local overlays = {}
local function Overlay(btn)
    local o = overlays[btn]
    if not o then
        o = btn:CreateTexture(nil, "OVERLAY", nil, 7)
        o:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
        overlays[btn] = o
    end
    return o
end

local function ItemAt(bag, slot)
    local CC = C_Container
    if CC and CC.GetContainerItemInfo then
        local info = CC.GetContainerItemInfo(bag, slot)
        return info and info.itemID
    end
    return GetContainerItemID and GetContainerItemID(bag, slot)
end

local function MarkButton(btn, bag, log)
    if not (btn and btn.IsShown and btn:IsShown()) then return end
    local slot = btn.GetID and btn:GetID()
    bag = (btn.GetBagID and btn:GetBagID()) or bag
    local st
    if (not Levelmate_DB or Levelmate_DB.bagHint ~= false) and bag and slot then
        local id = ItemAt(bag, slot)
        if id then
            local ok, s = pcall(B.Status, id, log)
            st = ok and s or nil
        end
    end
    local icon = st and ICONS[st]
    if icon then
        local o = Overlay(btn)
        o:SetTexture(icon.tex)
        o:SetSize(icon.size, icon.size)
        if o.SetDesaturated then o:SetDesaturated(icon.grey and true or false) end
        o:SetAlpha(icon.grey and 0.7 or 1)
        o:Show()
    elseif overlays[btn] then
        overlays[btn]:Hide()
    end
end

-- Knoepfe eines Taschenfensters (neuere Clients: EnumerateValidItems, sonst Namen)
local function Each(f, fn)
    if f.EnumerateValidItems then
        local ok, iter, st, ctl = pcall(f.EnumerateValidItems, f)
        if ok and type(iter) == "function" then
            for _, btn in iter, st, ctl do fn(btn) end
            return
        end
    end
    local name = f.GetName and f:GetName()
    if name then for j = 1, 36 do local b = _G[name .. "Item" .. j]; if b then fn(b) end end end
end

function B.UpdateBagFrames()
    local log = InLog()
    for i = 1, 13 do
        local f = _G["ContainerFrame" .. i]
        if f and f.IsShown and f:IsShown() then
            local bag = f.GetID and f:GetID()
            Each(f, function(btn) MarkButton(btn, bag, log) end)
        end
    end
    local comb = rawget(_G, "ContainerFrameCombinedBags")
    if comb and comb.IsShown and comb:IsShown() then
        Each(comb, function(btn) MarkButton(btn, nil, log) end)
    end
end

local pendingBags = false
local function SoonBags()
    if pendingBags then return end
    pendingBags = true
    local function Go() pendingBags = false; pcall(B.UpdateBagFrames) end
    if C_Timer and C_Timer.After then C_Timer.After(0.1, Go) else Go() end
end
B.SoonBags = SoonBags

local fb = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "BAG_OPEN" }) do
    pcall(fb.RegisterEvent, fb, e)
end
fb:SetScript("OnEvent", SoonBags)
if hooksecurefunc then
    if ContainerFrame_Update then pcall(hooksecurefunc, "ContainerFrame_Update", SoonBags) end
    if ToggleBag then pcall(hooksecurefunc, "ToggleBag", SoonBags) end
    if OpenAllBags then pcall(hooksecurefunc, "OpenAllBags", SoonBags) end
    if ToggleBackpack then pcall(hooksecurefunc, "ToggleBackpack", SoonBags) end
end
for i = 1, 13 do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then pcall(f.HookScript, f, "OnShow", SoonBags) end
end

---------------------------------------------------------------------------
-- Baganator: eigenes Ecken-Symbol (in Baganators Einstellungen unter
-- "Symbol-Ecken" frei verschiebbar), Standard oben links
---------------------------------------------------------------------------
local baganatorDone = false
local function RegisterBaganator()
    if baganatorDone then return end
    local BG = rawget(_G, "Baganator")
    if not (BG and BG.API and BG.API.RegisterCornerWidget) then return end
    baganatorDone = true
    pcall(BG.API.RegisterCornerWidget, L("Levelmate: Quest-Gegenstände"), "levelmate_questitems",
        function(tex, details)
            if Levelmate_DB and Levelmate_DB.bagHint == false then return false end
            local id = details and (details.itemID or (details.itemLink and tonumber(details.itemLink:match("item:(%d+)"))))
            if not id then return nil end
            local ok, st = pcall(B.Status, id)
            local icon = ok and st and ICONS[st]
            if not icon then return false end
            tex:SetTexture(icon.tex)
            tex:SetSize(icon.size, icon.size)
            if tex.SetDesaturated then tex:SetDesaturated(icon.grey and true or false) end
            tex:SetAlpha(icon.grey and 0.7 or 1)
            return true
        end,
        function(itemButton)
            local t = itemButton:CreateTexture(nil, "OVERLAY")
            t:SetSize(14, 14)
            return t
        end,
        { corner = "top_left", priority = 1 })
    local function Refresh()
        if BG.API.RequestItemButtonsRefresh then pcall(BG.API.RequestItemButtonsRefresh) end
    end
    local fr = CreateFrame("Frame")
    for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_TURNED_IN" }) do pcall(fr.RegisterEvent, fr, e) end
    local pend = false
    fr:SetScript("OnEvent", function()
        if pend then return end
        pend = true
        if C_Timer and C_Timer.After then C_Timer.After(1, function() pend = false; Refresh() end) else pend = false; Refresh() end
    end)
    B.RefreshBaganator = Refresh
end
RegisterBaganator()
local fl = CreateFrame("Frame")
pcall(fl.RegisterEvent, fl, "ADDON_LOADED")
pcall(fl.RegisterEvent, fl, "PLAYER_LOGIN")
fl:SetScript("OnEvent", function() RegisterBaganator() end)
