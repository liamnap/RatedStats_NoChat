local addonName = ...
local frame = CreateFrame("Frame", addonName.."Frame")

-- store player's chat keybinds
local storedKeys = {}

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
    print("|cff00ccffRatedStats:|r Chat input |cffff5555disabled|r in PvP.")
end

-- helper: restore the bindings
local function RestoreChat()
    for _, key in ipairs(storedKeys) do
        SetBinding(key, "OPENCHAT")
    end
    SaveBindings(GetCurrentBindingSet())
    print("|cff00ccffRatedStats:|r Chat input |cff55ff55restored|r.")
end

-- hook so clicks on [Raid]/[Whisper] also get cancelled
hooksecurefunc("ChatEdit_ActivateChat", function(editBox)
    local inInstance, instanceType = IsInInstance()
    if inInstance and (instanceType == "pvp" or instanceType == "arena") then
        editBox:ClearFocus()
        editBox:SetText("")
        print("|cff00ccffRatedStats:|r Chat input |cffff5555blocked|r in PvP.")
    end
end)

-- event handler
frame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        local inInstance, instanceType = IsInInstance()
        if #storedKeys == 0 then
            SaveChatKeys()
        end

        if inInstance and (instanceType == "pvp" or instanceType == "arena") then
            DisableChat()
        else
            RestoreChat()
        end
    end
end)

frame:RegisterEvent("PLAYER_ENTERING_WORLD")
