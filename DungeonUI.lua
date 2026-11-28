-- DungeonUI.lua (1.1.0)
-- Dungeon-Fenster im Stil der Einstellungen: links die Liste der Dungeons,
-- rechts die Detailseite mit drei Reitern (Übersicht, Bosse, Beute).
--   Übersicht: Quests mit Status (erledigt / im Log / abholbar / Vorquest fehlt)
--   Bosse:     Reihenfolge aus DungeonData.lua, Namen aus QuestieDB, Quest-Bezug
--   Beute:     was bei dir selbst von den Bossen gefallen ist (wird mitgeschrieben)
-- Ausserdem zaehlt Levelmate, wie oft du einen Dungeon betreten hast.
Levelmate = Levelmate or {}
local L = Levelmate.L or function(s) return s end
local dframe = Levelmate.DungeonFrame
if not dframe then return end

local WHITE = "Interface/Buttons/WHITE8X8"
local ROUND = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local GOLD = { 1, 0.82, 0 }
local BORDER = { 0.79, 0.60, 0.23 }
local SIDE_W = 190
local ICON = {
    done = "Interface\\RaidFrame\\ReadyCheck-Ready",
    log = "Interface\\GossipFrame\\ActiveQuestIcon",
    avail = "Interface\\GossipFrame\\AvailableQuestIcon",
    blocked = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    inside = "Interface\\Minimap\\Dungeon",
    boss = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull",
}
local STATUS_COL = { ideal = { 0.4, 1, 0.4 }, soon = { 1, 0.6, 0.2 }, low = { 0.55, 0.55, 0.55 }, grey = { 0.45, 0.45, 0.45 } }

local function DB() Levelmate_DB = Levelmate_DB or {}; return Levelmate_DB end
local function CharDB() Levelmate_CharDB = Levelmate_CharDB or {}; return Levelmate_CharDB end
local function Print(m) if Levelmate.Print then Levelmate.Print(m) end end
local function Tex(parent, layer, r, g, b, a, file)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND")
    t:SetTexture(file or WHITE)
    t:SetVertexColor(r, g, b, a or 1)
    return t
end
local function KeyOf(e) return e and string.upper(Levelmate.DB.DungeonEnglish(e.name) or e.name or "") or nil end
local function Bosses(key) return key and Levelmate.DungeonData and Levelmate.DungeonData[key] or nil end

-- Alte Elemente des frueheren Fensters (falls vorhanden) ausblenden
for _, k in ipairs({ "title", "sub", "scroll", "slider" }) do
    local o = rawget(dframe, k)
    if type(o) == "table" and o.Hide then o:Hide() end
end

---------------------------------------------------------------------------
-- Scrollbereich mit schmaler Leiste
---------------------------------------------------------------------------
local function MakeScroll(parent)
    local sc = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sc)
    child:SetSize(10, 10)
    sc:SetScrollChild(child)
    sc:EnableMouseWheel(true)
    local bar = CreateFrame("Slider", nil, parent)
    bar:SetOrientation("VERTICAL")
    bar:SetWidth(6)
    bar:SetPoint("TOPLEFT", sc, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", sc, "BOTTOMRIGHT", 2, 0)
    local track = Tex(bar, "BACKGROUND", 1, 1, 1, 0.06); track:SetAllPoints()
    bar:SetThumbTexture(WHITE)
    local th = bar:GetThumbTexture()
    if th then th:SetSize(6, 30); th:SetVertexColor(BORDER[1], BORDER[2], BORDER[3], 0.8) end
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    bar:SetValue(0)
    bar:Hide()
    bar:SetScript("OnValueChanged", function(_, v) sc:SetVerticalScroll(v) end)
    sc:SetScript("OnMouseWheel", function(_, d)
        local lo, hi = bar:GetMinMaxValues()
        bar:SetValue(math.max(lo, math.min(hi, bar:GetValue() - d * 36)))
    end)
    sc.child, sc.bar = child, bar
    sc.SetContentHeight = function(h)
        child:SetHeight(math.max(10, h))
        local view = sc:GetHeight() or 0
        local max = math.max(0, h - view)
        bar:SetMinMaxValues(0, max)
        if bar:GetValue() > max then bar:SetValue(max) end
        bar:SetShown(max > 0)
    end
    sc.ToTop = function() bar:SetValue(0); sc:SetVerticalScroll(0) end
    return sc
end

---------------------------------------------------------------------------
-- Aufbau: Seitenleiste
---------------------------------------------------------------------------
local side = CreateFrame("Frame", nil, dframe)
side:SetPoint("TOPLEFT", 1, -1)
side:SetPoint("BOTTOMLEFT", 1, 1)
side:SetWidth(SIDE_W)
local sideBg = Tex(side, "BACKGROUND", 0.016, 0.027, 0.07, 0.95); sideBg:SetAllPoints()
local sideLine = Tex(side, "BORDER", BORDER[1], BORDER[2], BORDER[3], 0.35)
sideLine:SetPoint("TOPRIGHT"); sideLine:SetPoint("BOTTOMRIGHT"); sideLine:SetWidth(1)
local sideTitle = side:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
sideTitle:SetPoint("TOPLEFT", 12, -12)
sideTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
local sideSub = side:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
sideSub:SetPoint("TOPLEFT", sideTitle, "BOTTOMLEFT", 0, -3)

-- Umschalter: passend / alle
local filter = CreateFrame("Button", nil, side, "BackdropTemplate")
filter:SetSize(SIDE_W - 24, 20)
filter:SetPoint("BOTTOMLEFT", 12, 10)
filter:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
filter:SetBackdropColor(0, 0, 0, 0)
filter:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.6)
filter.text = filter:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
filter.text:SetPoint("CENTER")
filter:SetScript("OnEnter", function(self) self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.18) end)
filter:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)

local navScroll = MakeScroll(side)
navScroll:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -50)
navScroll:SetPoint("BOTTOMRIGHT", side, "BOTTOMRIGHT", -9, 36)
local navRows = {}

---------------------------------------------------------------------------
-- Aufbau: Detailseite
---------------------------------------------------------------------------
local detail = CreateFrame("Frame", nil, dframe)
detail:SetPoint("TOPLEFT", dframe, "TOPLEFT", SIDE_W + 1, -1)
detail:SetPoint("BOTTOMRIGHT", dframe, "BOTTOMRIGHT", -1, 1)
local dTitle = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
dTitle:SetPoint("TOPLEFT", 12, -12)
dTitle:SetPoint("RIGHT", detail, "RIGHT", -30, 0)
dTitle:SetJustifyH("LEFT")
dTitle:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
local dSub = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
dSub:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -3)
dSub:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
dSub:SetJustifyH("LEFT")

