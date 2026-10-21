#!/usr/bin/bash
# Rebuild Terra's rawhide umbriel-nightly SRPM against Fedora 44. Terra's
# nightly bot bumps only rawhide, so its F44 build can lag upstream by weeks,
# and the rawhide binary needs a newer glibc than F44 ships.
#
# Never fails the image build. On any error the output directory stays empty
# and the main image keeps Terra's F44 umbriel-nightly.
set -uo pipefail

out=${1:?usage: rebuild-umbriel-nightly.sh OUTPUT_DIR}
mkdir -p "$out"

source_repo=https://repos.fyralabs.com/terrarawhide-source
# Signing key of terrarawhide-source. A rotated key fails verification and
# falls back instead of trusting whatever key the server now serves.
source_key_fpr=C51528598B2692F7752981F30A0129D5EA2224DF

rebuild() {
    set -euxo pipefail
    local work srpm rpm
    work=$(mktemp -d)

    dnf5 -y upgrade --refresh
    dnf5 -y install --setopt=install_weak_deps=False dnf5-plugins rpm-build gnupg2

    curl -fsSL "$source_repo/key.asc" -o "$work/key.asc"
    gpg --show-keys --with-colons "$work/key.asc" | grep -Fxq "fpr:::::::::$source_key_fpr:"
    rpm --import "$work/key.asc"

    dnf5 -y download --source --destdir "$work" \
        --repofrompath="terrarawhide-source,$source_repo" \
        --repo=terrarawhide-source umbriel-nightly
    srpm=$(find "$work" -maxdepth 1 -name 'umbriel-nightly-*.src.rpm' -print -quit)
    [[ -n $srpm ]]
    # rpm -K reports a missing key as success unless signatures are required.
    rpmkeys --checksig --define '_pkgverify_level all' "$srpm"

    dnf5 -y builddep "$srpm"
    rpmbuild --rebuild --define "_topdir $work/rpmbuild" "$srpm"

    rpm=$(find "$work/rpmbuild/RPMS" -name 'umbriel-nightly-*.x86_64.rpm' -print -quit)
    [[ -n $rpm ]]
    cp "$rpm" "$out/"
    # The compositor compiles against wlroots' private struct layouts, so the
    # image must run the exact wlroots build this binary saw.
    rpm -q --qf '%{EVR}\n' wlroots > "$out/wlroots-evr"
    rpm -qp --qf '%{NEVRA}\n' "$rpm" > "$out/built-nevra"
}

# A condition context (if, ||) would disable set -e inside the subshell.
(rebuild)
status=$?
if [[ $status -eq 0 ]]; then
    echo "umbriel rebuild: built $(cat "$out/built-nevra") against wlroots $(cat "$out/wlroots-evr")"
else
    echo "umbriel rebuild: FAILED, the image will use Terra's F44 umbriel-nightly" >&2
    find "$out" -mindepth 1 -delete
fi
dnf5 clean all
exit 0
