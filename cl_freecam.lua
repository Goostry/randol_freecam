local Config = lib.load('config')
lib.locale()

-- Lets this player exceed Config.MaxDistance. This is a session-only toggle
-- controlled server-side via /ccambypass (which itself requires a persisted
-- permission granted by an admin via /ccamgrant). We resync it here in case
-- this client script restarts while the server still holds the session state.
local hasBypassPermission = lib.callback.await('ccam:getBypassState', false) or false

RegisterNetEvent('ccam:setBypass', function(state)
    hasBypassPermission = state
    lib.notify({
        title = locale('menu_title'),
        description = state and locale('bypass_granted') or locale('bypass_revoked'),
        type = state and 'success' or 'inform'
    })
end)

RegisterNetEvent('ccam:permissionChanged', function(granted)
    lib.notify({
        title = locale('menu_title'),
        description = granted and locale('permission_granted') or locale('permission_revoked'),
        type = granted and 'success' or 'inform'
    })
end)

local FREE_CAM
local offsetRotX, offsetRotY, offsetRotZ = 0.0, 0.0, 0.0
local precision = 1.0
local speed = 1.0
local currFilter = 1
local camActive = false
local camFrozen = false
local freezeMode = 'off' -- 'off' | 'static' | 'follow'
local followActive = false
local followOffset = vector3(0.0, 0.0, 0.0)
local followBaseHeading = 0.0
local followBaseRot = vector3(0.0, 0.0, 0.0)
local dofOn = false
local dofStrength = 0.5
local dofFar = 150.0
local dofNear = 0.10
local barsOn = false
local isMenuOpen = false
local instructionalScaleform = nil

local function toggleMap()
    local isRadarVisible = not IsRadarHidden()
    DisplayRadar(not isRadarVisible)
end

local function toggleBars()
    barsOn = not barsOn
    if barsOn then
        while barsOn do
            DrawRect(1.0, 1.0, 2.0, 0.23, 0, 0, 0, 255)
            DrawRect(1.0, 0.0, 2.0, 0.23, 0, 0, 0, 255)
            Wait(0)
        end
    end
end

local function resetEverything()
    ClearFocus()
    SetCamUseShallowDofMode(FREE_CAM, false)
    RenderScriptCams(false, false, 0, true, false)
    DestroyCam(FREE_CAM, false)
    offsetRotX = 0.0
    offsetRotY = 0.0
    offsetRotZ = 0.0
    speed = 1.0
    precision = 1.0
    currFov = GetGameplayCamFov()
    currFilter = 1
    ClearTimecycleModifier()
    FREE_CAM = nil
    dofStrength = 0.5
    dofFar = 150.0
    dofNear = 0.10
    dofOn = false
    barsOn = false
    camActive = false
    camFrozen = false
    followActive = false

    if instructionalScaleform then
        SetScaleformMovieAsNoLongerNeeded(instructionalScaleform)
        instructionalScaleform = nil
    end
end

local function buildInstructionalButtons()

    instructionalScaleform = RequestScaleformMovie('instructional_buttons')

    while not HasScaleformMovieLoaded(instructionalScaleform) do
        Wait(0)
    end

    BeginScaleformMovieMethod(instructionalScaleform, 'CLEAR_ALL')
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(instructionalScaleform, 'SET_CLEAR_SPACE')
    ScaleformMovieMethodAddParamInt(200)
    EndScaleformMovieMethod()

    local groups = {
        {controls = {32, 33, 34, 35}, label = locale('ctrl_move')}, -- W A S D
        {controls = {22, 20}, label = locale('ctrl_vertical')}, -- Space / Duck
        {controls = {44, 38}, label = locale('ctrl_roll')}, -- Q / E
        {controls = {14, 15}, label = locale('ctrl_zoom')}, -- Mouse wheel
        {controls = {21, 15}, label = locale('ctrl_speed')}, -- Shift + wheel
        {controls = {2}, label = locale('ctrl_look')}, -- Mouse
    }

    for i = 1, #groups do

        BeginScaleformMovieMethod(instructionalScaleform, 'SET_DATA_SLOT')
        ScaleformMovieMethodAddParamInt(i - 1)

        for _, control in ipairs(groups[i].controls) do
            ScaleformMovieMethodAddParamTextureNameString(GetControlInstructionalButton(2, control, true))
        end

        ScaleformMovieMethodAddParamTextureNameString(groups[i].label)
        EndScaleformMovieMethod()
    end

    BeginScaleformMovieMethod(instructionalScaleform, 'DRAW_INSTRUCTIONAL_BUTTONS')
    EndScaleformMovieMethod()

    BeginScaleformMovieMethod(instructionalScaleform, 'SET_BACKGROUND_COLOUR')
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(0)
    ScaleformMovieMethodAddParamInt(80)

    EndScaleformMovieMethod()
