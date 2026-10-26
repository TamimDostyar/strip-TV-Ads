#!/usr/bin/env bash
set -uo pipefail

WORK="${TVHOME_DIR:-$HOME/tv-home}"
STATE="$HOME/Documents/tv-restore"
LOG="$STATE/disabled.txt"
JDK17=/opt/homebrew/opt/openjdk@17
SDK=/opt/homebrew/share/android-commandlinetools
PKG=com.mihir.tvhome
STOCK=com.google.android.apps.tv.launcherx
STOCK_ACT=$STOCK/.home.HomeActivity
SETUP=com.google.android.tungsten.setupwraith
SMARTTUBE=org.smarttube.stable
TV=""

bold()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
warn()  { printf '  \033[33m! %s\033[0m\n' "$*"; }
die()   { printf '\n\033[31m✗ %s\033[0m\n' "$*"; exit 1; }
ask()   { local a; read -r -p "  $1${2:+ [$2]}: " a </dev/tty; echo "${a:-${2:-}}"; }
yesno() {
  local d=$2 a; local hint; [ "$d" = y ] && hint="Y/n" || hint="y/N"
  read -r -p "  $1 [$hint]: " a </dev/tty; a=${a:-$d}
  case "$a" in [Yy]*) return 0;; *) return 1;; esac
}
tvsh()  { adb -s "$TV" shell "$@" </dev/null | tr -d '\r'; }
run()   { info "+ $*"; tvsh "$@" | sed 's/^/    /'; }
installed() { tvsh pm list packages | grep -qx "package:$1"; }
logpkg() { mkdir -p "$STATE"; grep -qx "$1" "$LOG" 2>/dev/null || echo "$1" >> "$LOG"; }
disable_pkg() { installed "$1" || { info "skip $1 (not installed)"; return; }; run pm disable-user --user 0 "$1"; logpkg "$1"; }

name_of() {
  case $1 in
    com.google.android.youtube.tv) echo "YouTube";;
    org.smarttube.stable) echo "SmartTube (ad-free YouTube)";;
    com.google.android.youtube.tvmusic) echo "YouTube Music";;
    com.google.android.youtube.tvunplugged) echo "YouTube TV";;
    com.netflix.ninja) echo "Netflix";;
    com.disney.disneyplus) echo "Disney+";;
    com.hulu.livingroomplus) echo "Hulu";;
    com.spotify.tv.android) echo "Spotify";;
    com.amazon.amazonvideo.livingroom) echo "Prime Video";;
    com.wbd.stream) echo "Max";;
    com.peacocktv.peacockandroid) echo "Peacock";;
    com.cbs.ott) echo "Paramount+";;
    com.apple.atve.androidtv.appletv) echo "Apple TV";;
    com.plexapp.android) echo "Plex";;
    tv.twitch.android.app) echo "Twitch";;
    com.crunchyroll.crunchyroid) echo "Crunchyroll";;
    tv.pluto.android) echo "Pluto TV";;
    com.tubitv) echo "Tubi";;
    *) echo "$1";;
  esac
}

check_prereqs() {
  bold "Checking this Mac"
  [ "$(uname)" = Darwin ] || die "This script is for macOS."
  command -v brew >/dev/null || die "Install Homebrew first: https://brew.sh"
  command -v git  >/dev/null || die "git not found (run: xcode-select --install)"
  if ! command -v adb >/dev/null; then
    yesno "adb isn't installed. Install android-platform-tools with Homebrew?" y || die "adb is required."
    brew install --cask android-platform-tools || die "adb install failed"
  fi
  info "✓ brew, git, adb"
}

