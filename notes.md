# Notes
tar --exclude='node_modules' --exclude='tmp' --exclude='package-lock.json' --exclude='yarn.lock' -cvf home_backup.tar ~/*

### Get terminal Profile
dconf dump /org/gnome/terminal/legacy/profiles:/

### Export one of the profiles 
### (for example the one with id: :1430663d-083b-4737-a7f5-8378cc8226d1 )
dconf dump /org/gnome/terminal/legacy/profiles:/:1430663d-083b-4737-a7f5-8378cc8226d1/ > my-custom-profile.dconf

### Load an existing profile
dconf load /org/gnome/terminal/legacy/profiles:/:1430663d-083b-4737-a7f5-8378cc8226d1/ < my-custom-profile.dconf

### Make a shell file executable 
#### by the owner
chmod u+x FILENAME
#### by all users
chmod a+rx FILENAME

## Specify the SSH key to use
By default, on my config, Github will use the SSH key at `~/.ssh/id_ed25519`.
But if I gave the key a different name (ex `github_id_ed25519`), I need to speciy which name.   
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

## VS code
### Sync Settings - overwrite the default `settings.yml`
First install the [Sync Settings](https://github.com/zokugun/vscode-sync-settings) extension. Which will create a `settings.yml` config file.

Replace that default file with your own from this repo:
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

Make sure to upload the `hostname` in the settings.yml file to the current machine.
