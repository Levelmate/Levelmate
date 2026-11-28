-- Levelmate: beste Questbelohnung fuer deine Klasse hervorheben
-- Bei mehreren Belohnungen zur Auswahl (Quest annehmen und abgeben) markiert
-- Levelmate die Belohnung, die fuer deine Klasse die groesste Verbesserung
-- gegenueber deiner angelegten Ausruestung ist. Ist nichts davon eine
-- Verbesserung, wird die Belohnung mit dem hoechsten Verkaufswert markiert.

Levelmate = Levelmate or {}
local L = Levelmate.L or function(s) return s end
local R = {}
Levelmate.Rewards = R

-- Gewichte fuers Leveln (grob, je Klasse)
local W = {
    WARRIOR = { STR = 1, AGI = 0.7, STA = 0.6, ARMOR = 0.02, DPS = 3, AP = 0.5 },
    PALADIN = { STR = 1, STA = 0.6, INT = 0.4, AGI = 0.3, ARMOR = 0.02, DPS = 3, AP = 0.5, SP = 0.5 },
    ROGUE   = { AGI = 1, STR = 0.5, STA = 0.5, ARMOR = 0.01, DPS = 3, AP = 0.5 },
    HUNTER  = { AGI = 1, INT = 0.3, STA = 0.5, ARMOR = 0.01, DPS = 1, RDPS = 3, AP = 0.4 },
    SHAMAN  = { STR = 0.8, INT = 0.6, AGI = 0.4, STA = 0.5, ARMOR = 0.015, DPS = 2.5, SP = 0.6, AP = 0.4 },
    DRUID   = { STR = 0.6, AGI = 0.7, INT = 0.6, STA = 0.5, SPI = 0.3, ARMOR = 0.01, DPS = 1, AP = 0.5, SP = 0.5 },
    MAGE    = { INT = 1, SPI = 0.5, STA = 0.5, SP = 1, ARMOR = 0.005, DPS = 0.2 },
    PRIEST  = { INT = 0.9, SPI = 0.7, STA = 0.5, SP = 1, ARMOR = 0.005, DPS = 0.2 },
    WARLOCK = { INT = 0.8, STA = 0.7, SPI = 0.4, SP = 1, ARMOR = 0.005, DPS = 0.2 },
}
local STATKEY = {
    ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
    ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI", RESISTANCE0_NAME = "ARMOR",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS", ITEM_MOD_ATTACK_POWER_SHORT = "AP",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "AP", ITEM_MOD_SPELL_POWER_SHORT = "SP",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "SP",
}
local SLOTS = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 }, INVTYPE_CHEST = { 5 },
    INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16 }, INVTYPE_2HWEAPON = { 16 }, INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_WEAPONOFFHAND = { 17 }, INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}
local NOARMORTYPE = { INVTYPE_CLOAK = true, INVTYPE_NECK = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true }

-- Heiler-Gewichte (Priester, Druide, Schamane, Paladin mit Heil-Talentbaum)
local HEALER = {
    PRIEST  = { INT = 0.8, SPI = 0.8, STA = 0.4, HEAL = 1, SP = 0.9, MP5 = 2, SCRIT = 6, ARMOR = 0.005 },
    DRUID   = { INT = 0.8, SPI = 0.6, STA = 0.4, HEAL = 1, SP = 0.9, MP5 = 2, SCRIT = 6, ARMOR = 0.005 },
    SHAMAN  = { INT = 0.8, SPI = 0.3, STA = 0.4, HEAL = 1, SP = 0.9, MP5 = 2, SCRIT = 6, ARMOR = 0.01 },
    PALADIN = { INT = 0.9, SPI = 0.2, STA = 0.4, HEAL = 1, SP = 0.9, MP5 = 2, SCRIT = 6, ARMOR = 0.01 },
}
-- Weitere Gewichte fuer Anlege-Effekte (Werte je Punkt bzw. je 1 %)
local EXTRA = {
    WARRIOR = { CRIT = 10, HIT = 8 }, PALADIN = { CRIT = 9, HIT = 7, MP5 = 1 },
    ROGUE = { CRIT = 10, HIT = 9 }, HUNTER = { CRIT = 10, HIT = 8, MP5 = 0.5 },
    SHAMAN = { CRIT = 8, HIT = 6, SCRIT = 5, MP5 = 1 }, DRUID = { CRIT = 8, HIT = 6, SCRIT = 5, MP5 = 1 },
    MAGE = { SCRIT = 8, SHIT = 7, MP5 = 1 }, PRIEST = { SCRIT = 7, SHIT = 5, MP5 = 1.5 },
    WARLOCK = { SCRIT = 7, SHIT = 7, MP5 = 1 },
}
for cls, e in pairs(EXTRA) do for k, v in pairs(e) do W[cls][k] = W[cls][k] or v end end
for _, w in pairs(W) do w.HEAL = w.HEAL or (w.SP and 0.1) or 0 end

