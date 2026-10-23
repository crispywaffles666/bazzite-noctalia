# bazzite-noctalia

Bazzite's gaming foundation with the GNOME desktop stack replaced by the Noctalia ecosystem: **Umbriel** compositor, **Noctalia Shell**, and **Noctalia Greeter** through greetd. This image was derived from my [bazzite-niri](https://github.com/crispywaffles666/bazzite-niri) image

- Base: `ghcr.io/ublue-os/bazzite-gnome:stable` (Fedora 44)
- Image: `ghcr.io/crispywaffles666/bazzite-noctalia:latest`
- Build: BlueBuild + bootc; daily GitHub Actions builds, cosign signing, verified base digest
- Package sources: Fedora, Terra (enabled only during build), Brave's official RPM repository; no added COPR
- Retained: Bazzite kernel, drivers, codecs, gaming stack, GNOME Keyring/PAM, Nautilus, Graphite GTK theme, Dracula icons, Overpass Nerd Font, and the existing desktop utilities
- Removed: GNOME Shell/session, GDM, GNOME portal, Niri, and tuigreet

## Desktop and session

The Terra RPM supplies `/usr/share/wayland-sessions/umbriel.desktop` with `Exec=start-umbriel`. Noctalia Greeter selects **Umbriel** by default. The starter [Umbriel config](files/system/etc/skel/.config/umbriel/config.toml) autostarts Noctalia, a helper that closes the overview when a window opens, and a helper that makes the largest landscape monitor primary in Xwayland so X11 and Proton games pick its resolutions instead of a rotated monitor's, and preserves the original image's Dracula colors, scrolling layout, common keybinds, and Screenshot notifier. Umbriel supplies Xwayland internally; Bazzite's existing Terra Xwayland package provides its server binary.

Noctalia's [starter config](files/system/etc/skel/.config/noctalia/config.toml) keeps the source image's shell look and functionality. Noctalia handles screenshots and saves them to `~/Pictures/Screenshots`. The included app configs and helper scripts are otherwise inherited from `bazzite-niri`.

Window moves use a spring curve, and Umbriel's drag physics adds motion and settling when a window is dragged into place.

`Mod+Space` opens Umbriel's overview. `Alt+Space` and `Mod+S` open Noctalia's launcher directly. Typing in Umbriel's overview opens the launcher, which needs Noctalia 5.2.0 or newer. The image installs Noctalia from Fedora before Terra is enabled: Terra dropped its package once Fedora took it over, and Bazzite's Terra priority would otherwise select Terra's leftover 5.0.0-beta.9 RPM.

VRR and HDR require supported hardware and are opt-in per output in the Umbriel config. See the commented `[output.DP-1]` example and [Umbriel's output documentation](https://docs.noctalia.dev/umbriel/outputs/). Fullscreen, direct scanout, multi-monitor placement, and native Xwayland use Umbriel's own implementation. Screen sharing uses the Umbriel portal.

The image uses two main portal backends: `xdg-desktop-portal-gtk` for general interfaces, and `xdg-desktop-portal-umbriel-nightly` for ScreenCast and Screenshot. The [portal preference](files/system/etc/xdg-desktop-portal/umbriel-portals.conf) is named for the `Umbriel` desktop session. GNOME Keyring remains for Secret Service and greetd PAM login-keyring unlock; it is not the GNOME screen-capture backend.

**Current Terra RPM caveat:** `umbriel-nightly` still declares `xwayland-satellite` as a hard dependency, although the installed binary uses wlroots native Xwayland. Satellite is installed transitively but is never started by the Umbriel config. The image removes it automatically once Terra drops that obsolete RPM requirement, avoiding a broken dependency graph in the meantime.

Fedora's greetd RPM creates the **`greetd`** account. The greeter runs as that account; tmpfiles and a service prestart create `/var/lib/noctalia-greeter` and its initial settings on each boot, because bootc does not ship `/var`. The image labels that directory `xdm_var_lib_t`, like `/var/lib/greetd`, so SELinux lets the greeter remember the scheme and session picked there. A second prestart copies the [greeter display and clock settings](files/system/etc/noctalia-greeter/greeter.toml) into its state directory. The greeter uses Breezy's portrait rotation and placement, scale 1, and a 12-hour clock. The existing Fedora greetd PAM stack includes `system-auth` and `pam_gnome_keyring.so`.

## First switch and signatures

The new repository must have an Actions secret named `SIGNING_SECRET` containing the private cosign key matching the committed `cosign.pub`. The public key is copied from the source image; you may reuse its private key in this separate repository or generate a new pair and update `cosign.pub` plus `files/system/etc/pki/containers/ghcr.io-crispywaffles666-bazzite-noctalia.pub` together. The workflow publishes signed images only from `main`.

Bootstrap the destination image's container signature policy from a reviewed checkout before the first switch:

```bash
git clone https://github.com/crispywaffles666/bazzite-noctalia.git
cd bazzite-noctalia
sudo bash scripts/install-image-trust.sh
sudo bootc switch --enforce-container-sigpolicy ghcr.io/crispywaffles666/bazzite-noctalia:latest
sudo systemctl reboot
```

The trust script merges only this image's rule into the host policy, installs the public key and sigstore lookup file, and saves the previous policy as `policy.json.before-bazzite-noctalia`. Review `cosign.pub` through a trusted channel before running it. Future pulls use the image's own policy and key. `sudo bootc rollback` returns to the previous deployment.

Existing users do not receive `/etc/skel` updates automatically. After switching, copy the starter configs if desired:

```bash
cp -r /etc/skel/.config/umbriel ~/.config/
cp -r /etc/skel/.config/noctalia ~/.config/
cp -r /etc/skel/.local/bin ~/.local/
```

If the graphical session fails, switch to a TTY with `Ctrl+Alt+F3`, sign in, and copy or repair those configs. The greeter uses VT2.

## Build and validation

```bash
python3 -m unittest discover -s tests -v
bluebuild build recipes/recipe.yml
```

CI verifies the Bazzite base with the vendored Universal Blue key, pins its digest for the build, and signs the published image. The build validates package presence and absence, portal routing, greetd/PAM integration, the Umbriel session, both starter configs with their installed binaries, themes, and signature policy. Terra and Brave are disabled in the shipped image. Build-time theme tools remain in a disposable stage.

`umbriel-nightly` and its portal are moving targets. Each built image is an immutable bootc deployment; keep a known good deployment available for rollback. The build records the installed RPM versions in its package database, while CI's scheduled builds take current Terra RPMs.

Terra's nightly bot bumps only its rawhide branch, so its F44 `umbriel-nightly` can lag upstream by weeks, and the rawhide binary needs a newer glibc than F44 ships. A disposable `umbriel-builder` stage therefore rebuilds Terra's signed rawhide SRPM against Fedora 44. The image installs that rebuild only when it is newer than Terra's F44 build, was compiled against the image's exact wlroots build, and runs. Otherwise it keeps Terra's F44 RPM. The build log states which one shipped.
