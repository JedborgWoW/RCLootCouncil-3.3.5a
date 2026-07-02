-- RCLootCouncil_WotLKFix.lua
-- Compatibility layer for RCLootCouncil v3.21.1 on standard WotLK 3.3.5a
-- (vanilla WotLK private servers — no Dragonflight API backports)
--
-- Ground truth: the old RCLootCouncil v2.0.4 (WotLK) works fine on 3.3.5a.
-- It stores council members as NAME strings, not GUIDs. It uses:
--   GetRaidRosterInfo only in raids; GetPartyMember/UnitName in parties.
--   UnitInRaid / UnitInParty for council-in-group checks.
--   UnitIsUnit for player comparison.
--   GetPlayerInfo returns: name, class, role, guildRank, enchant, lvl.
-- We replicate these patterns in our patches.
--
-- MUST be the FIRST file loaded in the TOC.
-- Design: every shim is guarded with `if not X then` so native APIs take priority.

-- ============================================================
-- 1. ENUM SHIMS
-- ============================================================
if not Enum then Enum = {} end

if not Enum.ItemBind then
    Enum.ItemBind = { None=0, OnAcquire=1, OnEquip=2, OnUse=3, Quest=4 }
end
if not Enum.LootMethod then
    Enum.LootMethod = { Freeforall=0, Roundrobin=1, Masterlooter=2, Group=3, Needbeforegreed=4, Personal=5 }
end
if not Enum.ItemClass then
    Enum.ItemClass = {
        Consumable=0, Container=1, Weapon=2, Gem=3, Armor=4, Reagent=5,
        Projectile=6, Tradegoods=7, ItemEnhancement=8, Recipe=9, Quiver=11,
        Questitem=12, Quest=12, Key=13, Miscellaneous=15, Glyph=16,
        Profession=19, Housing=20,
    }
end
if not Enum.ItemArmorSubclass then
    Enum.ItemArmorSubclass = {
        Generic=0, Cloth=1, Leather=2, Mail=3, Plate=4, Cosmetic=5,
        Shield=6, Libram=7, Idol=8, Totem=9, Sigil=10, Relic=11,
    }
end
if not Enum.ItemWeaponSubclass then
    Enum.ItemWeaponSubclass = {
        Axe1H=0, Axe2H=1, Bows=2, Guns=3, Mace1H=4, Mace2H=5, Polearm=6,
        Sword1H=7, Sword2H=8, Warglaive=9, Staff=10, Bearclaw=11, Catclaw=12,
        Unarmed=13, Generic=14, Dagger=15, Thrown=16, Spear=17,
        Crossbow=18, Wand=19, Fishingpole=20,
    }
end
if not Enum.ItemMiscellaneousSubclass then
    Enum.ItemMiscellaneousSubclass = { Junk=0, Reagent=1, CompanionPet=2, Companion=2, Holiday=3, Other=4, Mount=5 }
end
if not Enum.ItemQuality then
    Enum.ItemQuality = { Poor=0, Common=1, Uncommon=2, Rare=3, Epic=4, Legendary=5, Artifact=6, Heirloom=7 }
end
if not Enum.TooltipDataLineType then Enum.TooltipDataLineType = { None=0 } end
if not Enum.ItemReagentSubclass then Enum.ItemReagentSubclass = { ContextToken=99 } end
if not Enum.ItemSlotFilterType then Enum.ItemSlotFilterType = { NoFilter=0, Trinket=11 } end
if not Enum.TooltipDataType then Enum.TooltipDataType = { Item=0 } end
if not Enum.AddOnRestrictionState then Enum.AddOnRestrictionState = { Active=0, Activating=1 } end
-- CommsRestrictions.lua calls tInvert(Enum.AddOnRestrictionType) at file scope — must exist.
if not Enum.AddOnRestrictionType then
    Enum.AddOnRestrictionType = { None=0, Encounter=1, ChallengeMode=2, Map=3 }
end
if not Enum.SendAddonMessageResult then
    Enum.SendAddonMessageResult = {
        Success=0, AddonMessageThrottle=3, InvalidPrefix=4, NotInGroup=5,
        TargetRequired=6, InvalidChatType=7, ChannelThrottle=8, GeneralError=9,
    }
end

-- ============================================================
-- 2. WOW_PROJECT CONSTANTS
-- ============================================================
if WOW_PROJECT_MAINLINE == nil then WOW_PROJECT_MAINLINE = 1 end
if WOW_PROJECT_CLASSIC == nil then WOW_PROJECT_CLASSIC = 2 end
if WOW_PROJECT_WRATH_CLASSIC == nil then WOW_PROJECT_WRATH_CLASSIC = 11 end
if WOW_PROJECT_ID == nil then WOW_PROJECT_ID = WOW_PROJECT_WRATH_CLASSIC end

-- ============================================================
-- 3. GROUP API SHIMS
-- Old addon pattern: IsInRaid() -> GetNumRaidMembers() > 0
--                   IsInGroup() -> GetNumPartyMembers() > 0 (party only, excl. raid)
-- New addon uses IsInRaid / IsInGroup / GetNumGroupMembers globals.
-- ============================================================
if not IsInRaid then
    IsInRaid = function() return GetNumRaidMembers() > 0 end
end
if not IsInGroup then
    IsInGroup = function() return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0 end
end
if not GetNumGroupMembers then
    GetNumGroupMembers = function()
        local r = GetNumRaidMembers()
        if r > 0 then return r end
        local p = GetNumPartyMembers()
        return p > 0 and (p + 1) or 0
    end
end
if not UnitIsGroupLeader then
    UnitIsGroupLeader = function(unit)
        if unit == "player" then return IsRaidLeader() or IsPartyLeader() end
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name, rank = GetRaidRosterInfo(i)
                if name == UnitName(unit) then return rank == 2 end
            end
        end
        return UnitIsPartyLeader and UnitIsPartyLeader(unit) or false
    end
end
if not UnitIsGroupAssistant then
    UnitIsGroupAssistant = function(unit)
        if GetNumRaidMembers() > 0 then
            for i = 1, GetNumRaidMembers() do
                local name, rank = GetRaidRosterInfo(i)
                if name == UnitName(unit) then return rank == 1 end
            end
        end
        return false
    end
end
if not IsPartyLFG then IsPartyLFG = function() return false end end
if not IsInLFGDungeon then IsInLFGDungeon = function() return false end end
if not IsPartyWorldPVP then IsPartyWorldPVP = function() return false end end

-- ============================================================
-- 4. Ambiguate SHIM (MoP+ — not present on WotLK at all)
--    On standard WotLK servers, strip realm suffix if present.
-- ============================================================
if not Ambiguate then
    Ambiguate = function(name, context)
        if type(name) ~= "string" then return name end
        return name:match("^([^%-]+)") or name
    end
end

-- ============================================================
-- 5. LOOT API SHIMS
-- ============================================================
if not LootSlotHasItem then
    LootSlotHasItem = LootSlotIsItem or function(slot) return GetLootSlotLink(slot) ~= nil end
end
if not GetLootSourceInfo then
    GetLootSourceInfo = function(slot)
        local guid = UnitGUID and UnitGUID("target")
        if guid then return guid, 1 end
    end
end

-- GetLootSlotInfo signature adapter:
--   WotLK: texture, item, quantity, quality, locked
--   Retail: texture, name, quantity, currencyID, quality, locked, ...
do
    local orig = GetLootSlotInfo
    GetLootSlotInfo = function(slot)
        local a, b, c, d, e, f, g, h = orig(slot)
        if type(e) == "boolean" then
            -- WotLK: d=quality, e=locked -> remap to retail positions
            return a, b, c, nil, d, e
        end
        return a, b, c, d, e, f, g, h
    end
end

-- ============================================================
-- 6. ITEM INFO SIGNATURE ADAPTER
--    WotLK GetItemInfo: 11 values (no typeID, subTypeID, bindType)
--    We derive them from localized strings + tooltip scan.
-- ============================================================
local ItemTypeNameToID = {
    ["Consumable"]=0, ["Container"]=1, ["Weapon"]=2, ["Gem"]=3, ["Armor"]=4,
    ["Reagent"]=5, ["Projectile"]=6, ["Trade Goods"]=7, ["Item Enhancement"]=8,
    ["Recipe"]=9, ["Quiver"]=11, ["Quest"]=12, ["Key"]=13, ["Miscellaneous"]=15, ["Glyph"]=16,
}
local SubTypeNameToID = {
    [4] = { -- Armor
        ["Miscellaneous"]=0, ["Cloth"]=1, ["Leather"]=2, ["Mail"]=3, ["Plate"]=4,
        ["Shields"]=6, ["Shield"]=6, ["Librams"]=7, ["Idols"]=8, ["Totems"]=9, ["Sigils"]=10, ["Relic"]=11,
    },
    [2] = { -- Weapon
        ["One-Handed Axes"]=0, ["Two-Handed Axes"]=1, ["Bows"]=2, ["Guns"]=3,
        ["One-Handed Maces"]=4, ["Two-Handed Maces"]=5, ["Polearms"]=6, ["One-Handed Swords"]=7,
        ["Two-Handed Swords"]=8, ["Staves"]=10, ["Fist Weapons"]=13, ["Miscellaneous"]=14,
        ["Daggers"]=15, ["Thrown"]=16, ["Spears"]=17, ["Crossbows"]=18, ["Wands"]=19, ["Fishing Poles"]=20,
    },
    [15] = { ["Junk"]=0, ["Reagent"]=1, ["Pet"]=2, ["Companion Pets"]=2, ["Holiday"]=3, ["Other"]=4, ["Mount"]=5 },
}
local bindTypeCache = {}
local bindScanTip
local function ScanBindType(link)
    if not link then return 0 end
    local itemID = link:match("item:(%d+)")
    if itemID and bindTypeCache[itemID] then return bindTypeCache[itemID] end
    if not bindScanTip then
        bindScanTip = CreateFrame("GameTooltip", "RCWotLKFixBindScanTip", nil, "GameTooltipTemplate")
    end
    bindScanTip:SetOwner(UIParent, "ANCHOR_NONE")
    bindScanTip:SetHyperlink(link)
    local bind = 0
    for i = 2, math.min(4, bindScanTip:NumLines()) do
        local t = _G["RCWotLKFixBindScanTipTextLeft"..i]
        local text = t and t:GetText()
        if text then
            if text == ITEM_BIND_ON_PICKUP or text == ITEM_SOULBOUND then bind = 1; break
            elseif text == ITEM_BIND_ON_EQUIP then bind = 2; break
            elseif text == ITEM_BIND_ON_USE then bind = 3; break
            elseif text == ITEM_BIND_QUEST then bind = 4; break
            end
        end
    end
    bindScanTip:Hide()
    if itemID then bindTypeCache[itemID] = bind end
    return bind
end

local function AdaptedGetItemInfo(item)
    local name, link, quality, ilvl, reqLvl, itemType, itemSubType,
          stackCount, equipLoc, texture, vendorPrice,
          typeID, subTypeID, bindType, expacID, setID, isCraftingReagent = GetItemInfo(item)
    if not name then return nil end
    if typeID ~= nil then
        return name, link, quality, ilvl, reqLvl, itemType, itemSubType,
               stackCount, equipLoc, texture, vendorPrice, typeID, subTypeID, bindType, expacID, setID, isCraftingReagent
    end
    typeID = ItemTypeNameToID[itemType] or 0
    subTypeID = (SubTypeNameToID[typeID] and SubTypeNameToID[typeID][itemSubType]) or 0
    bindType = ScanBindType(link)
    return name, link, quality, ilvl, reqLvl, itemType, itemSubType,
           stackCount, equipLoc, texture, vendorPrice, typeID, subTypeID, bindType, nil, nil, false