local TABS = { { key = "overview", label = "Übersicht" }, { key = "bosses", label = "Bosse" }, { key = "loot", label = "Beute" } }
local tabButtons = {}
for i, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, detail)
    b:SetSize(78, 20)
    b:SetPoint("TOPLEFT", detail, "TOPLEFT", 12 + (i - 1) * 82, -52)
    local l = b:CreateTexture(nil, "BACKGROUND"); l:SetTexture(ROUND); l:SetSize(20, 20); l:SetPoint("LEFT")
    local r = b:CreateTexture(nil, "BACKGROUND"); r:SetTexture(ROUND); r:SetSize(20, 20); r:SetPoint("RIGHT")
    local m = b:CreateTexture(nil, "BACKGROUND"); m:SetTexture(WHITE); m:SetPoint("TOPLEFT", 10, 0); m:SetPoint("BOTTOMRIGHT", -10, 0)
    b.parts = { l, r, m }
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.key, b.raw = t.key, t.label
    tabButtons[#tabButtons + 1] = b
end

local body = MakeScroll(detail)
body:SetPoint("TOPLEFT", detail, "TOPLEFT", 12, -80)
body:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -20, 40)

local function FlatButton(parent, w)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.SetOn = function(self, on)
        self.on = on
        if on then
            self:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.95); self:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
            self.text:SetTextColor(0.04, 0.06, 0.12)
        else
            self:SetBackdropColor(0, 0, 0, 0); self:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.7)
            self.text:SetTextColor(1, 0.82, 0)
        end
    end
    b:SetScript("OnEnter", function(self)
        if not self.on then self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.18) end
        if self.tipTitle then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(L(self.tipTitle))
            GameTooltip:AddLine(L(self.tipText), 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self) if not self.on then self:SetBackdropColor(0, 0, 0, 0) end; GameTooltip:Hide() end)
    b:SetOn(false)
    return b
end
local goBtn = FlatButton(detail, 120)
goBtn:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 12, 10)
goBtn.tipTitle, goBtn.tipText = "Jetzt hin", "Der Dungeon wird sofort der nächste Schritt, z. B. wenn deine Gruppe bereit ist. Danach geht die Route normal weiter."
local focusBtn = FlatButton(detail, 140)
focusBtn:SetPoint("LEFT", goBtn, "RIGHT", 8, 0)
focusBtn.tipTitle, focusBtn.tipText = "Quests abholen", "Levelmate holt die Dungeonquests dieses Dungeons als Nächstes ab (nochmal klicken: aus)."

---------------------------------------------------------------------------
-- Zeilen im Inhaltsbereich (wiederverwendet)
---------------------------------------------------------------------------
local rows, nRows, cy, cw = {}, 0, 0, 300
Levelmate._dungeonRows = rows
local function Row()
    nRows = nRows + 1
    local r = rows[nRows]
    if not r then
        r = CreateFrame("Button", nil, body.child)
        r.hl = Tex(r, "HIGHLIGHT", 1, 1, 1, 0.05); r.hl:SetAllPoints()
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        r.text:SetJustifyH("LEFT")
        if r.text.SetWordWrap then r.text:SetWordWrap(true) end
        r.right = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.right:SetJustifyH("RIGHT")
        r.sub = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.sub:SetJustifyH("LEFT")
        r.sub:SetTextColor(0.62, 0.62, 0.62)
        r.line = Tex(r, "BORDER", BORDER[1], BORDER[2], BORDER[3], 0.35)
        r.line:SetHeight(1)
        r.acts = {}
        for k = 1, 2 do
            local b = CreateFrame("Button", nil, r, "BackdropTemplate")
            b:SetHeight(18)
            b:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("CENTER")
            b:SetScript("OnEnter", function(self)
                if not self.on then self:SetBackdropColor(BORDER[1], BORDER[2], BORDER[3], 0.25) end
                if self.tip then GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(self.tip, 1, 1, 1, 1, true); GameTooltip:Show() end
            end)
            b:SetScript("OnLeave", function(self)
                if not self.on then self:SetBackdropColor(0, 0, 0, 0) end
                GameTooltip:Hide()
            end)
            b:Hide()
            r.acts[k] = b
        end
        rows[nRows] = r
    end
    r:Show()
    r:SetScript("OnClick", nil); r:SetScript("OnEnter", nil); r:SetScript("OnLeave", nil)
    r.hl:SetShown(false)
    return r
