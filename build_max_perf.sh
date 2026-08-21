#!/bin/bash
# SM8550 Ultra-Performance Build Script
# Maximum performance compilation flags for Linux 5.15 GKI
# Requires: clang 17+, binutils 2.40+, LLD 17+, bolt, llvm-profdata

set -euo pipefail

# =========================================================================
# TOOLCHAIN CONFIGURATION
# =========================================================================
export CLANG_VERSION="${CLANG_VERSION:-clang-r584948b}"  # or use local clang-17+
export CLANG_DIR="${CLANG_DIR:-$HOME/tools/google-clang}"
export CLANG_BINARY="$CLANG_DIR/bin/clang"
export LLD_BINARY="$CLANG_DIR/bin/ld.lld"
export OBJCOPY_BINARY="$CLANG_DIR/bin/llvm-objcopy"
export OBJDUMP_BINARY="$CLANG_DIR/bin/llvm-objdump"
export NM_BINARY="$CLANG_DIR/bin/llvm-nm"
export STRIP_BINARY="$CLANG_DIR/bin/llvm-strip"
export READELF_BINARY="$CLANG_DIR/bin/llvm-readelf"
export PROFDATA_BINARY="$CLANG_DIR/bin/llvm-profdata"
export BOLT_BINARY="${BOLT_BINARY:-$(which llvm-bolt 2>/dev/null || which bolt 2>/dev/null)}"

export KBUILD_COMPILER_STRING="$($CLANG_BINARY --version | head -1 | sed 's/  */ /g')"

# =========================================================================
# OPTIMIZATION FLAGS - MAXIMUM PERFORMANCE
# =========================================================================

# Base: -O3 + aggressive loop opts + vectorization
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -O3"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fno-semantic-interposition"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fno-trapping-math"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fno-math-errno"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fno-rounding-math"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fno-signed-zeros"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -freciprocal-math"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -ffast-math"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -funsafe-math-optimizations"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fassociative-math"

# Loop optimizations
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -funroll-loops"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fpeel-loops"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -funswitch-loops"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fvect-cost-model=very-cheap"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fslp-vectorize-aggressive"

# Polymorphic inlining + devirtualization
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fdevirtualize"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fdevirtualize-speculatively"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fwhole-program-vtables"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fvisibility=hidden"

# Link-time optimization (FULL LTO with thin LTO cache)
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -flto=full"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fwhole-program-vtables"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fuse-ld=lld"

# Profile-guided optimization (requires training run)
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fprofile-generate=${OUT_DIR}/pgo"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fcs-profile-generate"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fprofile-use=${OUT_DIR}/pgo"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fprofile-correction"

# Machine-specific optimizations for Cortex-X3/A715/A510
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -mcpu=cortex-x3 -mtune=cortex-x3"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -march=armv9-a"

# BOLT post-link optimization (requires separate bolt step)
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fbolt-instrument"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -funique-internal-linkage-names"

# MLGO (Machine Learning Guided Optimization) - clang 16+
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fexperimental-new-pass-manager"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -mllvm -mlgo-inline-threshold=500"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -mllvm -mlgo-regalloc=1"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -mllvm -mlgo-branch-probabilities=1"

# Frame pointers for profiling (keep for perf/bpf)
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -fno-omit-frame-pointer"
export KBUILD_CFLAGS="${KBUILD_CFLAGS} -mno-omit-leaf-frame-pointer"

# =========================================================================
# LLD LINKER FLAGS
# =========================================================================
export KBUILD_LDFLAGS="${KBUILD_LDFLAGS} -Wl,--icf=all"
export KBUILD_LDFLAGS="${KBUILD_LDFLAGS} -Wl,--gc-sections"
export KBUILD_LDFLAGS="${KBUILD_LDFLAGS} -Wl,--build-id=sha1"
export KBUILD_LDFLAGS="${KBUILD_LDFLAGS} -Wl,--compress-debug-sections=zstd"
export KBUILD_LDFLAGS="${KBUILD_LDFLAGS} -Wl,-O3"
export KBUILD_LDFLAGS="${KBUILD_LDFLAGS} -Wl,--threads=$(nproc)"

# =========================================================================
# KERNEL CONFIG (gki_defconfig with all perf tweaks applied)
# =========================================================================
KERNEL_DEFCONFIG="${KERNEL_DEFCONFIG:-gki_defconfig}"
OUT_DIR="${OUT_DIR:-out}"
ARCH=arm64