end

-- ============================================================
-- 7. C_Item SHIMS
-- ============================================================
if not C_Item then C_Item = {} end
-- On plain WotLK, C_Item doesn't exist — always use the adapter.
C_Item.GetItemInfo = AdaptedGetItemInfo

if not C_Item.GetItemInfoInstant then
    C_Item.GetItemInfoInstant = function(item)
        -- itemID and icon can be resolved without the full item being cached,
        -- which matters for other players' gear we haven't seen yet.
        local itemID = tonumber(tostring(item)) or (tostring(item):match("item:(%d+)"))
        itemID = tonumber(itemID)
        local name, link, _, _, _, itemType, itemSubType, _, equipLoc, texture, _, typeID, subTypeID = C_Item.GetItemInfo(item)
        -- Fallback icon via GetItemIcon (works uncached on WotLK).
        if not texture and itemID and GetItemIcon then
            texture = GetItemIcon(itemID)
        end
        if not itemID and link then itemID = tonumber(link:match("item:(%d+)")) end
        return itemID, itemType, itemSubType, equipLoc, texture, typeID, subTypeID
    end
end
if not C_Item.GetItemStats then C_Item.GetItemStats = GetItemStats end
if not C_Item.IsEquippableItem then C_Item.IsEquippableItem = IsEquippableItem end
if not C_Item.GetItemFamily then C_Item.GetItemFamily = GetItemFamily end
if not C_Item.GetItemQualityColor then C_Item.GetItemQualityColor = GetItemQualityColor end
if not C_Item.IsItemBindToAccountUntilEquip then C_Item.IsItemBindToAccountUntilEquip = function() return false end end
if not C_Item.IsCorruptedItem then C_Item.IsCorruptedItem = function() return false end end
if not C_Item.UnlockItem then C_Item.UnlockItem = function() end end

-- ============================================================
-- 8. C_Container ADAPTER
--    WotLK GetContainerItemInfo returns multi-value, not a table.
-- ============================================================
do
    if not C_Container then C_Container = {} end
    local nativeGCII = GetContainerItemInfo
    if nativeGCII then
        C_Container.GetContainerItemInfo = function(bag, slot)
            local r = { nativeGCII(bag, slot) }
            if type(r[1]) == "table" then return r[1] end
            local texture, itemCount, locked, quality, readable, lootable, itemLink, isFiltered, noValue, itemID = unpack(r)
            if texture == nil and itemLink == nil then return nil end
            return {
                iconFileID=texture, stackCount=itemCount, isLocked=locked, quality=quality,
                isReadable=readable, hasLoot=lootable, hyperlink=itemLink,
                isFiltered=isFiltered, hasNoValue=noValue, itemID=itemID, isBound=nil,
            }
        end
    end
    if not C_Container.GetContainerNumSlots then C_Container.GetContainerNumSlots = GetContainerNumSlots end
    if not C_Container.GetContainerItemLink then C_Container.GetContainerItemLink = GetContainerItemLink end
    if not C_Container.GetContainerNumFreeSlots then C_Container.GetContainerNumFreeSlots = GetContainerNumFreeSlots end
    if not C_Container.PickupContainerItem then C_Container.PickupContainerItem = PickupContainerItem end
    if not C_Container.UseContainerItem then C_Container.UseContainerItem = UseContainerItem end
end

-- ============================================================
-- 9. C_AddOns SHIMS
-- ============================================================
if not C_AddOns then C_AddOns = {} end
if not C_AddOns.GetAddOnMetadata then C_AddOns.GetAddOnMetadata = GetAddOnMetadata end
if not C_AddOns.LoadAddOn then C_AddOns.LoadAddOn = LoadAddOn end
if not C_AddOns.IsAddOnLoaded then C_AddOns.IsAddOnLoaded = IsAddOnLoaded end

if not securecallfunction then
    securecallfunction = function(fn, ...)
        if type(fn) == "function" then return select(2, pcall(fn, ...)) end
    end
end

-- ============================================================
-- 10. C_ChatInfo SHIMS
--     On WotLK 3.3.5a, addon message prefixes are NOT filtered —
--     no registration needed. Simple no-ops are correct here.
-- ============================================================
if not RegisterAddonMessagePrefix then
    RegisterAddonMessagePrefix = function() return true end
end
if not C_ChatInfo then C_ChatInfo = {} end
if not C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix = function() return true end
end
if not C_ChatInfo.SendAddonMessage then
    C_ChatInfo.SendAddonMessage = function(prefix, text, chattype, target)
        SendAddonMessage(prefix, text, chattype, target)
        return Enum.SendAddonMessageResult.Success
    end
end
if not C_ChatInfo.SendChatMessage then C_ChatInfo.SendChatMessage = SendChatMessage end

-- ============================================================
-- 11. ENCOUNTER JOURNAL STUBS (Cata+, absent on WotLK)
-- ============================================================
if not C_EncounterJournal then C_EncounterJournal = {} end
if not C_EncounterJournal.GetLootInfoByIndex then C_EncounterJournal.GetLootInfoByIndex = function() return nil end end
if not C_EncounterJournal.GetInstanceForGameMap then C_EncounterJournal.GetInstanceForGameMap = function() return 0 end end
if not C_EncounterJournal.SetSlotFilter then C_EncounterJournal.SetSlotFilter = function() end end
if not EJ_GetNumTiers then EJ_GetNumTiers = function() return 0 end end
if not EJ_SelectTier then EJ_SelectTier = function() end end
if not EJ_GetInstanceByIndex then EJ_GetInstanceByIndex = function() return nil end end
if not EJ_SelectInstance then EJ_SelectInstance = function() end end
if not EJ_GetInstanceInfo then EJ_GetInstanceInfo = function() return nil end end
if not EJ_GetNumLoot then EJ_GetNumLoot = function() return 0 end end
if not EJ_SetDifficulty then EJ_SetDifficulty = function() end end
if not EJ_ResetLootFilter then EJ_ResetLootFilter = function() end end
if not EJ_SetLootFilter then EJ_SetLootFilter = function() end end
if not EJ_IsValidInstanceDifficulty then EJ_IsValidInstanceDifficulty = function() return false end end

-- ============================================================
-- 12. SPECIALIZATION STUBS (WotLK has no retail spec system)
-- ============================================================
if not C_SpecializationInfo then
    C_SpecializationInfo = { GetSpecialization=function() return nil end, GetSpecializationInfo=function() return nil end }
end
if not GetSpecialization then GetSpecialization = function() return nil end end
if not GetSpecializationInfo then GetSpecializationInfo = function() return nil end end
if not GetSpecializationInfoByID then GetSpecializationInfoByID = function() return nil end end
if not GetNumSpecializationsForClassID then GetNumSpecializationsForClassID = function() return 0 end end
if not GetSpecializationInfoForClassID then GetSpecializationInfoForClassID = function() return nil end end

-- ============================================================
-- 13. ROLE SHIM
-- ============================================================
if not UnitGroupRolesAssigned then
    UnitGroupRolesAssigned = function() return "NONE" end
end

-- ============================================================
-- 14. MISC NAMESPACE STUBS
-- ============================================================
if not C_TransmogCollection then
    C_TransmogCollection = {
        GetItemInfo=function() return nil end, GetAllAppearanceSources=function() return {} end,
        GetAppearanceSourceInfo=function() return nil end, PlayerCanCollectSource=function() return false, false end,
    }
end
if not C_Covenants then C_Covenants = { GetActiveCovenantID=function() return 0 end } end
if not C_RestrictedActions then C_RestrictedActions = { IsAddOnRestrictionActive=function() return false end } end
if not C_Secrets then C_Secrets = { HasSecretRestrictions=function() return false end } end
if not C_PlayerInfo then C_PlayerInfo = {} end
if not C_PlayerInfo.UnitIsSameServer then C_PlayerInfo.UnitIsSameServer = function() return true end end
if not PlayerLocation then
    PlayerLocation = { CreateFromGUID=function(guid) return {guid=guid} end, CreateFromUnit=function(unit) return {unit=unit} end }
end

-- Frame method shims for methods added after 3.3.5a.
do
    local function addMethod(frame, name, fn)
        local mt = getmetatable(frame)
        local idx = mt and mt.__index
        if type(idx) == "table" and not idx[name] then idx[name] = fn end
    end
    local pf = CreateFrame("Frame")
    local pt = CreateFrame("GameTooltip", "RCWotLKFixProbeTooltip", nil, "GameTooltipTemplate")
    local noop = function() end
    for _, f in ipairs({pf, pt}) do
        addMethod(f, "SetIgnoreParentScale", noop)
        addMethod(f, "SetIgnoreParentAlpha", noop)
        addMethod(f, "SetWindow", noop)
        addMethod(f, "GetIgnoreParentScale", function() return false end)
    end
    local ok, ag = pcall(function() return pf:CreateAnimationGroup() end)
    if ok and ag then
        local oka, aa = pcall(function() return ag:CreateAnimation("Alpha") end)
        if oka and aa then
            local mt = getmetatable(aa)
            local idx = mt and mt.__index
            if type(idx) == "table" then
                if not idx.SetFromAlpha then
                    idx.SetFromAlpha = function(self, v)
                        self.__fromAlpha = v
                        if self.SetChange and self.__toAlpha then self:SetChange(self.__toAlpha - v) end
                    end
                end
                if not idx.SetToAlpha then
                    idx.SetToAlpha = function(self, v)
                        self.__toAlpha = v
                        if self.SetChange and self.__fromAlpha then self:SetChange(v - self.__fromAlpha)
                        elseif self.SetChange then self:SetChange(v) end
                    end
                end
            end
        end
    end
end

if not C_FriendList then
    C_FriendList = { GetNumOnlineFriends=function() return 0 end, GetFriendInfoByIndex=function() return nil end }
end

-- PlaySound: WotLK expects string names; numeric IDs crash it.
if not SOUNDKIT then SOUNDKIT = setmetatable({}, {__index=function() return 0 end}) end
do
    local myShim
    local function install()
        if _G.PlaySound == myShim then return end
        local orig = _G.PlaySound
        myShim = function(sound, ...)
            if type(sound) ~= "string" then return end
            if orig then pcall(orig, sound, ...) end
        end
        _G.PlaySound = myShim
    end
    install()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", install)
end
do
    local orig = _G.PlaySoundFile
    if orig then
        _G.PlaySoundFile = function(file, channel, ...)
            if type(file) ~= "string" and type(file) ~= "number" then return end
            if not pcall(orig, file, channel, ...) then pcall(orig, file) end
        end
    end
end

if not C_GuildInfo then C_GuildInfo = {} end
if not C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster = GuildRoster end

-- GetGuildRosterInfo on WotLK returns 16 values — no GUID at position 17.
-- The new addon reads position 17 for council storage.
-- We inject a name-based key so Player:Get() can resolve it.
do
    local orig = GetGuildRosterInfo
    if orig then
        GetGuildRosterInfo = function(index)
            local t = { orig(index) }
            local name = t[1]
            if not t[17] and name then
                -- Use the bare character name as the "GUID" key.
                -- UpdateGroupCouncil resolves via candidates[player.name],
                -- and our UnitName normalization ensures names match.
                t[17] = name:match("^([^%-]+)") or name
            end
            return unpack(t, 1, 17)
        end
    end
end

if not C_DateAndTime then C_DateAndTime = {} end
if not C_DateAndTime.GetServerTimeLocal then
    C_DateAndTime.GetServerTimeLocal = function() return GetServerTime and GetServerTime() or time() end
end

