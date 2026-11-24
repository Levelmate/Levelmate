-- Extras.lua (1.1.0)
-- Kleine Komfort-Sachen rund um das Hauptfenster:
--   * Einfuehrung (Tipps beim ersten Start, /lm tipps)
--   * Meldung beim Stufenaufstieg
--   * Rueckblick auf die letzte Sitzung (/lm sitzung)
--   * Levelmate-Zeile im Tooltip von NPCs
--   * Gruppenfenster (/lm gruppe fenster)
-- Alles laeuft in pcall: ein Fehler hier darf das Addon nie stoeren.
Levelmate = Levelmate or {}
local L = Levelmate.L or function(s) return s end
local GOLD = { 0.95, 0.76, 0.31 }

local function DB() Levelmate_DB = Levelmate_DB or {}; return Levelmate_DB end
local function CharDB() Levelmate_CharDB = Levelmate_CharDB or {}; return Levelmate_CharDB end
local function Print(msg)
    if Levelmate.Print then Levelmate.Print(msg) elseif DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("Levelmate: " .. tostring(msg)) end
end
local function Safe(fn, ...) local ok, a, b = pcall(fn, ...); if ok then return a, b end end

-- Einheitlicher Fensterstil wie das Hauptfenster
local function StyledFrame(name, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    f:SetBackdropColor(0.035, 0.055, 0.12, 0.92)
    f:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) if not DB().locked then self:StartMoving() end end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 10, -9)
    f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", 1, 1)
    f.close = close
    f:Hide()
    return f
end

local function FormatDuration(sec)
    sec = math.max(0, math.floor(sec or 0))
    local h, m = math.floor(sec / 3600), math.floor((sec % 3600) / 60)
    if h > 0 then return string.format(L("%d Std. %d Min."), h, m) end
    return string.format(L("%d Min."), m)
end

---------------------------------------------------------------------------
-- 1) Einfuehrung
---------------------------------------------------------------------------
local TIPS = {
    { "Willkommen bei Levelmate!",
      "Levelmate plant für dich die Quests in einer sinnvollen Reihenfolge – von Stufe 1 bis 60. Oben im Fenster steht immer der nächste Schritt, darunter die folgenden Schritte nach Gebiet geordnet." },
    { "Zielpfeil und Karte",
      "Der Pfeil zeigt dir den Weg zum aktuellen Ziel. Auf der Weltkarte siehst du die nächsten Schritte als nummerierte Punkte (1, 2, 3 …)." },
    { "Fenster anpassen",
      "Mit dem Minus-Knopf oben klappst du Levelmate auf die Karte mit dem aktuellen Schritt zusammen. Das Schloss sperrt alle Fenster gegen versehentliches Verschieben. Größe und Hintergrund stellst du in den Optionen unter „Anzeige“ ein." },
    { "Befehle und Optionen",
      "/lm optionen öffnet die Einstellungen, /lm hilfe zeigt alle Befehle. Spielst du in einer Gruppe mit anderen Levelmate-Nutzern, bevorzugt Levelmate gemeinsame Quests (/lm gruppe). Viel Spaß beim Leveln!" },
}

