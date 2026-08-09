# BeamNG.drive Orbit Camera for Assetto Corsa

<p align="center">
  <img src="res/draft_logo.png?raw=true" width="20%">
</p>
  
I like the orbit camera in BeamNG.drive, so I decided to port its behavior to Assetto Corsa and share the result.

The goal of this mod is to reproduce the original BeamNG.drive orbit camera as closely as possible while adapting it to the APIs and limitations available in Assetto Corsa and CSP.

## Showcase

[![](https://img.youtube.com/vi/bgEGF9AT-Ps/0.jpg)](https://youtu.be/bgEGF9AT-Ps)

![Watch the video](https://youtu.be/bgEGF9AT-Ps)

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
- BeamNG-style target/render rotation separation
- Smooth rendered yaw behavior
- Near-clip-aware camera collisions
- Collision pull-in and smooth release
- Optional vehicle-specific reference nodes

## Mod Structure

The mod consists of two parts:

1. **Lua app** — stores the camera settings, provides the configuration UI, handles control bindings and supplies input to the camera script.
2. **Chaser camera script** — contains the actual camera logic and runs as a CSP custom chaser camera.

## How to install

The easiest way to install the mod is to drag the archive into Content Manager and install it normally. Content Manager should handle the files automatically.
You can also install it manually: extract the archive into the Assetto Corsa root directory so that the `apps` and `extension` folders merge with the existing ones.

After installation:

1. Go to **Settings → Custom Shaders Patch → Camera: General** and enable **Allow first chase camera** and/or **Allow second chase camera**, depending on which chase-camera slot you want to use.
2. Go to **Settings → Custom Shaders Patch → Camera: Chase**, enable the corresponding first or second chase camera, and select **BeamNG.drive Orbit Camera** as its camera script.
3. Make sure the **BeamNG Orbit Camera** Lua app is enabled under **Content → Miscellaneous → Lua Apps**. It should normally be enabled automatically after installation.

## Configuration

Camera and input settings are configured from the **BeamNG Orbit Camera** Lua app while you are in a session.

The **Camera** tab contains the camera parameters:

![](res/lua_app_camera.png?raw=true)

Most values intentionally follow the corresponding BeamNG.drive orbit-camera settings and ranges.

The camera ignores the standard Assetto Corsa chase-camera distance, height and pitch settings and uses its own values instead. This is intentional so all relevant camera settings can be adjusted from one place and tested immediately in-session.

### Input

The **Controls** tab contains common bindable actions and specifics for gamepad and mouse.

![](res/lua_app_controls.png?raw=true)

The gamepad and mouse are implemented using *predefined control schemes* to reduce the number of possible moving parts. And also because, in any case, there is no convenient way to assign gamepad axes and mouse buttons.

### Mouse Orbit Conflict

There can currently be a conflict with Assetto Corsa/CSP's built-in orbit camera if that camera is also configured to rotate while holding the **right mouse button**.

## Mod Specifics

The default camera target is based on the Assetto Corsa car position. Dynamic FOV and dynamic pitch use the car bounding box where BeamNG.drive would normally use vehicle-specific geometry.

Optional custom scene nodes can be added to improve the camera reference geometry:

- `BEAMNG_ORBIT_TARGET` — overrides the default camera target reference point.
- `BEAMNG_ORBIT_REAR` — overrides the rear reference used by Dynamic FOV.

If those nodes are not present, the camera automatically uses its normal fallbacks, so no vehicle modifications are required for regular use.

## How to uninstall

Be aware that using Content Manager's uninstall/remove option will remove the Lua app but leave the custom chaser-camera script installed. To make sure the mod is removed completely, delete both folders listed below manually.

```text
apps/lua/beamng-orbit-camera/
extension/lua/chaser-camera/beamng-orbit/
```

# Disclaimer

For those who care, the project was created using the power of LLM. It helped me a lot to understand the scripts of the BeamNG.drive camera.

# Credits

- **BeamNG.drive** devs for `orbit.lua` and `collision.lua`
