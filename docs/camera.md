# Orbit Camera Documentation

## Runtime behavior

- The extension keeps its own camera state in the shared core module and recalculates the camera pose every frame.
- It reads the current car transform, heading and speed and applies player input (yaw, pitch, zoom, glance and recenter actions).
- The result is then passed through dynamic camera behavior (distance/FOV/height/pitch) and obstacle collision correction.
- The final pose is written to `ac.Camera` for gameplay and to the OBS source when OBS integration is enabled.

## Data path

- App reads user settings and input and publishes them into shared bridges.
- The chaser-camera extension reads the same bridge and computes the camera pose.
- OBS uses the same core module through a separate instance.

## Difference from BeamNG behavior

- The implementation is a Lua port for Assetto Corsa runtime primitives, not BeamNG's internal camera runtime.
- Both chaser-camera and OBS rendering share one common core file to keep behavior aligned.
- User settings are stored via `ac.storage` and synchronized through shared structs.
- Dynamic parameters are adapted to AC coordinate and timing conventions while preserving BeamNG-style chase-camera feel.