local tips
local function BuildTips()
    tips = StyledFrame("LevelmateTipsFrame", 340, 170)
    tips:SetPoint("CENTER", 0, 120)
    tips.body = tips:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    tips.body:SetPoint("TOPLEFT", 12, -32)
    tips.body:SetPoint("TOPRIGHT", -12, -32)
    tips.body:SetJustifyH("LEFT")
    tips.body:SetJustifyV("TOP")
    tips.body:SetSpacing(2)
    tips.page = tips:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tips.page:SetPoint("BOTTOMLEFT", 12, 12)
    tips.next = CreateFrame("Button", nil, tips, "UIPanelButtonTemplate")
    tips.next:SetSize(90, 22)
    tips.next:SetPoint("BOTTOMRIGHT", -10, 8)
    tips.back = CreateFrame("Button", nil, tips, "UIPanelButtonTemplate")
    tips.back:SetSize(70, 22)
    tips.back:SetPoint("RIGHT", tips.next, "LEFT", -6, 0)
    tips.back:SetText(L("Zurück"))
    local function Show(i)
        tips.index = i
        local t = TIPS[i]
        tips.title:SetText(L(t[1]))
        tips.body:SetText(L(t[2]))
        tips.page:SetText(string.format(L("Tipp %d von %d"), i, #TIPS))
        tips.next:SetText(i < #TIPS and L("Weiter") or L("Los geht's"))
        tips.back:SetShown(i > 1)
        local h = (tips.body:GetStringHeight() or 60) + 80
        tips:SetHeight(math.max(140, h))
    end
    tips.ShowPage = Show
    tips.next:SetScript("OnClick", function()
        if tips.index < #TIPS then Show(tips.index + 1) else tips:Hide() end
    end)
    tips.back:SetScript("OnClick", function() if tips.index > 1 then Show(tips.index - 1) end end)
    tips:SetScript("OnHide", function() DB().tipsSeen = true end)
end

function Levelmate.ShowTips(force)
    if not force and DB().tipsSeen then return end
    if not tips then BuildTips() end
    tips:Show()
    tips.ShowPage(1)
end

---------------------------------------------------------------------------
-- 2) Meldung beim Stufenaufstieg
---------------------------------------------------------------------------
local toast
local function BuildToast()
    toast = CreateFrame("Frame", "LevelmateLevelToast", UIParent, "BackdropTemplate")
    toast:SetSize(320, 80)
    toast:SetPoint("TOP", 0, -150)
    toast:SetFrameStrata("HIGH")
    toast:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8X8", edgeFile = "Interface/Buttons/WHITE8X8", edgeSize = 1 })
    toast:SetBackdropColor(0.035, 0.055, 0.12, 0.9)
    toast:SetBackdropBorderColor(0.79, 0.60, 0.23, 0.9)
    toast:EnableMouse(true)
    toast:SetScript("OnMouseUp", function(self) self:Hide() end)
    toast.icon = toast:CreateTexture(nil, "ARTWORK")
    toast.icon:SetSize(40, 40)
    toast.icon:SetPoint("LEFT", 12, 0)
    toast.icon:SetTexture("Interface\\AddOns\\Levelmate\\Media\\Logo")
    toast.head = toast:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    toast.head:SetPoint("TOPLEFT", toast.icon, "TOPRIGHT", 10, 2)
    toast.head:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    toast.body = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    toast.body:SetPoint("TOPLEFT", toast.head, "BOTTOMLEFT", 0, -4)
    toast.body:SetPoint("RIGHT", -10, 0)
    toast.body:SetJustifyH("LEFT")
    toast.body:SetSpacing(2)
    toast:Hide()
    toast:SetScript("OnUpdate", function(self, el)
        self.t = (self.t or 0) + el
        if self.t > 9 then
            local a = 1 - (self.t - 9) / 1.5
            if a <= 0 then self:Hide() else self:SetAlpha(a) end
        end
    end)
end

local function ShowLevelToast(level)
    if DB().levelToast == false then return end
    if not toast then BuildToast() end
    local lines = {}
    local n = 0
    local Tr = Levelmate.Trainer
    if Tr and Tr.Learnable then n = Safe(Tr.Learnable) or 0 end
    if type(n) == "number" and n > 0 then
        lines[#lines + 1] = string.format(L("%d neue Fähigkeiten beim Lehrer"), n)
    end
    if Levelmate.Routes and Levelmate.Routes.GetHint then
        local faction = UnitFactionGroup and UnitFactionGroup("player") or "Horde"
        local hint = Safe(Levelmate.Routes.GetHint, faction, level)
        if hint then lines[#lines + 1] = L("Gebiete: ") .. hint end
    end
    if Levelmate.Planner and Levelmate.Planner.Last then
        local plan = Safe(Levelmate.Planner.Last)
        local act = plan and plan.actions and plan.actions[1]
        local q = act and act.c and act.c.q
        if q and q.name then lines[#lines + 1] = L("Weiter mit: ") .. q.name end
    end
    toast.head:SetText(string.format(L("Stufe %d erreicht!"), level))
    toast.body:SetText(table.concat(lines, "\n"))
    toast:SetHeight(math.max(64, (toast.body:GetStringHeight() or 20) + 46))
    toast.t = 0
    toast:SetAlpha(1)
    toast:Show()
end
Levelmate.ShowLevelToast = ShowLevelToast

---------------------------------------------------------------------------
-- 3) Sitzung
---------------------------------------------------------------------------
local session

local function XPNow() return (UnitXP and UnitXP("player")) or 0, (UnitXPMax and UnitXPMax("player")) or 0 end

local function StartSession()
    local xp, max = XPNow()
    local cdb = CharDB()
    local cur = cdb.curSession
    -- /reload oder kurz neu eingeloggt (unter 10 Min.): die Sitzung laeuft weiter
    if cur and cur.stop and (time() - cur.stop) < 600 then
        session = { start = cur.start, level = cur.level, xp = cur.xp or 0, quests = cur.quests or 0, lastXP = xp, lastMax = max }
    else
        if cur and cur.stop and (cur.stop - (cur.start or cur.stop)) >= 300 then cdb.lastSession = cur end
        session = { start = time(), level = UnitLevel("player") or 1, xp = 0, quests = 0, lastXP = xp, lastMax = max }
    end
    cdb.curSession = nil
end

local function TrackXP()
    if not session then return end
    local xp, max = XPNow()
    local d = xp - (session.lastXP or xp)
    if d < 0 then d = (session.lastMax or 0) - (session.lastXP or 0) + xp end   -- Stufenaufstieg
    if d > 0 then session.xp = session.xp + d end
    session.lastXP, session.lastMax = xp, max
end

local function SessionText(s, now)
    local levels = (s.endLevel or UnitLevel("player") or s.level) - (s.level or 0)
    local dur = (s.stop or now or time()) - (s.start or time())
    local perHour = dur > 300 and math.floor((s.xp or 0) / (dur / 3600)) or nil
    local t = string.format(L("%s gespielt, %d Quests abgegeben, %d XP"), FormatDuration(dur), s.quests or 0, s.xp or 0)
    if levels > 0 then t = t .. string.format(L(", +%d Stufe(n)"), levels) end
    if perHour then t = t .. string.format(L(" (%d XP/Std.)"), perHour) end
    return t
end

local function SaveSession()
    if not session then return end
    TrackXP()
    CharDB().curSession = { start = session.start, stop = time(), level = session.level, endLevel = UnitLevel("player"),
                            xp = session.xp, quests = session.quests }
end

local function ShowLastSession()
    if DB().sessionSummary == false then return end
    local s = CharDB().lastSession
    if not s or s.shown then return end
    s.shown = true
    Print(L("Letztes Mal: ") .. SessionText(s))
    local plan = Levelmate.Planner and Levelmate.Planner.Last and Safe(Levelmate.Planner.Last)
    local act = plan and plan.actions and plan.actions[1]
    local q = act and act.c and act.c.q
    if q and q.name then Print(L("Jetzt weiter mit: ") .. q.name) end
end

function Levelmate.SessionCommand()
    if session then Print(L("Diese Sitzung: ") .. SessionText(session, time())) end
    local s = CharDB().lastSession
    if s then Print(L("Letzte Sitzung: ") .. SessionText(s)) end
end

---------------------------------------------------------------------------
-- 4) NPC-Tooltip
---------------------------------------------------------------------------
local KIND_WORD = { ACCEPT = "annehmen", TURNIN = "abgeben", DO = "erledigen" }

-- Gegner, die fuer eine Quest gebraucht werden: Gegnername -> Suchwort im Questziel
-- (Gegnername bei Kill-Zielen, Gegenstandsname bei Drops; nur gezielte Drops mit wenigen Quellen).
local mobNameCache = {}
local function MobNames(questID)
    local c = mobNameCache[questID]
    if c ~= nil then return c or nil end
    local DBm = Levelmate.DB
    local q = DBm.Quest(questID)
    local obj = q and q.objectives
    c = {}
    if obj then
        for _, e in ipairs(obj[1] or {}) do
            local n = DBm.Npc(type(e) == "table" and e[1] or e)
            if n and n.name then c[n.name] = c[n.name] or n.name end
        end
        for _, e in ipairs(obj[3] or {}) do
            local itemId = type(e) == "table" and e[1] or e
            local iname = DBm.ItemName and DBm.ItemName(itemId)
            local ok, src = pcall(DBm.ItemSources, itemId)
            local cnt = 0
            for _, sx in ipairs(ok and src or {}) do if sx.kind == "npc" then cnt = cnt + 1 end end
            if iname and cnt > 0 and cnt <= 12 then
                for _, sx in ipairs(src) do
                    if sx.kind == "npc" then
                        local n = DBm.Npc(sx.id)
                        if n and n.name then c[n.name] = c[n.name] or iname end
                    end
                end
            end
        end
    end
    if not next(c) then c = false end
    mobNameCache[questID] = c
    return c or nil
end

local function TooltipLine(tt)
    if DB().npcTooltip == false then return end
    if Levelmate.InCombat and Levelmate.InCombat() then return end
    local _, unit = tt:GetUnit()
    if not unit then return end
    local name = UnitName(unit)
    if type(name) ~= "string" then return end
    local plan = Levelmate.Planner and Levelmate.Planner.Last and Levelmate.Planner.Last()
    plan = plan or { actions = {} }
    local added, shownQ = 0, {}
    for i = 1, math.min(#plan.actions, 12) do
        local a = plan.actions[i]
        local word = KIND_WORD[a.kind]
        if word and a.targetName == name and a.c and a.c.q then
            shownQ[a.c.q.id] = true
            if added == 0 then tt:AddLine(" ") end
            tt:AddLine(string.format(L("Levelmate: Schritt %d – %s %s"), i, a.c.q.name or "?", L(word)), GOLD[1], GOLD[2], GOLD[3], true)
            added = added + 1
            if added >= 3 then break end
        end
    end
    -- Quests im Log, die bei diesem NPC abgegeben werden (auch wenn noch nicht fertig)
    local DBm = Levelmate.DB
    local list = Levelmate.Quests and Levelmate.Quests.GetList and Levelmate.Quests.GetList() or {}
    for _, lq in ipairs(list) do
        if added >= 4 then break end
        local q = lq.questID and not shownQ[lq.questID] and DBm.Quest(lq.questID)
        local fb = q and q.finishedBy and q.finishedBy[1]
        if fb then
            for _, id in ipairs(fb) do
                local n = DBm.Npc(id)
                if n and n.name == name then
                    local ready = lq.status == "READY"
                    local prog = ""
                    if not ready then
                        local o = lq.objectives and lq.objectives[1]
                        if o and (o.need or 0) > 0 then prog = string.format(" (%d/%d)", o.have or 0, o.need) end
                    end
                    if added == 0 then tt:AddLine(" ") end
                    tt:AddLine(string.format(ready and L("Levelmate: %s hier abgeben – fertig") or L("Levelmate: %s wird hier abgegeben%s"),
                        q.name or "?", prog), GOLD[1], GOLD[2], GOLD[3], true)
                    added = added + 1
                    break
                end
            end
        end
    end
    -- Gegner: gehoert der Mob (oder sein Drop) zu einer Quest in deinem Log?
    if added < 4 and not (UnitIsPlayer and UnitIsPlayer(unit)) then
        for _, lq in ipairs(list) do
            if added >= 4 then break end
            if lq.questID and not shownQ[lq.questID] and lq.status ~= "READY" then
                local names = MobNames(lq.questID)
                local key = names and names[name]
                if key then
                    local o
                    for _, x in ipairs(lq.objectives or {}) do
                        if x.text and x.text:find(key, 1, true) then o = x; break end
                    end
                    local prog = (o and (o.need or 0) > 0) and string.format(" (%d/%d)", o.have or 0, o.need) or ""
                    if not (o and o.done) then
                        local q = DBm.Quest(lq.questID)
                        if added == 0 then tt:AddLine(" ") end
                        tt:AddLine(string.format(L("Levelmate: für %s%s"), (q and q.name) or "?", prog), GOLD[1], GOLD[2], GOLD[3], true)
                        added = added + 1
                        shownQ[lq.questID] = true
                    end
                end
            end
        end
    end
    if added > 0 then tt:Show() end
end

Levelmate._TooltipLine = TooltipLine

local function HookTooltip()
    local function Handler(tt) pcall(TooltipLine, tt) end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
            if tt == GameTooltip then Handler(tt) end
        end)
    elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", Handler)
    end
end

---------------------------------------------------------------------------
-- 5) Gruppenfenster
---------------------------------------------------------------------------
local gframe
local function RefreshGroupFrame()
    if not gframe or not gframe:IsShown() then return end
    local G = Levelmate.Group
    local mine = {}
    for _, lq in ipairs((Levelmate.Quests and Levelmate.Quests.GetList and Levelmate.Quests.GetList()) or {}) do mine[lq.questID] = true end
    local rows = {}
    if DB().groupOff then
        rows[1] = "|cff888888" .. L("Gruppenmodus ist in den Optionen ausgeschaltet.") .. "|r"
    elseif not (IsInGroup and IsInGroup()) then
        rows[1] = "|cff888888" .. L("Du bist in keiner Gruppe.") .. "|r"
    elseif not (G and G.Active and G.Active()) then
        rows[1] = "|cff888888" .. L("Noch keine Daten – Mitspieler brauchen Levelmate ab 1.0.8.") .. "|r"
    else
        local names = {}
        for name in pairs(G.members) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            local m = G.members[name]
            local n, shared = 0, 0
            for id in pairs(m.quests or {}) do n = n + 1; if mine[id] then shared = shared + 1 end end
            local lvl = tonumber(m.level)
            local my = UnitLevel("player") or 0
            local col = (not lvl) and "ffffff" or (math.abs(lvl - my) <= 2 and "66ff66" or math.abs(lvl - my) <= 5 and "ffd100" or "ff6666")
            rows[#rows + 1] = string.format("|cffffffff%s|r  |cff%s%s %s|r", name, col, L("Stufe"), tostring(m.level or "?"))
            rows[#rows + 1] = string.format("   |cffaaaaaa" .. L("%d Quests, davon %d gemeinsam mit dir") .. "|r", n, shared)
        end
        if #rows == 0 then rows[1] = "|cff888888" .. L("Keine Mitspieler mit Levelmate.") .. "|r" end
    end
    gframe.text:SetText(table.concat(rows, "\n"))
    gframe:SetHeight(math.max(70, (gframe.text:GetStringHeight() or 20) + 42))
end

local function BuildGroupFrame()
    gframe = StyledFrame("LevelmateGroupFrame", 260, 90)
    local pos = DB().groupPos
    if pos then gframe:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3]) else gframe:SetPoint("CENTER", 260, 0) end
    gframe:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local p, _, _, x, y = self:GetPoint(1)
        DB().groupPos = { p, x, y }
    end)
    gframe.title:SetText(L("Levelmate – Gruppe"))
    gframe.text = gframe:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gframe.text:SetPoint("TOPLEFT", 12, -30)
    gframe.text:SetPoint("RIGHT", -12, 0)
    gframe.text:SetJustifyH("LEFT")
    gframe.text:SetSpacing(3)
    gframe:SetScript("OnShow", function() DB().groupFrameOpen = true; RefreshGroupFrame() end)
    gframe:SetScript("OnHide", function() DB().groupFrameOpen = false end)
    gframe.elapsed = 0
    gframe:SetScript("OnUpdate", function(self, el)
        self.elapsed = self.elapsed + el
        if self.elapsed > 3 then self.elapsed = 0; pcall(RefreshGroupFrame) end
    end)
end

function Levelmate.ToggleGroupFrame(show)
    if not gframe then BuildGroupFrame() end
    if show == nil then show = not gframe:IsShown() end
    gframe:SetShown(show)
end


---------------------------------------------------------------------------
-- /lm journal: Pruefen, ob das Dungeon-Journal Daten fuer die alten Dungeons hat
---------------------------------------------------------------------------
function Levelmate.JournalTest()
    local function P(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end Print("Journal: " .. table.concat(t, "  ")) end
    local function Try(fn, ...) if type(fn) ~= "function" then return false, "fehlt" end return pcall(fn, ...) end
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal") end
    local ok, nTiers = Try(EJ_GetNumTiers)
    P("Tiers:", ok and nTiers or ("Fehler " .. tostring(nTiers)))
    if not ok or type(nTiers) ~= "number" then return end
    for tier = 1, math.min(nTiers, 3) do
        local ok2, tname = Try(EJ_GetTierInfo, tier)
        Try(EJ_SelectTier, tier)
        local names, first = {}, nil
        for i = 1, 40 do
            local ok3, id, name = Try(EJ_GetInstanceByIndex, i, false)
            if not ok3 or not id then break end
            names[#names + 1] = tostring(name)
            first = first or id
        end
        P("Tier " .. tier, ok2 and tname or "?", "Dungeons: " .. #names)
        if #names > 0 then P(table.concat(names, ", "):sub(1, 220)) end
        if tier == 1 and first then
            Try(EJ_SelectInstance, first)
            local bosses = {}
            for i = 1, 20 do
                local ok4, bname, _, eid = Try(EJ_GetEncounterInfoByIndex, i, first)
                if not ok4 or not bname then break end
                bosses[#bosses + 1] = tostring(bname)
                if i == 1 and eid then
                    Try(EJ_SelectEncounter, eid)
                    local ok5, nLoot = Try(EJ_GetNumLoot)
                    local item = "-"
                    if C_EncounterJournal and C_EncounterJournal.GetLootInfoByIndex then
                        local ok6, info = pcall(C_EncounterJournal.GetLootInfoByIndex, 1)
                        if ok6 and type(info) == "table" then item = tostring(info.name or info.itemID) end
                    end
                    P("Beute beim 1. Boss:", ok5 and nLoot or "?", "z. B.", item)
                end
            end
            P("Bosse:", #bosses, table.concat(bosses, ", "):sub(1, 200))
        end
    end
end

---------------------------------------------------------------------------
-- Befehle: /lm sitzung, /lm tipps, /lm gruppe fenster
---------------------------------------------------------------------------
local function HookSlash()
    local orig = SlashCmdList and SlashCmdList.LEVELMATE
    if not orig then return end
    SlashCmdList.LEVELMATE = function(msg)
        local m = ((msg or ""):match("^%s*(.-)%s*$") or ""):lower()
        if m == "sitzung" or m == "session" then return Levelmate.SessionCommand() end
        if m == "tipps" or m == "tips" then return Levelmate.ShowTips(true) end
        if m == "journal" then return Levelmate.JournalTest() end
        if m == "gruppe fenster" or m == "group window" or m == "gf" then return Levelmate.ToggleGroupFrame() end
        return orig(msg)
    end
end

---------------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "QUEST_TURNED_IN", "PLAYER_LOGOUT" }) do
    ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
    pcall(function()
        if event == "ADDON_LOADED" then
            -- Wer Levelmate schon vor 1.0.9 benutzt hat (gespeicherte Daten vorhanden),
            -- braucht die Einfuehrung nicht. Nur echte Neuinstallationen sehen sie.
            if arg1 == "Levelmate" or arg1 == Levelmate.name then
                ev:UnregisterEvent("ADDON_LOADED")
                if type(Levelmate_DB) == "table" and next(Levelmate_DB) ~= nil and Levelmate_DB.tipsSeen == nil then
                    Levelmate_DB.tipsSeen = true
                end
            end
        elseif event == "PLAYER_LOGIN" then
            StartSession()
            HookTooltip()
            HookSlash()
            if C_Timer and C_Timer.After then
                C_Timer.After(6, function() pcall(ShowLastSession) end)
                C_Timer.After(4, function()
                    if not (Levelmate.InCombat and Levelmate.InCombat()) then pcall(Levelmate.ShowTips, false) end
                end)
                if DB().groupFrameOpen then C_Timer.After(5, function() pcall(Levelmate.ToggleGroupFrame, true) end) end
            end
        elseif event == "PLAYER_XP_UPDATE" then
            TrackXP()
        elseif event == "QUEST_TURNED_IN" then
            if session then session.quests = session.quests + 1 end
        elseif event == "PLAYER_LEVEL_UP" then
            TrackXP()
            local lvl = tonumber(arg1) or UnitLevel("player")
            -- kurz warten, damit Lehrer-Daten und Plan schon zur neuen Stufe passen
            if C_Timer and C_Timer.After then C_Timer.After(1.5, function() pcall(ShowLevelToast, lvl) end)
            else ShowLevelToast(lvl) end
        elseif event == "PLAYER_LOGOUT" then
            SaveSession()
        end
    end)
end)
