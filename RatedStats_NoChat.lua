local addonName = ... -- "RatedStats_NoChat"
local frame = CreateFrame("Frame", addonName .. "Frame")

-- brown RatedStats prefix (canvas colour you picked earlier)
local RS_PREFIX = "|cffb69e86Rated Stats:|r "

-- store player's chat keybinds
local storedKeys = {}

-- SavedVariables table
RatedStats_NoChatDB = RatedStats_NoChatDB or {}

-- defaults
local defaults = {
    allowWhispers       = false, -- allow whispers (both character and BNet) while blocking other chat
    allowBNOnly         = false, -- allow only Battle.net whispers while blocking everything else

    -- per-mode blocks (all default ON)
    blockArenaSkirmish  = true,  -- non-rated arena skirmishes
    blockNormalBG       = true,  -- normal battlegrounds
    blockEpicBG         = true,  -- epic battlegrounds
    blockSoloShuffle    = true,  -- rated Solo Shuffle
    block2v2            = true,  -- rated 2v2
    block3v3            = true,  -- rated 3v3
    blockBlitz          = true,  -- rated Battleground Blitz (solo RBG)
    blockRatedBG        = true,  -- rated battlegrounds (10v10)
    blockOtherPvP       = true,  -- brawls / anything else not matched above
}

local function ApplyDefaults()
    for key, value in pairs(defaults) do
        if RatedStats_NoChatDB[key] == nil then
            RatedStats_NoChatDB[key] = value
        end
    end
end

-- helper: save all keys currently bound to OPENCHAT
local function SaveChatKeys()
    wipe(storedKeys)
    local k1, k2 = GetBindingKey("OPENCHAT")
    if k1 then table.insert(storedKeys, k1) end
    if k2 then table.insert(storedKeys, k2) end
end

-- helper: unbind those keys
local function DisableChat()
    for _, key in ipairs(storedKeys) do
        SetBinding(key, "")
    end
    SaveBindings(GetCurrentBindingSet())
    print(RS_PREFIX .. "Chat input |cffff5555disabled|r in PvP.")
end

-- helper: restore the bindings
local function RestoreChat()
    for _, key in ipairs(storedKeys) do
        SetBinding(key, "OPENCHAT")
    end
    SaveBindings(GetCurrentBindingSet())
    print(RS_PREFIX .. "Chat input |cff55ff55restored|r.")
end

local function IsSoloShuffle()
    if not C_PvP then
        return false
    end

    -- rated solo shuffle
    if C_PvP.IsRatedSoloShuffle and C_PvP.IsRatedSoloShuffle() then
        return true
    end

    -- generic solo shuffle flag (non-rated)
    if C_PvP.IsSoloShuffle then
        local ok, isSolo = pcall(C_PvP.IsSoloShuffle)
        if ok and isSolo then
            return true
        end
    end

    return false
end

-- classify the *current* PvP mode we are in
-- returns one of:
--   "skirmish", "normalbg", "epicbg",
--   "soloshuffle", "2v2", "3v3",
--   "blitz", "ratedbg", "other"
local function GetPvPMode()
    local inInstance, instanceType = IsInInstance()
    if not inInstance or (instanceType ~= "pvp" and instanceType ~= "arena") then
        return nil
    end

    -- brawl solo shuffle / solo RBG are always treated as "other"
    if C_PvP then
        if C_PvP.IsBrawlSoloShuffle and C_PvP.IsBrawlSoloShuffle() then
            return "other"
        end
        if C_PvP.IsBrawlSoloRBG and C_PvP.IsBrawlSoloRBG() then
            return "other"
        end
    end

    -- rated battleground blitz (solo RBG)
    if C_PvP and C_PvP.IsRatedSoloRBG and C_PvP.IsRatedSoloRBG() then
        return "blitz"
    end

    -- solo shuffle (rated or non-rated, brawl already filtered above)
    if IsSoloShuffle() then
        return "soloshuffle"
    end

    -- rated battlegrounds (10v10)
    if C_PvP and C_PvP.IsRatedBattleground and C_PvP.IsRatedBattleground() then
        return "ratedbg"
    end

    if instanceType == "arena" then
        if C_PvP and C_PvP.IsRatedArena and C_PvP.IsRatedArena() then
            -- distinguish 2v2 vs 3v3 by group size
            local size = GetNumGroupMembers()
            if size and size <= 2 then
                return "2v2"
            elseif size and size >= 3 then
                return "3v3"
            else
                return "other"
            end
        else
            -- non-rated arena = skirmish
            return "skirmish"
        end
    elseif instanceType == "pvp" then
        -- non-rated BGs: normal vs epic by max players
        local _, _, _, _, maxPlayers = GetInstanceInfo()
        if maxPlayers and maxPlayers >= 30 then
            return "epicbg"
        else
            return "normalbg"
        end
    end

    -- anything else (including odd future modes)
    return "other"
end

-- map a PvP mode string to the appropriate DB flag
local function IsModeBlocked(mode)
    if not RatedStats_NoChatDB or not mode then
        return false
    end

    local db = RatedStats_NoChatDB

    if mode == "skirmish" then
        return db.blockArenaSkirmish
    elseif mode == "normalbg" then
        return db.blockNormalBG
    elseif mode == "epicbg" then
        return db.blockEpicBG
    elseif mode == "soloshuffle" then
        return db.blockSoloShuffle
    elseif mode == "2v2" then
        return db.block2v2
    elseif mode == "3v3" then
        return db.block3v3
    elseif mode == "blitz" then
        return db.blockBlitz
    elseif mode == "ratedbg" then
        return db.blockRatedBG
    elseif mode == "other" then
        return db.blockOtherPvP
    end

    return false
