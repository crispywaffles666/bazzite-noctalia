#!/usr/bin/bash
set -euxo pipefail

systemctl enable greetd.service
systemctl set-default graphical.target

# OSTree does not ship /var. tmpfiles creates greetd and greeter state at boot.
# Fedora's greetd PAM stack already includes system-auth, which invokes
# pam_systemd, and optional pam_gnome_keyring for login keyring unlock.

# Fedora's policy labels /var/lib/greetd for the greeter but not Noctalia
# Greeter's state directory, so SELinux blocked saving the picked scheme and
# last session to sync.toml. Use the label greetd's own directory has.
semanage fcontext -a -t xdm_var_lib_t '/var/lib/noctalia-greeter(/.*)?'