-- Heilst du? Talentbaum mit den meisten Punkten (Klassik: GetTalentTabInfo)
local HEALTREE = { PRIEST = { [1] = true, [2] = true }, DRUID = { [3] = true }, SHAMAN = { [3] = true }, PALADIN = { [1] = true } }
local function IsHealer(cls)
    local pref = Levelmate_DB and Levelmate_DB.rewardRole
    if pref == "heal" then return HEALER[cls] ~= nil end
    if pref == "dps" then return false end
    if not (HEALTREE[cls] and GetTalentTabInfo) then return false end
    local best, bestPts = nil, 0
    for i = 1, 3 do
        local ok, a, b, c, d = pcall(GetTalentTabInfo, i)
        local pts = ok and (type(c) == "number" and c or type(d) == "number" and d) or 0
        if pts > bestPts then best, bestPts = i, pts end
    end
    return best ~= nil and bestPts >= 5 and HEALTREE[cls][best] == true
end

-- Anlege-Effekte aus dem Tooltip lesen (Zauberschaden, Heilung, Angriffskraft,
-- kritische Treffer, Trefferchance, Mana alle 5 Sek.) - Englisch und Deutsch
local SCHOOLS = {
    SHADOW = { "shadow", "schatten" }, FIRE = { "fire", "feuer" }, FROST = { "frost" },
    ARCANE = { "arcane", "arkan" }, NATURE = { "nature", "natur" }, HOLY = { "holy", "heilig" },
}
-- Wert einer Zauberschule je Klasse (Anteil eines Punkts "Zauberschaden")
local SCHOOLW = {
    WARLOCK = { SHADOW = 1, FIRE = 0.6 },
    MAGE = { FROST = 0.9, FIRE = 0.9, ARCANE = 0.5 },
    PRIEST = { SHADOW = 0.9, HOLY = 0.3 },
    DRUID = { NATURE = 0.7, ARCANE = 0.6 },
    SHAMAN = { NATURE = 0.7, FIRE = 0.5, FROST = 0.4 },
    PALADIN = { HOLY = 0.6 },
    HUNTER = { ARCANE = 0.2, NATURE = 0.1 },
}
local scan, effCache = nil, {}
local function Lower(s) return (s or ""):lower() end
local function Effects(link)
    if effCache[link] then return effCache[link] end
    local out = {}
    if not scan then
        scan = CreateFrame("GameTooltip", "LevelmateScanTip", nil, "GameTooltipTemplate")
    end
    if not (scan and scan.SetHyperlink) then return out end
    scan:SetOwner(WorldFrame or UIParent, "ANCHOR_NONE")
    scan:ClearLines()
    local ok = pcall(scan.SetHyperlink, scan, link)
    if not ok then return out end
    local equip = Lower(ITEM_SPELL_TRIGGER_ONEQUIP or "Equip:")
    for i = 2, (scan.NumLines and scan:NumLines() or 0) do
        local fs = _G["LevelmateScanTipTextLeft" .. i]
        local t = Lower(fs and fs:GetText())
        local n = tonumber(t:match("(%d+)"))
        if n and (t:find(equip, 1, true) or t:find("equip:", 1, true) or t:find("anlegen:", 1, true)) then
            local heal = t:find("heal") or t:find("heilung")
            local dmg = t:find("damage") or t:find("schaden")
            local spell = t:find("spell") or t:find("zauber") or t:find("magi")
            if t:find("attack power") or t:find("angriffskraft") then out.AP = (out.AP or 0) + n
            elseif t:find("mana") and (t:find("5 sec") or t:find("5 sek")) then out.MP5 = (out.MP5 or 0) + n
            elseif t:find("critical") or t:find("kritisch") then
                if spell then out.SCRIT = (out.SCRIT or 0) + n else out.CRIT = (out.CRIT or 0) + n end
            elseif t:find("to hit") or t:find("trefferchance") then
                if spell then out.SHIT = (out.SHIT or 0) + n else out.HIT = (out.HIT or 0) + n end
            elseif heal and dmg then out.SP = (out.SP or 0) + n
            elseif heal then out.HEAL = (out.HEAL or 0) + n
            elseif dmg then
                -- eine Zauberschule (z. B. Schattenschaden): je nach Klasse unterschiedlich viel wert
                local school
                for key, words in pairs(SCHOOLS) do
                    for _, wd in ipairs(words) do if t:find(wd, 1, true) then school = key; break end end
                    if school then break end
                end
                if school then out["SP_" .. school] = (out["SP_" .. school] or 0) + n
                elseif spell then out.SP = (out.SP or 0) + n * 0.7 end
            end
        end
    end
    scan:Hide()
    effCache[link] = out
    return out