-- ============================================================
-- 15. GLOBAL FUNCTION SHIMS
-- ============================================================
if not GetServerTime then GetServerTime = time end
if not UnitFullName then
    UnitFullName = function(unit) return UnitName(unit), GetRealmName() end
end
if not GetAverageItemLevel then
    -- WotLK has no native GetAverageItemLevel. Compute it by scanning the
    -- 17 equipment slots (1-17, skipping shirt/tabard which don't count)
    -- and averaging their item levels. Returns (overall, equipped, pvp)
    -- to match the retail signature; we return the same value for all.
    GetAverageItemLevel = function()
        local total, count = 0, 0
        -- Slots: 1 head ... 17 off-hand. Skip 4 (shirt) and 19 (tabard).
        for slot = 1, 18 do
            if slot ~= 4 then  -- skip shirt
                local link = GetInventoryItemLink("player", slot)
                if link then
                    local ilvl = select(4, GetItemInfo(link))
                    if ilvl and ilvl > 0 then
                        total = total + ilvl
                        count = count + 1
                    end
                end
            end
        end
        local avg = count > 0 and (total / count) or 0
        return avg, avg, avg
    end
end
if not GetProfessions then GetProfessions = function() return nil end end
if not GetProfessionInfo then GetProfessionInfo = function() return nil end end
if not UnitPosition then UnitPosition = function() return nil end end
if not IsGuildMember then IsGuildMember = function() return false end end

-- GetPlayerInfoByGUID: WotLK has this since 3.2, but the new addon
-- sometimes passes plain names when no GUID is available.
-- Wrap to handle names via guild roster / unit data.
do
    local native = GetPlayerInfoByGUID
    local rawRoster = GetGuildRosterInfo
    local function lookupByName(query)
        local short = query:match("^([^%-]+)") or query
        local realm = GetRealmName and GetRealmName() or ""
        if UnitExists and UnitExists(short) then
            local locClass, class = UnitClass(short)
            if class then return locClass, class, nil, nil, nil, short, realm end
        end
        if rawRoster and IsInGuild and IsInGuild() then
            local n = GetNumGuildMembers and GetNumGuildMembers() or 0
            for i = 1, n do
                local gname, _, _, _, classDisplay, _, _, _, _, _, classFile = rawRoster(i)
                if gname and (gname:match("^([^%-]+)") or gname) == short then
                    return classDisplay, classFile, nil, nil, nil, short, realm
                end
            end
        end
        return nil
    end
    GetPlayerInfoByGUID = function(guid)
        -- Native WotLK GUIDs are hex strings ("0x0180000000ABC123") — the
        -- native API handles those directly; never treat them as names.
        if type(guid) == "string" and guid:match("^0x%x+$") then
            if native then
                local r = { pcall(native, guid) }
                if r[1] then return select(2, unpack(r)) end
            end
            return nil
        end
        if type(guid) == "string" and guid:match("^Player%-%d") then
            if native then
                local r = { pcall(native, guid) }
                if r[1] then return select(2, unpack(r)) end
            end
            return nil
        end
        if type(guid) == "string" and guid ~= "" then return lookupByName(guid) end
        return nil
    end
end

if not GetCurrentRegion then GetCurrentRegion = function() return 3 end end
-- AceDB-3.0 (line ~263) does: regionTable[GetCurrentRegion()] or GetCurrentRegionName() or "TR".
-- GetCurrentRegionName is a retail global that doesn't exist on 3.3.5a; calling a nil
-- global there would error at AceDB load time. Shim it so the fallback path is safe,
-- returning "US" as a sensible default region for private servers.
if type(GetCurrentRegionName) ~= "function" then GetCurrentRegionName = function() return "US" end end

if not SecondsToTime then
    SecondsToTime = function(seconds, noSeconds)
        seconds = math.floor(seconds or 0)
        local d = math.floor(seconds/86400); seconds = seconds%86400
        local h = math.floor(seconds/3600);  seconds = seconds%3600
        local m = math.floor(seconds/60);    local s = seconds%60
        local p = {}
        if d>0 then p[#p+1]=d..(d==1 and " day" or " days") end
        if h>0 then p[#p+1]=h..(h==1 and " hr" or " hrs") end
        if m>0 then p[#p+1]=m..(m==1 and " min" or " mins") end
        if not noSeconds and s>0 then p[#p+1]=s..(s==1 and " sec" or " secs") end
        return #p>0 and table.concat(p," ") or "0 secs"
    end
end

if not GetDifficultyInfo then GetDifficultyInfo = function() return nil end end
if not RunNextFrame then RunNextFrame = function(func) C_Timer.After(0, func) end end

if not tIndexOf then
    tIndexOf = function(tbl, value)
        for i,v in ipairs(tbl) do if v==value then return i end end
        return nil
    end
end
if not tInvert then
    tInvert = function(tbl)
        local r = {}
        if type(tbl)~="table" then return r end
        for k,v in pairs(tbl) do r[v]=k end
        return r
    end
end
if not tFilter then
    tFilter = function(tbl, pred, isIndexed)
        local r = {}
        if type(tbl)~="table" then return r end
        if isIndexed then
            for _,v in ipairs(tbl) do if pred(v) then r[#r+1]=v end end
        else
            for k,v in pairs(tbl) do if pred(v) then r[k]=v end end
        end
        return r
    end
end
if not tAppendAll then
    tAppendAll = function(dst, src)
        for _,v in ipairs(src) do tinsert(dst,v) end
        return dst
    end
end
if not tInsertUnique then
    tInsertUnique = function(tbl, value)
        for _,v in ipairs(tbl) do if v==value then return end end
        tinsert(tbl, value)
    end
end
if not tCompare then
    tCompare = function(lhs, rhs, maxDepth)
        if type(lhs)~="table" or type(rhs)~="table" then return lhs==rhs end
        maxDepth = maxDepth or 1
        for k,v in pairs(lhs) do
            local rv = rhs[k]
            if type(v)=="table" and type(rv)=="table" then
                if maxDepth>1 and not tCompare(v,rv,maxDepth-1) then return false end
            elseif v~=rv then return false end
        end
        for k in pairs(rhs) do if lhs[k]==nil then return false end end
        return true
    end
end
if not AccumulateOp then
    AccumulateOp = function(tbl, op)
        local t = 0
        for _,v in pairs(tbl) do t = t + (op(v) or 0) end
        return t
    end
end
if not WrapTextInColorCode then
    WrapTextInColorCode = function(text, hex) return "|c"..(hex or "ffffffff")..(text or "").."|r" end
end
if not CreateSimpleTextureMarkup then
    CreateSimpleTextureMarkup = function(texture, width, height)
        width = width or 16; height = height or width
        if texture then return string.format("|T%s:%d:%d|t", texture, height, width) end
        return ""
    end
end
if not CreateAtlasMarkup then CreateAtlasMarkup = function() return "" end end
if not ConvertSecondsToUnits then
    ConvertSecondsToUnits = function(seconds)
        seconds = math.abs(seconds or 0)
        return {
            days=math.floor(seconds/86400), hours=math.floor((seconds%86400)/3600),
            minutes=math.floor((seconds%3600)/60), seconds=math.floor(seconds%60),
        }
    end
end
if not Clamp then Clamp = function(v,mn,mx) return math.min(math.max(v,mn),mx) end end
if not CopyTable then
    CopyTable = function(t, shallow)
        local c = {}
        for k,v in pairs(t) do
            c[k] = (type(v)=="table" and not shallow) and CopyTable(v) or v
        end
        return c
    end
end
if not MergeTable then
    MergeTable = function(dst, src)
        for k,v in pairs(src) do dst[k]=v end
        return dst
    end
end
if not FindInTableIf then
    FindInTableIf = function(tbl, pred)
        for k,v in pairs(tbl) do if pred(v) then return k,v end end
        return nil
    end
end
if not FindValueInTableIf then
    FindValueInTableIf = function(tbl, pred)
        for _,v in pairs(tbl) do if pred(v) then return v end end
        return nil
    end
end
if not ContainsIf then
    ContainsIf = function(tbl, pred)
        for _,v in pairs(tbl) do if pred(v) then return true end end
        return false
    end
end
if not TableIsArray then
    TableIsArray = function(tbl)
        if type(tbl)~="table" then return false end
        local n=0; for _ in pairs(tbl) do n=n+1 end
        return n==#tbl
    end
end

-- CreateColor with full ColorMixin.
do
    local cm = {}
    function cm:GetRGB() return self.r, self.g, self.b end
    function cm:GetRGBA() return self.r, self.g, self.b, self.a end
    function cm:GenerateHexColor()
        return string.format("ff%02x%02x%02x", (self.r or 1)*255, (self.g or 1)*255, (self.b or 1)*255)
    end
    function cm:GenerateHexColorMarkup() return "|c"..self:GenerateHexColor() end
    function cm:WrapTextInColorCode(text) return "|c"..self:GenerateHexColor()..text.."|r" end
    CreateColor = function(r,g,b,a)
        local c = {r=r or 1, g=g or 1, b=b or 1, a=a or 1}
        for k,v in pairs(cm) do c[k]=v end
        return c
    end
end

-- GetClassColorObj: WotLK has no native; build from RAID_CLASS_COLORS.
do
    local cache = {}
    local function wrapColor(col)
        if not col.WrapTextInColorCode then
            function col:WrapTextInColorCode(text)
                return string.format("|cff%02x%02x%02x%s|r", (self.r or 1)*255, (self.g or 1)*255, (self.b or 1)*255, text)
            end
        end
        if not col.GetRGB then function col:GetRGB() return self.r, self.g, self.b end end
        if not col.GenerateHexColor then
            function col:GenerateHexColor()
                return string.format("ff%02x%02x%02x", (self.r or 1)*255, (self.g or 1)*255, (self.b or 1)*255)
            end
        end
        return col
    end
    GetClassColorObj = function(class)
        if not class then return nil end
        if cache[class] then return cache[class] end
        local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if not col then return nil end
        local wrapped = wrapColor({r=col.r, g=col.g, b=col.b, a=col.a or 1})
        cache[class] = wrapped
        return wrapped
    end
end

-- ============================================================
-- 16. C_Timer SHIM
-- ============================================================
if not C_Timer then
    C_Timer = {}
    C_Timer.After = function(delay, func)
        local f = CreateFrame("Frame"); local e = 0
        f:SetScript("OnUpdate", function(self, dt)
            e = e + dt
            if e >= delay then self:SetScript("OnUpdate", nil); func() end
        end)
    end
    C_Timer.NewTimer = function(delay, func)
        local t = {cancelled=false}
        function t:Cancel() self.cancelled=true end
        C_Timer.After(delay, function() if not t.cancelled then func() end end)
        return t
    end
    C_Timer.NewTicker = function(interval, func, iterations)
        local t = {cancelled=false, count=0}
        function t:Cancel() self.cancelled=true end
        local f = CreateFrame("Frame"); local e = 0
        f:SetScript("OnUpdate", function(self, dt)
            if t.cancelled then self:SetScript("OnUpdate",nil); return end
            e = e + dt
            if e >= interval then
                e = e - interval; t.count = t.count + 1; func()
                if iterations and t.count >= iterations then t.cancelled=true end
            end
        end)
        return t
    end
end

-- ============================================================
-- 17. MISSING BLIZZARD GLOBAL STRINGS
-- ============================================================
local GLOBAL_STRING_FALLBACKS = {
    REQUEST_ROLL="Request Roll", ROLL_DISENCHANT="Disenchant", CLOSES_IN="Closes in",
    ITEM_CLASSES_ALLOWED="Classes: %s", ITEM_LEVEL_ABBR="iLvl", APPEARANCE_LABEL="Appearance",
    CORRUPTION_COLOR="Corruption", ITEM_MOD_CORRUPTION="Corruption", BONUS_ROLL_TOOLTIP_TITLE="Bonus Roll",
    HOUSING_ITEM_TOAST_TYPE_DECOR="Decor", RESET_TO_DEFAULT="Reset to Default",
    LE_GAME_ERR_TRADE_COMPLETE="Trade complete.", ITEM_CORRUPTION_BONUS_STAT="Corruption",
    ITEM_MOD_CR_AVOIDANCE_SHORT="Avoidance", ITEM_MOD_CR_LIFESTEAL_SHORT="Leech",
    ITEM_MOD_CR_SPEED_SHORT="Speed", ITEM_MOD_CR_STURDINESS_SHORT="Indestructible",
    HISTORY="History", STATUS="Status", AWARD_FOR="Award for", CHANGE_RESPONSE="Change Response",
    SETTINGS="Settings", ITEM_QUALITY2_DESC="Uncommon", DAMAGER="Damage", HEALER="Healer", TANK="Tank",
    BIND_TRADE_TIME_REMAINING="You may trade this item with players that were also eligible to loot this item for the next %s.",
    INT_SPELL_DURATION_HOURS="|4hour:hours;", INT_SPELL_DURATION_MIN="|4min:min;",
    INT_SPELL_DURATION_SEC="|4sec:sec;", TIME_UNIT_DELIMITER=" ", ROLL="Roll",
    MAINSPEC_GREED="Mainspec/Need", FRIENDS_FRIENDS_CHOICE_EVERYONE="Everyone",
    ADD="Add", CHANNEL="Channel ", HELP_LABEL="Help", LABEL_NOTE="Note", RANK="Rank",
    RESET="Reset", RETRIEVING_ITEM_INFO="Retrieving item information", START="Start",
    WHISPER="Whisper", CLOSE="Close", CANCEL="Cancel", ACCEPT="Accept",
    DISENCHANT="Disenchant", PASS="Pass", NEED="Need", GREED="Greed", ROLE="Role", NORMAL="Normal",
    ITEM_MOD_STRENGTH_SHORT="Strength", ITEM_MOD_AGILITY_SHORT="Agility",
    ITEM_MOD_INTELLECT_SHORT="Intellect", ITEM_MOD_SPIRIT_SHORT="Spirit",
    ITEM_MOD_STAMINA_SHORT="Stamina", ALL_CLASSES="All Classes", MELEE="Melee", RANGED="Ranged",
}
for name, fallback in pairs(GLOBAL_STRING_FALLBACKS) do
    if _G[name] == nil then _G[name] = fallback end
end

-- ColorMixin methods for WotLK color tables.
local function ensureColorMethods(c)
    if type(c)~="table" then return end
    if not c.GetRGB then function c:GetRGB() return self.r,self.g,self.b end end
    if not c.GetRGBA then function c:GetRGBA() return self.r,self.g,self.b,self.a or 1 end end
    if not c.GenerateHexColor then
        function c:GenerateHexColor()
            return string.format("ff%02x%02x%02x",(self.r or 1)*255,(self.g or 1)*255,(self.b or 1)*255)
        end
    end
    if not c.GenerateHexColorMarkup then
        function c:GenerateHexColorMarkup() return "|c"..self:GenerateHexColor() end
    end
    if not c.WrapTextInColorCode then
        function c:WrapTextInColorCode(text)
            return string.format("|cff%02x%02x%02x%s|r",(self.r or 1)*255,(self.g or 1)*255,(self.b or 1)*255,text)
        end
    end
end

if _G.NORMAL_FONT_COLOR    == nil then _G.NORMAL_FONT_COLOR    = {r=1,   g=0.82,b=0}   end
if _G.HIGHLIGHT_FONT_COLOR == nil then _G.HIGHLIGHT_FONT_COLOR = {r=1,   g=1,   b=1}   end
if _G.RED_FONT_COLOR       == nil then _G.RED_FONT_COLOR       = {r=1,   g=0.1, b=0.1} end
if _G.GREEN_FONT_COLOR     == nil then _G.GREEN_FONT_COLOR     = {r=0.1, g=1,   b=0.1} end
if _G.GRAY_FONT_COLOR      == nil then _G.GRAY_FONT_COLOR      = {r=0.5, g=0.5, b=0.5} end
ensureColorMethods(_G.NORMAL_FONT_COLOR)
ensureColorMethods(_G.HIGHLIGHT_FONT_COLOR)
ensureColorMethods(_G.RED_FONT_COLOR)
ensureColorMethods(_G.GREEN_FONT_COLOR)
ensureColorMethods(_G.GRAY_FONT_COLOR)
ensureColorMethods(_G.LIGHTYELLOW_FONT_COLOR)

if type(_G.RAID_CLASS_COLORS)   == "table" then for _,c in pairs(_G.RAID_CLASS_COLORS)   do ensureColorMethods(c) end end
if type(_G.CUSTOM_CLASS_COLORS) == "table" then for _,c in pairs(_G.CUSTOM_CLASS_COLORS) do ensureColorMethods(c) end end
if type(_G.ITEM_QUALITY_COLORS) == "table" then
    for _,entry in pairs(_G.ITEM_QUALITY_COLORS) do
        if type(entry)=="table" and not entry.color then
            entry.color = {r=entry.r or 1, g=entry.g or 1, b=entry.b or 1}
        end
        if type(entry)=="table" then ensureColorMethods(entry.color) end
    end
end
if type(_G.CORRUPTION_COLOR) ~= "table" then _G.CORRUPTION_COLOR = {r=0.6,g=0,b=0.85} end
ensureColorMethods(_G.CORRUPTION_COLOR)
if not ColorManager then
    ColorManager = {
        GetColorDataForItemQuality = function(quality)
            local entry = _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality or 0]
            if entry and entry.color then return entry end
            local c = {r=1,g=1,b=1}; ensureColorMethods(c)
            return {color=c}
        end,
    }
end

-- ============================================================
-- 18. SETTINGS UI SHIM (retail 10.0+ Settings API)
-- ============================================================
if not Settings then
    local byID = {}
    local function makeCategory(frame, name, parent)
        local cat = {ID=name, name=name, frame=frame, parent=parent, subcategories={}}
        function cat:GetID() return self.ID end
        function cat:GetName() return self.name end
        function cat:GetSubcategories() return self.subcategories end
        byID[name] = cat
        return cat
    end
    Settings = {}
    Settings.RegisterCanvasLayoutCategory = function(frame, name)
        if frame and not frame.name then frame.name = name end
        return makeCategory(frame, name, nil)
    end
    Settings.RegisterCanvasLayoutSubcategory = function(parent, frame, name)
        if frame and not frame.name then
            frame.name = name
            if parent and parent.frame then frame.parent = parent.frame.name end
        end
        local sub = makeCategory(frame, name, parent)
        if parent then tinsert(parent.subcategories, sub) end
        -- CRITICAL on WotLK: subpanels must be explicitly added to the Blizzard
        -- InterfaceOptions list (with .parent set) or they never appear and
        -- /rc council can't find the "Master Looter" category.
        if frame and InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(frame)
        end
        return sub
    end
    Settings.RegisterAddOnCategory = function(cat)
        if cat and cat.frame and InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(cat.frame)
        end
    end
    Settings.GetCategory = function(id) return byID[id] end
    Settings.OpenToCategory = function(id)
        local cat = byID[id]
        local frame = cat and cat.frame
        if InterfaceOptionsFrame_OpenToCategory then
            InterfaceOptionsFrame_OpenToCategory(frame or id)
            InterfaceOptionsFrame_OpenToCategory(frame or id)
        end
    end
    Settings._categoriesByID = byID
end
if not SettingsPanel then
    SettingsPanel = CreateFrame("Frame", "RCWotLKFixSettingsPanel", UIParent)
    SettingsPanel:Hide()
    function SettingsPanel:GetCategory(id)
        -- Return the real registered category. Its GetSubcategories() returns
        -- the subcategories registered via RegisterCanvasLayoutSubcategory
        -- (e.g. the "Master Looter" panel that holds council + auto-trade).
        local cat = Settings.GetCategory(id)
        if cat then return cat end
        -- Fallback stub if the category isn't registered yet.
        return {
            ID = id,
            GetID = function(s) return s.ID end,
            GetName = function(s) return s.ID end,
            GetSubcategories = function() return {} end,
        }
    end
    function SettingsPanel:SelectCategory(cat)
        local id = type(cat) == "table" and cat.ID or cat
        if id then Settings.OpenToCategory(id) end
    end
end
do
    local orig = HideUIPanel
    HideUIPanel = function(frame, ...)
        if frame == SettingsPanel then
            if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then orig(InterfaceOptionsFrame) end
            return
        end
        return orig(frame, ...)
    end
end

if not C_TooltipInfo then
    local st
    local function tip()
        if not st then st = CreateFrame("GameTooltip","RCWotLKFixInfoScanTip",nil,"GameTooltipTemplate") end
        return st
    end
    local function lines()
        local r = {lines={}}
        for i=1,st:NumLines() do
            local l = _G["RCWotLKFixInfoScanTipTextLeft"..i]
            r.lines[i] = {type=0, leftText=l and l:GetText() or ""}
        end
        st:Hide(); return r
    end
    C_TooltipInfo = {
        GetHyperlink = function(link) tip():SetOwner(UIParent,"ANCHOR_NONE"); st:SetHyperlink(link); return lines() end,
        GetItemByID  = function(id)   tip():SetOwner(UIParent,"ANCHOR_NONE"); st:SetHyperlink("item:"..id); return lines() end,
    }
end

-- ============================================================
-- 19. C_CreatureInfo SHIM
-- ============================================================
local VANILLA_CLASSES = {
    [1]="WARRIOR",[2]="PALADIN",[3]="HUNTER",[4]="ROGUE",
    [5]="PRIEST",[6]="DEATHKNIGHT",[7]="SHAMAN",[8]="MAGE",[9]="WARLOCK",[11]="DRUID",
}
if not C_CreatureInfo then C_CreatureInfo = {} end
if not C_CreatureInfo.GetClassInfo then
    C_CreatureInfo.GetClassInfo = function(idx)
        if GetClassInfo then
            local loc, file, id = GetClassInfo(idx)
            if file then return {className=loc, classFile=file, classID=id or idx} end
        end
        local file = VANILLA_CLASSES[idx]
        if not file then return nil end
        local loc = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[file]) or file
        return {className=loc, classFile=file, classID=idx}
    end
end
if not C_CreatureInfo.GetRaceInfo then
    C_CreatureInfo.GetRaceInfo = function(idx)
        if GetRaceInfo then
            local loc, file, id = GetRaceInfo(idx)
            if file then return {raceName=loc, clientFileString=file, raceID=id or idx} end
        end
        return nil
    end
end

-- ============================================================
-- 20. POST-LOAD PATCHES (ADDON_LOADED)
-- ============================================================
local fixFrame = CreateFrame("Frame")
fixFrame:RegisterEvent("ADDON_LOADED")
fixFrame:SetScript("OnEvent", function(self, event, name)
    if name ~= "RCLootCouncil" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local addon = RCLootCouncil
    if not addon then return end

    -- 20a. Force version check to pass.
    addon.IsCorrectVersion = function() return true end

    -- 20a-color. Re-apply ColorMixin (another addon may have replaced RAID_CLASS_COLORS).
    if type(_G.RAID_CLASS_COLORS)   == "table" then for _,c in pairs(_G.RAID_CLASS_COLORS)   do ensureColorMethods(c) end end
    if type(_G.CUSTOM_CLASS_COLORS) == "table" then for _,c in pairs(_G.CUSTOM_CLASS_COLORS) do ensureColorMethods(c) end end
    if type(_G.ITEM_QUALITY_COLORS) == "table" then
        for _,entry in pairs(_G.ITEM_QUALITY_COLORS) do
            if type(entry)=="table" then
                if not entry.color then entry.color={r=entry.r or 1,g=entry.g or 1,b=entry.b or 1} end
                ensureColorMethods(entry.color)
            end
        end
    end

    -- 20b. Mirror C_Item.
    addon.C_Item = C_Item

    -- 20c. Block Blizzard_EncounterJournal (doesn't exist on WotLK).
    local origLoad = C_AddOns.LoadAddOn
    C_AddOns.LoadAddOn = function(n, ...)
        if n == "Blizzard_EncounterJournal" then return false, "DISABLED" end
        return origLoad(n, ...)
    end

    -- 20d. CLASS WHITELIST: 9 vanilla classes only.
    local ALLOWED = {WARRIOR=true,PALADIN=true,HUNTER=true,ROGUE=true,PRIEST=true,SHAMAN=true,MAGE=true,WARLOCK=true,DRUID=true,DEATHKNIGHT=true}
    local function PruneClassTables()
        if not addon.classTagNameToID then return end
        local removeIDs = {}
        for cf, id in pairs(addon.classTagNameToID) do
            if not ALLOWED[cf] then
                removeIDs[id] = true
                addon.classTagNameToID[cf] = nil
                if addon.classTagNameToDisplayName then addon.classTagNameToDisplayName[cf] = nil end
            end
        end
        for id in pairs(removeIDs) do
            if addon.classIDToDisplayName then
                local dn = addon.classIDToDisplayName[id]
                if dn and addon.classDisplayNameToID then addon.classDisplayNameToID[dn] = nil end
                addon.classIDToDisplayName[id] = nil
            end
            if addon.classIDToFileName then addon.classIDToFileName[id] = nil end
        end
    end
    local origInit = addon.InitClassIDs
    if origInit then
        addon.InitClassIDs = function(s, ...)
            origInit(s, ...); PruneClassTables()
        end
    end
    PruneClassTables()

    -- 20e. GetClassNamesFromFlag: guard nil entries after pruning.
    addon.GetClassNamesFromFlag = function(s, classesFlag)
        local result = {}
        for i = 1, s.Utils.GetNumClasses() do
            if bit.band(classesFlag, bit.lshift(1,i-1)) > 0 then
                local class = s.classIDToFileName and s.classIDToFileName[i]
                local classText = s.classIDToDisplayName and s.classIDToDisplayName[i]
                if class and classText then
                    local colorObj = GetClassColorObj(class)
                    result[#result+1] = colorObj and colorObj:WrapTextInColorCode(classText) or classText
                end
            end
        end
        return table.concat(result, ", ")
    end

    -- 20f. GetPlayerInfo: mirror old addon's approach.
    --      Old: name, class, role, guildRank, enchant, lvl
    --      New expects: role, rank, enchant, lvl, ilvl, specID
    addon.GetPlayerInfo = function(s)
        local enchant, lvl = nil, 0
        if IsSpellKnown and IsSpellKnown(13262) then enchant, lvl = true, 450 end
        local ilvl = 0
        if GetAverageItemLevel then ilvl = select(2, GetAverageItemLevel()) or 0 end
        return s.Utils:GetPlayerRole(), s.guildRank, enchant, lvl, ilvl, nil
    end

    -- 20g. FindInTooltip: handle both table-line and string formats.
    if addon.Utils and addon.Utils.FindInTooltip then
        addon.Utils.FindInTooltip = function(s, tooltipLines, ...)
            if type(tooltipLines)~="table" then return nil end
            local searches = type(select(1,...))=="table" and select(1,...) or {...}
            for _,line in ipairs(tooltipLines) do
                local text = type(line)=="table" and line.leftText or tostring(line)
                local lt = (type(line)=="table" and line.type) or 0
                if lt==0 and text then
                    for _,str in ipairs(searches) do
                        if text:find(str) then return text end
                    end
                end
            end
        end
    end

    -- 20h. GetPlayerRole: LibGroupTalents approach would be ideal, but
    --      we don't have it in the new addon. Return NONE safely.
    --      Users who want real role detection can add LibGroupTalents separately.
    if addon.Utils then
        addon.Utils.GetPlayerRole = function() return "NONE" end
    end

    -- 20i. Spec helpers.
    addon.GetCurrentSpec = function() return nil end

    -- 20i-0. NAME NORMALIZATION.
    --   On WotLK private servers, names may appear as "Name-Realm" in
    --   some contexts (sender fields etc.). Normalize to bare character
    --   name so candidatesInGroup keys and council keys always match.
    if addon.Utils then
        addon.Utils.UnitName = function(self, input)
            if self:IsSecretValue(input) then return input end
            if not input or input=="" then return "" end
            local namePart = tostring(input):gsub(" ",""):match("^([^%-]+)") or tostring(input)
            return namePart:lower():gsub("^%l", string.upper)
        end
        addon.Utils.UnitNameFromNameRealm = function(self, name, realm)
            return self:UnitName(name)
        end
        if addon.Utils.unitNameLookup then wipe(addon.Utils.unitNameLookup) end
        if addon.UpdateCandidatesInGroup then addon:ScheduleTimer("UpdateCandidatesInGroup", 1) end
    end

    -- 20i-1. UpdateCandidatesInGroup: handle BOTH raid and party correctly.
    --   Old addon: raid -> GetRaidRosterInfo; party -> UnitName("party"..i) via GetPartyMember.
    addon.UpdateCandidatesInGroup = function(self)
        -- AceBucket/AceTimer may invoke this without `self`, so fall back to addon.
        if not self or self.candidatesInGroup == nil then self = addon end
        self.candidatesInGroup = self.candidatesInGroup or {}
        wipe(self.candidatesInGroup)
        if IsInRaid and IsInRaid() then
            for i = 1, GetNumRaidMembers() do
                local name = GetRaidRosterInfo(i)
                if name then self.candidatesInGroup[self.Utils:UnitName(name)] = true end
            end
        else
            -- Party: iterate party1..partyN (same as old addon's GetPartyMember pattern).
            local n = GetNumPartyMembers and GetNumPartyMembers() or 0
            for i = 1, n do
                local unit = "party"..i
                if UnitExists(unit) then
                    local name = UnitName(unit)
                    if name then self.candidatesInGroup[self.Utils:UnitName(name)] = true end
                end
            end
        end
        -- Always include the player themselves.
        self.candidatesInGroup[self.Utils:UnitName(UnitName("player"))] = true
        return self.candidatesInGroup
    end

    -- 20i-2. ConfigTableChanged nil guard.
    --   AceBucket can fire with nil if no messages arrived before timeout.
    local MLModule = addon.GetModule and addon:GetModule("RCLootCouncilML", true)
    if MLModule and MLModule.ConfigTableChanged then
        local orig = MLModule.ConfigTableChanged
        MLModule.ConfigTableChanged = function(self2, value)
            return orig(self2, value or {})
        end
    end

    -- 20i-3. GetRaidRosterInfo party shim.
    --   The Group Council Members options panel calls GetRaidRosterInfo(i) for
    --   i=1..GetNumGroupMembers(). This only works in a raid. In a party it
    --   returns nil → Player:Get(nil) → "Unknown" placeholder.
    --   Wrap to synthesize roster data from party unit tokens when not in raid.
    if not _G._RCWOTLK_RAIDROSTER_PATCHED then
        _G._RCWOTLK_RAIDROSTER_PATCHED = true
        local origGRRI = _G.GetRaidRosterInfo
        _G.GetRaidRosterInfo = function(index)
            if GetNumRaidMembers and GetNumRaidMembers() > 0 then
                return origGRRI(index)
            end
            -- Synthesize: index 1 = player, 2..N = party1..(N-1)
            local unit = index == 1 and "player" or ("party"..(index-1))
            if not UnitExists(unit) then return nil end
            local name = UnitName(unit)
            local level = UnitLevel(unit) or 0
            local _, classFile = UnitClass(unit)
            local zone = GetZoneText and GetZoneText() or ""
            -- Return 16 values matching the real GetRaidRosterInfo signature:
            -- name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML, combatRole
            return name, 0, 1, level, classFile or "", classFile or "", zone, true, false, "NONE", false, "NONE"
        end
    end

    -- 20i-4. ML self-receive council fix.
    --   On WotLK, SendAddonMessage to RAID/PARTY is NOT echoed back to the sender.
    --   So the ML sends council but never receives its own broadcast →
    --   hasReceivedCouncil stays false → "Please wait until synchronized".
    --   Fix: hook SendCouncil to also apply the council locally.
    if MLModule and MLModule.SendCouncil then
        local CouncilData = addon.Require and addon.Require("Data.Council")
        local TempTableSvc = addon.Require and addon.Require("Utils.TempTable")
        local origSC = MLModule.SendCouncil
        MLModule.SendCouncil = function(self2, ...)
            local r = {origSC(self2, ...)}
            if addon.OnCouncilReceived and CouncilData and CouncilData.GetForTransmit then
                local council = CouncilData:GetForTransmit()
                addon:OnCouncilReceived(addon.masterLooter or addon.player:GetName(), council)
                if TempTableSvc and TempTableSvc.Release then TempTableSvc:Release(council) end
            end
            return unpack(r)
        end
    end

    -- 20i-5. Safety timer: if we are ML and still haven't received council
    --   after 3 seconds (e.g. the hook above didn't fire because we became
    --   ML before ADDON_LOADED), force hasReceivedCouncil = true.
    C_Timer.After(3, function()
        if addon.isMasterLooter and not addon.hasReceivedCouncil then
            addon.hasReceivedCouncil = true
        end
    end)

    -- 20i-5b. Bulletproof StartSession / Start-button gating.
    --   On WotLK the ML never receives its own council broadcast, so the
    --   hasReceivedCouncil flag and Council:GetNum() can both stay at their
    --   blocking values even though the ML obviously has the council locally.
    --   When WE are the ML, force-populate the council and set the flag
    --   right before any session start so the "Please wait" guard passes.
    local MLMod = addon.GetModule and addon:GetModule("RCLootCouncilML", true)
    local CouncilSvc = addon.Require and addon.Require("Data.Council")
    local function ensureCouncilReady()
        if not addon.isMasterLooter then return end
        addon.hasReceivedCouncil = true
        -- Rebuild the in-group council from db so GetNum() > 0.
        if MLMod and MLMod.UpdateGroupCouncil then
            pcall(function() MLMod:UpdateGroupCouncil() end)
        end
        -- Absolute fallback: make sure at least the ML is in the council.
        if CouncilSvc and CouncilSvc.GetNum and CouncilSvc:GetNum() == 0 and addon.player then
            pcall(function() CouncilSvc:Add(addon.player) end)
        end
    end

    if MLMod and MLMod.StartSession then
        local origStart = MLMod.StartSession
        MLMod.StartSession = function(self2, ...)
            ensureCouncilReady()
            return origStart(self2, ...)
        end
    end

    -- 20i-5c. Set hasReceivedCouncil the moment we become ML, so the
    --   sessionFrame Start-button guard (which checks the flag BEFORE
    --   StartSession runs) passes. Also rebuild the council then.
    if MLMod and MLMod.NewML then
        local origNewML = MLMod.NewML
        MLMod.NewML = function(self2, newML, ...)
            local r = { origNewML(self2, newML, ...) }
            -- If, after NewML, this client is the ML, mark council ready.
            C_Timer.After(addon.testMode and 0.1 or 2.5, function()
                if addon.isMasterLooter then
                    ensureCouncilReady()
                end
            end)
            return unpack(r)
        end
    end

    -- 20j. AutoPass safety net.
    if addon.AutoPass and addon.AutoPass.AutoPassCheck then
        local realCheck = addon.AutoPass.AutoPassCheck
        addon.AutoPass.AutoPassCheck = function(s, ...)
            local ok, result = pcall(realCheck, s, ...)
            if ok then return result end
            return false
        end
    end

    -- 20k. CLASS ICON via CLASS_ICON_TCOORDS (no atlas on WotLK).
    local CLASS_ICON_TEX = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
    local iconCache = {}
    addon.AddClassIconToText = function(self, class, text, size)
        size = size or 12
        if not class then return text or "" end
        local id = tostring(class)..size
        if not iconCache[id] then
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
            if coords then
                local l = math.floor(coords[1]*256); local r = math.floor(coords[2]*256)
                local t = math.floor(coords[3]*256); local b = math.floor(coords[4]*256)
                iconCache[id] = string.format("|T%s:%d:%d:0:0:256:256:%d:%d:%d:%d|t", CLASS_ICON_TEX, size, size, l, r, t, b)
            else
                iconCache[id] = ""
            end
        end
        return string.format("%s %s", iconCache[id], text or "")
    end

    -- 20l. Strip |W..|w word-wrap markup (MoP 5.4.1+, renders literally on WotLK).
    --   Also strip "-Realm" suffixes in colored name strings.
    local function cleanName(s)
        if type(s)~="string" then return s end
        s = s:gsub("|W",""):gsub("|w","")
        s = s:gsub("%-[%a]+%-[%a]+","")
        s = s:gsub("%-[%a]+(|r)","%1")
        s = s:gsub("%-[%a]+%s"," ")
        return s
    end
    local origGCIC = addon.GetClassIconAndColoredName
    if origGCIC then
        addon.GetClassIconAndColoredName = function(s, np, size)
            return cleanName(origGCIC(s, np, size))
        end
    end
    local origGSIC = addon.GetSpecIconAndColoredName
    if origGSIC then
        addon.GetSpecIconAndColoredName = function(s, np, size)
            return cleanName(origGSIC(s, np, size))
        end
    end
    local origASI = addon.AddSpecIconToText
    if origASI then
        addon.AddSpecIconToText = function(s, specID, text, size)
            if not specID then return text or "" end
            local ok, result = pcall(origASI, s, specID, text, size)
            return ok and result or (text or "")
        end
    end

    -- 20m. Trade timer detection (/rc add all).
    if addon.GetContainerItemTradeTimeRemaining then
        local tipName = "RCWotLKTradeScanTip"
        local scanTip = _G[tipName] or CreateFrame("GameTooltip", tipName, nil, "GameTooltipTemplate")
        addon.GetContainerItemTradeTimeRemaining = function(self, container, slot)
            scanTip:SetOwner(UIParent, "ANCHOR_NONE")
            scanTip:SetBagItem(container, slot)
            local n = scanTip:NumLines() or 0
            if n==0 then scanTip:Hide(); return 0 end
            local bounded, found = false, false
            for i = 1, n do
                local line = _G[tipName.."TextLeft"..i]
                local text = line and line.GetText and line:GetText() or ""
                if text==_G.ITEM_SOULBOUND or text==_G.ITEM_ACCOUNTBOUND then bounded=true end
                local lower = text:lower()
                if lower:find("you may trade this item",1,true) or lower:find("eligible to loot this item",1,true) then
                    found=true
                end
            end
            scanTip:Hide()
            if found then return 7200 end
            return bounded and 0 or math.huge
        end
    end

    if addon.Log then addon.Log:D("[WotLKFix] All patches applied.") end
end)

-- ============================================================
-- 21. Item MIXIN SHIM (retail ItemMixin — absent on WotLK)
--     The global `Item` object with Item:CreateFromItemID etc. is
--     a retail (Legion+) ItemMixin. WotLK has no such global.
--     Used by:
--       core.lua       -> Item:CreateFromItemGUID (/rc lock,/unlock — UNGUARDED → crash)
--       ItemStorage    -> Item:CreateFromBagAndSlot (guarded with `and`)
--       CSVImport      -> Item:CreateFromItemLink/ID (pcall-wrapped)
--     We provide a minimal ItemMixin that supports the methods these
--     call: ContinueOnItemLoad, GetItemLink, GetItemID, GetItemGUID,
--     UnlockItem, LockItem, IsItemLocked, IsItemEmpty.
-- ============================================================
if not Item then
    local ItemMixin = {}
    ItemMixin.__index = ItemMixin

    local function newItem(fields)
        return setmetatable(fields or {}, ItemMixin)
    end

    -- Constructors --------------------------------------------------------
    Item = {}
    function Item:CreateFromItemID(itemID)
        return newItem({ itemID = tonumber(itemID) })
    end
    function Item:CreateFromItemLink(itemLink)
        local id = itemLink and tonumber(string.match(tostring(itemLink), "item:(%d+)"))
        return newItem({ itemLink = itemLink, itemID = id })
    end
    function Item:CreateFromItemGUID(guid)
        -- WotLK has no item GUIDs; store it but most queries degrade gracefully.
        return newItem({ itemGUID = guid })
    end
    function Item:CreateFromBagAndSlot(bag, slot)
        local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
        local id = link and tonumber(string.match(link, "item:(%d+)"))
        return newItem({ bag = bag, slot = slot, itemLink = link, itemID = id })
    end

    -- Instance methods ----------------------------------------------------
    function ItemMixin:GetItemID() return self.itemID end
    function ItemMixin:GetItemLink()
        if self.itemLink then return self.itemLink end
        if self.bag and self.slot and GetContainerItemLink then
            return GetContainerItemLink(self.bag, self.slot)
        end
        if self.itemID then
            return (select(2, GetItemInfo(self.itemID)))
        end
        return nil
    end
    function ItemMixin:GetItemGUID() return self.itemGUID end
    function ItemMixin:GetItemName()
        local link = self:GetItemLink()
        return link and (GetItemInfo(link))
    end
    function ItemMixin:IsItemEmpty()
        return not (self.itemID or self.itemLink or self.itemGUID or (self.bag and self.slot))
    end
    function ItemMixin:IsItemDataCached()
        local link = self.itemLink or self.itemID
        return link and GetItemInfo(link) ~= nil or false
    end
    -- ContinueOnItemLoad: retail async loader. On WotLK GetItemInfo is
    -- synchronous (or returns nil until cached). We fire a tooltip
    -- prime then poll briefly, calling the callback once data exists.
    function ItemMixin:ContinueOnItemLoad(callback)
        local query = self.itemLink or self.itemID
        if not query then return end
        if GetItemInfo(query) then
            callback()
            return
        end
        -- Prime the cache and poll up to ~2 seconds.
        if self.itemID and GameTooltip then
            GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
            pcall(function() GameTooltip:SetHyperlink("item:"..self.itemID) end)
            GameTooltip:Hide()
        end
        local tries = 0
        local function poll()
            tries = tries + 1
            if GetItemInfo(query) then
                callback()
            elseif tries < 40 then
                C_Timer.After(0.05, poll)
            else
                -- Give up gracefully; call back anyway so chains don't hang.
                callback()
            end
        end
        C_Timer.After(0.05, poll)
    end
    function ItemMixin:ContinueWithCancelOnItemLoad(callback)
        self:ContinueOnItemLoad(callback)
        return function() end -- cancel func (no-op)
    end
    -- Lock state: WotLK uses container item lock flags, not item GUIDs.
    -- These are only used by /rc lock & /rc unlock (testing commands).
    function ItemMixin:UnlockItem() end
    function ItemMixin:LockItem() end
    function ItemMixin:IsItemLocked() return false end
    function ItemMixin:GetItemIcon()
        local link = self:GetItemLink()
        return link and (select(10, GetItemInfo(link)))
    end
    function ItemMixin:GetItemQuality()
        local link = self:GetItemLink()
        return link and (select(3, GetItemInfo(link)))
    end
end

-- ============================================================
-- 22. POST-LOAD ADDENDUM (second ADDON_LOADED listener)
-- ============================================================
local fixFrame3 = CreateFrame("Frame")
fixFrame3:RegisterEvent("ADDON_LOADED")
fixFrame3:SetScript("OnEvent", function(self, event, name)
    if name ~= "RCLootCouncil" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local addon = RCLootCouncil
    if not addon then return end

    -- 22a. Guard /rc lock & /rc unlock (core.lua uses Item:CreateFromItemGUID
    --      then calls :UnlockItem/:IsItemLocked). With our Item mixin these
    --      now no-op safely, but wrap in pcall so a missing-item edge case
    --      can't throw to the user.
    if addon.UnlockItem then
        local orig = addon.UnlockItem
        addon.UnlockItem = function(self2, item)
            local ok = pcall(orig, self2, item)
            if not ok then self2:Print("Item unlock not supported on this client.") end
        end
    end
    if addon.LockItem then
        local orig = addon.LockItem
        addon.LockItem = function(self2, item)
            pcall(orig, self2, item)
        end
    end

    -- 22b. WrapTextInClassColor safety. Player:CreateClassColoredName calls
    --      RCLootCouncil:WrapTextInClassColor(class, name). If class is nil
    --      (unresolved council member on WotLK), make sure it doesn't error.
    if addon.WrapTextInClassColor then
        local orig = addon.WrapTextInClassColor
        addon.WrapTextInClassColor = function(self2, class, text)
            if not class then return text or "" end
            local ok, res = pcall(orig, self2, class, text)
            return ok and res or (text or "")
        end
    end
end)

-- ============================================================
-- 23. TEXTURE METHOD SHIMS (SetColorTexture — Legion+)
--     WotLK has no Texture:SetColorTexture. The equivalent is
--     Texture:SetTexture(r,g,b,a) which fills a solid color.
--     This affects lib-st (voting/session frame backgrounds and
--     row highlights — the wrong colors you saw) and the AceGUI
--     ColorPicker swatch (the black Need/Greed swatches).
-- ============================================================
do
    -- Get the Texture metatable by creating a throwaway texture.
    local probe = UIParent:CreateTexture(nil, "BACKGROUND")
    local mt = getmetatable(probe)
    local idx = mt and mt.__index
    if type(idx) == "table" then
        if not idx.SetColorTexture then
            idx.SetColorTexture = function(self, r, g, b, a)
                -- WotLK SetTexture with color args fills solid color.
                self:SetTexture(r, g, b, a or 1)
            end
        end
        -- SetGradient/SetGradientAlpha signature changed in DF; provide
        -- a tolerant shim that no-ops if the WotLK form isn't available.
        if not idx.SetGradientAlpha then
            idx.SetGradientAlpha = function() end
        end
    end
    probe:SetTexture(nil)
end

-- ============================================================
-- 24. Retail frame templates (BackdropTemplate, DialogBorder*) + methods
--     AceConfigDialog popup (validation/confirm dialog) uses a
--     retail template and Cata+ frame methods. Shim them so the
--     popup frame creation in AceConfigDialog doesn't crash.
--     The CreateFrame interceptor below also strips the Shadowlands
--     "BackdropTemplate" so the addon no longer depends on !!!ClassicAPI
--     to define it.
-- ============================================================
do
    -- Frame method shims (SetFixedFrameStrata/Level, SetPropagateKeyboardInput).
    local probe = CreateFrame("Frame")
    local mt = getmetatable(probe)
    local idx = mt and mt.__index
    if type(idx) == "table" then
        if not idx.SetFixedFrameStrata then idx.SetFixedFrameStrata = function() end end
        if not idx.SetFixedFrameLevel then idx.SetFixedFrameLevel = function() end end
        if not idx.SetPropagateKeyboardInput then idx.SetPropagateKeyboardInput = function() end end
    end
end

-- Create a virtual frame template named "DialogBorderOpaqueTemplate" so
-- CreateFrame("Frame", nil, parent, "DialogBorderOpaqueTemplate") works.
-- WotLK can't define XML templates from Lua, so instead we intercept
-- CreateFrame and strip the unknown template, then apply a backdrop border
-- manually to mimic the dialog border.
do
    local origCreateFrame = CreateFrame
    -- Retail-only templates that draw a dialog/tooltip border. When stripped we
    -- mimic that border manually with a backdrop so the frame still looks right.
    local DIALOG_BORDER_TEMPLATES = {
        ["DialogBorderOpaqueTemplate"] = true,
        ["DialogBorderTemplate"] = true,
        ["DialogBorderDarkTemplate"] = true,
        ["TooltipBorderBackdropTemplate"] = true,
    }
    -- Retail-only templates that are pure no-ops on WotLK and are stripped
    -- silently (no border applied). "BackdropTemplate" (Shadowlands 9.0+) only
    -- re-attaches the Backdrop system that is already native on every 3.3.5a
    -- frame, so dropping it is safe — the caller's own Frame:SetBackdrop() calls
    -- keep working. On plain WotLK this template is supplied by !!!ClassicAPI;
    -- stripping it here removes that hidden dependency so RCLootCouncil no longer
    -- needs ClassicAPI loaded (lootFrame/IconBordered create frames with it).
    local NOOP_TEMPLATES = {
        ["BackdropTemplate"] = true,
    }
    CreateFrame = function(frameType, name, parent, template, id)
        if template and type(template) == "string" then
            -- Handle comma-separated template lists; filter retail-only ones.
            local kept, strippedDialogBorder = {}, false
            for tpl in template:gmatch("[^,%s]+") do
                if DIALOG_BORDER_TEMPLATES[tpl] then
                    strippedDialogBorder = true
                elseif not NOOP_TEMPLATES[tpl] then
                    kept[#kept + 1] = tpl
                end
            end
            local newTemplate = #kept > 0 and table.concat(kept, ", ") or nil
            local frame = origCreateFrame(frameType, name, parent, newTemplate, id)
            -- Apply a backdrop border to mimic DialogBorderOpaqueTemplate.
            if strippedDialogBorder and frame and frame.SetBackdrop then
                frame:SetBackdrop({
                    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                    tile = true, tileSize = 32, edgeSize = 32,
                    insets = { left = 11, right = 12, top = 12, bottom = 11 },
                })
            end
            return frame
        end
        return origCreateFrame(frameType, name, parent, template, id)
    end
end

-- ============================================================
-- 25. AceComm prefix length check removal
--     Newer AceComm enforces a `#prefix > 16` error that did NOT
--     exist in the WotLK-era AceComm. WotLK's SendAddonMessage has
--     no such hard limit, and the error() thrown here is caught by
--     OTHER addons sharing this AceComm instance (AtlasLoot,
--     SpecializedAbsorbs), spamming Lua errors on login.
--     We neutralize it by pre-registering a tolerant RegisterComm.
--     (The actual fix is applied to the lib file below; this is a
--      runtime safety net in case load order differs.)
-- ============================================================
-- Handled by patching AceComm-3.0.lua directly (see TOC load order).
-- No runtime shim needed here.

-- ============================================================
-- 26. POST-LOAD: Council name resolution (THE core fix)
--     On WotLK, db.profile.council stores NAMES (our design).
--     Player:Get(name) must reliably return a Player object with a
--     valid .guid even when that player is offline / not grouped.
--     The stock GetGUIDFromPlayerNameByGuild fails for offline guild
--     members (GetNumGuildMembers only counts online unless
--     SetGuildRosterShowOffline(true) was set). We make name lookups
--     always succeed by using the NAME ITSELF as the guid, mirroring
--     how the old v2.0.4 addon worked (council = list of names).
-- ============================================================
local fixFrame4 = CreateFrame("Frame")
fixFrame4:RegisterEvent("ADDON_LOADED")
fixFrame4:SetScript("OnEvent", function(self, event, name)
    if name ~= "RCLootCouncil" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local addon = RCLootCouncil
    if not addon then return end

    -- Ensure the guild roster includes offline members so council
    -- members who are offline can still be resolved by name.
    if SetGuildRosterShowOffline then
        pcall(SetGuildRosterShowOffline, true)
    end

    local Player = addon.Require and addon.Require("Data.Player")
    if not Player then return end

    -- Capture the real Player metatable safely (before overriding Get) by
    -- asking for a player we know resolves: the local player via their GUID.
    -- We grab the metatable from the returned object and reuse it.
    local PLAYER_MT
    do
        local ok, p = pcall(function() return Player:Get(UnitName("player")) end)
        if ok and type(p) == "table" then PLAYER_MT = getmetatable(p) end
    end

    -- Override Player:Get so that on WotLK a plain name ALWAYS yields a
    -- usable Player object. We resolve class from group/guild/cache when
    -- possible, but never fail to produce a .guid (we use the name as guid).
    local origGet = Player.Get
    Player.Get = function(self2, input)
        -- Secret values: defer to original.
        if addon.Utils and addon.Utils:IsSecretValue(input) then
            return origGet(self2, input)
        end
        -- Retail-format GUIDs: defer to original handling.
        if type(input) == "string" and input:match("Player%-%d") then
            return origGet(self2, input)
        end
        -- Native WotLK hex GUIDs ("0x..."): resolve to a name via the
        -- (wrapped) GetPlayerInfoByGUID instead of treating them as names.
        if type(input) == "string" and input:match("^0x%x+$") then
            local name = select(6, GetPlayerInfoByGUID(input))
            if name then
                input = name -- fall through to the plain name path below
            else
                return origGet(self2, input)
            end
        end
        -- Plain name path (WotLK council storage).
        if type(input) == "string" and input ~= "" then
            -- CRITICAL: handle unit tokens ("player", "target", "party1",
            -- "raid5", etc.) by resolving them to a real name FIRST.
            -- Otherwise "player" would be treated as the literal name "Player".
            local UNIT_TOKENS = {
                player = true, target = true, focus = true, mouseover = true,
                pet = true, npc = true, vehicle = true,
            }
            local lowered = input:lower()
            local isUnitToken = UNIT_TOKENS[lowered]
                or lowered:match("^party%d$") or lowered:match("^raid%d+$")
                or lowered:match("^partypet%d$") or lowered:match("^raidpet%d+$")
                or lowered:match("^arena%d$") or lowered:match("^boss%d$")
            if isUnitToken then
                if UnitExists(input) then
                    local realName = UnitName(input)
                    local realGuid = UnitGUID and UnitGUID(input)
                    if realGuid and realGuid:match("^Player%-") then
                        return origGet(self2, realGuid)
                    end
                    if realName then
                        input = realName  -- fall through to name handling below
                    else
                        return origGet(self2, input)
                    end
                else
                    return origGet(self2, input)
                end
            end

            local short = input:match("^([^%-]+)") or input
            short = short:lower():gsub("^%l", string.upper)

            -- Resolve class: try the player themselves, live units, then guild.
            local class
            -- Self: UnitExists("PlayerName") is false, so check explicitly.
            local myName = UnitName("player")
            if myName and short == (myName:match("^([^%-]+)") or myName) then
                class = select(2, UnitClass("player"))
            end
            -- Live group/target units.
            if not class and UnitExists(short) then
                class = select(2, UnitClass(short))
            end
            -- Scan raid/party members by name (covers grouped council members).
            if not class then
                local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
                if n > 0 then
                    for i = 1, n do
                        local rname, _, _, _, _, cFile = GetRaidRosterInfo(i)
                        if rname and (rname:match("^([^%-]+)") or rname) == short then
                            class = cFile
                            break
                        end
                    end
                else
                    local p = (GetNumPartyMembers and GetNumPartyMembers()) or 0
                    for i = 1, p do
                        local unit = "party"..i
                        if UnitExists(unit) and (UnitName(unit) or ""):match("^([^%-]+)") == short then
                            class = select(2, UnitClass(unit))
                            break
                        end
                    end
                end
            end
            -- Guild roster fallback (also resolves guild RANK).
            local rank
            if IsInGuild and IsInGuild() then
                -- Self: GetGuildInfo("player") gives our own rank directly.
                local myName2 = UnitName("player")
                if myName2 and short == (myName2:match("^([^%-]+)") or myName2) then
                    rank = select(2, GetGuildInfo("player"))
                end
                for i = 1, (GetNumGuildMembers() or 0) do
                    local gname, grank, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
                    if gname and (gname:match("^([^%-]+)") or gname) == short then
                        if not class then class = classFile end
                        rank = rank or grank
                        break
                    end
                end
            end

            -- Build a Player object directly. Use the name as the guid so
            -- council storage, __eq comparison, and caching all work.
            local realm = GetRealmName and GetRealmName() or ""
            local player = setmetatable({
                name = short,
                guid = short,           -- name doubles as guid on WotLK
                class = class,          -- may be nil if truly unknown
                rank = rank,            -- guild rank (nil if not in our guild)
                realm = realm,
                isInGuild = rank ~= nil,
            }, PLAYER_MT or {})

            return player
        end
        return origGet(self2, input)
    end

    -- Re-run CouncilChanged so council repopulates with working players.
    if addon.CouncilChanged then
        pcall(function() addon:CouncilChanged() end)
    end
end)

-- ============================================================
-- 27. COMM SELF-ECHO for the player's OWN loot response
--     On standard WotLK 3.3.5a, SendAddonMessage to RAID/PARTY/GUILD is
--     NOT echoed back to the sender. So when YOU click a loot button,
--     your own "response" comm never comes back to you, the voting frame
--     never records it, and the offline timer flips you to "Offline or
--     RCLootCouncil not installed".
--
--     Targeted fix: hook RCLootCouncil:SendResponse so that, right after
--     sending, we apply our OWN response locally to the voting frame —
--     exactly what OnResponseReceived would do if the echo had arrived.
--     This is narrow and safe (only our own response, only the voting
--     frame), avoiding any double-processing of others' messages.
-- ============================================================
local fixFrame5 = CreateFrame("Frame")
fixFrame5:RegisterEvent("ADDON_LOADED")
fixFrame5:SetScript("OnEvent", function(self, event, name)
    if name ~= "RCLootCouncil" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local addon = RCLootCouncil
    if not addon then return end

    local myName = addon.Utils and addon.Utils:UnitName(UnitName("player")) or UnitName("player")

    -- Apply our own response to the voting frame locally.
    local function applyOwnResponse(session, dataTbl)
        local VF = addon.GetActiveModule and addon:GetActiveModule("votingframe")
        if not VF then
            VF = addon.GetModule and addon:GetModule("RCVotingFrame", true)
        end
        if VF and VF.OnResponseReceived then
            pcall(function() VF:OnResponseReceived(myName, session, dataTbl) end)
        end
    end

    if addon.SendResponse and not addon._wotlkResponseEchoHooked then
        addon._wotlkResponseEchoHooked = true
        local origSendResponse = addon.SendResponse
        addon.SendResponse = function(self2, target, session, response, isTier, isRelic, note, roll,
                                       link, ilvl, equipLoc, relicType, sendAvgIlvl, sendSpecID)
            local r = { origSendResponse(self2, target, session, response, isTier, isRelic, note, roll,
                                          link, ilvl, equipLoc, relicType, sendAvgIlvl, sendSpecID) }
            -- Only echo broadcast responses for real sessions.
            if (target == "group" or target == "guild") and type(session) == "number" then
                local g1, g2, diff
                if link and ilvl then
                    g1, g2 = self2:GetGear(link, equipLoc, relicType)
                    diff = self2:GetIlvlDifference(link, g1, g2)
                end
                local dataTbl = {
                    gear1    = g1 and addon.Require("Utils.Item"):GetItemStringFromLink(g1) or nil,
                    gear2    = g2 and addon.Require("Utils.Item"):GetItemStringFromLink(g2) or nil,
                    diff     = diff,
                    note     = note,
                    response = response,
                    roll     = roll,
                }
                -- Next frame so it runs after the send completes.
                C_Timer.After(0, function() applyOwnResponse(session, dataTbl) end)
            end
            return unpack(r)
        end
    end

    -- Also self-apply lootAck so the ML sees their OWN gear (G1/G2/Diff/iLvl)
    -- and clears ANNOUNCED. SendLootAck sends (specID, ilvl, toSend); we must
    -- reconstruct the same payload and feed it to the voting frame locally,
    -- because the server doesn't echo our own group message back to us.
    if addon.SendLootAck and not addon._wotlkLootAckEchoHooked then
        addon._wotlkLootAckEchoHooked = true
        local origSendLootAck = addon.SendLootAck
        local ItemUtils = addon.Require and addon.Require("Utils.Item")
        addon.SendLootAck = function(self2, tbl, skip)
            local r = { origSendLootAck(self2, tbl, skip) }
            -- Rebuild the same payload SendLootAck just broadcast.
            local ok = pcall(function()
                local toSend = { gear1 = {}, gear2 = {}, diff = {}, response = {}, roll = {} }
                local hasData = false
                for k, v in pairs(tbl) do
                    local session = v.session or k
                    if session > (skip or 0) then
                        hasData = true
                        local g1, g2 = self2:GetGear(v.link, v.equipLoc)
                        local diff = self2:GetIlvlDifference(v.link, g1, g2)
                        -- Match the real SendLootAck format: CLEAN item strings,
                        -- which OnLootAckReceived runs UncleanItemString() on.
                        toSend.gear1[session] = g1 and ItemUtils and ItemUtils:GetItemStringClean(g1) or nil
                        toSend.gear2[session] = g2 and ItemUtils and ItemUtils:GetItemStringClean(g2) or nil
                        toSend.diff[session] = diff
                        toSend.response[session] = v.autopass
                        toSend.roll[session] = (v.isRoll and v.autopass and "-") or (v.isRoll and "?") or nil
                    end
                end
                if not next(toSend.roll) then toSend.roll = nil end
                if hasData then
                    local VF = addon.GetActiveModule and addon:GetActiveModule("votingframe")
                    if not VF then VF = addon.GetModule and addon:GetModule("RCVotingFrame", true) end
                    if VF and VF.OnLootAckReceived then
                        local ilvl = select(2, GetAverageItemLevel())
                        C_Timer.After(0, function()
                            pcall(function() VF:OnLootAckReceived(myName, nil, ilvl, toSend) end)
                        end)
                    end
                end
            end)
            return unpack(r)
        end
    end
end)

-- ============================================================
-- 28. GEAR ICON CACHE PRIMING (GET_ITEM_INFO_RECEIVED)
--     When council members receive each other's gear via lootAck,
--     the items are often not in the local API cache yet. GetItemIcon()
--     and GetItemInfo() return nil until the server responds.
--     Fix: hook OnLootAckReceived to pre-fetch all gear items, then
--     listen for GET_ITEM_INFO_RECEIVED and trigger a VotingFrame
--     update so the icons populate as each item resolves.
-- ============================================================
local fixFrame6 = CreateFrame("Frame")
fixFrame6:RegisterEvent("ADDON_LOADED")
fixFrame6:SetScript("OnEvent", function(self, event, name)
    if name ~= "RCLootCouncil" then return end
    self:UnregisterEvent("ADDON_LOADED")
    local addon = RCLootCouncil
    if not addon then return end

    -- Track which item IDs we're waiting for.
    local pendingItems = {}
    local refreshScheduled = false

    -- Listen for item data arriving from server.
    local cacheFrame = CreateFrame("Frame")
    cacheFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    cacheFrame:SetScript("OnEvent", function(_, _, itemID, success)
        if not (success and pendingItems[itemID]) then return end
        pendingItems[itemID] = nil
        -- Batch refreshes: schedule at most one pending update so multiple
        -- simultaneous arrivals only trigger one re-render.
        if refreshScheduled then return end
        refreshScheduled = true
        C_Timer.After(0.1, function()
            refreshScheduled = false
            local VF = addon.GetActiveModule and addon:GetActiveModule("votingframe")
            if not VF then VF = addon.GetModule and addon:GetModule("RCVotingFrame", true) end
            if VF and VF.Update then
                pcall(function() VF:Update(true) end)
            end
        end)
    end)

    -- Hook OnLootAckReceived to prime the cache for all received gear items.
    local VF = addon.GetModule and addon:GetModule("RCVotingFrame", true)
    if VF and VF.OnLootAckReceived and not VF._wotlkGearCacheHooked then
        VF._wotlkGearCacheHooked = true
        local orig = VF.OnLootAckReceived
        VF.OnLootAckReceived = function(self2, name, specID, ilvl, sessionData)
            orig(self2, name, specID, ilvl, sessionData)
            -- After storing the data, prime the cache for any gear items
            -- that aren't loaded yet so the icons appear quickly.
            if type(sessionData) ~= "table" then return end
            for k, d in pairs(sessionData) do
                if (k == "gear1" or k == "gear2") and type(d) == "table" then
                    for _, itemStr in pairs(d) do
                        if itemStr and itemStr ~= "" then
                            local fullStr = "item:" .. tostring(itemStr):gsub("^item:", "")
                            local itemID = tonumber(tostring(itemStr):match("^(%d+)") or
                                           tostring(itemStr):match("item:(%d+)"))
                            if itemID and not GetItemInfo(fullStr) then
                                -- Not cached yet — request it and track it.
                                pendingItems[itemID] = true
                                -- Secondary prime: tooltip forces a server query.
                                if GameTooltip then
                                    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
                                    pcall(function() GameTooltip:SetHyperlink(fullStr) end)
                                    GameTooltip:Hide()
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

-- ============================================================
-- 29. SPELL TOOLTIP SAFETY (#132 ACCESS_VIOLATION)
--     On 3.3.5a, GameTooltip:SetSpellByID does NOT exist, and
--     GameTooltip:SetHyperlink("spell:<id>") with a spell ID that
--     isn't present on the core crashes the client NATIVELY (a hard
--     ACCESS_VIOLATION the Lua layer cannot catch — pcall won't save us).
--     We must therefore ALWAYS validate a spell with GetSpellInfo
--     BEFORE the link is ever handed to the C side.
--
--     Two-pronged shim applied to the GameTooltip metatable so it
--     covers every tooltip (the addon's own scan tips, library tips,
--     and any future code path):
--       1. SetSpellByID: provide the missing method, validating first.
--       2. SetHyperlink: wrap it to intercept "spell:" links and drop
--          any whose spell ID GetSpellInfo can't resolve. All other
--          link types (item:, enchant:, etc.) pass through untouched.
-- ============================================================
do
    local probe = CreateFrame("GameTooltip", "RCWotLKFixSpellSafeProbe", nil, "GameTooltipTemplate")
    local mt = getmetatable(probe)
    local idx = mt and mt.__index
    if type(idx) == "table" then
        -- 1. SetSpellByID (retail since Legion; absent on WotLK).
        if not idx.SetSpellByID then
            idx.SetSpellByID = function(self, spellId)
                -- Drop invalid/unknown spells before they reach the C side.
                if not spellId or not GetSpellInfo(spellId) then return end
                return self:SetHyperlink("spell:" .. spellId)
            end
        end

        -- 2. Wrap SetHyperlink to validate "spell:" links. A spell ID the
        --    core doesn't know crashes SetHyperlink natively, so we must
        --    refuse to call the original in that case.
        if not idx.__rcWotLKSpellSafe then
            idx.__rcWotLKSpellSafe = true
            local origSetHyperlink = idx.SetHyperlink
            idx.SetHyperlink = function(self, link, ...)
                if type(link) == "string" then
                    local spellId = link:match("^spell:(%d+)")
                    if spellId and not GetSpellInfo(tonumber(spellId)) then
                        -- Unknown spell on this core — would ACCESS_VIOLATION. Skip.
                        return
                    end
                end
                return origSetHyperlink(self, link, ...)
            end
        end
    end
end

-- ============================================================
-- 30. REMAINING RETAIL FRAME / TEXTURE / COOLDOWN METHODS
--     Defensive no-op (or graceful) shims for retail-only methods that
--     are not present on 3.3.5a. Most are either guarded at the call
--     site already (SetResizeBounds) or unused by this addon, but a few
--     are reachable through bundled libraries (e.g. MSA-DropDownMenu's
--     icon:SetAtlas when info.iconAtlas is set). Shimming them on the
--     shared metatables keeps upstream lib code untouched.
-- ============================================================
do
    -- Texture methods (SetAtlas — Legion; SetMask/SetMaskTexture — Legion).
    local tex = UIParent:CreateTexture(nil, "BACKGROUND")
    local tmt = getmetatable(tex)
    local tidx = tmt and tmt.__index
    if type(tidx) == "table" then
        -- SetAtlas: no atlas system on WotLK. No-op (icon simply won't draw).
        if not tidx.SetAtlas then tidx.SetAtlas = function() end end
        if not tidx.SetMask then tidx.SetMask = function() end end
        if not tidx.SetMaskTexture then tidx.SetMaskTexture = function() end end
    end
    tex:SetTexture(nil)

    -- Frame methods (SetAtlas on textures of buttons; CreateMaskTexture — Legion;
    -- SetResizeBounds — 10.0, already guarded at call sites but harmless to add).
    local frame = CreateFrame("Frame")
    local fmt = getmetatable(frame)
    local fidx = fmt and fmt.__index
    if type(fidx) == "table" then
        if not fidx.SetResizeBounds then
            -- Map the retail (minW, minH, maxW, maxH) form onto WotLK's
            -- SetMinResize / SetMaxResize when available.
            fidx.SetResizeBounds = function(self, minW, minH, maxW, maxH)
                if self.SetMinResize and minW and minH then self:SetMinResize(minW, minH) end
                if self.SetMaxResize and maxW and maxH then self:SetMaxResize(maxW, maxH) end
            end
        end
        if not fidx.CreateMaskTexture then
            -- Return a real texture so callers that keep a reference don't error;
            -- the mask just has no effect on WotLK.
            fidx.CreateMaskTexture = function(self, ...) return self:CreateTexture(...) end
        end
    end

    -- Cooldown methods (SetSwipeColor/SetSwipeTexture/SetDrawSwipe/
    -- SetHideCountdownNumbers — all Legion+). None are used by this addon,
    -- but shim them as no-ops so any future/library use degrades gracefully.
    local ok, cd = pcall(function() return CreateFrame("Cooldown", nil, UIParent, "CooldownFrameTemplate") end)
    if not ok or not cd then
        ok, cd = pcall(function() return CreateFrame("Cooldown", nil, UIParent) end)
    end
    if ok and cd then
        local cmt = getmetatable(cd)
        local cidx = cmt and cmt.__index
        if type(cidx) == "table" then
            if not cidx.SetSwipeColor then cidx.SetSwipeColor = function() end end
            if not cidx.SetSwipeTexture then cidx.SetSwipeTexture = function() end end
            if not cidx.SetDrawSwipe then cidx.SetDrawSwipe = function() end end
            if not cidx.SetHideCountdownNumbers then cidx.SetHideCountdownNumbers = function() end end
        end
        cd:Hide()
    end
end
