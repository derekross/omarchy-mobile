#!/bin/bash
# SPDX-License-Identifier: MIT
set -euo pipefail

[[ $# == 3 ]] || {
    printf '%s\n' 'usage: stream-systemd-ram-root.sh USB_INTERFACE ROOT.img.zst PRIVATE_SSH_DIR' >&2
    exit 2
}
interface=$1
image=$2
private=$3
[[ $interface =~ ^[a-zA-Z0-9._-]+$ ]]
expected=382587d6e073c55e738a98a2741f1a893c598d45f9e93e67c64c1055ee6594b8
printf '%s  %s\n' "$expected" "$image" | shasum -a 256 -c
ssh_cmd=(ssh -F /dev/null -T -a -x -p 2222
    -o BatchMode=yes -o ConnectTimeout=4 -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=yes -o HostKeyAlias=grizzly-systemd-root
    -o GlobalKnownHostsFile=/dev/null -o "UserKnownHostsFile=$private/known_hosts"
    -i "$private/client" "root@fe80::b8e7%$interface")

for (( attempt = 0; attempt < 30; attempt++ )); do
    if [[ "$("${ssh_cmd[@]}" status 2>/dev/null)" == GRIZZLY_ROOT_READY ]]; then
        [[ "$("${ssh_cmd[@]}" receive < "$image")" == GRIZZLY_ROOT_VERIFIED ]]
        [[ "$("${ssh_cmd[@]}" handoff)" == GRIZZLY_ROOT_HANDOFF_REQUESTED ]]
        printf '%s\n' 'Omarchy RAM image verified on the phone and systemd handoff requested.'
        exit 0
    fi
    sleep 2
done
printf '%s\n' 'Grizzly RAM root receiver did not become ready on the selected USB interface.' >&2
exit 1