end

local function ShouldBlockChat(editBox)
    if not RatedStats_NoChatDB then
        return false
    end

    local mode = GetPvPMode()
    if not IsModeBlocked(mode) then
        return false
    end

    local chatType = editBox and (editBox:GetAttribute("chatType") or editBox.chatType)
    local db = RatedStats_NoChatDB

    -- No whisper-related allowances at all: block everything in blocked modes.
    if not db.allowWhispers and not db.allowBNOnly then
        return true
    end

    -- Allow all whispers: both character and Battle.net.
    if db.allowWhispers then
        if chatType == "WHISPER" or chatType == "BN_WHISPER" then
            return false
        end
    end

    -- Allow BNet-only: only BN_WHISPER is permitted.
    if db.allowBNOnly then
        if chatType == "BN_WHISPER" then
            return false
        end

        -- Explicitly block character whispers when only BNet is allowed.
        if chatType == "WHISPER" then
            return true
        end
    end

    -- Any other chat type in a blocked mode is blocked.
    return true
end

-- evaluate whether to disable/restore keybinds based on current instance + settings
local function EvaluateInstanceChat()
    if not RatedStats_NoChatDB then
        if #storedKeys > 0 then
            RestoreChat()
        end
        return
    end

    local mode = GetPvPMode()
    local shouldBlock = IsModeBlocked(mode)

    if #storedKeys == 0 then
        SaveChatKeys()
    end

    if shouldBlock then
        DisableChat()
    else
        RestoreChat()
    end
end

-- hook so clicks on [Raid]/[Whisper] etc also get cancelled
hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
    if ShouldBlockChat(editBox) then
        editBox:ClearFocus()
        editBox:SetText("")
        print(RS_PREFIX .. "Chat input |cffff5555blocked|r in PvP.")
    end
end)

-- also re-check any time the header/chat type is changed (e.g. Whisper -> Instance)
hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
    if ShouldBlockChat(editBox) then
        editBox:ClearFocus()
        editBox:SetText("")
        print(RS_PREFIX .. "Chat input |cffff5555blocked|r in PvP.")
    end
end)

-- Blizzard Settings (Menu > Options > AddOns)
local function CreateOptions()
    if not Settings or not Settings.RegisterAddOnSetting then
        return
    end

    local category = Settings.RegisterVerticalLayoutCategory("Rated Stats - NoChat")
    Settings.RegisterAddOnCategory(category)

    local function AddCheckbox(variable, key, name, tooltip, defaultValue)
        local setting = Settings.RegisterAddOnSetting(
            category,                 -- category table
            variable,                 -- internal variable name
            key,                      -- key in our SavedVariables table
            RatedStats_NoChatDB,      -- SavedVariables table
            Settings.VarType.Boolean, -- type
            name,                     -- label in UI
            defaultValue              -- default value
        )
        Settings.CreateCheckbox(category, setting, tooltip)
    end

    AddCheckbox(
        "RATEDSTATS_NOCHAT_ALLOW_WHISPERS",
        "allowWhispers",
        "Allow whispers",
        "Allow whisper chat even when other chat is blocked in PvP instances.",
        defaults.allowWhispers
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_ALLOW_BN_ONLY",
        "allowBNOnly",
        "Allow Battle.net whispers only",
        "Allow only Battle.net whispers when other chat is blocked. In-game character whispers remain blocked.",
        defaults.allowBNOnly
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_ARENA_SKIRMISH",
        "blockArenaSkirmish",
        "Block chat in Arena Skirmishes",
        "Block chat input in non-rated Arena Skirmishes.",
        defaults.blockArenaSkirmish
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_NORMAL_BG",
        "blockNormalBG",
        "Block chat in Normal Battlegrounds",
        "Block chat input in Normal (non-epic) Battlegrounds.",
        defaults.blockNormalBG
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_EPIC_BG",
        "blockEpicBG",
        "Block chat in Epic Battlegrounds",
        "Block chat input in Epic Battlegrounds.",
        defaults.blockEpicBG
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_SOLO_SHUFFLE",
        "blockSoloShuffle",
        "Block chat in Solo Shuffle",
        "Block chat input in Rated Solo Shuffle matches.",
        defaults.blockSoloShuffle
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_2V2",
        "block2v2",
        "Block chat in 2v2",
        "Block chat input in Rated 2v2 Arenas.",
        defaults.block2v2
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_3V3",
        "block3v3",
        "Block chat in 3v3",
        "Block chat input in Rated 3v3 Arenas.",
        defaults.block3v3
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_BLITZ",
        "blockBlitz",
        "Block chat in Battleground Blitz",
        "Block chat input in Rated Battleground Blitz (Solo RBG).",
        defaults.blockBlitz
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_RATED_BG",
        "blockRatedBG",
        "Block chat in Rated Battlegrounds",
        "Block chat input in Rated Battlegrounds.",
        defaults.blockRatedBG
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_OTHER_PVP",
        "blockOtherPvP",
        "Block chat in other PvP Modes",
        "Block chat input in Brawls and any other PvP instances not matched above.",
        defaults.blockOtherPvP
    )
end

-- event handler
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == addonName then
            ApplyDefaults()
            CreateOptions()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        EvaluateInstanceChat()
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
