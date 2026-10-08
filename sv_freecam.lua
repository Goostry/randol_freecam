local bypassActive = {}

CreateThread(function()

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `ccam_permissions` (
            `identifier` VARCHAR(60) NOT NULL,
            `allowed` TINYINT(1) NOT NULL DEFAULT 1,
            PRIMARY KEY (`identifier`)
        )
    ]])
end)

local function getIdentifier(source)
    return GetPlayerIdentifierByType(source, 'license')
end

local function isPermissionGranted(identifier)

    if not identifier then return false end

    local row = MySQL.scalar.await('SELECT allowed FROM ccam_permissions WHERE identifier = ?', { identifier })

    return row == 1 or row == true
end

local function setPermission(identifier, allowed)
    MySQL.insert.await(
        'INSERT INTO ccam_permissions (identifier, allowed) VALUES (?, ?) ON DUPLICATE KEY UPDATE allowed = ?',
        { identifier, allowed and 1 or 0, allowed and 1 or 0 }
    )
end

lib.callback.register('ccam:getBypassState', function(source)
    return bypassActive[source] == true
end)

lib.addCommand('ccamgrant', {
    help = 'Grant or revoke permission to use /ccambypass for a player (persisted)',
    restricted = 'group.admin',
    params = {
        { name = 'target', help = 'Target player ID', type = 'playerId' },
        { name = 'state', help = 'on / off (toggles if omitted)', type = 'string', optional = true },
    }
}, function(source, args)
    local target = args.target
    local identifier = getIdentifier(target)

    if not identifier then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {'[ccam]', "Could not resolve that player's identifier."}
        })
        return
    end

    local newState
    if args.state == 'on' then
        newState = true
    elseif args.state == 'off' then
        newState = false
    else
        newState = not isPermissionGranted(identifier)
    end

    setPermission(identifier, newState)

    if not newState then
        bypassActive[target] = nil
        TriggerClientEvent('ccam:setBypass', target, false)
    end

    TriggerClientEvent('ccam:permissionChanged', target, newState)

    local targetName = GetPlayerName(target) or ('ID ' .. target)
    TriggerClientEvent('chat:addMessage', source, {
        color = {255, 165, 0},
        multiline = true,
        args = {'[ccam]', ('Bypass permission %s for %s.'):format(newState and 'granted' or 'revoked', targetName)}
    })
end)

lib.addCommand('ccambypass', {
    help = 'Toggle the freecam max-distance bypass (requires granted permission)',
}, function(source)
    local identifier = getIdentifier(source)

    if not isPermissionGranted(identifier) then
        TriggerClientEvent('chat:addMessage', source, {
            color = {255, 0, 0},
            args = {'[ccam]', 'You do not have permission to use this command.'}
        })
        return
    end

    local newState = not bypassActive[source]
    bypassActive[source] = newState or nil
    TriggerClientEvent('ccam:setBypass', source, newState)
end)

AddEventHandler('playerDropped', function()
    bypassActive[source] = nil
end)
