#!/bin/bash
# Smile can only copy on Wayland. Type its pick once Umbriel restores focus.

# Count clipboard copies while Smile is open. Comparing text would miss
# picking the emoji that is already on the clipboard.
copies="$(mktemp)"
trap 'kill "$watcher" 2>/dev/null; rm -f "$copies"' EXIT
wl-paste --watch sh -c 'echo >> "$1"' sh "$copies" &
watcher=$!

# The watcher reports the current clipboard once on start.
for _ in $(seq 20); do
    [ -s "$copies" ] && break
    sleep 0.05
done
started="$(wc -l < "$copies")"

flatpak run it.mijorus.smile
sleep 0.1 # Let the watcher see Smile's copy.

pick="$(wl-paste --no-newline 2>/dev/null)"
if [ "$(wc -l < "$copies")" -le "$started" ] || [ -z "$pick" ]; then
    exit 0
fi

# Do not type raw image data into the focused window.
if ! wl-paste --list-types 2>/dev/null | grep -q '^text/plain'; then
    exit 0
fi

sleep 0.15 # Wait for Umbriel to restore focus.

# Chromium apps ignore wtype's Unicode keys. Use Ctrl+V there, but not in
# terminals, where Ctrl+V means "insert the next key as text."
app_id="$(umbriel windows --json 2>/dev/null | jq -r '.[] | select(.active == true) | .app_id' 2>/dev/null | head -n 1)"
shopt -s nocasematch
case "$app_id" in
    *brave*|*chrom*|*edge*|*vivaldi*|*opera*)
        wtype -M ctrl v -m ctrl
        ;;
    *)
        wtype -- "$pick"
        ;;
esac