end

local function destroyInstructionalButtons()

    if instructionalScaleform then
        SetScaleformMovieAsNoLongerNeeded(instructionalScaleform)
        instructionalScaleform = nil
    end
end

local function setNewFov(setNewFov)

    if DoesCamExist(FREE_CAM) then
        local currFov = GetCamFov(FREE_CAM)
        local newFov = currFov + setNewFov

        if ((newFov >= Config.MinFov) and (newFov <= Config.MaxFov)) then
            SetCamFov(FREE_CAM, newFov)
        end
    end
end

local function toggleDof()

    dofOn = not dofOn
    if dofOn then
        if DoesCamExist(FREE_CAM) then
            SetCamUseShallowDofMode(FREE_CAM, true)
            SetCamNearDof(FREE_CAM, dofNear)
            SetCamFarDof(FREE_CAM, dofFar)
            SetCamDofStrength(FREE_CAM, dofStrength)
        end
    else
        dofStrength = 0.5
        dofFar = 150.0
        dofNear = 0.10
        SetCamNearDof(FREE_CAM, dofNear)
        SetCamFarDof(FREE_CAM, dofFar)
        SetCamDofStrength(FREE_CAM, dofStrength)
        SetCamUseShallowDofMode(FREE_CAM, false)
        ClearFocus()
    end
end

local function processNewPos(x, y, z)

    local currentPos = vector3(x, y, z)
    local moveSpeed = 0.1 * speed

    local rot = vector3(offsetRotX, offsetRotY, offsetRotZ)
    local forwardVector = GetDirectionFromRotation(rot)

    local rightVector = vector3(forwardVector.y, -forwardVector.x, 0.0)

    local velocity = vector3(0, 0, 0)

    if IsDisabledControlPressed(1, 32) then -- W
        velocity = velocity + (forwardVector * moveSpeed)
    elseif IsDisabledControlPressed(1, 33) then -- S
        velocity = velocity - (forwardVector * moveSpeed)
    end

    if IsDisabledControlPressed(1, 34) then -- A
        velocity = velocity - (rightVector * moveSpeed)
    elseif IsDisabledControlPressed(1, 35) then -- D
        velocity = velocity + (rightVector * moveSpeed)
    end

    if IsDisabledControlPressed(1, 22) then -- Space (Haut)
        velocity = velocity + vector3(0, 0, moveSpeed)
    elseif IsDisabledControlPressed(1, 20) then -- Z (Bas)
        velocity = velocity - vector3(0, 0, moveSpeed)
    end

    if IsDisabledControlPressed(1, 21) then -- Shift (hold)
        if IsDisabledControlPressed(1, 15) then -- Mouse wheel up (speed up)
            speed = math.min(speed + 0.1, Config.MaxSpeed)
        elseif IsDisabledControlPressed(1, 14) then -- Mouse wheel down (speed down)
            speed = math.max(speed - 0.1, Config.MinSpeed)
        end
    else
        if IsDisabledControlPressed(1, 15) then -- Mouse wheel up (zoom in)
            setNewFov(-1.0)
        elseif IsDisabledControlPressed(1, 14) then -- Mouse wheel down (zoom out)
            setNewFov(1.0)
        end
    end

    local idealPos = currentPos + velocity

    offsetRotX = offsetRotX - (GetDisabledControlNormal(1, 2) * precision * 8.0)
    offsetRotZ = offsetRotZ - (GetDisabledControlNormal(1, 1) * precision * 8.0)

    if IsDisabledControlPressed(1, 44) then -- Q (roll left)
        offsetRotY = offsetRotY - precision
    elseif IsDisabledControlPressed(1, 38) then -- E (roll right)
        offsetRotY = offsetRotY + precision
    end

    offsetRotX = math.clamp(offsetRotX, -90.0, 90.0)
    offsetRotY = math.clamp(offsetRotY, -90.0, 90.0)
    offsetRotZ = offsetRotZ % 360.0

    return idealPos
