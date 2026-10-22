#!/usr/bin/bash
# Catch Fedora, Terra, or Bazzite changes that would break this desktop.
set -euxo pipefail

required=(
    umbriel-nightly
    noctalia
    noctalia-greeter
    greetd
    gnome-keyring
    # The PAM module that unlocks the login keyring via greetd. GDM depends
    # on it, so the GNOME removal path must not let autoremove take it.
    gnome-keyring-pam
    xdg-desktop-portal-umbriel-nightly
    xdg-desktop-portal-gtk
    nautilus
)

banned=(
    gnome-shell
    mutter
    gdm
    gnome-session
    xdg-desktop-portal-gnome
    niri
    tuigreet
)

for pkg in "${required[@]}"; do
    if ! rpm -q --quiet "$pkg"; then
        echo "ERROR: required package is not installed: $pkg" >&2
        exit 1
    fi
done

# Terra's abandoned noctalia RPM outranks Fedora's under Bazzite's Terra
# priority. Typing in the overview to open the launcher needs 5.2.0 or newer.
noctalia_version=$(rpm -q --qf '%{VERSION}' noctalia)
if [[ $(rpm --eval "%{lua: print(rpm.vercmp('$noctalia_version', '5.2.0'))}") -lt 0 ]]; then
    echo "ERROR: noctalia $noctalia_version is older than Fedora's; Terra's stale RPM won" >&2
    exit 1
fi

# Record which Umbriel snapshot this image ships; install-rebuilt-umbriel.sh
# logs whether it is the F44 rebuild or Terra's F44 fallback.
echo "Shipping $(rpm -q umbriel-nightly)"

for pkg in "${banned[@]}"; do
    if rpm -q --quiet "$pkg"; then
        echo "ERROR: forbidden desktop package is installed: $pkg" >&2
        exit 1
    fi
done

# Terra's current Umbriel RPM has a stale hard dependency on Satellite despite
# using wlroots native Xwayland. Keep RPM dependencies consistent until Terra
# removes it; fail if Satellite becomes an unneeded leftover.
if rpm -q --quiet xwayland-satellite; then
    if ! rpm -q --requires umbriel-nightly | grep -Fxq xwayland-satellite; then
        echo "ERROR: xwayland-satellite is installed without an Umbriel RPM requirement" >&2
        exit 1
    fi
    echo "WARNING: Terra umbriel-nightly still requires unused xwayland-satellite" >&2
fi

if rpm -q --quiet sassc; then
    echo "ERROR: theme build-only package leaked into the final image: sassc" >&2
    exit 1
fi

graphite_theme=/usr/share/themes/Graphite-purple-Dark-dracula
graphite_files=(
    "$graphite_theme/index.theme"
    "$graphite_theme/gtk-3.0/gtk.css"
    "$graphite_theme/gtk-3.0/gtk-dark.css"
    "$graphite_theme/gtk-4.0/gtk.css"
    "$graphite_theme/gtk-4.0/gtk-dark.css"
)
for theme_file in "${graphite_files[@]}"; do
    if [[ ! -s "$theme_file" ]]; then
        echo "ERROR: generated Graphite theme file is missing: $theme_file" >&2
        exit 1
    fi
done
for asset_dir in "$graphite_theme/gtk-3.0/assets" "$graphite_theme/gtk-4.0/assets"; do
    if [[ ! -d "$asset_dir" || -z "$(find "$asset_dir" -type f -print -quit)" ]]; then
        echo "ERROR: generated Graphite assets are missing: $asset_dir" >&2
        exit 1
    fi
done

dracula_icons=/usr/share/icons/dracula-icons-main
for icon_file in "$dracula_icons/index.theme" "$dracula_icons/icon-theme.cache"; do
    if [[ ! -s "$icon_file" ]]; then
        echo "ERROR: Dracula icon theme file is missing: $icon_file" >&2
        exit 1
    fi
done
if [[ ! -s /usr/share/licenses/Graphite-gtk-theme/LICENSE ]]; then
    echo "ERROR: Graphite upstream license is missing" >&2
    exit 1
fi
if [[ ! -s /usr/share/licenses/dracula-icons/README.md ]]; then
    echo "ERROR: Dracula Icons upstream licensing notice is missing" >&2
    exit 1
fi

for gtk_settings in /etc/skel/.config/gtk-{3,4}.0/settings.ini; do
    if ! grep -Fxq 'gtk-theme-name=Graphite-purple-Dark-dracula' "$gtk_settings"; then
        echo "ERROR: configured GTK theme name is incorrect: $gtk_settings" >&2
        exit 1
    fi
    if ! grep -Fxq 'gtk-icon-theme-name=dracula-icons-main' "$gtk_settings"; then
        echo "ERROR: configured icon theme name is incorrect: $gtk_settings" >&2
        exit 1
    fi
