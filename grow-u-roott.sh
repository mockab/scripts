#!/usr/bin/env bash
set -euo pipefail

#############################################
# 1. Detect root filesystem device
#############################################
echo "=== Detecting root filesystem device ==="

rootdev=$(findmnt -no SOURCE /)

if [[ -z "$rootdev" ]]; then
    echo "ERROR: Unable to detect root filesystem device."
    exit 1
fi

echo "Root LV/device: $rootdev"

#############################################
# 2. Walk device chain to detect LUKS
#############################################
echo "=== Checking for LUKS encryption ==="

get_device_chain() {
    local dev="$1"
    while true; do
        echo "$dev"
        parent=$(lsblk -no PKNAME "$dev" 2>/dev/null || true)
        [[ -z "$parent" ]] && break
        dev="/dev/$parent"
    done
}

device_chain=$(get_device_chain "$rootdev")

echo "Device chain:"
echo "$device_chain" | sed 's/^/  - /'

is_encrypted=false

while read -r dev; do
    type=$(lsblk -no TYPE "$dev" 2>/dev/null || true)
    if [[ "$type" == "crypt" ]]; then
        echo "Found dm-crypt layer at: $dev"
        if cryptsetup isLuks "$dev" >/dev/null 2>&1; then
            echo "Confirmed: $dev is a LUKS container."
            is_encrypted=true
        fi
    fi
done <<< "$device_chain"

if $is_encrypted; then
    echo ""
    echo "ERROR: LUKS encryption detected. This script does NOT expand encrypted devices."
    echo "Use the LUKS+LVM expansion script instead."
    exit 1
fi

echo "No LUKS encryption detected. Continuing..."
echo ""

#############################################
# 3. Detect physical partition under LVM or raw root
#############################################
echo "=== Locating physical partition ==="

phys=$(lsblk -no PKNAME "$rootdev" 2>/dev/null || true)

if [[ -z "$phys" ]]; then
    # Not LVM, rootdev is physical partition itself
    physdev="$rootdev"
else
    physdev="/dev/$phys"
fi

echo "Physical partition: $physdev"

#############################################
# 4. Extract disk and partition number
#############################################
echo "=== Parsing disk and partition number ==="

if [[ "$physdev" =~ ^/dev/nvme[0-9]n[0-9]p[0-9]+$ ]]; then
    disk="${physdev%p*}"
    partnum="${physdev##*p}"
else
    disk="${physdev%%[0-9]*}"
    partnum="${physdev#"$disk"}"
fi

if [[ -z "$partnum" ]]; then
    echo "ERROR: Unable to determine partition number from $physdev"
    exit 1
fi

echo "Disk: $disk"
echo "Partition number: $partnum"
echo ""

#############################################
# 5. Require essential tools
#############################################
need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: Required tool '$1' not installed."
        exit 1
    fi
}

echo "=== Checking required tools ==="
need_tool parted
need_tool lsblk
need_tool blkid
need_tool findmnt

fstype=$(blkid -o value -s TYPE "$rootdev")

case "$fstype" in
    ext4) need_tool resize2fs ;;
    xfs)  need_tool xfs_growfs ;;
    *) echo "ERROR: Unsupported filesystem: $fstype"; exit 1 ;;
esac

echo "Filesystem type: $fstype"
echo ""

#############################################
# 6. Grow partition
#############################################
echo "=== Growing partition using growpart or parted ==="

if command -v growpart >/dev/null 2>&1; then
    echo "Using growpart..."
    sudo growpart "$disk" "$partnum"
else
    echo "growpart not found — using parted fallback."
    end=$(parted -m "$disk" unit MiB print | awk -F: '/^/dev/ {print $2}' | sed 's/MiB//')
    sudo parted "$disk" ---pretend-input-tty <<EOF
unit MiB
resizepart $partnum ${end}
Yes
quit
EOF
fi

echo "Partition expansion complete."
echo ""

#############################################
# 7. Filesystem Resize
#############################################
echo "=== Growing filesystem ==="

case "$fstype" in
    ext4)
        sudo resize2fs "$rootdev"
        ;;
    xfs)
        sudo xfs_growfs /
        ;;
esac

echo ""
echo "=== SUCCESS: Root filesystem expanded ==="
df -h /
