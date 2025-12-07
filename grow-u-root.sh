#!/usr/bin/env bash
set -euo pipefail

echo "=== Detecting root device and backing devices ==="

rootdev=$(findmnt -no SOURCE /)

# function: get full chain of devices leading to physical disk
get_device_chain() {
    local dev="$1"
    while true; do
        echo "$dev"
        # Get parent (PKNAME); empty when at physical device
        parent=$(lsblk -no PKNAME "$dev" 2>/dev/null || true)
        [[ -z "$parent" ]] && break
        dev="/dev/$parent"
    done
}

device_chain=$(get_device_chain "$rootdev")

echo "Device chain:"
echo "$device_chain" | sed 's/^/  - /'

echo "=== Checking for LUKS encryption ==="

is_encrypted=false

while read -r dev; do
    type=$(lsblk -no TYPE "$dev" 2>/dev/null || true)

    if [[ "$type" == "crypt" ]]; then
        echo "Detected device-mapper crypt device: $dev"
        if cryptsetup isLuks "$dev" >/dev/null 2>&1; then
            echo "Confirmed: $dev is a LUKS encrypted container."
            is_encrypted=true
        fi
    fi
done <<< "$device_chain"

if $is_encrypted; then
    echo "ERROR: LUKS encryption detected. This script does NOT resize encrypted volumes."
    echo "       A different (safe) procedure is required for LUKS + LVM."
    exit 1
fi

echo "No LUKS encryption detected. Continuing..."
echo ""

# -------------------------------
# Normal non-LUKS resizing logic
# -------------------------------

# Extract base disk + partition number
if [[ "$rootdev" =~ ^/dev/nvme[0-9]n[0-9]p[0-9]+$ ]]; then
    disk="${rootdev%p*}"
    partnum="${rootdev##*p}"
else
    disk="${rootdev%%[0-9]*}"
    partnum="${rootdev#"$disk"}"
fi

echo "Root filesystem: $rootdev"
echo "Disk: $disk"
echo "Partition number: $partnum"

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required tool '$1' is not installed."
        exit 1
    fi
}

echo "=== Checking required tools ==="
need_tool findmnt
need_tool parted
need_tool blkid

fstype=$(blkid -o value -s TYPE "$rootdev")

case "$fstype" in
    ext4) need_tool resize2fs ;;
    xfs) need_tool xfs_growfs ;;
    *) echo "Unsupported filesystem: $fstype" ; exit 1 ;;
esac

growpart_available=false
if command -v growpart >/dev/null 2>&1; then
    growpart_available=true
fi

echo ""
echo "=== Growing partition ==="

if $growpart_available; then
    sudo growpart "$disk" "$partnum"
else
    echo "growpart not found; using parted fallback"

    end=$(parted -m "$disk" unit MiB print | awk -F: '/^/dev/ {print $2}' | sed 's/MiB//')
    sudo parted "$disk" ---pretend-input-tty <<EOF
unit MiB
resizepart $partnum ${end}
Yes
quit
EOF
fi

echo "=== Resizing filesystem ($fstype) ==="
case "$fstype" in
    ext4) sudo resize2fs "$rootdev" ;;
    xfs)  sudo xfs_growfs / ;;
esac

echo "=== Expansion complete ==="
df -h /
