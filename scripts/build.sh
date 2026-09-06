#!/usr/bin/env bash
set -euo pipefail

# (env-overridable)
KERNEL_DEFCONFIG=${KERNEL_DEFCONFIG:-gki_defconfig}
CLANG_VERSION=${CLANG_VERSION:-clang-r596125}
OUT_DIR=${OUT_DIR:-out}
CLANG_DIR=${CLANG_DIR:-\"$HOME/tools/google-clang\"}
CLANG_BINARY=\"$CLANG_DIR/bin/clang\"
START_TIME=$(date +%s)

# --- pretty logs ---
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GREEN}[INFO]${NC} $*"; }
err(){  echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Try to use pre-installed clang (e.g., from CI workflow) first
find_clang() {
    # Check common CI locations FIRST (prioritize LLVM apt-installed clang)
    for dir in /usr/lib/llvm-*/bin /usr/bin; do
        if [ -f "$dir/clang" ] && [ -f "$dir/ld.lld" ]; then
            local clang_path="$dir/clang"
            local clang_ver=$($clang_path --version | head -n1)
            info "Found clang in $dir: $clang_ver"
            export CLANG_BINARY="$clang_path"
            export CLANG_DIR="$(dirname $dir)"
            export LLD_BINARY="$dir/ld.lld"
            export PATH="$dir:$PATH"
            export KBUILD_COMPILER_STRING="$clang_ver"
            return 0
        fi
    done
    # Then check if clang is in PATH (but verify ld.lld exists)
    if command -v clang >/dev/null 2>&1; then
        local clang_path=$(command -v clang)
        local lld_path=$(command -v ld.lld 2>/dev/null || echo "")
        if [ -n "$lld_path" ]; then
            local clang_ver=$($clang_path --version | head -n1)
            info "Using pre-installed clang: $clang_ver"
            export CLANG_BINARY="$clang_path"
            export CLANG_DIR="$(dirname $(dirname $clang_path))"
            export LLD_BINARY="$lld_path"
            export PATH="$CLANG_DIR/bin:$PATH"
            export KBUILD_COMPILER_STRING="$clang_ver"
            return 0
        fi
    fi
    return 1
}

setup_clang() {
    # First try to find pre-installed clang
    if find_clang; then
        info "Using existing clang installation"
        return 0
    fi
    
    info "Fetching clang version $CLANG_VERSION..."
    mkdir -p "$CLANG_DIR"
    TARBALL="$(mktemp)"

    URL_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive"
    CLANG_URL="$URL_BASE/mirror-goog-main-llvm-toolchain-source/${CLANG_VERSION}.tar.gz"

    if command -v wget >/dev/null 2>&1; then
      DOWNLOAD_CLANG=(wget -q --show-progress -O "$TARBALL" "$CLANG_URL")
    elif command -v curl >/dev/null 2>&1; then
      DOWNLOAD_CLANG=(curl -L --fail -o "$TARBALL" "$CLANG_URL")
    else
      err "Need wget or curl to download the toolchain."
    fi
    
    "${DOWNLOAD_CLANG[@]}"  >/dev/null 2>&1 || err "Download failed"

    info "Extracting toolchain..."
    tar -xzf "$TARBALL" -C "$CLANG_DIR" --no-same-owner --no-same-permissions || err "Extract failed"
    rm -f "$TARBALL"

    export PATH="$CLANG_DIR/bin:$PATH"
    ver="$("$CLANG_BINARY" --version | head -n1)"
    ver="$(echo "$ver" | sed -E 's/\(http[^)]*\)//g; s/[[:space:]]+/ /g; s/[[:space:]]+$//')"
    export KBUILD_COMPILER_STRING="$ver"
}

build_kernel() {
  info "Starting kernel build..."
  setup_clang
  mkdir -p "$OUT_DIR"

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       "$KERNEL_DEFCONFIG" || err "Defconfig failed"

  # Keep the performance configuration validated by the CI workflow.
  if grep -q '^CONFIG_DEBUG_KERNEL=y$' "$OUT_DIR/.config"; then
    info "Disabling CONFIG_DEBUG_KERNEL for performance build"
    sed -i 's/^CONFIG_DEBUG_KERNEL=y$/# CONFIG_DEBUG_KERNEL is not set/' \
        "$OUT_DIR/.config"
  fi

  # Sanity check before compilation.
  if grep -q '^CONFIG_DEBUG_KERNEL=y$' "$OUT_DIR/.config"; then
    err "CONFIG_DEBUG_KERNEL is still enabled"
  fi

  # Disable BFQ I/O scheduler for Kyber-only (UFS performance)
  if grep -q '^CONFIG_IOSCHED_BFQ=y$' "$OUT_DIR/.config"; then
    info "Disabling CONFIG_IOSCHED_BFQ for Kyber-only I/O scheduler"
    sed -i 's/^CONFIG_IOSCHED_BFQ=y$/# CONFIG_IOSCHED_BFQ is not set/' \
        "$OUT_DIR/.config"
  fi

  make -j"$(nproc --all)" O="$OUT_DIR" ARCH=arm64 CC=clang LD=ld.lld LLVM=1 LLVM_IAS=1 \
       || err "Build failed"

  total_time=$(($(date +%s) - START_TIME))
  info "Build completed in ${total_time}s"
  info "Kernel Image: $OUT_DIR/arch/arm64/boot/Image.gz"
}

build_kernel