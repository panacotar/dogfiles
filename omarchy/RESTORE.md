# Captured environment

- Captured: 2026-10-25
- Omarchy package: `4.0.6-1`
- Preferred theme: `lupine` (light; updated 2026-10-29)
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

Apply the preferred light theme manually after installation (the installer does
not change themes):

```bash
omarchy theme set lupine
```

This applies the Lupine palette and sets the system color preference to light.

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

## Hot corners

Pause the pointer in the bottom-left corner of any display for one second to
turn off all displays. This does not immediately lock or suspend the laptop.
Move the pointer or press a key to wake the displays. Normal idle locking still
applies; use Stay Awake Sessions in `sleep` scope to prevent suspension while
seeding. The hot corner itself does not create or extend a sleep inhibitor.

Settings live in `omarchy/config/hypr/hotcorners.lua`, linked by the installer
into `~/.config/hypr/hotcorners.lua` and loaded by `hyprland.lua`. Its settings
table controls `enabled`, `interval_ms` (250), `dwell_ms` (1000), `size` (5 logical
pixels), and `corners`. Set any of `top_left`, `top_right`, `bottom_left`, or
`bottom_right` to `"display_off"`, or `false` to leave it inactive. To disable all
hot corners, set `enabled = false` and reload Hyprland.

Cursor checks run inside Hyprland four times per second without launching
processes. Sampling can add up to 250 ms to activation time and cannot detect
excursions that happen entirely between checks. Each visit fires once; leave
the active corner before using it again. Loading/reloading while the pointer
is already in the corner also requires leaving first. Monitor geometry is read
live, including scaling, rotation, and layout changes.

After changing settings, run `hyprctl reload` and `hyprctl configerrors`.
Run the offline behavior checks with `lua tests/test_hotcorners.lua` from the
repository root. To remove the feature, remove the hot-corner `require` from
`hyprland.lua`, remove its manifest entry and installed module link, and reload.