connect_tv() {
  bold "Connect to the TV"
  info "On the TV: Settings → System → Developer options → Wireless debugging (turn it on)."
  info "(No Developer options? Settings → System → About → click Build 7 times.)"
  local ip pport code cport
  while :; do
    ip=$(ask "TV IP address (shown on the Wireless debugging screen)")
    [ -n "$ip" ] || continue
    ping -c 1 -t 2 "$ip" >/dev/null 2>&1 && break
    warn "Can't reach $ip. Same Wi-Fi? Check the IP and try again."
  done

  if ! yesno "Has this Mac already been paired with the TV?" n; then
    info "On the TV, open Wireless debugging → 'Pair device with pairing code'."
    info "Keep that dialog open. It shows a 6-digit code and an IP:PORT just for pairing."
    while :; do
      pport=$(ask "Pairing PORT (from the pairing dialog, NOT the main screen)")
      code=$(ask "6-digit pairing code")
      if adb pair "$ip:$pport" "$code" 2>&1 | tee /dev/stderr | grep -q "Successfully paired"; then break; fi
      warn "Pairing failed. Reopen the pairing dialog (code/port change) and retry."
    done
  fi

  info "Now use the port on the MAIN Wireless debugging screen (it changes when the TV sleeps)."
  info "(Using old-style USB debugging instead? Enter 5555.)"
  while :; do
    cport=$(ask "Connect PORT (main screen)")
    TV="$ip:$cport"
    adb devices | awk -v ip="$ip:" -v tv="$TV" 'index($1,ip)==1 && $1!=tv {print $1}' \
      | while read -r d; do adb disconnect "$d" >/dev/null 2>&1; done
    adb connect "$TV" >/dev/null 2>&1
    local state; state=$(adb -s "$TV" get-state 2>/dev/null || true)
    case "$state" in
      device) info "✓ connected to $TV"; break;;
      *) warn "Not connected (state: ${state:-none}). If the TV shows 'Allow debugging?', accept it."
         yesno "Retry?" y || die "Couldn't connect.";;
    esac
  done
  info "Model: $(tvsh getprop ro.product.model), Android $(tvsh getprop ro.build.version.release), $(tvsh getprop ro.product.cpu.abi)"
}

get_repo() {
  bold "Launcher source"
  if [ -d "$WORK/.git" ]; then info "✓ using $WORK"
  else
    info "Downloading github.com/mihirgupta0900/tv-home to $WORK"
    git clone -q https://github.com/mihirgupta0900/tv-home.git "$WORK" || die "clone failed"
  fi
  git -C "$WORK" checkout -q -- launcher/res/values/config.xml
}

backup() {
  bold "Backing up the TV's current state"
  mkdir -p "$STATE"; local ts; ts=$(date +%Y%m%d-%H%M%S)
  tvsh pm list packages    > "$STATE/packages-$ts.txt"
  tvsh pm list packages -d > "$STATE/disabled-before-$ts.txt"
  tvsh cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME > "$STATE/home-before-$ts.txt"
  info "✓ $(wc -l < "$STATE/packages-$ts.txt" | tr -d ' ') packages saved to $STATE"
}

offer_smarttube() {
  bold "SmartTube (ad-free YouTube client)"
  if installed $SMARTTUBE; then info "✓ already installed"; return; fi
  info "Open source, skips YouTube ads + sponsor segments. Trade-offs:"
  info " - against YouTube's terms of service"
  info " - one maintainer; its signing key was compromised in Dec 2025 (fixed with a new app ID)"
  info " - you trust every future update. Tip: turn off auto-update in its settings."
  info "The official YouTube app stays installed either way."
  yesno "Install SmartTube?" n || return
  local abi url
  abi=$(tvsh getprop ro.product.cpu.abi)
  url=$(curl -s https://api.github.com/repos/yuliskov/SmartTube/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 \
        | grep -E "_${abi}\.apk$" | head -1)
  [ -n "$url" ] || url=$(curl -s https://api.github.com/repos/yuliskov/SmartTube/releases/latest \
        | grep -o '"browser_download_url": *"[^"]*"' | cut -d'"' -f4 | grep -E "_universal\.apk$" | head -1)
  case "$url" in https://github.com/yuliskov/SmartTube/*) ;; *) warn "Couldn't find an official APK; skipping."; return;; esac
  info "Downloading $(basename "$url")"
  curl -sL -o "$WORK/smarttube.apk" "$url" && adb -s "$TV" install -r "$WORK/smarttube.apk" \
    && info "✓ SmartTube installed" || warn "SmartTube install failed"
}

