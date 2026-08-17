--------
-- Optional OBS integration for BeamNG Orbit Camera.
--
-- Disabled by default and runtime-only. Camera core and OBS helper are loaded
-- lazily on first enable, and no second camera update runs while disabled.
--------

local M = {}

local CAMERA_CORE_MODULE = '../../../extension/lua/chaser-camera/beamng-orbit/modules/orbit-camera'

M.enabled = false
local obs = nil
---@type BeamNGOrbitCameraModule|nil
local OrbitCamera = nil
local obsSource = nil
local obsShot = nil
local obsSceneRoot = nil

local latestPosition = vec3()
local latestDirection = vec3(0, 0, 1)
local latestUp = vec3(0, 1, 0)
local latestFov = 65.0
local poseReady = false

local shaderParams = {
  textures = { txHDR = nil },
  shader = [[float4 main(PS_IN pin){
    float4 r = txHDR.Sample(samLinear, pin.Tex);
    return float4(r.rgb, 1);
  }]]
}

local function disposeShot()
  if obsShot == nil then return end
  obsShot:dispose()
  obsShot = nil
  shaderParams.textures.txHDR = nil
end

local function resizeShot(size)
  disposeShot()

  if obsSceneRoot == nil then
    obsSceneRoot = ac.findNodes('sceneRoot:yes')
  end

  obsShot = ac.GeometryShot(
    obsSceneRoot,
    size,
    1,
    false,
    render.AntialiasingMode.YEBIS,
    render.TextureFormat.R16G16B16A16.Float,
    0
  )
  obsShot:setClippingPlanes(0.1, 5e3)
  obsShot:setBestSceneShotQuality()
  obsShot:setShadersType(render.ShadersType.Main)
  shaderParams.textures.txHDR = obsShot
end

local function drawSource(canvas)
  if not poseReady or obsShot == nil then return end

  obsShot:update(latestPosition, latestDirection, latestUp, latestFov)
  canvas:updateWithShader(shaderParams)
end

local function setEnabled(value)
  if value == M.enabled then return end

  M.enabled = value
  poseReady = false

  if M.enabled then
    obs = obs or require('shared/utils/obs')
    OrbitCamera = OrbitCamera or require(CAMERA_CORE_MODULE)
    OrbitCamera.reset()

    obsSource = obs.register(
      'Custom',
      'BeamNG Orbit Camera',
      obs.Flags.HDR + obs.Flags.ApplyCMAA + obs.Flags.UserSize,
      resizeShot,
      drawSource
    )
    return
  end

  if obsSource ~= nil then
    obsSource:dispose()
    obsSource = nil
  end
  disposeShot()
end

---@param dt number
---@param cameraConfig BeamNGOrbitCameraConfig
---@param input BeamNGOrbitCameraInput
function M.update(dt, cameraConfig, input)
  if not M.enabled then return end

  local targetCar = ac.getCar(0)
  if targetCar == nil then return end

  ---@cast OrbitCamera BeamNGOrbitCameraModule
  local pose = OrbitCamera.update(dt, targetCar, cameraConfig, input)
  if pose == nil then return end

  latestPosition:set(pose.position)
  latestDirection:set(pose.direction)
  latestUp:set(pose.up)
  latestFov = pose.fov
  poseReady = true
end

function M.drawObsIntegrationTab()
  ui.text('OBS Integration')
  ui.separator()

  if ui.checkbox('Enable OBS integration', M.enabled) then
    setEnabled(not M.enabled)
  end

  ui.pushStyleColor(ui.StyleColor.Text, rgbm.colors.gray)
  ui.textWrapped(
    'If OBS Integration is enabled while this camera is active as the chase camera, its camera logic will run twice per frame.'
  )
  ui.popStyleColor()
end

ac.onRelease(function()
  if obsSource ~= nil then
    obsSource:dispose()
    obsSource = nil
  end
  disposeShot()
end)

return M
