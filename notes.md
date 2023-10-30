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

## VS code
### Sync Settings - overwrite the default `settings.yml`
First install the [Sync Settings](https://github.com/zokugun/vscode-sync-settings) extension. Which will create a `settings.yml` config file.

Replace that default one:
```
cp vscode/sync_settings/settings.yml ~/Library/Application\ Support/Code/User/globalStorage/zokugun.sync-settings/
```

It will ask to overwrite -> `y`. Open the VSCode command prompt and select: `Sync Settings - Download (repository -> user)`. A prompt should eventually appear, accept it and the VSCode will restart.
