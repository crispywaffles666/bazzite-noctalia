#!/usr/bin/bash
# Run from a reviewed checkout before the first signature-enforced bootc switch.
# The optional sysroot is for tests/offline preparation; never changes the host
# when a different root is explicitly selected.
set -euo pipefail
sysroot=${1:-/}
if [[ $sysroot == / && $EUID != 0 ]]; then
    echo 'Run with sudo to install host container trust.' >&2
    exit 1
fi
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
image=ghcr.io/crispywaffles666/bazzite-noctalia
key_path=/etc/pki/containers/ghcr.io-crispywaffles666-bazzite-noctalia.pub
policy="${sysroot%/}/etc/containers/policy.json"
[[ -s $policy ]] || { echo "Missing existing policy: $policy; refusing to invent defaults." >&2; exit 1; }

# Prepare the merge before installing anything. Do not replace the machine's
# default policy or any unrelated transport/repository trust rules.
tmp=$(mktemp "${policy}.XXXXXX")
trap 'rm -f "$tmp"' EXIT
jq -e --arg image "$image" --arg key "$key_path" '
    if type != "object" or (.default | type) != "array" then
        error("expected an existing containers policy object with a default rule")
    else . end |
    .transports.docker[$image] = [{
        type: "sigstoreSigned", keyPath: $key,
        signedIdentity: {type: "matchRepository"}
    }]' "$policy" >"$tmp"
chmod --reference="$policy" "$tmp"
if [[ $EUID == 0 ]]; then chown --reference="$policy" "$tmp"; fi

install -D -m 0644 "$repo_root/cosign.pub" "${sysroot%/}$key_path"
install -D -m 0644 \
    "$repo_root/files/system/etc/containers/registries.d/ghcr.io-crispywaffles666-bazzite-noctalia.yaml" \
    "${sysroot%/}/etc/containers/registries.d/ghcr.io-crispywaffles666-bazzite-noctalia.yaml"
# Preserve the pre-bootstrap policy once, including when the script is rerun.
if [[ ! -e ${policy}.before-bazzite-noctalia ]]; then
    cp -p -- "$policy" "${policy}.before-bazzite-noctalia"
fi
mv -f -- "$tmp" "$policy"
if [[ $sysroot == / ]] && command -v restorecon >/dev/null; then
    restorecon "$policy" "$key_path" /etc/containers/registries.d/ghcr.io-crispywaffles666-bazzite-noctalia.yaml
fi
echo 'Installed bazzite-noctalia trust; unrelated policy entries preserved.'
echo "Original policy backup: ${policy}.before-bazzite-noctalia"
