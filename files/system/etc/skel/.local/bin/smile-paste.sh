#!/bin/bash
# Smile can only copy on Wayland. Type its pick once Umbriel restores focus.

baseline="$(wl-paste --no-newline 2>/dev/null)"

flatpak run it.mijorus.smile

pick="$(wl-paste --no-newline 2>/dev/null)"
if [ -z "$pick" ] || [ "$pick" = "$baseline" ]; then
    exit 0
fi

# Do not type raw image data into the focused window.
if ! wl-paste --list-types 2>/dev/null | grep -q '^text/plain'; then
    exit 0
fi

sleep 0.15 # Wait for Umbriel to restore focus.

# Chromium apps ignore wtype's Unicode keys. Use Ctrl+V there, but not in
# terminals, where Ctrl+V means "insert the next key as text."
app_id="$(umbriel windows --json 2>/dev/null | jq -r '.[] | select(.focused == true) | .app_id' 2>/dev/null | head -n 1)"
shopt -s nocasematch
case "$app_id" in
    *brave*|*chrom*|*edge*|*vivaldi*|*opera*)
        wtype -M ctrl v -m ctrl
        ;;
    *)
        wtype -- "$pick"
        ;;
esac