end

local function processCamControls()
    DisableFirstPersonCamThisFrame()


    for k, v in pairs(Config.DisabledControls) do
        DisableControlAction(0, v, true)
    end

    local camCoords = GetCamCoord(FREE_CAM)
    local newPos = processNewPos(camCoords.x, camCoords.y, camCoords.z)
    local currentPos = GetEntityCoords(cache.ped)

    if not hasBypassPermission and #(currentPos - vec3(newPos.x, newPos.y, newPos.z)) > Config.MaxDistance then

        if not IsEntityDead(cache.ped) then
            DrawSphere(currentPos.x, currentPos.y, currentPos.z, Config.MaxDistance, 255, 0, 0, 0.1)
        end

    else

        local rayHandle = StartShapeTestSweptSphere(
            camCoords.x, camCoords.y, camCoords.z,
            newPos.x, newPos.y, newPos.z,
            0.4, 17, 0, 0
        )

        local _, hit, endCoords, surfaceNormal, _ = GetShapeTestResult(rayHandle)

        if hit == 0 then

            SetCamCoord(FREE_CAM, newPos.x, newPos.y, newPos.z)
        else
            local targetVec = vec3(newPos.x, newPos.y, newPos.z)
            local moveDir = targetVec - camCoords

            local dot = moveDir.x * surfaceNormal.x + moveDir.y * surfaceNormal.y + moveDir.z * surfaceNormal.z

            local slideVec = moveDir - (surfaceNormal * dot)
            local finalPos = camCoords + slideVec

            finalPos = finalPos + (surfaceNormal * 0.05)

            SetCamCoord(FREE_CAM, finalPos.x, finalPos.y, finalPos.z)
        end

        SetFocusArea(GetCamCoord(FREE_CAM), 0.0, 0.0, 0.0)
        SetCamRot(FREE_CAM, offsetRotX, offsetRotY, offsetRotZ, 2)
    end

    if dofOn then
        SetUseHiDof()
    end

    if instructionalScaleform then
        DrawScaleformMovieFullscreen(instructionalScaleform, 255, 255, 255, 255)
    end
end

local function rotateOffsetByHeading(offset, deltaDeg)
    local rad = math.rad(deltaDeg)
    local cosA, sinA = math.cos(rad), math.sin(rad)
    return vector3(
        offset.x * cosA - offset.y * sinA,
        offset.x * sinA + offset.y * cosA,
        offset.z
    )
end

local function startFollowCam()

    if followActive or not DoesCamExist(FREE_CAM) then return end

    followActive = true

    local playerCoords = GetEntityCoords(cache.ped)
    local camCoords = GetCamCoord(FREE_CAM)
    followOffset = camCoords - playerCoords
    followBaseHeading = GetEntityHeading(cache.ped)
    followBaseRot = GetCamRot(FREE_CAM, 2)

    CreateThread(function()
        while followActive and camFrozen and DoesCamExist(FREE_CAM) do

            local newPlayerCoords = GetEntityCoords(cache.ped)
            local headingDelta = GetEntityHeading(cache.ped) - followBaseHeading
            local rotatedOffset = rotateOffsetByHeading(followOffset, headingDelta)
            local newCoords = newPlayerCoords + rotatedOffset

            SetCamCoord(FREE_CAM, newCoords.x, newCoords.y, newCoords.z)
            SetCamRot(FREE_CAM, followBaseRot.x, followBaseRot.y, followBaseRot.z + headingDelta, 2)
            Wait(0)
        end
        followActive = false
    end)
end

local function stopFollowCam()
    followActive = false
end

local function startCam()
    if camActive then return end
    stopFollowCam()
    camActive = true
    camFrozen = false

    if not DoesCamExist(FREE_CAM) then
        ClearFocus()
        FREE_CAM = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', GetEntityCoords(cache.ped), 0, 0, 0, GetGameplayCamFov() * 1.0)
        SetCamActive(FREE_CAM, true)
        RenderScriptCams(true, false, 0, true, false)
        SetCamAffectsAiming(FREE_CAM, false)
    end

    buildInstructionalButtons()

    CreateThread(function()
        while camActive do
            processCamControls()
            Wait(0)
        end
        if not camFrozen then
            resetEverything()
        end
    end)
