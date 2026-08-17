--------
-- BeamNG-style Orbit Camera companion Lua App.
--
-- Keeps orchestration only. Persisted settings, device input and optional OBS
-- rendering each live in their own module.
--------

local Settings = require('modules/settings')
local Input = require('modules/input')
local ObsIntegration = require('modules/obs-integration')

local cameraIndex = -1;

local cameraBridge = ac.connect({
  ac.StructItem.key('beamng_orbit_camera.camera_bridge'),
  cameraIndex = ac.StructItem.uint32(),
}, false, ac.SharedNamespace.Shared)

---@param dt number
---@diagnostic disable-next-line: duplicate-set-field
function script.update(dt)

  cameraIndex = cameraBridge.cameraIndex

  local cameraMode = ac.getSim().driveableCameraMode

  local shouldUpdate = cameraIndex == 1 and cameraMode == ac.DrivableCamera.Chase or
                      cameraIndex == 2 and cameraMode == ac.DrivableCamera.Chase2 or
                      ObsIntegration.enabled

  if shouldUpdate then
    Settings.update()
    Input.update(dt)
    ObsIntegration.update(dt, Settings.cameraConfig, Input.cameraInput)
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
