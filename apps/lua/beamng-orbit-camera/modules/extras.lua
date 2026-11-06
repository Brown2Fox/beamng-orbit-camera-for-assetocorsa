---@class ExtrasModule
local M = {}
local ObsIntegration = require('modules/obs-integration')
local Settings = require('modules/settings')

function M.drawExtrasTab()
  ui.text('Glance')
  ui.separator()
  Settings.drawCheckbox('disableGlance', false)
  if ui.itemHovered() then
    ui.setTooltip('Disables camera response to glance left, right and back. These use the standard game controls, configured in Content Manager, not in this app.')
  end
  if Settings.get('disableGlance') == 0 then
    Settings.drawSlider('glanceTransitionDuration', false)
    if ui.itemHovered() then
      ui.setTooltip('Time to switch glance views and return to the orbit camera. 0 = instant.')
    end
  end
  ui.newLine()
  Settings.drawCollisionSettings()
  ui.newLine()
  ObsIntegration.drawObsIntegrationTab()
end

return M
