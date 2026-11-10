#!/usr/bin/env bash
# Build/package only. Never installs into the host or changes boot settings.
set -Eeuo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
MODE=${1:-build}
if [[ "$MODE" == --help ]]; then
  printf '%s\n' 'Usage: build.sh [configure|build]' \
    'Environment: KERNEL_COMMIT (40 hex), DEFCONFIG, JOBS, WORK_DIR, OUTPUT_DIR' \
    'Default: pinned Raspberry Pi 6.12 source; experimental, not approved for deployment.'
  exit 0
fi
COMMIT=${KERNEL_COMMIT:-$(<"$HERE/../kernel.commit")}
DEFCONFIG=${DEFCONFIG:-bcm2711_defconfig}
JOBS=${JOBS:-2}
WORK_DIR=${WORK_DIR:-/work}
OUTPUT_DIR=${OUTPUT_DIR:-/out}
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
[[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail 'KERNEL_COMMIT must be a lowercase 40-character hexadecimal commit, not a branch.'
[[ "$MODE" == configure || "$MODE" == build ]] || fail 'Mode must be configure or build.'
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || fail 'JOBS must be a positive integer.'
case "$DEFCONFIG" in
  bcm2711_defconfig) SUFFIX='-v8' ;;
  bcm2712_defconfig) SUFFIX='-v8-16k' ;;
  *) fail 'DEFCONFIG must be bcm2711_defconfig or bcm2712_defconfig.' ;;
esac
for tool in git make aarch64-linux-gnu-gcc aarch64-linux-gnu-readelf pahole python3 flex bison; do
  command -v "$tool" >/dev/null || fail "Missing $tool; run inside the builder image."
done

mkdir -p "$WORK_DIR" "$OUTPUT_DIR"
WORK_DIR=$(cd "$WORK_DIR" && pwd)
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)
SRC="$WORK_DIR/source/$COMMIT"
OBJ="$WORK_DIR/build/$COMMIT/$DEFCONFIG"
mkdir -p "$SRC" "$OBJ"
if [[ ! -d "$SRC/.git" ]]; then
  git init -q "$SRC"
fi
if ! git -C "$SRC" cat-file -e "$COMMIT^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch --depth=1 https://github.com/raspberrypi/linux.git "$COMMIT"
fi
# Refuse to destroy edits in an existing work volume.
[[ -z $(git -C "$SRC" status --porcelain) ]] || fail "Source has local changes: $SRC"
git -C "$SRC" checkout --detach "$COMMIT"
[[ $(git -C "$SRC" rev-parse HEAD) == "$COMMIT" ]] || fail 'Source commit mismatch.'

export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=docker
export KBUILD_BUILD_VERSION=1
export KBUILD_BUILD_TIMESTAMP
KBUILD_BUILD_TIMESTAMP=$(git -C "$SRC" show -s --format=%cD HEAD)
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git -C "$SRC" show -s --format=%ct HEAD)
LOCALVERSION="${SUFFIX}-btf48-${COMMIT:0:12}"
km() { make -C "$SRC" O="$OBJ" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- "$@"; }
km "$DEFCONFIG"
"$SRC/scripts/config" --file "$OBJ/.config" \
  --disable DEBUG_INFO_NONE \
  --disable DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
  --disable DEBUG_INFO_DWARF5 --enable DEBUG_INFO_DWARF4 \
  --disable DEBUG_INFO_REDUCED --disable DEBUG_INFO_SPLIT \
  --enable BPF_SYSCALL --enable DEBUG_INFO_BTF \
  --disable ARM64_VA_BITS_36 --disable ARM64_VA_BITS_39 \
  --disable ARM64_VA_BITS_42 --disable ARM64_VA_BITS_47 \
  --disable ARM64_VA_BITS_52 --enable ARM64_VA_BITS_48 \
  --disable LOCALVERSION_AUTO --set-str LOCALVERSION "$LOCALVERSION"
km olddefconfig
python3 "$HERE/verify-config.py" "$OBJ/.config"
RELEASE=$(make -s --no-print-directory -C "$SRC" O="$OBJ" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease)
[[ "$RELEASE" =~ ^[A-Za-z0-9._+-]+$ ]] || fail 'Unexpected kernel release string.'
DEST="$OUTPUT_DIR/$RELEASE-$DEFCONFIG"
mkdir -p "$DEST"
cp "$OBJ/.config" "$DEST/kernel.config"
{
  printf 'source_url=https://github.com/raspberrypi/linux.git\nsource_commit=%s\ndefconfig=%s\nkernelrelease=%s\n' "$COMMIT" "$DEFCONFIG" "$RELEASE"
  printf 'build_mode=%s\n' "$MODE"
  aarch64-linux-gnu-gcc --version
  pahole --version
  make --version
} > "$DEST/build-info.txt"
if [[ "$MODE" == configure ]]; then
  printf 'Configuration verified. No kernel compiled. Output: %s\n' "$DEST"
  exit 0
fi

km -j"$JOBS" Image.gz modules dtbs
# pipefail catches a failed readelf as well as a missing BTF section.
aarch64-linux-gnu-readelf -SW "$OBJ/vmlinux" | grep -F ' .BTF ' > "$DEST/btf-section.txt"
STAGE=$(mktemp -d "$WORK_DIR/package.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
km INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1 modules_install
# Do not distribute build-machine-only links.
rm -f -- "$STAGE/lib/modules/$RELEASE/build" "$STAGE/lib/modules/$RELEASE/source"
mkdir -p "$STAGE/boot/overlays" "$STAGE/build-metadata"
cp "$OBJ/arch/arm64/boot/Image.gz" "$STAGE/boot/kernel-btf48.img"
cp "$OBJ/arch/arm64/boot/dts/broadcom/"*.dtb "$STAGE/boot/"
cp "$OBJ/arch/arm64/boot/dts/overlays/"*.dtbo "$STAGE/boot/overlays/"
cp "$SRC/arch/arm64/boot/dts/overlays/README" "$STAGE/boot/overlays/"
cp "$DEST/kernel.config" "$DEST/build-info.txt" "$DEST/btf-section.txt" "$STAGE/build-metadata/"
printf '%s\n' \
  'Experimental kernel. No boot or runtime tests have been performed.' \
  'Do not extract directly over a live root filesystem.' \
  'kernel-btf48.img is an alternate boot filename; installation/recovery instructions are separate.' \
  > "$STAGE/README-NOT-INSTALLED.txt"
ARCHIVE="raspi-$RELEASE-$DEFCONFIG.tar.xz"
tar --sort=name --mtime="@$SOURCE_DATE_EPOCH" --owner=0 --group=0 --numeric-owner \
  -C "$STAGE" -cJf "$DEST/$ARCHIVE.partial" .
mv "$DEST/$ARCHIVE.partial" "$DEST/$ARCHIVE"
(cd "$DEST" && sha256sum "$ARCHIVE" > "$ARCHIVE.sha256")
printf 'Build/package complete: %s/%s\nNo host installation or reboot was performed.\n' "$DEST" "$ARCHIVE"
