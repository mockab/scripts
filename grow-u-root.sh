#!/usr/bin/env bash
set -euo pipefail

echo "=== Detecting root device ==="
rootdev=$(findmnt -no SOURCE /)

# Prevent running on LUKS unless requested
if [[ "$rootdev" == /dev/mapper/* ]]; then
    echo "ERROR: Root filesystem is on LUKS/mapper. This script does not modify encrypted setups."
    exit 1
fi

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
echo ""

# --- Check for tools ---
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

# Filesystem tools
fstype=$(blkid -o value -s TYPE "$rootdev")

case "$fstype" in
    ext4) need_tool resize2fs ;;
    xfs) need_tool xfs_growfs ;;
    *)
        echo "ERROR: Unsupported filesystem type: $fstype"
        exit 1
        ;;
esac

# Partition resizers
growpart_available=false
if command -v growpart >/dev/null 2>&1; then
    growpart_available=true
fi

echo "growpart available: $growpart_available"
echo ""

echo "=== Growing partition ==="
if $growpart_available; then
    echo "Using growpart..."
    sudo growpart "$disk" "$partnum"
else
    echo "growpart not found; falling back to parted."

    # Get end of disk (in MiB)
    end=$(parted -m "$disk" unit MiB print | awk -F: '/^/dev//{print $2}' | sed 's/MiB//')

    echo "Resizing partition $partnum on $disk to end=${end}MiB"
    sudo parted "$disk" ---pretend-input-tty <<EOF
unit MiB
resizepart $partnum ${end}
Yes
quit
EOF
fi

echo "=== Resizing filesystem ($fstype) ==="
case "$fstype" in
    ext4)
        sudo resize2fs "$rootdev"
        ;;
    xfs)
        sudo xfs_growfs /
        ;;
esac

echo "=== Done! Root filesystem successfully expanded ==="
df -h /
