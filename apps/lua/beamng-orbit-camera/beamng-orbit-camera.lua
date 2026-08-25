--------
-- BeamNG-style Orbit Camera companion Lua App.
--
-- Keeps orchestration only. Persisted settings, device input and optional OBS
-- rendering each live in their own module.
--------

local Settings = require('modules/settings')
local Input = require('modules/input')
local ObsIntegration = require('modules/obs-integration')

Input.setSettings(Settings)

local cameraIndex = -1;
local playerWasInPit = false

local cameraBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.camera_bridge'),
  cameraIndex = ac.StructItem.uint32(),
}, false, ac.SharedNamespace.Shared)

local function updateAutomaticRecenter()
  local playerCar = ac.getCar(0)
  if playerCar == nil then
    return
  end

  local playerInPit = playerCar.isInPit
  if playerInPit and not playerWasInPit then
    Input.cameraInput.recenterKeepValuesPressed = true
  end
  playerWasInPit = playerInPit
end

ac.onSessionStart(function(_, restarted)
  if not restarted then return end

  Input.cameraInput.recenterKeepValuesPressed = true
end)

---@param dt number
---@diagnostic disable-next-line: duplicate-set-field
function script.update(dt)

  cameraIndex = cameraBridge.cameraIndex

  local cameraMode = ac.getSim().driveableCameraMode

  local cameraActive = cameraIndex == 1 and cameraMode == ac.DrivableCamera.Chase or
                      cameraIndex == 2 and cameraMode == ac.DrivableCamera.Chase2
  local shouldUpdate = cameraActive or
                      ObsIntegration.enabled

  if shouldUpdate then
    if cameraActive then
      Input.update(dt)
      Settings.update()
    end

    updateAutomaticRecenter()

    ObsIntegration.update(dt, Settings.cameraConfig, Input.cameraInput)

    Input.writeToBridge()
    Input.reset()
  end
end

local function drawTabs()
  ui.tabItem('Camera', Settings.drawCameraTab)
  ui.tabItem('Controls', Input.drawControlsTab)
  ui.tabItem('OBS Integration', ObsIntegration.drawObsIntegrationTab)
end

---@param dt number
function script.windowMain(dt)
  ui.tabBar('beamngOrbitCameraTabs', drawTabs)
end