end

local function Class() local _, c = UnitClass("player"); return c end
-- Beste Ruestungsart: 1 Stoff, 2 Leder, 3 Kette, 4 Platte
local function BestArmor(cls, level)
    if cls == "WARRIOR" or cls == "PALADIN" then return level >= 40 and 4 or 3 end
    if cls == "HUNTER" or cls == "SHAMAN" then return level >= 40 and 3 or 2 end
    if cls == "ROGUE" or cls == "DRUID" then return 2 end
    return 1
end

local function Stats(link)
    local fn = (C_Item and C_Item.GetItemStats) or GetItemStats
    if not (fn and link) then return {} end
    local ok, t = pcall(fn, link)
    return ok and t or {}
end

-- Wert eines Gegenstands fuer deine Klasse (nil = Daten noch nicht geladen)
local function Score(link, cls, level)
    if not link then return 0 end
    local _, _, _, _, _, _, _, _, loc, _, _, classID, subID = GetItemInfo(link)
    if not loc then return nil end
    local w = (IsHealer(cls) and HEALER[cls]) or W[cls] or W.WARRIOR
    local s = 0
    local fromStats = {}
    for k, v in pairs(Stats(link)) do
        local key = STATKEY[k]
        if key then fromStats[key] = true end
        if key == "DPS" and (loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" or loc == "INVTYPE_THROWN") and w.RDPS then
            s = s + v * w.RDPS
        elseif key and w[key] then
            s = s + v * w[key]
        end
    end
    -- Anlege-Effekte (nur, was GetItemStats nicht schon geliefert hat)
    for key, v in pairs(Effects(link)) do
        local school = key:match("^SP_(%u+)$")
        if school then
            local sw = SCHOOLW[cls] and SCHOOLW[cls][school] or 0
            s = s + v * sw * (w.SP or 0)
        elseif not fromStats[key] and w[key] then
            s = s + v * w[key]
        end
    end
    if classID == 4 and subID and subID >= 1 and subID <= 4 and not NOARMORTYPE[loc] then
        if subID < BestArmor(cls, level) then s = s * 0.6 end
    end
    return s
end

-- GearQuest Forever installiert? Dann dessen Bewertung nutzen: sie kennt deine
-- gewaehlte Spezialisierung und genauere Gewichte. (Nur zur Laufzeit gelesen.)
local function GQScore(link, loc)
    local GQ = rawget(_G, "GearQuest")
    if not (Levelmate_DB and Levelmate_DB.useGearQuest == false) and type(GQ) == "table"
       and type(GQ.Compare) == "table" and GQ.Compare.ScoreItemLinkStats then
        local ranged = loc == "INVTYPE_RANGED" or loc == "INVTYPE_RANGEDRIGHT" or loc == "INVTYPE_THROWN"
        local ok, v = pcall(GQ.Compare.ScoreItemLinkStats, GQ.Compare, link, ranged and "Ranged" or "Weapon")
        if ok and type(v) == "number" then return v end
    end
end
R.UsingGearQuest = function() return GQScore("item:6948", "INVTYPE_HEAD") ~= nil end

local ScoreOwn = Score
Score = function(link, cls, level)
    if not link then return 0 end
    local loc = select(9, GetItemInfo(link))
    if not loc then return nil end
    local v = GQScore(link, loc)
    if v ~= nil then return v end
    return ScoreOwn(link, cls, level)
end

local function EquippedScore(slots, cls, level, loc)
    local worst
    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        local v = link and Score(link, cls, level) or 0
        if loc == "INVTYPE_2HWEAPON" then
            local off = GetInventoryItemLink("player", 17)
            v = v + (off and (Score(off, cls, level) or 0) or 0)
        end
        if not worst or v < worst then worst = v end
    end
    return worst or 0
end

--- Beste Wahl unter den Belohnungen: index, Art ("upgrade"/"gold"), Gegenstands-Link
function R.Best(kind)
    kind = kind or "choice"
    local n = GetNumQuestChoices and GetNumQuestChoices() or 0
    if n < 2 then return nil end
    local cls, level = Class(), UnitLevel("player") or 1
    local best, bestGain, richest, richestPrice, missing = nil, 0, nil, -1, false
    for i = 1, n do
        local _, _, _, _, usable = GetQuestItemInfo(kind, i)
        local link = GetQuestItemLink(kind, i)
        local info = link and { GetItemInfo(link) }
        if not (info and info[9]) then
            missing = true
        else
            local price = info[11] or 0
            if price > richestPrice then richest, richestPrice = i, price end
            local slots = SLOTS[info[9]]
            if usable ~= false and slots then
                local sNew = Score(link, cls, level)
                if sNew then
                    local gain = sNew - EquippedScore(slots, cls, level, info[9])
                    if gain > bestGain + 0.01 then best, bestGain = i, gain end
                end
            end
        end
    end
    if missing then return nil, "loading" end
    if best then return best, "upgrade", GetQuestItemLink(kind, best) end
    if richest then return richest, "gold", GetQuestItemLink(kind, richest) end
end

---------------------------------------------------------------------------
-- Anzeige: goldener Rahmen um die beste Belohnung
---------------------------------------------------------------------------
local mark
local function Button(i)
    if QuestInfo_GetRewardButton and QuestInfoRewardsFrame then
        local ok, b = pcall(QuestInfo_GetRewardButton, QuestInfoRewardsFrame, i)
        if ok and b then return b end
    end
    return _G["QuestInfoRewardsFrameQuestInfoItem" .. i] or _G["QuestInfoItem" .. i]
end
local function Hide() if mark then mark:Hide() end end

local markWhy
local hooked = {}
local function TipLine(why)
    if why == "upgrade" then
        return L("|cffffd100Levelmate: beste Wahl für dich|r")
    end
    return L("|cffb0b0b0Levelmate: keine Verbesserung dabei – diese bringt am meisten Gold|r")
end

local function Show(i, why)
    local b = Button(i)
    if not (b and b.IsShown and b:IsShown()) then return false end
    local icon = b.Icon or (b.GetName and b:GetName() and _G[b:GetName() .. "IconTexture"]) or b
    if not mark then
        mark = CreateFrame("Frame", nil, UIParent)
        -- feiner goldener Rahmen um das Symbol
        mark.lines = {}
        for k = 1, 4 do
            local t = mark:CreateTexture(nil, "OVERLAY")
            t:SetColorTexture(1, 0.82, 0.2, 1)
            mark.lines[k] = t
        end
        mark.lines[1]:SetPoint("TOPLEFT", -2, 2); mark.lines[1]:SetPoint("TOPRIGHT", 2, 2); mark.lines[1]:SetHeight(2)
        mark.lines[2]:SetPoint("BOTTOMLEFT", -2, -2); mark.lines[2]:SetPoint("BOTTOMRIGHT", 2, -2); mark.lines[2]:SetHeight(2)
        mark.lines[3]:SetPoint("TOPLEFT", -2, 2); mark.lines[3]:SetPoint("BOTTOMLEFT", -2, -2); mark.lines[3]:SetWidth(2)
        mark.lines[4]:SetPoint("TOPRIGHT", 2, 2); mark.lines[4]:SetPoint("BOTTOMRIGHT", 2, -2); mark.lines[4]:SetWidth(2)
        -- kleines Abzeichen oben links (Levelmate-Logo bzw. Goldmuenze), Tooltip beim Drueberfahren
        local badge = CreateFrame("Frame", nil, mark)
        badge:SetSize(16, 16)
        badge:SetPoint("CENTER", mark, "TOPLEFT", 4, -4)
        badge:EnableMouse(true)
        badge.tex = badge:CreateTexture(nil, "OVERLAY", nil, 7)
        badge.tex:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(TipLine(markWhy))
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
        mark.badge = badge
    end
    markWhy = why
    mark:SetParent(b)
    mark:SetFrameLevel((b.GetFrameLevel and b:GetFrameLevel() or 1) + 5)
    mark:ClearAllPoints()
    mark:SetAllPoints(icon)
    local up = why == "upgrade"
    for _, t in ipairs(mark.lines) do t:SetShown(up) end
    if up then
        mark.badge.tex:SetTexture("Interface\\AddOns\\Levelmate\\Media\\Logo")
        mark.badge:SetSize(15, 15)
    else
        mark.badge.tex:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
        mark.badge:SetSize(11, 11)
    end
    -- auch im normalen Gegenstands-Tooltip eine Zeile
    if not hooked[b] and b.HookScript then
        hooked[b] = true
        b:HookScript("OnEnter", function(self)
            if mark and mark:IsShown() and mark:GetParent() == self and GameTooltip:IsShown() then
                GameTooltip:AddLine(TipLine(markWhy))
                GameTooltip:Show()
            end
        end)
    end
    mark:Show()
    return true
end

local function Update(kind, tries)
    tries = tries or 0
    if Levelmate_DB and Levelmate_DB.rewardHint == false then Hide(); return end
    local i, why, link = R.Best(kind)
    if why == "loading" and tries < 8 then
        if C_Timer then C_Timer.After(0.25, function() Update(kind, tries + 1) end) end
        return
    end
    if not i then Hide(); return end
    if not Show(i, why) and tries < 4 and C_Timer then
        C_Timer.After(0.1, function() Update(kind, tries + 1) end)
        return
    end
    if kind == "choice" and DEFAULT_CHAT_FRAME and link then
        local msg = why == "upgrade" and L("Beste Belohnung für dich: %s") or L("Keine echte Verbesserung dabei – am meisten Gold bringt: %s")
        local via = (why == "upgrade" and R.UsingGearQuest()) and L(" (bewertet mit GearQuest)") or ""
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLevelmate|r: " .. string.format(msg, link) .. via)
    end
end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_FINISHED" }) do pcall(f.RegisterEvent, f, ev) end
local lastSaid
f:SetScript("OnEvent", function(_, event)
    if event == "QUEST_FINISHED" then Hide(); return end
    -- Chatzeile nur einmal je Quest, Rahmen immer
    local id = GetQuestID and GetQuestID()
    local say = (event == "QUEST_COMPLETE") and lastSaid ~= id
    if say then lastSaid = id end
    if C_Timer then
        C_Timer.After(0.05, function() Update(say and "choice" or "choice-silent") end)
    end
end)

-- "choice-silent": gleiche Auswertung, ohne Chatzeile
local origBest = R.Best
R.Best = function(kind) return origBest(kind == "choice-silent" and "choice" or kind) end