configure_launcher() {
  bold "Customize the home screen"
  local apps=() p i
  while read -r p; do
    case "$p" in ""|$PKG|$STOCK|com.android.tv.settings|com.google.android.tv.remote.service) continue;; esac
    apps+=("$p")
  done < <(tvsh cmd package query-activities --brief -a android.intent.action.MAIN \
             -c android.intent.category.LEANBACK_LAUNCHER | grep / | sed 's/^ *//; s|/.*||' | sort -u)
  [ ${#apps[@]} -gt 0 ] || die "Couldn't list apps on the TV."

  info "Apps on your TV:"
  for i in "${!apps[@]}"; do printf '    %2d) %s\n' $((i+1)) "$(name_of "${apps[$i]}")"; done
  info "Pick the dock apps in left-to-right order. Everything else goes in the grid (press Down)."
  local picks dock=()
  while :; do
    picks=$(ask "Numbers separated by spaces (e.g. 3 1 5)")
    dock=()
    for n in $picks; do
      [[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#apps[@]} ] && dock+=("${apps[$((n-1))]}")
    done
    [ ${#dock[@]} -gt 0 ] || { warn "Pick at least one."; continue; }
    info "Dock: $(for d in "${dock[@]}"; do printf '%s · ' "$(name_of "$d")"; done)"
    yesno "Look right?" y && break
  done

  local cols; cols=$(ask "Apps per row in the grid" 5)
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=5

  local items="" cfg="$WORK/launcher/res/values/config.xml"
  for d in "${dock[@]}"; do items+=$'\n'"        <item>$d</item>"; done
  DOCK="$items" perl -0pi -e 's|<string-array name="dock_apps">.*?</string-array>|<string-array name="dock_apps">$ENV{DOCK}\n    </string-array>|s' "$cfg"
  perl -0pi -e 's|<string-array name="hidden_apps">.*?</string-array>|<string-array name="hidden_apps">\n        <item>com.netflix.tokenmanager</item>\n    </string-array>|s' "$cfg"
  perl -pi -e 's|(<string name="live_tv_package"[^>]*>)[^<]*(</string>)|$1$2|; s|(<string name="input_picker_package"[^>]*>)[^<]*(</string>)|$1$2|; s|<integer name="columns">\d+</integer>|<integer name="columns">'"$cols"'</integer>|' "$cfg"

  if yesno "Use your own wallpapers instead of the 12 bundled nature photos?" n; then
    local dir; dir=$(ask "Folder with 1920×1080 .jpg files")
    dir="${dir/#\~/$HOME}"
    if ls "$dir"/*.jpg >/dev/null 2>&1; then
      rm -f "$WORK/launcher/assets/wallpapers/"*.jpg
      cp "$dir"/*.jpg "$WORK/launcher/assets/wallpapers/"
      info "✓ $(ls "$dir"/*.jpg | wc -l | tr -d ' ') wallpapers copied"
    else warn "No .jpg files in $dir; keeping the bundled ones."; fi
  fi
}

ensure_sdk() {
  bold "Build tools"
  if [ -x "$JDK17/bin/javac" ] && [ -d "$SDK/build-tools/34.0.0" ] && [ -d "$SDK/platforms/android-34" ]; then
    info "✓ JDK 17 + Android SDK present"; return
  fi
  info "Building the launcher needs JDK 17 and the Android SDK (~1 GB, accepts Google's SDK licence)."
  yesno "Install them with Homebrew now?" y || die "Can't build without them."
  brew list openjdk@17 >/dev/null 2>&1 || brew install openjdk@17 || die "JDK install failed"
  brew list --cask android-commandlinetools >/dev/null 2>&1 || brew install --cask android-commandlinetools || die "SDK tools install failed"
  (yes || true) | JAVA_HOME=$JDK17 sdkmanager --sdk_root="$SDK" "platforms;android-34" "build-tools;34.0.0" >/dev/null \
    || die "sdkmanager failed"
  info "✓ installed"
}

build_and_try() {
  bold "Building the launcher"
  (cd "$WORK/launcher" && JAVA_HOME=$JDK17 ANDROID_HOME=$SDK ./build-and-install.sh --build) || die "Build failed (output above)."
  bold "Installing it on the TV (your current home screen is untouched for now)"
  adb -s "$TV" install -r "$WORK/launcher/build/tvhome.apk" || die "Install failed"
  run pm grant $PKG android.permission.ACCESS_FINE_LOCATION
  run am start -n $PKG/.MainActivity
}

commit_home() {
  bold "Make it the home screen"
  info "This disables Google's stock launcher (where the home-screen ads come from)."
  yesno "Look at the TV. Does the new home screen look right? Commit it?" y || { info "Skipped. Stock home still active."; return 1; }
  run cmd package set-home-activity --user 0 $PKG/.MainActivity
  disable_pkg $STOCK
  disable_pkg $SETUP
  run cmd package set-home-activity --user 0 $PKG/.MainActivity
  run am force-stop com.android.tv.settings
  run am force-stop $PKG
  run input keyevent KEYCODE_HOME
  info "✓ Test it: open any app, press Home on the remote. It should land on the new launcher."
}

debloat() {
  bold "Remove Google TV clutter (disabled, not uninstalled)"
  local p desc def
  while IFS='|' read -r p desc def <&3; do
    installed "$p" || continue
    yesno "Disable $desc ($p)?" "$def" && disable_pkg "$p"
  done 3<<'EOF'
com.google.android.apps.tv.dreamx|ambient screensaver with recommendations/ads|y
android.autoinstalls.config.google.gtvpai|silent installer for promoted apps|y
com.google.android.videos|Google TV / Play Movies app|y
com.google.android.play.games|Google Play Games|y
com.google.android.feedback|feedback reporter|y
EOF
  info "Never disabled: casting (mediashell), voice/Assistant (katniss), Play Services."
}

restore_tv() {
  bold "Restore the TV to stock"
  connect_tv
  if [ -f "$LOG" ]; then while read -r p; do [ -n "$p" ] && run pm enable "$p"; done < "$LOG"; fi
  run pm enable $SETUP
  run pm enable $STOCK
  run cmd package set-home-activity --user 0 $STOCK_ACT
  run input keyevent KEYCODE_HOME
  [ -f "$LOG" ] && mv "$LOG" "$LOG.restored-$(date +%Y%m%d-%H%M%S)"
  yesno "Uninstall the custom launcher too?" y && adb -s "$TV" uninstall $PKG
  installed $SMARTTUBE && yesno "Uninstall SmartTube?" n && adb -s "$TV" uninstall $SMARTTUBE
  info "✓ Restored. Press Home on the remote."
}

cleanup_mac() {
  bold "Clean up this Mac?"
  info "The TV keeps its new setup. Undo info stays in $STATE."
  yesno "Remove JDK 17, the Android SDK and the build folder ($WORK)?" n || return
  brew uninstall --cask android-commandlinetools 2>/dev/null
  rm -rf "$SDK"
  brew uninstall openjdk@17 2>/dev/null; brew autoremove
  rm -rf "$WORK"
  if yesno "Also remove adb? (You'd need it again to restore or change the TV.)" n; then
    adb kill-server 2>/dev/null; brew uninstall --cask android-platform-tools; rm -rf ~/.android
  fi
  info "✓ cleaned"
}

bold "TV setup — debloat + clean home screen for Google TV"
echo "    1) Set up / customize the TV"
echo "    2) Restore the TV to stock"
echo "    3) Quit"
case "$(ask "Choose" 1)" in
  1)
    check_prereqs
    connect_tv
    get_repo
    backup
    offer_smarttube
    configure_launcher
    ensure_sdk
    build_and_try
    if commit_home; then debloat; fi
    cleanup_mac
    bold "Done."
    info "Re-run this script any time to change the dock, or choose 2 to undo everything."
    ;;
  2) check_prereqs; restore_tv ;;
  *) exit 0 ;;
esac
