#!/usr/bin/bash
# Keep the GTK portal, keyring, file manager, and their shared GTK tools.
# Check each package first because Bazzite may change its package set.
set -euxo pipefail

packages=(
    gnome-shell gnome-session gnome-session-wayland-session
    gnome-session-xsession mutter mutter-common gdm
    gnome-control-center gnome-settings-daemon gnome-remote-desktop
    gnome-bluetooth gnome-color-manager gnome-user-share rygel
    gnome-disk-utility gnome-system-monitor gnome-tour gnome-software
    gnome-initial-setup gnome-terminal ptyxis yelp gnome-user-docs
    gnome-browser-connector gnome-characters
    # Fedora's Nautilus needs tinysparql and localsearch.
    steamdeck-gnome-presets steamdeck-backgrounds
    gnome-search-yafti nautilus-gsconnect rom-properties-gtk4
    rom-properties-localsearch3
    gnome-backgrounds gnome-epub-thumbnailer
    gnome-shell-extension-user-theme gnome-shell-extension-gsconnect
    xdg-desktop-portal-gnome
)

family_pattern='^(gnome-shell-extension-|papers)'

remove=()
for pkg in "${packages[@]}"; do
    if rpm -q --quiet "$pkg"; then
        remove+=("$pkg")
    fi
done
while read -r pkg; do
    [ -n "$pkg" ] && remove+=("$pkg")
done < <(rpm -qa --qf '%{NAME}\n' | grep -E "$family_pattern" || true)

# Mark these as user-picked so autoremove keeps them.
dnf5 -y mark user xdg-desktop-portal-umbriel-nightly xdg-desktop-portal-gtk gnome-keyring gnome-keyring-pam nautilus

if [ "${#remove[@]}" -gt 0 ]; then
    # A normal remove ignores install reasons and drops Nautilus with its add-ons.
    # Autoremove honors the user-picked marks above.
    dnf5 -y remove --setopt=clean_requirements_on_remove=false "${remove[@]}"
fi

dnf5 -y autoremove

# An older Terra Umbriel RPM declares an obsolete hard requirement on
# xwayland-satellite. Drop the package as soon as Terra removes that metadata;
# while the requirement remains, leave the RPM transaction graph consistent.
if rpm -q --quiet xwayland-satellite && ! rpm -q --requires umbriel-nightly | grep -Fxq xwayland-satellite; then
    dnf5 -y remove xwayland-satellite
fi
