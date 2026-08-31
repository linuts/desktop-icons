# Desktop Icons

Desktop icons for Omarchy: files and folders from `~/Desktop`, mounted drives,
network mounts, plus Home and Trash, with sorting, icon size, alignment, and
auto-hide while windows are open on the workspace.

## Install

```sh
omarchy plugin add https://github.com/linuts/desktop-icons.git --enable
```

## Usage

Icons are drawn on the desktop layer below windows. The desktop shows:

- Files and folders from `~/Desktop`
- Mounted drives under `/run/media/$USER`, `/mnt`, or `/media`
- Network mounts (SSHFS, NFS, SMB/CIFS, Ceph, 9p, WebDAV, rclone)
- **Home** and **Trash** shortcuts

Left-click an item to open it. Right-click the desktop or an item to open the
settings menu, or press **Shift+TAB** while keyboard navigation is active.

## Keyboard navigation

A desktop keybinding focuses the desktop so you can move between icons with the
keyboard. It is defined in your Hyprland config (Omarchy does not ship it with
the plugin). Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Desktop icons", "omarchy-shell io.github.linuts.desktop-icons focus")
```

Then reload Hyprland:

```sh
hyprctl reload
```

With the desktop focused:

| Key            | Action                    |
| -------------- | ------------------------- |
| `SUPER + D`    | Focus the desktop icons   |
| `Tab`          | Next icon                 |
| `Shift+Tab`    | Open the context menu     |
| Arrow keys     | Move the selection        |
| `Enter`        | Open the selected item    |
| `Esc`          | Leave keyboard navigation |

Clicking the desktop also focuses it for keyboard navigation. The binding shows
up in the Omarchy keybindings menu (`omarchy menu keybindings`).

To release the desktop without a keypress:

```sh
omarchy-shell io.github.linuts.desktop-icons unfocus
```

## Configure

The settings menu (right-click the desktop or an item, or press `Shift+TAB`
while keyboard navigation is active) offers:

- **Sort By**: Name, Type, or Size, with optional reverse order
- **Appearance**: Align left/center/right, icon size (small/medium/large), and
  whether labels are shown
- **Hide while windows open**: hide the icons when any window is on the workspace
- **Show On Desktop**: toggle Desktop files, Mounted drives, Network mounts,
  Home folder, and Trash
- **Refresh**: rescan the desktop and mounts

Settings persist to `~/.local/state/omarchy/desktop-icons/config.json`.

### IPC

```sh
omarchy-shell io.github.linuts.desktop-icons refresh          # rescan
omarchy-shell io.github.linuts.desktop-icons focus            # enter keyboard nav
omarchy-shell io.github.linuts.desktop-icons unfocus          # leave keyboard nav
omarchy-shell io.github.linuts.desktop-icons listItems        # dump state as JSON
```

## Remove

```sh
omarchy plugin remove io.github.linuts.desktop-icons
```

Remove the plugin's state if you want a clean sweep:

```sh
rm -rf ~/.local/state/omarchy/desktop-icons
```

If you added the `SUPER + D` keybinding above, delete that `o.bind` line and run
`hyprctl reload`.

## License

MIT. See [LICENSE](LICENSE).