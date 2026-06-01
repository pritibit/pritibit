# Cursor Cloud — Maestro

Maestro mobile UI testing is available on this environment.

## CLI

```bash
maestro --help
maestro test flow.yaml
```

`maestro` is on `PATH` via `/etc/profile.d/maestro.sh` (`~/.maestro/bin`).

## Maestro Studio (desktop)

```bash
maestro-studio
```

- AppImage: `/opt/maestro-studio/MaestroStudio.AppImage`
- FUSE-less fallback: `/opt/maestro-studio/extracted` (pre-extracted) or `--appimage-extract-and-run`
- Force extracted tree: `MAESTRO_STUDIO_USE_EXTRACTED=1 maestro-studio`

Use from the VNC desktop when a display is required.

## Reinstall

```bash
bash scripts/install-maestro-cursor-cloud.sh
```
