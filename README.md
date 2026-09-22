# BeamNG.drive Orbit Camera for Assetto Corsa

<p align="center">
  <img src="res/draft_logo.png?raw=true" width="20%">
</p>
  
I like the orbit camera in BeamNG.drive, so I decided to port its behavior to Assetto Corsa and share the result.


What I like most about it is how well suited it is to driving with a gamepad or keyboard, especially when drifting or rallying, and makes it easy to see what the car is doing without unnecessary camera shake getting in the way.


The goal of this mod is to bring the familiar BeamNG.drive orbit-camera feel to Assetto Corsa, while adapting it to the APIs and limitations available in AC and CSP.

## Showcase

<div align="center">
  <a href="https://www.youtube.com/watch?v=bgEGF9AT-Ps" target="_blank">
    <img src="https://utfs.io/f/nGnSqDveMsqxa2oqMUuADdzv8Pr5ybLj14U2EZXKMNIwm7GQ" width="60%" style="border: 2px solid #30363d;">
  </a>
</div>

## Description

This is a nearly 1:1 behavioral port of the BeamNG.drive orbit camera. The following camera features and behaviors have been reproduced:

- Movement-based camera heading
- BeamNG-style camera relaxation
- Manual orbit yaw and pitch
- Manual recentering
- Camera lock / hemisphere handling
- Reverse-direction camera flip behavior
- Distance zoom
- Analogue gamepad zoom
- Mouse orbit control
- Mouse-wheel zoom
- Dynamic pitch at speed
- Dynamic camera height at speed
- Dynamic FOV at speed
- Dolly-zoom distance compensation
- Smooth rendered yaw behavior
- Near-clip-aware camera collisions
- Collision pull-in and smooth release

## Mod Structure

The mod consists of two parts:

1. **Lua app** — stores the camera settings, provides the configuration UI, handles control bindings and supplies input to the camera script.
2. **Chaser camera script** — contains the actual camera logic and runs as a CSP custom chaser camera.

## Requirements

- Assetto Corsa with Custom Shaders Patch (CSP).
- CSP **0.3.0-preview120 or newer** for mouse controls and camera collisions. On CSP below 0.3, these features are disabled and their settings are hidden.
- Content Manager is recommended for installation and setup.

## How to install

The easiest way to install the mod is to drag the archive into Content Manager and press install. It's properly packed mod zip archive, so Content Manager should handle this fine.

Or you can install it manually: extract the archive into the Assetto Corsa root directory so that the `apps` and `extension` folders merge with the existing ones.

After installation:

1. Go to **Settings → Custom Shaders Patch → Camera: General** and enable **Allow first chase camera** and/or **Allow second chase camera**, depending on which chase-camera slot you want to use.
2. Go to **Settings → Custom Shaders Patch → Camera: Chase**, enable the corresponding first or second chase camera, and select **BeamNG.drive Orbit Camera** as its camera script.
3. Make sure the **BeamNG Orbit Camera** Lua app is enabled under **Content → Miscellaneous → Lua Apps**. It should normally be enabled automatically after installation.

## Configuration

Camera and input settings are configured from the **BeamNG Orbit Camera** Lua app while you are in a session.

In smaller windows, tab contents scroll above the status bar. Status indicators appear only while the camera or OBS integration is active.

The **Camera** tab contains the camera parameters:

![](res/lua_app_camera.png?raw=true)

Most values follow the corresponding BeamNG.drive orbit-camera settings and ranges.

While the camera is active, gray readouts show its current distance, FOV, pitch and height, including speed offsets and manual orbit adjustments.

- **Recenter** returns the camera behind the car and restores the pitch and distance from the settings.
- **Recenter, keep pitch/distance** returns the camera behind the car while preserving the current orbit pitch and distance.
- **Capture current pitch/distance** saves the current orbit pitch and distance to the settings, without the additional speed offsets.

**Follow vehicle direction** supports values down to 0.2. Values below 0.5 gradually take effect at higher speeds while keeping the camera less reactive at low speeds.

The camera ignores the standard Assetto Corsa chase-camera distance, height and pitch settings and uses its own values instead. This is intentional so all relevant camera settings can be adjusted from one place and tested immediately in-session.

### Input

The **Controls** tab contains common bindable actions and specifics for gamepad and mouse.

![](res/lua_app_controls.png?raw=true)

The gamepad and mouse are implemented using *predefined control schemes* to reduce the number of possible moving parts. And also because, in any case, there is no convenient way to assign gamepad axes and mouse buttons.

The camera uses the gamepad selected in the game's control settings.

Standard glance left/right/back controls are enabled by default. Hold **left + back** or **right + back** for a front-left or front-right view at 45 degrees. **Controls → Additional → Disable glance left/right/back** disables the camera's response to these controls.

## Mod Specifics

The **Extras** tab contains collision settings and OBS integration:

![](res/lua_app_extras.png?raw=true)

### Collisions

**Extras → Collision** offers three handling modes: **Disabled**, **Collision with physics shapes** (default), and **Collision with visuals**.

**Disable collision for recentered camera** is off by default. Enabling it skips collision checks while the camera is recentered, which can slightly reduce CPU load. Collision checks resume after manual orbit or zoom input when a collision handling mode is enabled.

### OBS Integration

Enable **Extras → Enable OBS integration** to make the camera available in OBS as a custom `BeamNG Orbit Camera` source. Integration is off by default.

**_Caution:_** If OBS Integration is enabled while this camera is active as the chase camera, its camera logic will run **twice** per frame.

Unfortunately, running the camera logic only once causes jitter (and/or other misbehaviors) because the in-game camera and OBS source are updated from different contexts.

## Release archive

Run from the project root with PowerShell 7:

```powershell
pwsh -File tools/package_release.ps1
```

Creates `dist/beamng-orbit-camera-<version>.zip` with the `apps/` and `extension/` folders ready for installation. The version comes from the manifests, which must agree. `dist/` is ignored by Git. See [packaging notes](tools/README.md).

## How to uninstall

Be aware that using Content Manager's uninstall/remove option will remove the Lua app but leave the custom chaser-camera script installed. To make sure the mod is removed completely, delete both folders listed below manually.

```text
apps/lua/beamng-orbit-camera/
extension/lua/chaser-camera/beamng-orbit/
```

# Future Plans​

- Maybe presets

# Disclaimer

For those who care, the project was created using the power of LLM. It helped me a lot to understand the scripts of the BeamNG.drive camera.

# Credits

- **BeamNG.drive** devs for `orbit.lua` and `collision.lua`