done
theme_schema=/usr/share/glib-2.0/schemas/zz_bazzite-noctalia.gschema.override
if ! grep -Fxq "gtk-theme='Graphite-purple-Dark-dracula'" "$theme_schema"; then
    echo "ERROR: GNOME schema override has the wrong GTK theme name" >&2
    exit 1
fi
if ! grep -Fxq "icon-theme='dracula-icons-main'" "$theme_schema"; then
    echo "ERROR: GNOME schema override has the wrong icon theme name" >&2
    exit 1
fi

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# Parse the starter config with the installed Umbriel binary. This needs no
# graphical session and rejects renamed actions and unsupported options.
umbriel_skel=/etc/skel/.config/umbriel
if [[ ! -f "$umbriel_skel/config.toml" ]]; then
    fail "skel Umbriel config.toml missing: $umbriel_skel/config.toml"
fi
test_home="$(mktemp -d)"
mkdir -p "$test_home/.config"
cp -r "$umbriel_skel" "$test_home/.config/umbriel"
if ! HOME="$test_home" XDG_CONFIG_HOME="$test_home/.config" umbriel config validate; then
    fail "skel Umbriel config failed umbriel config validate"
fi
rm -rf "$test_home"
[[ -x /etc/skel/.local/bin/umbriel-auto-fullwidth.py ]] || fail "Umbriel column-width helper missing"
python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("/etc/skel/.local/bin/umbriel-auto-fullwidth.py").read_text())' || fail "Umbriel column-width helper has invalid Python syntax"
python3 -c 'import json, pathlib; json.loads(pathlib.Path("/etc/skel/.config/umbriel/output-widths.json").read_text())' || fail "Umbriel output widths are invalid JSON"

# Check the exact greeter executable, account, state path, and PAM/keyring
# setup provided by the Fedora greetd and Terra greeter RPMs.
[[ -x /usr/bin/noctalia-greeter-session ]] || fail "Noctalia greeter session wrapper missing"
[[ -x /usr/bin/noctalia-greeter-apply-appearance ]] || fail "Noctalia greeter state helper missing"
[[ -x /usr/bin/start-umbriel ]] || fail "Umbriel native launcher missing"
[[ -x /usr/bin/Xwayland ]] || fail "Umbriel native Xwayland server missing"
grep -Eq '^Exec=(/usr/bin/)?start-umbriel$' /usr/share/wayland-sessions/umbriel.desktop || fail "Umbriel session does not use start-umbriel"
grep -Fxq 'DesktopNames=Umbriel' /usr/share/wayland-sessions/umbriel.desktop || fail "Umbriel session desktop name changed"
grep -Fxq 'command = "/usr/bin/noctalia-greeter-session -- --session Umbriel"' /etc/greetd/config.toml || fail "greetd does not select Umbriel via Noctalia Greeter"
grep -Fxq 'user = "greetd"' /etc/greetd/config.toml || fail "greetd greeter user changed"
getent passwd greetd >/dev/null || fail "Fedora greetd account missing"
grep -Eq '^d /var/lib/noctalia-greeter 0750 greetd greetd ' /usr/lib/tmpfiles.d/noctalia-greeter.conf || fail "greeter state tmpfiles rule missing"
grep -Eq '^auth[[:space:]]+substack[[:space:]]+system-auth' /etc/pam.d/greetd || fail "greetd PAM system-auth missing"
grep -Eq '^session[[:space:]]+include[[:space:]]+system-auth' /etc/pam.d/greetd || fail "greetd PAM systemd session path missing"
grep -Eq '^[-]?auth[[:space:]]+optional[[:space:]]+pam_gnome_keyring.so' /etc/pam.d/greetd || fail "greetd PAM keyring unlock missing"
grep -Eq '^[-]?session[[:space:]]+optional[[:space:]]+pam_gnome_keyring.so auto_start' /etc/pam.d/greetd || fail "greetd PAM keyring startup missing"
greeter_admin=/etc/noctalia-greeter/greeter.toml
[[ -r "$greeter_admin" ]] || fail "Noctalia Greeter administrator config missing"
python3 -c 'import tomllib,sys; c=tomllib.load(open(sys.argv[1],"rb")); assert c["clock"]["time_format"] == "%I:%M %p"; assert c["output"]["layout"] == "DP-4:0,184; DP-3:2560,0"; assert c["output"]["transforms"] == "DP-4:normal; DP-3:270"; assert c["output"]["scales"] == "DP-4:1; DP-3:1"' "$greeter_admin" || fail "Noctalia Greeter display or 12-hour clock settings invalid"
grep -Fq 'ExecStartPre=/usr/bin/install -m 0640 -o greetd -g greetd /etc/noctalia-greeter/greeter.toml /var/lib/noctalia-greeter/greeter.toml' /etc/systemd/system/greetd.service.d/10-noctalia-greeter.conf || fail "Noctalia Greeter administrator config is not installed at startup"

