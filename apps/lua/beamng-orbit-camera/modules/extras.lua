local M = {}
local ObsIntegration = require('modules/obs-integration')
local Settings = require('modules/settings')

function M.drawExtrasTab()
  Settings.drawCollisionSettings()
  ui.newLine()
  ObsIntegration.drawObsIntegrationTab()
end

return M
