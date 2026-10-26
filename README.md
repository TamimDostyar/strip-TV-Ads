# Google TV Cleanup

An interactive script that removes ads and clutter from a Chromecast with Google TV (or other Google TV device) and replaces the home screen with a clean, Apple TV-style launcher. It runs entirely over Wi-Fi, and everything it changes can be undone.

## Requirements
- macOS with [Homebrew](https://brew.sh)
- TV and Mac on the same Wi-Fi
- On the TV: Settings → System → About → click **Build** 7 times, then Developer options → turn on **Wireless debugging**

## Usage
```bash
bash all_in_one.sh
```
The script walks you through:
1. Connecting to the TV (IP, pairing code, port)
2. Backing up the current setup
3. Optionally installing SmartTube (ad-free YouTube client; see the warning in the script)
4. Choosing your dock apps, grid size, and wallpapers
5. Building the launcher and testing it before anything changes
6. Making it the home screen and disabling Google TV clutter
7. Optionally cleaning up the build tools from your Mac

## Undo
Run the script again and choose **2) Restore the TV to stock**. Restore info is kept in `~/Documents/tv-restore`.

## Notes
- Packages are disabled, never uninstalled. A factory reset also undoes everything.
- Ads inside apps (YouTube, Hulu, etc.) come from those apps and aren't affected.
- Tested on Chromecast with Google TV (armeabi-v7a), macOS.

## Credits
The launcher is from [mihirgupta0900/tv-home](https://github.com/mihirgupta0900/tv-home) (MIT); this script downloads and builds it. Wallpapers are from Wikimedia Commons; see that repo for credits.
