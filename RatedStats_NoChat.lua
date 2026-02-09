local addonName = ... -- "RatedStats_NoChat"
local frame = CreateFrame("Frame", addonName .. "Frame")

-- brown RatedStats prefix (canvas colour you picked earlier)
local RS_PREFIX = "|cffb69e86Rated Stats:|r "

-- state so we only print on transitions (not every keypress/click)
local lastInstanceBlocked = nil
local lastBlockNoticeTime = 0

-- SavedVariables table
RatedStats_NoChatDB = RatedStats_NoChatDB or {}

-- defaults
local defaults = {
    allowWhispers       = false, -- allow whispers (both character and BNet) while blocking other chat
    allowBNOnly         = false, -- allow only Battle.net whispers while blocking everything else
    allowParty          = false, -- always allow PARTY chat, even in blocked PvP modes

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

    if not editBox then
        -- If we don't have an edit box, we can't make a safe decision.
        -- Fail open rather than accidentally blocking system stuff.
        return false
    end

    local chatType = editBox:GetAttribute("chatType") or editBox.chatType
    if not chatType then
        -- Same deal: if Blizzard hasn't set a chatType yet, do nothing.
        return false
    end

    local db = RatedStats_NoChatDB

    -- Always allow party chat if configured, regardless of other restrictions.
    if db.allowParty and chatType == "PARTY" then
        return false
    end
    
    -- No whisper-related allowances at all: block everything in blocked modes.
    if not db.allowWhispers and not db.allowBNOnly then
        return true
    end

    -- Allow all whispers: both character and Battle.net.
    if db.allowWhispers and (chatType == "WHISPER" or chatType == "BN_WHISPER") then
        return false
    end

    -- Allow BNet-only: only BN_WHISPER is permitted.
    if db.allowBNOnly then
        if chatType == "BN_WHISPER" then
            return false
        end
        if chatType == "WHISPER" then
            return true
        end
    end

    -- Any other chat type in a blocked mode is blocked.
    return true
end

local function PrintInstanceState(shouldBlock)
    if not RatedStats_NoChatDB then
        return
    end

    if shouldBlock then
        -- If whispers are allowed, be honest: it’s restricted, not fully “off”
        if RatedStats_NoChatDB.allowWhispers or RatedStats_NoChatDB.allowBNOnly then
            print(RS_PREFIX .. "Chat input |cffffaa55restricted|r in PvP (whispers allowed by settings).")
        else
            print(RS_PREFIX .. "Chat input |cffff5555disabled|r in PvP.")
        end
    else
        print(RS_PREFIX .. "Chat input |cff55ff55restored|r.")
    end
end

local function EvaluateInstanceChatState()
    local mode = GetPvPMode()
    local shouldBlock = IsModeBlocked(mode)

    if lastInstanceBlocked == nil then
        -- First evaluation: only announce if we're actually in a blocked mode.
        lastInstanceBlocked = shouldBlock
        if shouldBlock then
            PrintInstanceState(true)
        end
        return
    end

    if shouldBlock ~= lastInstanceBlocked then
        lastInstanceBlocked = shouldBlock
        PrintInstanceState(shouldBlock)
    end
end

local function BlockEditBox(editBox)
    if not editBox then
        return
    end
    editBox:ClearFocus()
    editBox:SetText("")
    -- Prevent spam if user keeps hitting Enter
    local now = GetTime()
    if now - lastBlockNoticeTime >= 2 then
        lastBlockNoticeTime = now
        print(RS_PREFIX .. "Chat input |cffff5555blocked|r in PvP.")
    end
end

-- hook so clicks on [Raid]/[Whisper] etc also get cancelled
hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
    if editBox and ShouldBlockChat(editBox) then
        BlockEditBox(editBox)
    end
end)

-- also re-check any time the header/chat type is changed (e.g. Whisper -> Instance)
hooksecurefunc("ChatEdit_UpdateHeader", function(editBox)
    if editBox and ShouldBlockChat(editBox) then
        BlockEditBox(editBox)
    end
end)

-- hook all chat edit boxes so that simply focusing them in a blocked mode
-- immediately clears and defocuses them
local function HookChatEditBoxes()
    if not NUM_CHAT_WINDOWS then
        return
    end

    for i = 1, NUM_CHAT_WINDOWS do
        local editBox = _G["ChatFrame"..i.."EditBox"]
        if editBox and not editBox.RatedStats_NoChatHooked then
            editBox.RatedStats_NoChatHooked = true

            -- Wrap OnEnterPressed so we can block sending in a blocked mode
            local origEnter = editBox:GetScript("OnEnterPressed") or ChatEdit_OnEnterPressed
            editBox.RatedStats_NoChat_OrigEnter = origEnter

            editBox:SetScript("OnEnterPressed", function(self)
                if ShouldBlockChat(self) then
                    BlockEditBox(self)
                    return
                end
                if self.RatedStats_NoChat_OrigEnter then
                    self.RatedStats_NoChat_OrigEnter(self)
                end
            end)

            -- Still block as soon as the box gains focus in a blocked mode
            editBox:HookScript("OnEditFocusGained", function(self)
                if ShouldBlockChat(self) then
                    BlockEditBox(self)
                end
            end)
        end
    end
end

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
        "Allow all whispers",
        "Allow all whisper chat even when other chat is blocked in PvP instances.",
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
        "RATEDSTATS_NOCHAT_ALLOW_PARTY",
        "allowParty",
        "Always allow Party chat",
        "Never block Party chat, even when other chat is restricted/blocked in PvP instances.",
        defaults.allowParty
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
            HookChatEditBoxes()
            EvaluateInstanceChatState()
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        HookChatEditBoxes()
        EvaluateInstanceChatState()
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
