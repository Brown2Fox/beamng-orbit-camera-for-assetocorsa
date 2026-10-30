# BeamNG.drive Orbit Camera for Assetto Corsa

<p align="center">
  <img src="res/draft_logo.png?raw=true" width="20%">
</p>
  
I like the orbit camera in BeamNG.drive, so I decided to port it to Assetto Corsa.

A calm, smooth camera, without unnecessary shake. Well suited to drifting and rallying with a gamepad or keyboard.

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
- Distance, FOV and dolly zoom (mouse wheel, with two configurable modifier keys)
- Analogue gamepad zoom
- Mouse orbit control
- Mouse-wheel zoom
- Dynamic pitch at speed
- Dynamic camera height at speed
- Dynamic FOV at speed
- Dolly-zoom distance compensation
- Smooth rendered yaw behavior
- Near-clip-aware camera collisions
- Smart collisions: the camera rises over the ground and under ceilings, and pulls in smoothly at walls
- Follow road slope
- Helicopter mode: a second, separately stored set of camera values
- Camera angle held to the car while rewinding or scrubbing a replay
- Optional: keep the orbit angle when switching cars

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

The window is resizable and scrolls when it is small. The camera settings are at the top; **Obstacles**, **Controls** and **Streaming** are collapsible sections below them. Status indicators appear only while the camera or OBS integration is active.

The **Chase / Helicopter** switch selects which set of camera values the sliders and buttons act on. Each mode keeps its own values; Helicopter is far away with a long lens.

The sliders are grouped as **Where the camera sits** (**Distance**, **Lens**, **Angle**, **Aim point**), **How it follows** (**Turns with car**, **Tilts with hills**) and **Extra at full speed** (**Wider lens**, **Higher angle**, **Higher aim**). Most values follow the corresponding BeamNG.drive orbit-camera settings and ranges.

While the camera is active, gray readouts show its current distance, lens, angle and aim point, including speed offsets and manual orbit adjustments.

- **Straighten** (behind the car) returns the camera behind the car and restores the angle and distance from the settings.
- **Straighten** (keep zoom & angle) returns the camera behind the car while keeping the current distance, lens and angle.
- **Save view** (as default) saves the current orbit distance, lens and angle to the settings, without the additional speed offsets.
- **Reset** (all sliders) restores the defaults of the active mode.

**Turns with car** supports values down to 0.2. Values below 0.5 gradually take effect at higher speeds while keeping the camera less reactive at low speeds. **Tilts with hills** scales how much of the camera's vertical angle follows the road slope, so a long camera stays calm over crests and dips.

The camera ignores the standard Assetto Corsa chase-camera distance, height and pitch settings and uses its own values instead. This is intentional so all relevant camera settings can be adjusted from one place and tested immediately in-session.

### Input

The **Controls** section shows its current state in the header (for example "Right-drag orbit · wheel zoom"). It contains:

- **Wheel**, **Extra key 1 / 2** and **Extra key 1 / 2 + wheel** (shown while mouse orbit is on): what the mouse wheel does, and what it does while an extra key (Ctrl, Alt or Shift) is held. The actions are **Moves camera** (distance), **Changes lens** (FOV) and **Does both** (dolly zoom: the car keeps its size and only the perspective changes). Defaults: **Does both**, Ctrl + wheel moves the camera, Alt + wheel changes the lens.
- **Orbit speed** and **Zoom speed**.
- **Mouse options**: **Orbit** (**Off** / **Right-drag**) and **Wheel zooms** (**Only while dragging** / **Always**).
- **Gamepad**: **Orbit** (**Off** / **Right stick**), **Zoom with** (**None**, **Left stick**, **Right stick** or **Right + turn**), the **Zoom button** to hold while zooming, and the stick deadzones.
- **Keys and buttons**: **Orbit left/right**, **Tilt down/up**, **Zoom out/in**, **Straighten** and **Straighten, keep view**.

The gamepad and mouse are implemented using *predefined control schemes* to reduce the number of possible moving parts. And also because, in any case, there is no convenient way to assign gamepad axes and mouse buttons.

The camera uses the gamepad selected in the game's control settings.

Standard glance left/right/back controls are enabled by default. Hold **left + back** or **right + back** for a front-left or front-right view at 45 degrees. **Controls → Ignore glance left/right/back** disables the camera's response to these controls.

**Controls → Keep view when switching cars** is off by default: each car starts from your default view. When on, the orbit angle and zoom carry over to the next car.

## Mod Specifics

The **Obstacles** section contains the collision settings and the **Streaming** section contains the OBS integration.

### Collisions

**Blocked by** selects what the camera reacts to: **Nothing**, **Track** (physics shapes) or **Track + trees** (visuals, the default). **When blocked** selects **Pull in** (closer to the car at walls) or **Pull in + rise** (default), which also lifts the camera over the ground and under tunnel ceilings at the same distance, keeping **Clearance over ground**. Rise casts up to 15 rays per frame, so it costs more CPU than plain pull-in. **Ignore above** (Track only) ignores hits higher than that above the car.

**Closest to car** sets the nearest the camera can pull in. **Keep car the same size when pulled in** (on by default) widens the lens while the camera is pulled in, up to **Widest lens when pulled in**.

**No obstacle checks while straightened** is off by default. Enabling it skips collision checks while the camera is straightened, which can slightly reduce CPU load. Collision checks resume after manual orbit or zoom input when **Blocked by** is not **Nothing**.

### OBS Integration

Enable **Streaming → Send camera to OBS** to make the camera available in OBS as a custom `BeamNG Orbit Camera` source. Integration is off by default.

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
