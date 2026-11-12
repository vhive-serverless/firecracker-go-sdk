#!/usr/bin/env bash
# Fixed upstream artifacts; downloads are accepted only after SHA-256 validation.
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -m)" = x86_64 || { echo 'Pinned test fixtures currently cover x86_64 only.' >&2; exit 1; }
dest=${FC_TEST_DATA_PATH:-testdata}
mkdir -p "$dest"
dest=$(cd "$dest" && pwd)
artifact_base=https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/20261105-6ea6634994fa-0/x86_64

# External fixture directories also need the small inputs checked into this
# revision. Go tests resolve all fixtures through FC_TEST_DATA_PATH.
if [ "$dest" != "$PWD/testdata" ]; then
    install -m 644 testdata/drive-2.img testdata/drive-3.img "$dest/"
    install -m 755 testdata/sigprint.sh "$dest/sigprint.sh"
fi

fetch() {
    local url=$1 output=$2 checksum=$3
    if ! echo "$checksum  $output" | sha256sum --check --status; then
        curl --fail --location --retry 3 --output "$output.partial" "$url"
        echo "$checksum  $output.partial" | sha256sum --check -
        mv "$output.partial" "$output"
    fi
}

fetch "$artifact_base/vmlinux-6.18.56" "$dest/vmlinux" \
    af348226aa2a25b846156150d5cdb5dae3bf2a022f1db176e3a2b9a3249817bf
fetch https://s3.amazonaws.com/spec.ccfc.min/img/hello/fsfiles/hello-rootfs.ext4 \
    "$dest/root-drive.img" 786f0612582cadcee4c8ad46e30e4cc93dff9a3c0b4ede3f3c597b4c241dd547
fetch https://github.com/firecracker-microvm/firecracker/releases/download/v1.18.0/firecracker-v1.18.0-x86_64.tgz \
    "$dest/firecracker.tgz" 1ac8eec866dd5eea14efecf6323e22b23eea24054545338a5b34bc5bca6623cd
tar -xzf "$dest/firecracker.tgz" -C "$dest"
install -m 755 "$dest/release-v1.18.0-x86_64/firecracker-v1.18.0-x86_64" "$dest/firecracker"
install -m 755 "$dest/release-v1.18.0-x86_64/jailer-v1.18.0-x86_64" "$dest/jailer"
touch "$dest/fc.stamp"

if [ "${1:-}" = --ssh ]; then
    fetch "$artifact_base/ubuntu-24.04.squashfs" "$dest/ubuntu-24.04.squashfs" \
        91da33c2013bd1b018f2c1e6b3d37a3316e0ff8c19a71de640d7a4c3ca31b92b
    staging=$(mktemp -d "$dest/.ssh-rootfs.XXXXXXXX")
    trap 'sudo -n rm -rf "$staging"' EXIT
    sudo -n unsquashfs -d "$staging/rootfs" "$dest/ubuntu-24.04.squashfs"
    # Test-only credentials are generated locally and never committed.
    ssh-keygen -q -t ed25519 -N '' -f "$staging/id_ed25519"
    sudo -n install -D -m 600 "$staging/id_ed25519.pub" "$staging/rootfs/root/.ssh/authorized_keys"
    truncate -s 2G "$staging/rootfs.ext4"
    sudo -n mkfs.ext4 -q -F -d "$staging/rootfs" "$staging/rootfs.ext4"
    sudo -n chown "$(id -u):$(id -g)" "$staging/rootfs.ext4"
    mv "$staging/rootfs.ext4" "$dest/root-drive-with-ssh.img"
    mv "$staging/id_ed25519" "$dest/root-drive-ssh-key"
fi