# The RPM provides the backend ID and the desktop-specific filename. The
# /etc preference chooses GTK generally and Umbriel for screen capture.
portal_impl=/usr/share/xdg-desktop-portal/portals/umbriel.portal
portal_pref=/etc/xdg-desktop-portal/umbriel-portals.conf
[[ -r "$portal_impl" && -r "$portal_pref" ]] || fail "Umbriel portal implementation or preference missing"
grep -Fq 'org.freedesktop.impl.portal.ScreenCast' "$portal_impl" || fail "Umbriel portal has no ScreenCast interface"
grep -Fq 'org.freedesktop.impl.portal.Screenshot' "$portal_impl" || fail "Umbriel portal has no Screenshot interface"
grep -Fxq 'default=gtk' "$portal_pref" || fail "GTK portal is not default"
grep -Fxq 'org.freedesktop.impl.portal.ScreenCast=umbriel' "$portal_pref" || fail "ScreenCast does not use Umbriel"
grep -Fxq 'org.freedesktop.impl.portal.Screenshot=umbriel' "$portal_pref" || fail "Screenshot does not use Umbriel"

# Parse the shipped Noctalia shell config with the exact noctalia build in
# this image. Validating by directory path keeps the check offline: no
# running shell, graphical session, or user DBus is required.
noctalia_skel=/etc/skel/.config/noctalia
if [[ ! -f "$noctalia_skel/config.toml" ]]; then
    fail "skel noctalia config.toml missing: $noctalia_skel/config.toml"
fi
noctalia_home="$(mktemp -d)"
mkdir -p "$noctalia_home/.config"
cp -r "$noctalia_skel" "$noctalia_home/.config/noctalia"
noctalia_log="$noctalia_home/validate.log"
noctalia_status=0
HOME="$noctalia_home" XDG_CONFIG_HOME="$noctalia_home/.config" \
    XDG_STATE_HOME="$noctalia_home/.local/state" \
    noctalia config validate "$noctalia_home/.config/noctalia" \
    >"$noctalia_log" 2>&1 || noctalia_status=$?
# Keep the validator's own output in the build log either way.
cat "$noctalia_log"
if [[ "$noctalia_status" -ne 0 ]]; then
    fail "skel noctalia config failed noctalia config validate (exit $noctalia_status)"
fi
# Unknown/removed settings, bad enum values, and migration-needed keys are
# reported as WARN diagnostics with exit status 0, so exit code alone cannot
# catch a stale shipped config. Those diagnostics always start with "WARN ";
# timestamped log lines (e.g. container-environment noise) never do.
if grep -E '^WARN[[:space:]]' "$noctalia_log"; then
    fail "skel noctalia config is stale for the installed noctalia (validator warnings above)"
fi
rm -rf "$noctalia_home"

# The update verification chain must stay internally consistent: policy.json,
# the registries.d sigstore config, and the public key all name the same GHCR
# namespace and key path. The README tells forks to change the namespace and
# key together; a forgotten half-edit must fail the build here.
sig_key=/etc/pki/containers/ghcr.io-crispywaffles666-bazzite-noctalia.pub
if [[ ! -s "$sig_key" ]]; then
    fail "container signature public key missing: $sig_key"
fi

sigstore_config=/etc/containers/registries.d/ghcr.io-crispywaffles666-bazzite-noctalia.yaml
if [[ ! -r "$sigstore_config" ]]; then
    fail "registries sigstore config missing: $sigstore_config"
fi
if ! grep -q 'use-sigstore-attachments: true' "$sigstore_config"; then
    fail "registries config missing use-sigstore-attachments"
fi
if ! grep -q 'ghcr.io/crispywaffles666/bazzite-noctalia' "$sigstore_config"; then
    fail "registries config missing GHCR namespace"
fi

policy_file=/etc/containers/policy.json
if [[ ! -r "$policy_file" ]]; then
    fail "container policy missing: $policy_file"
fi
if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$policy_file" 2>/dev/null; then
        fail "container policy is not valid JSON: $policy_file"
    fi
fi
if ! grep -q '"ghcr.io/crispywaffles666/bazzite-noctalia"' "$policy_file"; then
    fail "container policy missing GHCR namespace"
fi
if ! grep -q '"type": "sigstoreSigned"' "$policy_file"; then
    fail "container policy missing sigstoreSigned rule"
fi
if ! grep -q "$sig_key" "$policy_file"; then
    fail "container policy does not reference the signature public key path: $sig_key"
fi

echo "Package-set and skel config validation passed."
