#!/usr/bin/bash
set -euxo pipefail

systemctl enable greetd.service
systemctl set-default graphical.target

# OSTree does not ship /var. tmpfiles creates greetd and greeter state at boot.
# Fedora's greetd PAM stack already includes system-auth, which invokes
# pam_systemd, and optional pam_gnome_keyring for login keyring unlock.
