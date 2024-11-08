# Notes
tar --exclude='node_modules' --exclude='tmp' --exclude='package-lock.json' --exclude='yarn.lock' -cvf home_backup.tar ~/*

### Get terminal Profile
```
dconf dump /org/gnome/terminal/legacy/profiles:/
```

### Export one of the profiles 
### (for example the one with id: :1430663d-083b-4737-a7f5-8378cc8226d1 )
```
dconf dump /org/gnome/terminal/legacy/profiles:/:1430663d-083b-4737-a7f5-8378cc8226d1/ > my-custom-profile.dconf
```

### Load an existing profile
```
dconf load /org/gnome/terminal/legacy/profiles:/:1430663d-083b-4737-a7f5-8378cc8226d1/ < my-custom-profile.dconf
```

### Load keybinding
```sh
# Load custom keybinding
dconf dump /org/gnome/terminal/legacy/keybindings/

# Read one of the keys
dconf read /org/gnome/terminal/legacy/keybindings/close-tab

# Write a new custom keybinding
dconf write /org/gnome/terminal/legacy/keybindings/close-tab "'<Primary><Alt>w'"
```

### Add a startup command
For example, a command to switch the CTRL-CAPS_LOCK keys.    
Menu > Startup Applications (can have other name ex: *Session & Startup*) > Add a new Custom Command > `/usr/bin/setxkbmap -option "ctrl:swapcaps"`.

**Note:** `/usr/bin/setxkbmap -option "ctrl:nocaps"` also works.

You can find the startup commands/applications in `~/.config/autostart`.

Alternative using:
- gnome-tweaks
```
gsettings set org.gnome.desktop.input-sources xkb-options "['ctrl:nocaps']"
```
- xmodmap (create the `~/.xmodmap` file)
```
!
! Swap Caps_Lock and Control_L
!
remove Lock = Caps_Lock
remove Control = Control_L
keysym Control_L = Caps_Lock
keysym Caps_Lock = Control_L
add Lock = Caps_Lock
add Control = Control_L
```

### Make a shell file executable 
#### by the owner
chmod u+x FILENAME
#### by all users
chmod a+rx FILENAME

## Specify the SSH key to use
By default, on my config, Github will use the SSH key at `~/.ssh/id_ed25519`.
But if I gave the key a different name (ex `github_id_ed25519`), I need to specify which name.   
I should create a file (called `config`) in `~/.ssh/`

```
Host github.com
  AddKeysToAgent yes
  IgnoreUnknown UseKeychai
  UseKeychain yes
  IdentityFile ~/.ssh/github_id_ed25519

```

## Brief doc on using `vnstat`
https://askubuntu.com/a/846455

## Disable Firefox menu bar toggle on ALT key press
By default, pressing the ALT key will toggle the Firefox menu bar (Linux + Windows).   
To disable this, you can search for `about:config` in Firefox, and then search for `ui.key.menuAccessKeyFocuses` and set its value to `false`.   

You can also change the default for `ui.key.menuAccessKey` config (it should have a value of `18`). Replace its value to `20` (Caps Lock).

## Terminate a process after a certain time
The `timeout` command can be used to terminate a process after some time. You need to prepend it to your command, example for the `openvpn` command:
```
timeout {SECONDS}s openvpn ~/path/to/config_file
```
Instead of `s`, use `h` for hours or `d` for days.
By default, `timeout` will send a SIGTERM signal, but you can send another signal, example SIGKILL:

```
timeout --signal SIGKILL {SECONDS} openvpn ~/path/to/config_file
```

## VSCode
### Sync Settings - overwrite the default `settings.yml`
First install the [Sync Settings](https://github.com/zokugun/vscode-sync-settings) extension. Which will create a `settings.yml` config file.

Replace that default file with your own from this repo:   
**Note:** Make sure to upload the `hostname` in the settings.yml file to the current machine.

```
cp vscode/sync_settings/settings.yml ~/Library/Application\ Support/Code/User/globalStorage/zokugun.sync-settings/
```
Or for Linux:
```
cp vscode/sync_settings/settings.yml ~/.config/Code/User/globalStorage/zokugun.sync-settings/  
```
Or for Windows:
```
cp vscode/sync_settings/settings.yml   ~/AppData/Roaming/Code/User/globalStorage/zokugun.sync-settings/
```

It will ask to overwrite -> `y`. Open the VSCode command prompt and select: `Sync Settings - Download (repository -> user)`. A prompt should eventually appear, accept it and the VSCode will restart.

## tmux
Common **commands**:
- `tmux` (aliased to `tns`) - start a new tmux session
- `tmux ls` - list active sessions
- `tmux attach-session -t {session_index}` (aliased to `ta #`)- attach to existing session
- `tmux kill-session -t {session_index}`

Some common defaults **shortcuts** (`C-b` = CTRL+b):
- `C-b + %` - horizontal split
- `C-b + "` - vertical split
- `C-b + {arrow_key}` - switch to the pane
- `C-b + x` - kill current pane
- `C-b + d` (aliased to `C-d`) - detach from the current session
- `C-b + c` - create a new window
- `C-b + {#}` - switch to the window with index {#}
- `C-b + n/p` - switch to the `n`ext/`p`revious window
- `C-b + l` - switch to the last active window