# =========================================================================
# BUILD FUNCTIONS
# =========================================================================
log() { echo -e "\033[1;32m[BUILD]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

setup_clang() {
    log "Setting up clang toolchain: $CLANG_VERSION"
    mkdir -p "$CLANG_DIR"
    
    if [ ! -f "$CLANG_BINARY" ]; then
        log "Downloading clang..."
        local TARBALL=$(mktemp)
        local URL_BASE="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive"
        local CLANG_URL="$URL_BASE/mirror-goog-main-llvm-toolchain-source/${CLANG_VERSION}.tar.gz"
        
        if command -v wget >/dev/null; then
            wget -q --show-progress -O "$TARBALL" "$CLANG_URL"
        else
            curl -L --fail -o "$TARBALL" "$CLANG_URL"
        fi
        
        tar -xzf "$TARBALL" -C "$CLANG_DIR"
        rm -f "$TARBALL"
    fi
    
    export PATH="$CLANG_DIR/bin:$PATH"
    log "Using: $($CLANG_BINARY --version | head -1)"
}

build_kernel() {
    log "Starting PGO training build..."
    mkdir -p "${OUT_DIR}/pgo"
    
    # Phase 1: Instrumented build for PGO
    make -j"$(nproc)" O="$OUT_DIR" ARCH="$ARCH" \
         CC="$CLANG_BINARY" LD="$LLD_BINARY" \
         LLVM=1 LLVM_IAS=1 \
         NM="$NM_BINARY" OBJCOPY="$OBJCOPY_BINARY" OBJDUMP="$OBJDUMP_BINARY" \
         STRIP="$STRIP_BINARY" READELF="$READELF_BINARY" \
         KCFLAGS="$KBUILD_CFLAGS" KLDFLAGS="$KBUILD_LDFLAGS" \
         "$KERNEL_DEFCONFIG" || err "Defconfig failed"
    
    make -j"$(nproc)" O="$OUT_DIR" ARCH="$ARCH" \
         CC="$CLANG_BINARY" LD="$LLD_BINARY" \
         LLVM=1 LLVM_IAS=1 \
         KCFLAGS="$KBUILD_CFLAGS" KLDFLAGS="$KBUILD_LDFLAGS" \
         || err "PGO instrumented build failed"
    
    # Phase 2: Profile generation (requires device/emulator run)
    log "PGO instrumented kernel built at: $OUT_DIR/arch/arm64/boot/Image.gz"
    log ">>> Run kernel on device to generate profiles in /sys/kernel/debug/pgo/"
    log ">>> Then run: $0 --pgo-use"
    
    if [ "${1:-}" = "--pgo-use" ]; then
        log "Merging PGO profiles..."
        find /sys/kernel/debug/pgo -name "*.profraw" -exec $PROFDATA_BINARY merge {} -o ${OUT_DIR}/pgo/merged.profdata \;
        
        log "Building optimized kernel with PGO..."
        export KBUILD_CFLAGS="${KBUILD_CFLAGS/-fprofile-generate=/ -fprofile-use=${OUT_DIR}/pgo/merged.profdata }"
        make -j"$(nproc)" O="$OUT_DIR" ARCH="$ARCH" \
             CC="$CLANG_BINARY" LD="$LLD_BINARY" \
             LLVM=1 LLVM_IAS=1 \
             KCFLAGS="$KBUILD_CFLAGS" KLDFLAGS="$KBUILD_LDFLAGS" \
             || err "PGO optimized build failed"
    fi
    
    # Phase 3: BOLT post-link optimization (optional)
    if [ -n "$BOLT_BINARY" ] && [ "${1:-}" = "--bolt" ]; then
        log "Running BOLT optimization..."
        $BOLT_BINARY "$OUT_DIR/vmlinux" \
            --data="${OUT_DIR}/pgo/merged.profdata" \
            -o "$OUT_DIR/vmlinux.bolt" \
            -reorder-blocks=ext-tsp \
            -reorder-functions=hfsort \
            -split-functions=2 \
            -split-all-cold \
            -dyno-stats \
            -lite=false \
            && mv "$OUT_DIR/vmlinux.bolt" "$OUT_DIR/vmlinux"
    fi
    
    log "Build complete: $OUT_DIR/arch/arm64/boot/Image.gz"
}

# Main
setup_clang
build_kernel "$@"