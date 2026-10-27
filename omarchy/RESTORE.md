# Captured environment

- Captured: 2026-10-25
- Omarchy package: `4.0.6-1`
- Theme: `tokyo-night`
- Desktop shortcut: Super + Shift + A launches `codex-desktop` (package `openai-codex-desktop`).
- Touchpad: natural scrolling enabled.
- Monitor settings: automatic preferred output/mode/scale, with `GDK_SCALE=2`.

Install Omarchy before applying these files. They use Omarchy's Lua-based
Hyprland configuration and installed helpers; they are not standalone Hyprland
configuration. Review compatibility when restoring onto a different Omarchy
version. Omarchy updates or refresh commands may replace linked files: check
`git diff` and rerun the installer if a link is replaced.

Personal destinations declared in `conf/common.links` and `conf/shell.links` always
take priority, including when running `omarchy/install.sh` directly. The desktop
installer skips those destinations; bootstrap installs the personal links.

Apply the theme manually after installation:

```bash
omarchy theme set tokyo-night
```

Generated colors/backgrounds under `~/.local/state/omarchy/current` are not
tracked. Terminal configs retain their references to those generated files.
No custom themes or plugins were present when this snapshot was made.
Bundled invitation hooks and sample hooks are intentionally excluded.

## Undo installation

The installer prints the backup directory for each run. To undo a file, remove
its installed symbolic link and move the corresponding original file or link
from that backup directory back to the same path under `~/.config`. If there
was no original file, just remove the installed link. Back up any later edits
before undoing. Reload Hyprland and check its configuration errors afterward.
