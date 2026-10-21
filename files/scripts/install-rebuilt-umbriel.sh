#!/usr/bin/bash
# Swap Terra's F44 umbriel-nightly for the rawhide rebuild from the
# umbriel-builder stage when it is newer and safe to run. Terra must still be
# enabled so the rebuild's dependencies resolve.
set -euxo pipefail

dir=/tmp/umbriel-rebuild
rpm=$(find "$dir" -maxdepth 1 -name 'umbriel-nightly-*.x86_64.rpm' -print -quit 2>/dev/null || true)

fallback() {
    echo "umbriel rebuild: $*; keeping Terra's $(rpm -q umbriel-nightly)" >&2
    rm -rf "$dir"
    exit 0
}

[[ -n $rpm ]] || fallback "no rebuilt RPM"

built_wlroots=$(cat "$dir/wlroots-evr" 2>/dev/null || true)
image_wlroots=$(rpm -q --qf '%{EVR}' wlroots 2>/dev/null || true)
[[ -n $built_wlroots && -n $image_wlroots ]] || fallback "cannot compare wlroots builds"
[[ $built_wlroots == "$image_wlroots" ]] ||
    fallback "built against wlroots $built_wlroots, image has $image_wlroots"

# upgrade does nothing when Terra's F44 build has caught up or passed it.
dnf5 -y upgrade "$rpm" || fallback "dnf could not install $(basename "$rpm")"

# Startup needs a seat, so only check that the binary loads and parses config.
if ! umbriel config schema >/dev/null; then
    dnf5 -y distro-sync umbriel-nightly
    fallback "rebuilt binary does not run"
fi

echo "umbriel rebuild: installed $(rpm -q umbriel-nightly)"
rm -rf "$dir"
