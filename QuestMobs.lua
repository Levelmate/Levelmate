-- Levelmate: Questgegner an den Namensplaketten markieren
-- Gegner, die du fuer eine Quest in deinem Log noch brauchst, bekommen ein
-- kleines Symbol mit dem Fortschritt (z. B. 3/8) ueber der Namensplakette.

Levelmate = Levelmate or {}
local QM = {}
Levelmate.QuestMobs = QM

local needed = {}       -- [Gegnername] = "3/8" (oder "" ohne Zaehler)
local marks = {}        -- [Namensplakette] = Symbol-Frame

local function Enabled() return not (Levelmate_DB and Levelmate_DB.questPlates == false) end

local function Rebuild()
    needed = {}
    if not Enabled() then return end
    local Q, MobNames = Levelmate.Quests, Levelmate._MobNames
    if not (Q and Q.GetList and MobNames) then return end
    for _, lq in ipairs(Q.GetList() or {}) do
        if lq.status ~= Q.STATUS_READY then
            local ok, mobs = pcall(MobNames, lq.questID)
            for mob, keyword in pairs(ok and mobs or {}) do
                -- passendes, noch offenes Ziel suchen (Gegnername oder Gegenstand)
                local hit
                for _, o in ipairs(lq.objectives or {}) do
                    local text = o.text or ""
                    if not o.done and keyword and text:find(keyword, 1, true) then
                        hit = (o.need and o.need > 1) and string.format("%d/%d", o.have or 0, o.need) or ""
                        break
                    end
                end
                if hit and (not needed[mob] or needed[mob] == "") then needed[mob] = hit end
            end
        end
    end
end

local function Mark(plate)
    local m = marks[plate]
    if not m then
        m = CreateFrame("Frame", nil, plate)
        m:SetSize(16, 16)
        m:SetPoint("BOTTOM", plate, "TOP", 0, -2)
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\GossipFrame\\ActiveQuestIcon")
        t:SetAllPoints()
        m.icon = t
        local fs = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", m, "RIGHT", 1, 0)
        fs:SetTextColor(1, 0.82, 0)
        m.text = fs
        marks[plate] = m
    end
    return m
end

local function UpdateUnit(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local name = UnitName(unit)
    local need = Enabled() and name and needed[name]
    local show = need and not UnitIsPlayer(unit) and not UnitIsDead(unit)
        and (UnitCanAttack and UnitCanAttack("player", unit))
    if show then
        local m = Mark(plate)
        m.text:SetText(need)
        m:Show()
    elseif marks[plate] then
        marks[plate]:Hide()
    end
end

local function UpdateAll()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then UpdateUnit(unit) elseif marks[plate] then marks[plate]:Hide() end
    end
end

function QM.Refresh() Rebuild(); UpdateAll() end

local f = CreateFrame("Frame")
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD" }) do
    pcall(f.RegisterEvent, f, ev)
end
local pending = false
f:SetScript("OnEvent", function(_, event, unit)
    if event == "NAME_PLATE_UNIT_ADDED" then
        UpdateUnit(unit)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        if plate and marks[plate] then marks[plate]:Hide() end
    else
        -- Questlog aendert sich oft in schneller Folge: gebuendelt neu aufbauen
        if pending then return end
        pending = true
        local function Go() pending = false; QM.Refresh() end
        if C_Timer and C_Timer.After then C_Timer.After(0.5, Go) else Go() end
    end
end)