end
-- o = { icon, iconColor, text, right, rightColor, sub, onClick, item, header, gap, indent }
local function Add(o)
    local r = Row()
    local indent = o.indent or 0
    r:ClearAllPoints()
    cy = cy - (o.gap or 0)
    r:SetPoint("TOPLEFT", body.child, "TOPLEFT", 0, cy)
    r:SetWidth(cw)
    r.icon:ClearAllPoints(); r.text:ClearAllPoints(); r.right:ClearAllPoints(); r.sub:ClearAllPoints()
    if o.header then
        r.icon:Hide(); r.right:Hide(); r.sub:Hide()
        for _, b in ipairs(r.acts) do b:Hide() end
        r.text:SetFontObject("GameFontNormalSmall")
        r.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        r.text:SetPoint("TOPLEFT", r, "TOPLEFT", 2, -6)
        r.text:SetWidth(cw - 4)
        r.text:SetText(o.text)
        r.right:SetShown(o.right ~= nil)
        if o.right then
            r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2, -6)
            r.right:SetText(o.right)
            r.right:SetTextColor(0.6, 0.6, 0.6)
        end
        r.line:Show()
        r.line:ClearAllPoints()
        r.line:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -3)
        r.line:SetPoint("RIGHT", r, "RIGHT", 0, 0)
        local h = 6 + (r.text:GetStringHeight() or 12) + 8
        r:SetHeight(h)
        cy = cy - h
        return r
    end
    r.line:Hide()
    r.text:SetFontObject(o.small and "GameFontHighlightSmall" or "GameFontHighlight")
    local tc = o.textColor or { 0.92, 0.92, 0.92 }
    r.text:SetTextColor(tc[1], tc[2], tc[3])
    local x = 4 + indent
    if o.icon then
        r.icon:Show()
        r.icon:SetTexture(o.icon)
        if o.iconCoords then r.icon:SetTexCoord(unpack(o.iconCoords)) else r.icon:SetTexCoord(0, 1, 0, 1) end
        local ic = o.iconColor
        if ic then r.icon:SetVertexColor(ic[1], ic[2], ic[3]) else r.icon:SetVertexColor(1, 1, 1) end
        r.icon:SetSize(o.iconSize or 14, o.iconSize or 14)
        r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", x, -4)
        x = x + (o.iconSize or 14) + 6
    else
        r.icon:Hide()
    end
    local rightW = 0
    for k, b in ipairs(r.acts) do
        local a = o.actions and o.actions[k]
        if a then
            b.text:SetText(a.label)
            local w = math.floor((b.text:GetStringWidth() or 30) + 14)
            b:SetWidth(w)
            b:ClearAllPoints()
            b:SetPoint("TOPRIGHT", r, "TOPRIGHT", -2 - rightW, -2)
            rightW = rightW + w + 4
            b.on, b.tip = a.on, a.tip
            if a.on then
                b:SetBackdropColor(GOLD[1], GOLD[2], GOLD[3], 0.95); b:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
                b.text:SetTextColor(0.04, 0.06, 0.12)
            else
                b:SetBackdropColor(0, 0, 0, 0); b:SetBackdropBorderColor(BORDER[1], BORDER[2], BORDER[3], 0.7)
                b.text:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
            end
            b:SetScript("OnClick", a.onClick)
            b:Show()
        else
            b:Hide()
        end
    end
    if rightW > 0 then rightW = rightW + 4 end
    if o.right then
        r.right:Show()
        r.right:SetText(o.right)
        local rc = o.rightColor or { 0.6, 0.6, 0.6 }
        r.right:SetTextColor(rc[1], rc[2], rc[3])
        r.right:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4 - rightW, -5)
        rightW = rightW + (r.right:GetStringWidth() or 30) + 10
    else
        r.right:Hide()
    end
    r.text:SetPoint("TOPLEFT", r, "TOPLEFT", x, -4)
    r.text:SetWidth(math.max(60, cw - x - rightW - 4))
    r.text:SetText(o.text or "")
    local h = 4 + math.max(14, r.text:GetStringHeight() or 12)
    if o.sub then
        r.sub:Show()
        r.sub:SetPoint("TOPLEFT", r.text, "BOTTOMLEFT", 0, -2)
        r.sub:SetWidth(math.max(60, cw - x - 4))
        r.sub:SetText(o.sub)
        h = h + 2 + (r.sub:GetStringHeight() or 10)
    else
        r.sub:Hide()
    end
    h = h + 4
    if o.actions then h = math.max(h, 24) end
    r:SetHeight(h)
    if o.onClick or o.item or o.tip then
        r.hl:SetShown(true)
        if o.onClick then r:SetScript("OnClick", o.onClick) end
        r:SetScript("OnEnter", function(self)
            if o.item then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetItemByID, GameTooltip, o.item)
                GameTooltip:Show()
            elseif o.tip then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(o.tip, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cy = cy - h
    return r
end
local function Begin()
    nRows, cy = 0, 0
    cw = math.max(200, (body:GetWidth() or 300) - 4)
    body.child:SetWidth(cw)
end
local function Finish()
    for i = nRows + 1, #rows do rows[i]:Hide() end
    body.SetContentHeight(-cy + 6)
end

---------------------------------------------------------------------------
-- Quests eines Bosses (Kill-Ziele und Drops) fuer den Reiter "Bosse"
---------------------------------------------------------------------------
local questNpcCache = {}
local function QuestNpcs(q)
    local c = questNpcCache[q.id]
    if c then return c end
    c = {}
    local obj = q.objectives or {}
    for _, e in ipairs(obj[1] or {}) do
        local id = type(e) == "table" and e[1] or e
        if id then c[id] = true end
    end
    for _, e in ipairs(obj[3] or {}) do
        local itemId = type(e) == "table" and e[1] or e
        if itemId and Levelmate.DB.ItemSources then
            local ok, src = pcall(Levelmate.DB.ItemSources, itemId)
            -- nur bossspezifische Drops (wenige Quellen), nicht "faellt bei allen Gegnern"
            local npcs = {}
            if ok and src then for _, s in ipairs(src) do if s.kind == "npc" then npcs[#npcs + 1] = s.id end end end
            if #npcs <= 3 then for _, id in ipairs(npcs) do c[id] = true end end
        end
    end
    questNpcCache[q.id] = c
    return c
end

local function BossName(b)
    local n = Levelmate.DB.Npc and Levelmate.DB.Npc(b[1])
    if n and n.name and not n.name:find("^NPC ") then return n.name end
    return L(b[2])
end

---------------------------------------------------------------------------
-- Gelernte Beute und gezaehlte Laeufe
---------------------------------------------------------------------------
local bossIndex
local function BossIndex()
    if bossIndex then return bossIndex end
    bossIndex = {}
    for key, list in pairs(Levelmate.DungeonData or {}) do
        for _, b in ipairs(list) do bossIndex[b[1]] = key end
    end
    return bossIndex
end

local function RecordLoot()
    if not (GetNumLootItems and GetLootSourceInfo and GetLootSlotLink) then return end
    local idx = BossIndex()
    local n = GetNumLootItems() or 0
    for slot = 1, n do
        local link = GetLootSlotLink(slot)
        local itemId = link and tonumber(link:match("item:(%d+)"))
        local quality = select(5, GetLootSlotInfo(slot))
        if itemId and (tonumber(quality) or 0) >= 2 then
            local guid = GetLootSourceInfo(slot)
            local npcId = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
            if npcId and (idx[npcId] or (Levelmate.Atlas and Levelmate.Atlas.IsBoss(npcId))) then
                local db = DB()
                db.bossLoot = db.bossLoot or {}
                local t = db.bossLoot[npcId] or {}
                db.bossLoot[npcId] = t
                t[itemId] = (t[itemId] or 0) + 1
            end
        end
    end
end

local function CurrentDungeonKey()
    local inInst, kind = false, nil
    local ok, a, b = pcall(IsInInstance)
    if ok then inInst, kind = a, b end
    if not inInst or kind ~= "party" then return nil end
    local instID = select(8, GetInstanceInfo())
    local area = Levelmate.DB.InstanceArea and Levelmate.DB.InstanceArea(instID)
    local name = area and Levelmate.DB.Dungeon(area)
    if not name then return nil end
    return string.upper(Levelmate.DB.DungeonEnglish(name) or name)
end

local function CountRun()
    local key = CurrentDungeonKey()
    if not key then return end
    local c = CharDB()
    c.dungeonRuns = c.dungeonRuns or {}
    local now = time()
    local last = c.lastDungeon
    -- gleicher Dungeon innerhalb einer halben Stunde (Geist, Reload): kein neuer Lauf
    if not (last and last.key == key and now - (last.t or 0) < 1800) then
        local r = c.dungeonRuns[key] or { n = 0 }
        r.n, r.last = r.n + 1, now
        c.dungeonRuns[key] = r
    end
    c.lastDungeon = { key = key, t = now }
    dframe.selKey = key
end

---------------------------------------------------------------------------
-- Ort auf der Weltkarte zeigen (Questgeber / Anfang einer Vorquest)
---------------------------------------------------------------------------
local function ShowOnMap(point, questName, giver, fmt)
    if not (point and point.map and point.x and point.y) then
        Print(string.format(L("Für „%s“ kennt Levelmate keinen Ort."), questName or "?"))
        return
    end
    local map, x, y = point.map, point.x / 100, point.y / 100
    -- Wegpunkt des Spiels (Stecknadel auf der Karte und am Bildschirmrand)
    local pinned = false
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        local ok = pcall(function()
            if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then error("no") end
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        end)
        pinned = ok
    end
    if not pinned and TomTom and TomTom.AddWaypoint then
        pinned = pcall(TomTom.AddWaypoint, TomTom, map, x, y, { title = (giver or questName or "Levelmate"), persistent = false })
    end
    -- Karte oeffnen und auf das Gebiet stellen
    pcall(function()
        if WorldMapFrame and not WorldMapFrame:IsShown() then
            if ToggleWorldMap then ToggleWorldMap() else ShowUIPanel(WorldMapFrame) end
        end
        if WorldMapFrame and WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(map) end
    end)
    local zone = Levelmate.Planner.MapName and Levelmate.Planner.MapName(map) or "?"
    Print(string.format(fmt or L("Anfang von „%s“: %s, %s (%.1f, %.1f)"), questName or "?", giver or "?", zone, point.x, point.y)
        .. (pinned and L(" – auf der Karte markiert.") or ""))
end
Levelmate.ShowOnMap = ShowOnMap

-- Wo beginnt eine Quest, wenn der Planer keinen Punkt hat? Questgeber im Dungeon
-- (z. B. Belnistrasz in den Huegeln) -> Eingang des Dungeons; Gegenstand -> Gegner,
-- der ihn fallen laesst (oder dessen Dungeon).
local function StartLocation(q)
    local DBm = Levelmate.DB
    local sb = q and q.startedBy
    if type(sb) ~= "table" then return nil end
    local function FromNpc(id)
        local n = DBm.Npc and DBm.Npc(id)
        if not n then return nil end
        if n.points and #n.points > 0 then return n.points[1], n.name, nil end
        if n.dungeonArea then
            local dname, entrance = DBm.Dungeon(n.dungeonArea)
            if entrance then return entrance, n.name, dname end
        end
    end
    for _, id in ipairs(sb[1] or {}) do
        local pt, who, dname = FromNpc(id)
        if pt then return pt, who, dname, false end
    end
    for _, itemId in ipairs(sb[3] or {}) do
        local ok, src = pcall(DBm.ItemSources, itemId)
        for _, s in ipairs(ok and src or {}) do
            if s.kind == "npc" then
                local pt, who, dname = FromNpc(s.id)
                if pt then return pt, who, dname, true end
            end
        end
    end
end

---------------------------------------------------------------------------
-- "Zuerst": eine Quest an die erste Stelle der Route setzen
---------------------------------------------------------------------------
local function IsFirst(id) return id and Levelmate.Planner.forceQuest == id end
local function SetFirst(id, name, acceptOnly)
    local P = Levelmate.Planner
    if P.forceQuest == id then
        P.forceQuest, P.forceAccept = nil, nil
        Print(L("Normale Reihenfolge wiederhergestellt."))
    else
        P.forceQuest, P.forceAccept = id, acceptOnly or nil
        Print(string.format(L("Als Nächstes: %s"), name or "?") .. L(" – nochmal klicken zum Aufheben."))
    end
    if Levelmate.RequestRefresh then Levelmate.RequestRefresh(true) end
end
local function FirstAction(id, name, acceptOnly)
    return { label = IsFirst(id) and L("Gewählt") or L("Zuerst"), on = IsFirst(id),
             tip = IsFirst(id) and L("Steht als nächster Schritt in der Route. Klicken: aufheben.")
                 or L("Diese Quest als nächsten Schritt in die Route setzen (vor allem anderen)."),
             onClick = function() SetFirst(id, name, acceptOnly); Levelmate.DungeonLayout() end }
end

---------------------------------------------------------------------------
-- Inhalt der drei Reiter
---------------------------------------------------------------------------
local function QName(q) return q.name or ("#" .. tostring(q.id)) end
local function Lvl(q) return q.questLevel and ("[" .. q.questLevel .. "] ") or "" end

-- Gleichnamige Quests (Varianten fuer Rassen/Klassen oder wiederholbare Abgaben wie
-- "Der Funkelmat 5200!") nur einmal zeigen und zaehlen.
local function Unique(list, skip)
    local out, seen = {}, {}
    for _, x in ipairs(list or {}) do
        local nm = x.q and x.q.name or ""
        if not seen[nm] and not (skip and skip[nm]) and not (x.start and x.start.name == nm and x.start.id ~= x.q.id) then
            seen[nm] = true
            out[#out + 1] = x
        end
    end
    return out, seen
end

local function ShowOverview(e)
    local inLog, seenLog = Unique(e.inLog)
    local avail = Unique(e.available, seenLog)
    local blocked = Unique(e.blocked, seenLog)
    local inside = Unique(e.insideList, seenLog)
    local ready = 0
    for _, x in ipairs(inLog) do if x.ready then ready = ready + 1 end end
    -- Kopf: Stand der Vorbereitung. Gezaehlt wird, was du jetzt haben kannst
    -- (im Log + abholbar); Vorquests und Quests aus dem Dungeon stehen extra.
    local possible = #inLog + #avail
    local head
    if possible > 0 and #avail == 0 then
        head = "|cff5fd35f" .. L("Bereit – alle Quests, die du jetzt bekommen kannst, sind im Log.") .. "|r"
            .. (ready > 0 and string.format(L(" (%d fertig)"), ready) or "")
    elseif possible > 0 then
        head = string.format(L("%d von %d möglichen Quests im Log"), #inLog, possible)
            .. (ready > 0 and string.format(L(" (%d fertig)"), ready) or "")
    elseif #e.done > 0 and #blocked == 0 then
        head = "|cff5fd35f" .. L("Alle Quests erledigt – Lauf nur noch für Erfahrung und Beute.") .. "|r"
    elseif #blocked > 0 then
        head = L("Noch keine Quest möglich – erst eine Vorquest machen.")
    else
        head = L("Keine offenen Quests bekannt.")
    end
    local extra = {}
    if #blocked > 0 then extra[#extra + 1] = string.format(L("%d brauchen eine Vorquest"), #blocked) end
    if #inside > 0 then extra[#extra + 1] = string.format(L("%d starten im Dungeon"), #inside) end
    if (e.xp or 0) > 0 then extra[#extra + 1] = string.format(L("≈ %d XP aus Quests"), math.floor(e.xp + 0.5)) end
    if (e.later or 0) > 0 then extra[#extra + 1] = string.format(L("%d Quest(s) ab Stufe %d"), e.later, e.laterLevel or (e.min or 0)) end
    if e.story and CharDB().mode == "story" then extra[#extra + 1] = "|cffb070ff" .. L("Finale von: ") .. e.story .. "|r" end
    Add({ text = head, sub = (#extra > 0) and table.concat(extra, " · ") or nil })
    local fq = Levelmate.Planner.forceQuest
    if fq then
        local q = Levelmate.DB.Quest(fq)
        Add({ text = "|cffffd100" .. L("Als Nächstes gewählt: ") .. "|r" .. (q and q.name or tostring(fq)), small = true,
              actions = { { label = L("Aufheben"), tip = L("Normale Reihenfolge wiederherstellen"),
                            onClick = function() SetFirst(fq); Levelmate.DungeonLayout() end } } })
    end
    if e.wings then
        local lv = UnitLevel("player") or 0
        local w = {}
        for _, x in ipairs(e.wings) do
            local c = (lv >= x[2] and lv <= x[3]) and "|cff66ff66" or "|cff888888"
            w[#w + 1] = c .. L(x[1]) .. " " .. x[2] .. "–" .. x[3] .. "|r"
        end
        Add({ text = string.format(L("%d Flügel: "), #e.wings) .. table.concat(w, ", "), small = true })
    end

    if #inLog > 0 then
        Add({ header = true, text = L("Im Questlog"), right = tostring(#inLog), gap = 4 })
        for _, x in ipairs(inLog) do
            local id = x.q.id
            Add({ icon = ICON.log, iconColor = x.ready and { 0.4, 1, 0.4 } or nil,
                  text = Lvl(x.q) .. QName(x.q), right = x.ready and L("fertig") or nil, rightColor = { 0.4, 1, 0.4 },
                  onClick = function() if Levelmate.OpenQuest then Levelmate.OpenQuest(id) end end })
        end
    end
    if #avail > 0 then
        Add({ header = true, text = L("Abholen"), right = tostring(#avail), gap = 4 })
        for _, x in ipairs(avail) do
            local zone = x.map and Levelmate.Planner.MapName(x.map)
            local where = (x.giver and (L("bei ") .. x.giver) or "") .. (zone and ((x.giver and ", " or "") .. zone) or "")
            local pt, qn, gv, qid = x.point, QName(x.q), x.giver, x.q.id
            local acts = { FirstAction(qid, qn, true) }
            if pt then acts[2] = { label = L("Karte"), tip = L("Questgeber auf der Karte zeigen"), onClick = function() ShowOnMap(pt, qn, gv) end } end
            Add({ icon = ICON.avail, text = Lvl(x.q) .. qn, sub = where ~= "" and where or nil, actions = acts })
        end
    end
    local nChain = (e.chainLater or 0)
    if #blocked > 0 or nChain > 0 then
        Add({ header = true, text = L("Vorquest fehlt"), right = tostring(#blocked), gap = 4 })
        for _, b in ipairs(blocked) do
            local sub
            if b.start then
                local where = b.startInLog and L("im Log") or (b.startMap and Levelmate.Planner.MapName(b.startMap))
                sub = where and string.format(L("Anfang: %s (%s)"), b.start.name or "?", where)
                    or (L("Anfang: ") .. (b.start.name or "?"))
                if b.startGiver and not b.startInLog then sub = sub .. " – " .. L("bei ") .. b.startGiver end
            end
            local pt = (not b.startInLog) and b.startPoint or nil
            local sname, gv = b.start and b.start.name or QName(b.q), b.startGiver
            local inDungeon = false
            if not pt and not b.startInLog and b.start then
                local p2, who, dname, viaItem = StartLocation(b.start)
                if p2 then
                    pt = p2
                    if dname then
                        inDungeon = true
                        gv = string.format(L("%s im Dungeon %s (Eingang)"), who or "?", dname)
                        sub = (sub or "") .. "\n" .. string.format(viaItem and L("Gegenstand von %s im Dungeon %s") or L("Questgeber %s steht im Dungeon %s"), who or "?", dname)
                    else
                        gv = viaItem and string.format(L("Gegenstand von %s"), who or "?") or who
                        if viaItem then sub = (sub or "") .. "\n" .. string.format(L("Gegenstand von %s"), who or "?") end
                    end
                end
            end
            if b.startItem and not b.startInLog and not pt then
                sub = (sub or "") .. "\n" .. L("Beginnt mit einem Gegenstand, den man findet oder erbeutet.")
            end
            local sid = b.startInLog and b.start and b.start.id
            local acts = {}
            local startId = b.start and b.start.id
            -- "Zuerst" nur, wenn der Anfang draussen liegt (oder schon im Log ist)
            if startId and not inDungeon and (pt or sid) then
                acts[#acts + 1] = FirstAction(startId, sname, not b.startInLog)
            end
            if pt then
                acts[#acts + 1] = { label = L("Karte"), onClick = function() ShowOnMap(pt, sname, gv) end,
                    tip = inDungeon and L("Die Questreihe beginnt im Dungeon. Klicken: Eingang auf der Karte zeigen")
                        or L("Anfang der Questreihe auf der Karte zeigen") }
            elseif sid then
                acts[#acts + 1] = { label = L("Questlog"), tip = L("Anfangsquest im Questlog öffnen"),
                    onClick = function() if Levelmate.OpenQuest then Levelmate.OpenQuest(sid) end end }
            end
            Add({ icon = inDungeon and ICON.inside or ICON.blocked, iconSize = inDungeon and 16 or nil,
                  text = Lvl(b.q) .. QName(b.q), textColor = { 0.7, 0.7, 0.7 }, sub = sub,
                  actions = #acts > 0 and acts or nil })
        end
        if nChain > 0 then
            Add({ icon = ICON.blocked, text = string.format(L("%d weitere aus Questreihen, die du noch nicht so weit hast"), nChain),
                  textColor = { 0.6, 0.6, 0.6 }, small = true })
        end
    end
    if #inside > 0 then
        Add({ header = true, text = L("Starten im Dungeon"), right = tostring(#inside), gap = 4 })
        for _, x in ipairs(inside) do
            Add({ icon = ICON.inside, iconSize = 16, text = Lvl(x.q) .. QName(x.q), textColor = { 0.8, 0.8, 0.8 },
                  tip = L("Diese Quest bekommst du erst im Dungeon (von einem NPC oder Gegenstand dort).") })
        end
    end
    if #e.done > 0 then
        local open = not dframe.hideDone
        local uniq, su = 0, {}
        for _, x in ipairs(e.done) do local nm = QName(x.q); if not su[nm] then su[nm] = true; uniq = uniq + 1 end end
        Add({ header = true, text = L("Erledigt"), right = tostring(uniq) .. "  " .. (open and L("einklappen") or L("anzeigen")), gap = 4 })
        local r = rows[nRows]
        r.hl:SetShown(true)
        r:SetScript("OnClick", function() dframe.hideDone = not dframe.hideDone or nil; Levelmate.DungeonLayout() end)
        if open then
            local seenN = {}
            for _, x in ipairs(e.done) do
                local nm = QName(x.q)
                if not seenN[nm] then
                    seenN[nm] = true
                    Add({ icon = ICON.done, text = Lvl(x.q) .. nm, textColor = { 0.55, 0.55, 0.55 } })
                end
            end
        end
    end
end

local function QuestsByNpc(e)
    local map = {}
    local function Put(list, status)
        for _, x in ipairs(list) do
            for npc in pairs(QuestNpcs(x.q)) do
                map[npc] = map[npc] or {}
                table.insert(map[npc], { q = x.q, status = status, ready = x.ready })
            end
        end
    end
    Put(e.inLog, "log"); Put(e.available, "avail"); Put(e.blocked, "blocked"); Put(e.done, "done")
    return map
end

local SCOL = { log = "|cffffd100", avail = "|cffffff66", blocked = "|cff888888", done = "|cff5fd35f" }
local SMARK = { log = "", avail = "", blocked = "", done = "" }

local function ShowBosses(e, key)
    local list = Bosses(key)
    if not list then
        -- Keine eigene Bossliste (z. B. neue Forever-Dungeons): Bosse aus AtlasLoot
        local Atlas = Levelmate.Atlas
        local sections = Atlas and Atlas.Installed() and Atlas.Ensure() == "ok"
            and Atlas.ForDungeon(e and e.area, e and e.name, nil, e and e.atlasKey)
        if sections then
            local n = 0
            for _, sec in ipairs(sections) do
                if #sections > 1 then Add({ header = true, text = sec.title or "", gap = n > 0 and 4 or 0 }) end
                for _, boss in ipairs(sec.bosses) do
                    if #boss.npcs > 0 then
                        n = n + 1
                        Add({ icon = ICON.boss, iconSize = 16, text = n .. ". " .. boss.name,
                              right = string.format(L("%d Gegenstände"), #boss.items) })
                    end
                end
            end
            if n > 0 then
                Add({ text = L("Bossliste aus AtlasLoot – die Beute steht unter „Beute“."), small = true,
                      textColor = { 0.65, 0.65, 0.65 }, gap = 6 })
                return
            end
        end
        Add({ text = L("Für diesen Dungeon kennt Levelmate noch keine Bossliste."), textColor = { 0.7, 0.7, 0.7 } })
        return
    end
    local qmap = QuestsByNpc(e)
    local loot = DB().bossLoot or {}
    local wing
    local n = 0
    for _, b in ipairs(list) do
        if b[4] and b[4] ~= wing then
            wing = b[4]
            Add({ header = true, text = L(wing), gap = n > 0 and 4 or 0 })
        end
        n = n + 1
        local qs = qmap[b[1]]
        local sub
        if qs then
            local t, seenN = {}, {}
            for _, x in ipairs(qs) do
                local nm = QName(x.q)
                if not seenN[nm] then
                    seenN[nm] = true
                    t[#t + 1] = (SCOL[x.status] or "") .. (SMARK[x.status] or "") .. nm .. "|r"
                end
            end
            sub = L("Quest: ") .. table.concat(t, ", ")
        end
        local seen = 0
        for _ in pairs(loot[b[1]] or {}) do seen = seen + 1 end
        local tip = seen > 0 and string.format(L("%d Gegenstände schon gesehen – siehe „Beute“"), seen) or nil
        Add({ icon = ICON.boss, iconSize = 16, text = n .. ". " .. BossName(b), right = b[3] and (L("Stufe") .. " " .. b[3]) or nil,
              sub = sub, tip = tip })
    end
end

local QCOL = { [0] = "9d9d9d", [1] = "ffffff", [2] = "1eff00", [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local pendingItems = false
local function ItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, name, link, quality, _, _, _, _, _, _, icon = pcall(f, id)
    if ok then return name, link, quality, icon end
end
local function ItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    local ok, icon = pcall(f or function() end, id)
    return ok and icon or nil
end
local function ItemLine(id)
    local name, _, quality, icon = ItemInfo(id)
    if not name then
        pendingItems = true
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        return "|cff888888" .. string.format(L("Gegenstand %d (wird geladen …)"), id) .. "|r",
            ItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark", 0
    end
    return "|cff" .. (QCOL[quality or 1] or "ffffff") .. name .. "|r", icon, quality or 1
end

local function LootRow(itemId, text, icon, right)
    Add({ icon = icon, iconSize = 18, iconCoords = { 0.08, 0.92, 0.08, 0.92 }, text = text,
          right = right, item = itemId,
          onClick = function()
              if IsModifiedClick and IsModifiedClick("CHATLINK") then
                  local _, link = ItemInfo(itemId)
                  if link and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
              end
          end })
end

local function SeenText(cnt)
    return "|cff66dd66" .. string.format(L("%d× bei dir"), cnt) .. "|r"
end

local function ShowOwnLoot(list, loot, skip)
    local any = false
    for _, b in ipairs(list or {}) do
        local items = loot[b[1]]
        if items and next(items) and not (skip and skip[b[1]]) then
            any = true
            Add({ header = true, text = BossName(b), gap = 6 })
            local sorted = {}
            for id, cnt in pairs(items) do
                local text, icon, q = ItemLine(id)
                sorted[#sorted + 1] = { id = id, cnt = cnt, text = text, icon = icon, q = q }
            end
            table.sort(sorted, function(x, y) if x.q ~= y.q then return x.q > y.q end return x.id < y.id end)
            for _, it in ipairs(sorted) do
                LootRow(it.id, it.text, it.icon, it.cnt > 1 and ("×" .. it.cnt) or nil)
            end
        end
    end
    return any
end

local function ShowLoot(e, key)
    local list = Bosses(key)
    local loot = DB().bossLoot or {}
    local Atlas = Levelmate.Atlas
    local sections
    if Atlas and Atlas.Installed() then
        local st = Atlas.Ensure()
        if st == "ok" then
            local npcs = {}
            for _, b in ipairs(list or {}) do npcs[#npcs + 1] = b[1] end
            sections = Atlas.ForDungeon(e and e.area, e and e.name, npcs, e and e.atlasKey)
        elseif st == "combat" then
            Atlas.waiting = true
            Add({ text = L("AtlasLoot-Beute wird nach dem Kampf geladen."), small = true, textColor = { 1, 0.82, 0 } })
        end
    end

    if sections then
        Add({ text = L("Beute laut AtlasLoot, mit Dropchance. Grün markiert, was bei dir schon gefallen ist."),
              small = true, textColor = { 0.65, 0.65, 0.65 } })
        local covered = {}
        for _, sec in ipairs(sections) do
            if #sections > 1 then
                Add({ text = "|cffffffff" .. (sec.title or "") .. "|r", gap = 10 })
            end
            for _, boss in ipairs(sec.bosses) do
                Add({ header = true, text = boss.name, gap = 6 })
                local own = {}
                for _, npc in ipairs(boss.npcs) do
                    covered[npc] = true
                    for id, cnt in pairs(loot[npc] or {}) do own[id] = (own[id] or 0) + cnt end
                end
                local shown = {}
                for _, it in ipairs(boss.items) do
                    shown[it.id] = true
                    local text, icon = ItemLine(it.id)
                    local parts = {}
                    if own[it.id] then parts[#parts + 1] = SeenText(own[it.id]) end
                    if it.rate then
                        local r = it.rate >= 10 and string.format("%d%%", math.floor(it.rate + 0.5)) or string.format("%.1f%%", it.rate)
                        parts[#parts + 1] = "|cffaaaaaa" .. r .. "|r"
                    end
                    LootRow(it.id, text, icon, #parts > 0 and table.concat(parts, "  ") or nil)
                end
                -- bei dir gefallen, aber nicht in der Tabelle
                for id, cnt in pairs(own) do
                    if not shown[id] then
                        local text, icon = ItemLine(id)
                        LootRow(id, text, icon, SeenText(cnt))
                    end
                end
            end
        end
        -- eigene Beute von Bossen, die AtlasLoot hier nicht fuehrt
        ShowOwnLoot(list, loot, covered)
        return
    end

    Add({ text = L("Levelmate merkt sich, was bei dir von den Bossen fällt (grün und besser). Mit jedem Lauf wird die Liste voller."),
          small = true, textColor = { 0.65, 0.65, 0.65 } })
    if not (Atlas and Atlas.Installed()) then
        Add({ text = L("Tipp: Mit AtlasLoot installiert zeigt Levelmate hier die komplette Beute jedes Bosses."),
              small = true, textColor = { 1, 0.82, 0 } })
    end
    if not list then
        Add({ text = L("Für diesen Dungeon kennt Levelmate noch keine Bossliste."), textColor = { 0.7, 0.7, 0.7 }, gap = 6 })
        return
    end
    if not ShowOwnLoot(list, loot) then
        Add({ text = L("Noch keine Beute gesehen. Lauf den Dungeon einmal – danach steht hier, was die Bosse fallen gelassen haben."),
              textColor = { 0.8, 0.8, 0.8 }, gap = 6 })
    end
end

---------------------------------------------------------------------------
-- Anordnen
---------------------------------------------------------------------------
local function SelectedEntry()
    local list = dframe.list or {}
    if dframe.selKey then
        for _, e in ipairs(list) do if KeyOf(e) == dframe.selKey then return e end end
    end
    -- Ausgewaehlter Dungeon nicht in der Liste (z. B. "passend"): aus "alle" holen
    if dframe.selKey and dframe.allList then
        for _, e in ipairs(dframe.allList) do if KeyOf(e) == dframe.selKey then return e end end
    end
    return list[1]
end

local function NavRow(i)
    local r = navRows[i]
    if r then return r end
    r = CreateFrame("Button", nil, navScroll.child)
    r:SetHeight(34)
    r.bg = Tex(r, "BACKGROUND", BORDER[1], BORDER[2], BORDER[3], 0.16); r.bg:SetAllPoints()
    r.bar = Tex(r, "ARTWORK", GOLD[1], GOLD[2], GOLD[3], 1)
    r.bar:SetPoint("TOPLEFT"); r.bar:SetPoint("BOTTOMLEFT"); r.bar:SetWidth(2)
    local hl = Tex(r, "HIGHLIGHT", 1, 1, 1, 0.05); hl:SetAllPoints()
    r.dot = r:CreateTexture(nil, "ARTWORK")
    r.dot:SetTexture(ROUND); r.dot:SetSize(8, 8)
    r.dot:SetPoint("TOPLEFT", 10, -7)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("TOPLEFT", 24, -4)
    r.name:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.name:SetJustifyH("LEFT")
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.info = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.info:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.info:SetJustifyH("LEFT")
    navRows[i] = r
    return r
end

local function NavInfo(e)
    local lv = string.format("%d–%d", e.min or 0, e.max or 0)
    local inLog, seen = Unique(e.inLog)
    local avail = Unique(e.available, seen)
    local blocked = Unique(e.blocked, seen)
    if #avail > 0 then
        return lv .. " · |cffff9933" .. string.format(L("%d offen"), #avail) .. "|r"
    elseif #inLog > 0 then
        return lv .. " · |cff5fd35f" .. L("bereit") .. "|r"
    elseif #blocked > 0 then
        return lv .. " · " .. L("Vorquest")
    elseif #e.done > 0 then
        return lv .. " · |cff5fd35f" .. L("alle erledigt") .. "|r"
    end
    return lv
end

function Levelmate.DungeonLayout()
    if not dframe:IsShown() then return end
    local showAll = DB().dungeonShowAll
    sideTitle:SetText(L("Dungeons"))
    sideSub:SetText(string.format(L("Stufe %d"), UnitLevel("player") or 0))
    filter.text:SetText(showAll and L("Nur passende zeigen") or L("Alle Dungeons zeigen"))
    -- Liste
    local list = dframe.list or {}
    local sel = SelectedEntry()
    dframe.selKey = sel and KeyOf(sel) or dframe.selKey
    local navW = SIDE_W - 10
    navScroll.child:SetWidth(navW)
    for i, e in ipairs(list) do
        local r = NavRow(i)
        r:SetWidth(navW)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", navScroll.child, "TOPLEFT", 0, -(i - 1) * 36)
        local on = (e == sel)
        r.bg:SetShown(on); r.bar:SetShown(on)
        r.name:SetText(e.name)
        r.name:SetTextColor(on and GOLD[1] or 0.9, on and GOLD[2] or 0.9, on and GOLD[3] or 0.9)
        local c = STATUS_COL[e.status] or { 1, 1, 1 }
        r.dot:SetVertexColor(c[1], c[2], c[3])
        r.info:SetText(NavInfo(e))
        local key = KeyOf(e)
        r:SetScript("OnClick", function()
            dframe.selKey = key
            body.ToTop()
            Levelmate.DungeonLayout()
        end)
        r:Show()
    end
    for i = #list + 1, #navRows do navRows[i]:Hide() end
    navScroll.SetContentHeight(#list * 36)

    -- Reiter
    local tab = DB().dungeonTab or "overview"
    for _, b in ipairs(tabButtons) do
        local on = b.key == tab
        for _, p in ipairs(b.parts) do
            if on then p:SetVertexColor(GOLD[1], GOLD[2], GOLD[3], 1) else p:SetVertexColor(0.23, 0.25, 0.31, 1) end
        end
        b.text:SetText(L(b.raw))
        if on then b.text:SetTextColor(0.04, 0.06, 0.12) else b.text:SetTextColor(0.8, 0.8, 0.8) end
        b:SetScript("OnClick", function() DB().dungeonTab = b.key; body.ToTop(); Levelmate.DungeonLayout() end)
    end

    -- Details
    Begin()
    pendingItems = false
    if not sel then
        dTitle:SetText(L("Dungeons"))
        dSub:SetText("")
        Add({ text = L("Gerade kein Dungeon für deine Stufe bekannt."), textColor = { 0.8, 0.8, 0.8 } })
        goBtn:Hide(); focusBtn:Hide()
        Finish()
        return
    end
    local key = KeyOf(sel)
    dTitle:SetText(sel.name)
    local parts = {}
    local ent = sel.entrance and Levelmate.Planner.MapName(sel.entrance.map)
    if ent then parts[#parts + 1] = ent end
    parts[#parts + 1] = string.format(L("Stufe %d–%d"), sel.min or 0, sel.max or 0)
    local runs = CharDB().dungeonRuns and CharDB().dungeonRuns[key]
    if runs and runs.n > 0 then parts[#parts + 1] = string.format(L("%d× gelaufen"), runs.n) end
    dSub:SetText(table.concat(parts, " · "))
    if tab == "bosses" then ShowBosses(sel, key)
    elseif tab == "loot" then ShowLoot(sel, key)
    else ShowOverview(sel) end
    Finish()

    -- Knoepfe
    goBtn:Show()
    goBtn.text:SetText(sel.going and L("Doch nicht") or L("Jetzt hin"))
    goBtn:SetOn(sel.going)
    local area, name = sel.area, sel.name
    goBtn:SetScript("OnClick", function()
        local on = Levelmate.Planner.SetDungeonGo(area)
        Print(on and string.format(L("Nächster Schritt: %s. Viel Spaß!"), name)
            or string.format(L("%s abgebrochen – die Route geht normal weiter."), name))
        Levelmate.Refresh()
    end)
    focusBtn:Hide()
end

function Levelmate.UpdateDungeonFrame()
    if not dframe:IsShown() then return end
    local P = Levelmate.Planner
    if not P.DungeonOverview then return end
    local showAll = DB().dungeonShowAll
    dframe.allList = nil
    if showAll then
        dframe.list = P.DungeonOverview(true) or {}
        dframe.allList = dframe.list
    else
        dframe.list = P.DungeonOverview() or {}
        -- ausgewaehlter Dungeon (z. B. gerade betreten) fehlt in "passend"? dann aus "alle"
        local found = false
        for _, e in ipairs(dframe.list) do if KeyOf(e) == dframe.selKey then found = true; break end end
        if dframe.selKey and not found then dframe.allList = P.DungeonOverview(true) end
    end
    Levelmate.DungeonLayout()
end

filter:SetScript("OnClick", function()
    DB().dungeonShowAll = not DB().dungeonShowAll or nil
    navScroll.ToTop()
    Levelmate.UpdateDungeonFrame()
end)
dframe:HookScript("OnSizeChanged", function()
    if dframe:IsShown() then Levelmate.DungeonLayout() end
end)

---------------------------------------------------------------------------
-- Ereignisse: Beute mitschreiben, Laeufe zaehlen, Gegenstandsdaten nachladen
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "LOOT_OPENED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "GET_ITEM_INFO_RECEIVED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local itemRefresh = false
ev:SetScript("OnEvent", function(_, event)
    if event == "LOOT_OPENED" then
        pcall(RecordLoot)
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        if pendingItems and not itemRefresh and dframe:IsShown() and C_Timer and C_Timer.After then
            itemRefresh = true
            C_Timer.After(0.3, function() itemRefresh = false; pcall(Levelmate.DungeonLayout) end)
        end
    else
        -- frueheres "Quests abholen" (ersetzt durch "Zuerst" je Quest): alten Zustand loeschen
        if event == "PLAYER_ENTERING_WORLD" and Levelmate_CharDB and Levelmate_CharDB.dungeonFocus then
            Levelmate_CharDB.dungeonFocus = nil
        end
        local ok = pcall(CountRun)
        if ok and dframe:IsShown() then pcall(Levelmate.UpdateDungeonFrame) end
    end
end)
