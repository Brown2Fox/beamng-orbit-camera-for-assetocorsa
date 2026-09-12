# Release archive

Run from the project root with PowerShell 7:

```powershell
pwsh -File tools/package_release.ps1
```

Creates `dist/beamng-orbit-camera-<version>.zip` for uploading to a mod website. The archive contains `apps/` and `extension/` at its root for installation with Content Manager or extraction into the Assetto Corsa folder.

The version comes from the two manifests; packaging stops if they disagree. Running again replaces the archive for that version. `dist/` is ignored by Git.
