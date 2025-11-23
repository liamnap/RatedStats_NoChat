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
    enabled = true,                 -- master toggle
    allowWhispers = false,          -- allow whispers while blocking other chat
    blockPvp = true,                -- block chat in battlegrounds
    blockArena = true,              -- block chat in arenas
    allowChatInSoloShuffle = false, -- allow chat in Solo Shuffle even if arenas are blocked
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
    if C_PvP and C_PvP.IsSoloShuffle then
        local ok, isSolo = pcall(C_PvP.IsSoloShuffle)
        if ok then
            return isSolo
        end
    end
    return false
end

local function ShouldBlockChat(editBox)
    if not RatedStats_NoChatDB or not RatedStats_NoChatDB.enabled then
        return false
    end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        return false
    end

    local blockInstance = false

    if instanceType == "pvp" then
        blockInstance = RatedStats_NoChatDB.blockPvp
    elseif instanceType == "arena" then
        if IsSoloShuffle() and RatedStats_NoChatDB.allowChatInSoloShuffle then
            blockInstance = false
        else
            blockInstance = RatedStats_NoChatDB.blockArena
        end
    end

    if not blockInstance then
        return false
    end

    -- respect whisper setting
    local chatType = editBox and (editBox:GetAttribute("chatType") or editBox.chatType)
    if chatType == "WHISPER" or chatType == "BN_WHISPER" then
        if RatedStats_NoChatDB.allowWhispers then
            return false
        end
    end

    return true
end

-- evaluate whether to disable/restore keybinds based on current instance + settings
local function EvaluateInstanceChat()
    if not RatedStats_NoChatDB or not RatedStats_NoChatDB.enabled then
        -- addon disabled => ensure bindings are restored
        if #storedKeys > 0 then
            RestoreChat()
        end
        return
    end

    local inInstance, instanceType = IsInInstance()
    if #storedKeys == 0 then
        SaveChatKeys()
    end

    local shouldBlock = false

    if inInstance then
        if instanceType == "pvp" then
            shouldBlock = RatedStats_NoChatDB.blockPvp
        elseif instanceType == "arena" then
            if IsSoloShuffle() and RatedStats_NoChatDB.allowChatInSoloShuffle then
                shouldBlock = false
            else
                shouldBlock = RatedStats_NoChatDB.blockArena
            end
        end
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
        "RATEDSTATS_NOCHAT_ENABLED",
        "enabled",
        "Enable NoChat",
        "Block your chat input in PvP instances according to the options below.",
        defaults.enabled
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_ALLOW_WHISPERS",
        "allowWhispers",
        "Allow whispers",
        "Allow whisper chat even when other chat is blocked in PvP instances.",
        defaults.allowWhispers
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_PVP",
        "blockPvp",
        "Block chat in battlegrounds",
        "Block chat input in battlegrounds and epic battlegrounds.",
        defaults.blockPvp
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_BLOCK_ARENA",
        "blockArena",
        "Block chat in arenas",
        "Block chat input in arenas.",
        defaults.blockArena
    )

    AddCheckbox(
        "RATEDSTATS_NOCHAT_ALLOW_SHUFFLE",
        "allowChatInSoloShuffle",
        "Allow chat in Solo Shuffle",
        "Allow chat input in Solo Shuffle even if arenas are blocked.",
        defaults.allowChatInSoloShuffle
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