end

local function stopCam(mode)
    if not camActive then return end
    camActive = false
    destroyInstructionalButtons()

    if mode == 'static' then
        camFrozen = true
    elseif mode == 'follow' then
        camFrozen = true
        startFollowCam()
    else
        camFrozen = false
    end
end

local function toggleCam()
    if camActive then
        stopCam('off')
    else
        startCam()
    end
end

local function setFreezeMode(mode)
    freezeMode = (freezeMode == mode) and 'off' or mode
end

local function registerCamMenu()

    lib.registerMenu({
        id = 'cinematic_cam_menu',
        title = locale('menu_title'),
        position = 'top-right',
        onSideScroll = function(selected, scrollIndex, args)

            if selected == 2 then
                SetTimecycleModifier(Config.Filters[scrollIndex])
                currFilter = scrollIndex
            elseif selected == 6 then
                dofNear = tonumber(Config.NearDof[scrollIndex])
                SetCamNearDof(FREE_CAM, dofNear)
            elseif selected == 7 then
                dofFar = tonumber(Config.FarDof[scrollIndex])
                SetCamFarDof(FREE_CAM, dofFar)
            elseif selected == 8 then
                dofStrength = tonumber(Config.StrengthDof[scrollIndex])
                SetCamDofStrength(FREE_CAM, dofStrength)
            end
        end,
        onCheck = function(selected, checked, args)

            if selected == 1 then
                toggleCam()
            elseif selected == 3 then
                toggleDof()
            elseif selected == 4 then
                toggleBars()
            elseif selected == 5 then
                toggleMap()
            elseif selected == 9 then
                setFreezeMode('static')
            elseif selected == 10 then
                setFreezeMode('follow')
            end
        end,
        onClose = function(keyPressed)

            isMenuOpen = false
            stopCam(freezeMode)
        end,
        options = {
            {label = locale('toggle_camera'), checked = camActive, icon = 'camera'},
            {label = locale('camera_filters'), values = Config.Filters, icon = 'camera', defaultIndex = currFilter, description = locale('camera_filters_desc')},
            {label = locale('toggle_dof'), checked = dofOn, icon = 'eye', description = locale('toggle_dof_desc')},
            {label = locale('toggle_bars'), checked = barsOn, icon = 'film', description = locale('toggle_bars_desc')},
            {label = locale('toggle_map'), checked = not IsRadarHidden(), icon = 'map', description = locale('toggle_map_desc')},
            {label = locale('dof_near'), values = Config.NearDof, icon = 'left-right', description = locale('dof_near_desc')},
            {label = locale('dof_far'), values = Config.FarDof, icon = 'left-right', description = locale('dof_far_desc')},
            {label = locale('dof_strength'), values = Config.StrengthDof, icon = 'left-right', description = locale('dof_strength_desc')},
            {label = locale('freeze_static'), checked = freezeMode == 'static', icon = 'snowflake', description = locale('freeze_static_desc')},
            {label = locale('freeze_follow'), checked = freezeMode == 'follow', icon = 'video', description = locale('freeze_follow_desc')},
        }
    }, function(selected, scrollIndex, args)

        if selected == 2 then
            ClearTimecycleModifier()
            currFilter = 1
        end
    end)
end

registerCamMenu()

RegisterCommand(Config.CommandName, function()
    if isMenuOpen then
        lib.hideMenu()
    else
        isMenuOpen = true
        startCam()
        registerCamMenu()
        lib.showMenu('cinematic_cam_menu')
    end
end)

RegisterKeyMapping(Config.CommandName, locale('keymap_desc'), 'keyboard', 'F7')

AddEventHandler('gameEventTriggered', function(event, data)

    if event ~= 'CEventNetworkEntityDamage' then return end

    local victim, victimDied = data[1], data[4]
    if not IsPedAPlayer(victim) then return end

    if victimDied and NetworkGetPlayerIndexFromPed(victim) == cache.playerId and (IsPedDeadOrDying(victim, true) or IsPedFatallyInjured(victim)) then
        if DoesCamExist(FREE_CAM) then
            resetEverything()
        end
    end
end)

function GetDirectionFromRotation(rotation)
    local z = math.rad(rotation.z)
    local x = math.rad(rotation.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end