#!/bin/bash

set -e

ARCH="${1:-$ARCH}"
API_LEVEL="${2:-$API_LEVEL}"
API_LEVEL="${API_LEVEL:-29}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VALID_ARCHES="aarch64 armv7 x86 x86_64 riscv64"

if [[ -z "$ARCH" || ! " $VALID_ARCHES " =~ $ARCH ]]; then
	echo "Usage: $0 <aarch64|armv7|x86|x86_64|riscv64> [API_LEVEL]"
	echo "Default API_LEVEL: 29"
	exit 1
fi

if [[ "$API_LEVEL" -gt 35 ]]; then
	echo "ERROR: API_LEVEL greater than 35 is not supported (got $API_LEVEL)"
	exit 1
fi

if [[ -z "$ANDROID_NDK_ROOT" ]]; then
	echo "ERROR: ANDROID_NDK_ROOT environment variable is not set"
	exit 1
fi

if [ -z "$ANDROID_NDK_ZIP" ]; then
    echo "Error: ANDROID_NDK_ZIP is not set. Aborting."
    exit 1
elif [ ! -f "$ANDROID_NDK_ZIP" ]; then
    echo "Error: ANDROID_NDK_ZIP file '$ANDROID_NDK_ZIP' does not exist. Aborting."
    exit 1
fi

if [ -z "$ANDROID_NDK_VERSION" ]; then
    echo "Error: ANDROID_NDK_VERSION is not set. Aborting."
    exit 1
fi

if [[ ! -d "$ANDROID_NDK_ROOT" ]]; then
	echo "ERROR: ANDROID_NDK_ROOT directory does not exist: $ANDROID_NDK_ROOT"
	exit 1
fi

if [[ "$ARCH" == "riscv64" && "$API_LEVEL" -lt 35 ]]; then
	export API_LEVEL=35
fi

case "$(uname -s)" in
Linux) HOST_OS=linux ;;
Darwin) HOST_OS=darwin ;;
CYGWIN* | MINGW* | MSYS*) HOST_OS=windows ;;
*)
	echo "ERROR: Unsupported host OS: $(uname -s)"
	exit 1
	;;
esac

case "$ARCH" in
aarch64)
	HOST=aarch64-linux-android
	ANDROID_ABI=arm64-v8a
	CLANG_TRIPLE=aarch64-linux-android
	;;
armv7)
	HOST=arm-linux-androideabi
	ANDROID_ABI=armeabi-v7a
	CLANG_TRIPLE=armv7a-linux-androideabi
	;;
x86)
	HOST=i686-linux-android
	ANDROID_ABI=x86
	CLANG_TRIPLE=i686-linux-android
	;;
x86_64)
	HOST=x86_64-linux-android
	ANDROID_ABI=x86_64
	CLANG_TRIPLE=x86_64-linux-android
	;;
riscv64)
	HOST=riscv64-linux-android
	ANDROID_ABI=riscv64
	CLANG_TRIPLE=riscv64-linux-android
	;;
*)
	echo "Unsupported architecture: $ARCH"
	exit 1
	;;
esac

TOOLCHAIN_ROOT="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$HOST_OS-x86_64"

export CC="${TOOLCHAIN_ROOT}/bin/${CLANG_TRIPLE}${API_LEVEL}-clang"
export CXX="${TOOLCHAIN_ROOT}/bin/${CLANG_TRIPLE}${API_LEVEL}-clang++"
export AR="${TOOLCHAIN_ROOT}/bin/llvm-ar"
export RANLIB="${TOOLCHAIN_ROOT}/bin/llvm-ranlib"
export STRIP="${TOOLCHAIN_ROOT}/bin/llvm-strip"
export NM="${TOOLCHAIN_ROOT}/bin/llvm-nm"
export STRINGS="${TOOLCHAIN_ROOT}/bin/llvm-strings"
export OBJDUMP="${TOOLCHAIN_ROOT}/bin/llvm-objdump"
export OBJCOPY="${TOOLCHAIN_ROOT}/bin/llvm-objcopy"

case "$ARCH" in
x86 | x86_64)
	if command -v nasm >/dev/null 2>&1; then
		export AS=nasm
	else
		export AS="$CC"
	fi
	;;
aarch64 | armv7)
	export AS="$CC"
	;;
*)
	echo "Warning: Unknown architecture for assembler setup: $ARCH"
	export AS="$CC"
	;;
esac

resolve_absolute_path() {
	local tool_name="$1"
	local abs_path

	if [[ "$tool_name" = /* ]]; then
		abs_path="$tool_name"
	else
		abs_path=$(which "$tool_name" 2>/dev/null)
	fi

	if [ -z "$abs_path" ] || [ ! -f "$abs_path" ]; then
		echo "ERROR: Tool '$tool_name' not found" >&2
		exit 1
	fi
	echo "$abs_path"
}

CC_ABS=$(resolve_absolute_path "$CC")
CXX_ABS=$(resolve_absolute_path "$CXX")
AR_ABS=$(resolve_absolute_path "$AR")
RANLIB_ABS=$(resolve_absolute_path "$RANLIB")
STRIP_ABS=$(resolve_absolute_path "$STRIP")
NM_ABS=$(resolve_absolute_path "$NM")

BUILD_DIR="$ROOT_DIR/build/android/$ARCH"
PREFIX="$BUILD_DIR/prefix"

mkdir -p "$BUILD_DIR" "$PREFIX"
mkdir -p "$PREFIX/lib/pkgconfig"
mkdir -p "$PREFIX/lib64/pkgconfig"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/lib64/pkgconfig:$PKG_CONFIG_PATH"
export PKG_CONFIG_ALLOW_CROSS=1

export PATH=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

SIZE_CFLAGS="-O3 -ffunction-sections -fdata-sections"
SIZE_CXXFLAGS="-O3 -ffunction-sections -fdata-sections"
SIZE_LDFLAGS="-Wl,--gc-sections"

MATH_FLAGS="-fno-math-errno -fno-trapping-math -fassociative-math"
PERF_FLAGS="$MATH_FLAGS -funroll-loops -fomit-frame-pointer"

ANDROID_FLAGS="-fvisibility=default -fPIC"

export CFLAGS="-I${PREFIX}/include $SIZE_CFLAGS $PERF_FLAGS $ANDROID_FLAGS -D_SYS_USER_H=1 -DNDEBUG"
export CXXFLAGS="$SIZE_CXXFLAGS $PERF_FLAGS $ANDROID_FLAGS -DNDEBUG"
export CPPFLAGS="-I${PREFIX}/include -DNDEBUG -fPIC"
export LDFLAGS="-L${PREFIX}/lib -L${PREFIX}/lib64 $SIZE_LDFLAGS -fPIC"

export SYSROOT="$TOOLCHAIN_ROOT/sysroot"



COMMON_AUTOTOOLS_FLAGS=(
	"--prefix=$PREFIX"
	"--host=$HOST"
	"--enable-static"
	"--disable-shared"
)


set_autotools_env() {
	export CC="$CC_ABS"
	export CXX="$CXX_ABS"
	export AR="$AR_ABS"
	export RANLIB="$RANLIB_ABS"
	export STRIP="$STRIP_ABS"
	export CFLAGS="$CFLAGS"
	export CXXFLAGS="$CXXFLAGS"
	export LDFLAGS="$LDFLAGS"
	export CPPFLAGS="-I$PREFIX/include"
	export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
}


autotools_build() {
	local project_name="$1"
	local build_dir="$2"
	shift 2
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	(make clean && make distclean) || true
	
	set_autotools_env
	
	./configure "${COMMON_AUTOTOOLS_FLAGS[@]}" "$@"
	make -j"$(nproc)"
	make install
	
	echo "✔ $project_name built successfully"
}


autotools_build_autoreconf() {
	local project_name="$1"
	local build_dir="$2"
	shift 2
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	(make clean && make distclean) || true
	autoreconf -fi
	
	set_autotools_env
	
	./configure "${COMMON_AUTOTOOLS_FLAGS[@]}" "$@"
	make -j"$(nproc)"
	make install
	
	echo "✔ $project_name built successfully"
}


make_build() {
	local project_name="$1"
	local build_dir="$2"
	local make_target="${3:-all}"
	local install_target="${4:-install}"
	shift 4
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	make clean || true
	
	make -j"$(nproc)" "$make_target" \
		CC="$CC_ABS" \
		AR="$AR_ABS" \
		RANLIB="$RANLIB_ABS" \
		STRIP="$STRIP_ABS" \
		CFLAGS="$CFLAGS" \
		LDFLAGS="$LDFLAGS" \
		PREFIX="$PREFIX" \
		"$@"
	
	make "$install_target" PREFIX="$PREFIX"
	
	echo "✔ $project_name built successfully"
}

generate_pkgconfig() {
	local name="$1"
	local description="$2"
	local version="$3"
	local libs="$4"
	local cflags="${5:--I\${includedir}}"
	local requires="${6:-}"
	local libs_private="${7:-}"
	
	local pc_dir="$PREFIX/lib/pkgconfig"
	local pc_file="$pc_dir/${name}.pc"
	
	[ -f "$pc_file" ] && return 0
	
	mkdir -p "$pc_dir"
	cat >"$pc_file" <<EOF
prefix=$PREFIX
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: $name
Description: $description
Version: $version
${requires:+Requires: $requires}
Libs: -L\${libdir} $libs
${libs_private:+Libs.private: $libs_private}
Cflags: $cflags
EOF
}


get_asm_flags() {
	case "$ARCH" in
		x86|riscv64) echo "--disable-asm" ;;
		*) echo "" ;;
	esac
}

get_host_override() {
	case "$ARCH" in
		riscv64) echo "riscv64-unknown-linux-gnu" ;;
		*) echo "$HOST" ;;
	esac
}

COMMON_CMAKE_FLAGS=(
	"-DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake"
	"-DANDROID_ABI=$ANDROID_ABI"
	"-DANDROID_PLATFORM=android-$API_LEVEL"
	"-DANDROID_NDK=$ANDROID_NDK_ROOT"
	"-DCMAKE_BUILD_TYPE=Release"
	"-DCMAKE_INSTALL_PREFIX=$PREFIX"
	"-DCMAKE_C_COMPILER=$CC_ABS"
	"-DCMAKE_CXX_COMPILER=$CXX_ABS"
	"-DCMAKE_C_FLAGS=$CFLAGS -I$PREFIX/include"
	"-DCMAKE_CXX_FLAGS=$CXXFLAGS -I$PREFIX/include"
	"-DCMAKE_EXE_LINKER_FLAGS=$LDFLAGS -L$PREFIX/lib"
	"-DCMAKE_AR=$AR_ABS"
	"-DCMAKE_RANLIB=$RANLIB_ABS"
	"-DCMAKE_STRIP=$STRIP_ABS"
	"-DCMAKE_FIND_ROOT_PATH=$SYSROOT;$PREFIX"
	"-DCMAKE_SYSROOT=$SYSROOT"
	"-DCMAKE_POSITION_INDEPENDENT_CODE=ON"
)

MINIMAL_CMAKE_FLAGS=(
	"-DCMAKE_BUILD_TYPE=Release"
	"-DCMAKE_INSTALL_PREFIX=$PREFIX"
	"-DCMAKE_C_COMPILER=$CC_ABS"
	"-DCMAKE_CXX_COMPILER=$CXX_ABS"
	"-DCMAKE_AR=$AR_ABS"
	"-DCMAKE_RANLIB=$RANLIB_ABS"
	"-DCMAKE_STRIP=$STRIP_ABS"
	"-DCMAKE_C_FLAGS=$CFLAGS"
	"-DCMAKE_CXX_FLAGS=$CXXFLAGS"
	"-DCMAKE_EXE_LINKER_FLAGS=$LDFLAGS"
)


cmake_build() {
	local project_name="$1"
	local build_dir="$2"
	local use_common_flags="${3:-true}"  # default to common flags
	shift 3
	
	echo "[+] Building $project_name for $ARCH..."
	cd "$build_dir" || exit 1
	
	rm -rf build && mkdir build && cd build
	
	local cmake_flags=()
	if [ "$use_common_flags" = "true" ]; then
		cmake_flags=("${COMMON_CMAKE_FLAGS[@]}")
	else
		cmake_flags=("${MINIMAL_CMAKE_FLAGS[@]}")
	fi
	
	cmake .. -G Ninja "${cmake_flags[@]}" "$@"
	ninja -j"$(nproc)"
	ninja install
	
	echo "✓ $project_name built successfully"
}

cmake_ninja_build() {
	cmake_build "$@"
}

get_simd_flags() {
	case "$ARCH" in
		x86|x86_64|i686)
			echo "-DENABLE_SIMD=ON"
			;;
		*)
			echo "-DENABLE_SIMD=OFF"
			;;
	esac
}

CROSS_FILE_TEMPLATE="$BUILD_DIR/.meson-cross-template"
DOWNLOADER_SCRIPT="${ROOT_DIR}/download_sources.sh"

source "$DOWNLOADER_SCRIPT"

sanitize_flags() {
    local flags="$1"
    echo "$flags" | xargs -n1 | sed "/^$/d; s/.*/'&'/" | paste -sd, -
}

create_meson_cross_file() {
    local output_file="$1"
    local system="${2:-android}"  # default to android
    
    local S_CFLAGS=$(sanitize_flags "$CFLAGS")
    local S_CXXFLAGS=$(sanitize_flags "$CXXFLAGS") 
    local S_LDFLAGS=$(sanitize_flags "$LDFLAGS")
    
    cat >"$output_file" <<EOF
[binaries]
c = '$CC_ABS'
cpp = '$CXX_ABS'
ar = '$AR_ABS'
nm = '$NM_ABS'
strip = '$STRIP_ABS'
pkg-config = 'pkg-config'
ranlib = '$RANLIB_ABS'

[built-in options]
c_args = [${S_CFLAGS}]
cpp_args = [${S_CXXFLAGS}]
c_link_args = [${S_LDFLAGS}]
cpp_link_args = [${S_LDFLAGS}]

[host_machine]
system = '${system}'
cpu_family = '${ARCH}'
cpu = '${ARCH}'
endian = 'little'
EOF
}

meson_build() {
    local project_name="$1"
    local build_dir="$2"
    local cross_file="$3"
    shift 3  # remove first 3 args rest are meson options
    
    echo "[+] Building $project_name for $ARCH..."
    cd "$build_dir" || exit 1
    
    rm -rf build && mkdir build
    
    meson setup build . \
        --cross-file="$cross_file" \
        --prefix="$PREFIX" \
        --buildtype=release \
        --default-library=static \
        "$@"
        
    ninja -C build -j"$(nproc)"
    ninja -C build install
    
    echo "✔ $project_name built successfully"
}

init_cross_files() {
    create_meson_cross_file "$CROSS_FILE_TEMPLATE" "android"
    create_meson_cross_file "$CROSS_FILE_TEMPLATE.linux" "linux"
}

build_zlib() {
	echo "[+] Building zlib for $ARCH..."
	cd "$BUILD_DIR/zlib" || exit 1
	
	export CHOST="$HOST"
	CFLAGS="$CFLAGS" ./configure --prefix="$PREFIX" --static
	make -j"$(nproc)" CFLAGS="$CFLAGS"
	make install
	
	echo "✔ zlib built successfully"
}

build_liblzma() {
	autotools_build "liblzma" "$BUILD_DIR/xz" \
		CC="$CC_ABS" \
		CFLAGS="$CFLAGS" \
		CXXFLAGS="$CXXFLAGS" \
		LDFLAGS="$LDFLAGS"
}

build_lz4() {
    echo "Building LZ4..."
    make -C "$BUILD_DIR/lz4" lib CC="$CC" CFLAGS="$CFLAGS" || exit 1
    make -C "$BUILD_DIR/lz4" install PREFIX="$PREFIX" || exit 1
}

build_zstd() {
	meson_build "zstd" "$BUILD_DIR/zstd/build/meson" "$CROSS_FILE_TEMPLATE" \

}

build_libffi() {
	autotools_build "libffi" "$BUILD_DIR/libffi" \
		--prefix="$PREFIX" \
		--host="$HOST"
}

build_libxml2() {
	echo "[+] Building libxml2 for $ARCH..."
	cd "$BUILD_DIR/libxml2" || exit 1
	
	(make clean && make distclean) || true
	./autogen.sh || true
	
	autotools_build "libxml2" "$BUILD_DIR/libxml2" \
		--without-python \
		CFLAGS="$CFLAGS -I$PREFIX/include" \
		LDFLAGS="$LDFLAGS -L$PREFIX/lib"
}

build_ncurses() {
	cd "$BUILD_DIR/ncurses"
	
	set_autotools_env
	
	./configure \
		"${COMMON_AUTOTOOLS_FLAGS[@]}" \
		--without-ada \
		--without-manpages \
		--without-progs \
		--without-tests \
		--with-fallbacks=linux,screen,screen-256color,tmux,tmux-256color,vt100,xterm,xterm-256color \
		--enable-widec \
		--disable-database \
		--with-default-terminfo-dir=/etc/terminfo
	
	make -j$(nproc)
	make install
	
	cd "$PREFIX/lib"
	ln -sf libtinfow.a libtinfo.a
	ln -sf libncursesw.a libncurses.a
	cd "$PREFIX/include" && ln -s ncursesw ncurses
	
	echo "✔ ncurses built successfully"
}

build_yasm() {
    echo "[+] Building YASM for $ARCH..."
    cd "$BUILD_DIR/yasm" || exit 1

    # Clean previous builds
    (make clean && make distclean) || true
    autoreconf -fi  

    set_autotools_env

    ./configure \
        --prefix="$PREFIX" \
        --host="$HOST" \
        --enable-static \
        --disable-shared \
        --disable-nls \
        --disable-dependency-tracking \
        CC="$CC_ABS" \
        CFLAGS="$CFLAGS" \
        LDFLAGS="$LDFLAGS -static"

    
    make -j"$(nproc)"
    make install

    echo "✔ YASM built successfully"
}

build_llvm() {
    echo "[+] Building LLVM for Android NDK replacement ($ARCH)..."
    cd "$BUILD_DIR/llvm-project" || exit 1
    
    rm -rf build && mkdir build && cd build
    
    # Check if we need to build native tablegen tools first
    local NATIVE_BUILD_DIR="$BUILD_DIR/llvm-project/native-build"
    local LLVM_TBLGEN="$NATIVE_BUILD_DIR/bin/llvm-tblgen"
    local CLANG_TBLGEN="$NATIVE_BUILD_DIR/bin/clang-tblgen"
    
    # Build native tablegen tools if they don't exist
    if [[ ! -f "$LLVM_TBLGEN" ]] || [[ ! -f "$CLANG_TBLGEN" ]]; then
        echo "[+] Building native tablegen tools..."
        rm -rf "$NATIVE_BUILD_DIR"
        mkdir -p "$NATIVE_BUILD_DIR"
        cd "$NATIVE_BUILD_DIR"
        
        cmake ../llvm -G Ninja \
            -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_INSTALL_PREFIX="$NATIVE_BUILD_DIR" \
            -DLLVM_TARGETS_TO_BUILD="X86" \
            -DCMAKE_C_COMPILER="$(which gcc)" \
            -DCMAKE_CXX_COMPILER="$(which g++)" \
            -DLLVM_ENABLE_PROJECTS="clang" \
            -DLLVM_BUILD_TOOLS=ON \
            -DLLVM_INCLUDE_TESTS=OFF \
            -DLLVM_INCLUDE_BENCHMARKS=OFF \
            -DLLVM_INCLUDE_EXAMPLES=OFF \
            -DLLVM_INCLUDE_DOCS=OFF \
            -DLLVM_OPTIMIZED_TABLEGEN=ON
            
        # Build only the tablegen tools we need
        ninja -j"$(nproc)" llvm-tblgen clang-tblgen llvm-min-tblgen
        
        if [[ ! -f "bin/llvm-tblgen" ]] || [[ ! -f "bin/clang-tblgen" ]] || [[ ! -f "bin/llvm-min-tblgen" ]]; then
            echo "ERROR: Failed to build tablegen tools"
            exit 1
        fi
        
        cd ../build
    fi


    local LLVM_CMAKE_FLAGS=(
    "${MINIMAL_CMAKE_FLAGS[@]}"
    "-DCMAKE_CROSSCOMPILING=ON"
    "-DLLVM_TABLEGEN=$LLVM_TBLGEN"
    "-DCLANG_TABLEGEN=$CLANG_TBLGEN"
    "-DLLVM_DEFAULT_TARGET_TRIPLE=$CLANG_TRIPLE"
    "-DLLVM_TARGET_ARCH=$ARCH"
    
    "-DLLVM_TARGETS_TO_BUILD=AArch64;ARM;X86;RISCV"
    "-DLLVM_ENABLE_PROJECTS=clang;lld"
    
    # Build configuration
    "-DLLVM_BUILD_RUNTIME=OFF"
    "-DLLVM_BUILD_STATIC=ON"
    "-DBUILD_SHARED_LIBS=OFF"
    
    "-DLLVM_INCLUDE_TESTS=OFF"
    "-DLLVM_INCLUDE_BENCHMARKS=OFF"
    "-DLLVM_INCLUDE_EXAMPLES=OFF"
    "-DLLVM_INCLUDE_DOCS=OFF"
    
    # Clang tools configuration - KEEP useful ones, disable problematic ones
    "-DCLANG_BUILD_TOOLS=ON"                        # Keep most Clang tools
    "-DCLANG_ENABLE_STATIC_ANALYZER=OFF"            # Disable static analyzer
    "-DCLANG_ENABLE_ARCMT=OFF"                      # Disable ARC migration tool
    "-DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF"           # Disable c-index-test
    "-DCLANG_TOOL_LIBCLANG_BUILD=OFF"               # Disable libclang
    
    # LLVM tools configuration  
    "-DLLVM_BUILD_TOOLS=ON"                         # Keep LLVM tools
    "-DLLVM_BUILD_UTILS=OFF"                        
    
    # Features configuration
    "-DLLVM_ENABLE_LIBEDIT=OFF"                     
    "-DLLVM_ENABLE_LIBXML2=ON"                      
    "-DLLVM_ENABLE_ZLIB=ON"                         
    
    # Library paths
    "-DLIBXML2_LIBRARY=$PREFIX/lib/libxml2.a"       # Only if you built libxml2
    "-DLIBXML2_INCLUDE_DIR=$PREFIX/include/libxml2/libxml"
    "-DZLIB_LIBRARY=$PREFIX/lib/libz.a"
    "-DZLIB_INCLUDE_DIR=$PREFIX/include"
)
    
    echo "[+] Configuring LLVM with NDK-focused options..."
    cmake ../llvm -G Ninja "${LLVM_CMAKE_FLAGS[@]}"
    
    echo "[+] Building LLVM (this will take a while)..."
    ninja -j"$(nproc)"
    
    echo "[+] Installing LLVM..."
    ninja install
    
    echo "✓ LLVM built successfully for NDK replacement"
}

download_sources
prepare_sources
init_cross_files

build_zlib
build_liblzma
build_lz4
build_zstd
build_libffi
build_libxml2
build_ncurses
build_llvm
build_yasm


mkdir -p "$ROOT_DIR/output"
export OUTPUT="$ROOT_DIR/output"
unzip "$ANDROID_NDK_ZIP" -d "$OUTPUT"
mv "$OUTPUT"/android-ndk* "$OUTPUT"/android-ndk
export ANDROID_NDK_NEW_ROOT="$OUTPUT/android-ndk"
export NDK_BIN_DIR="$ANDROID_NDK_NEW_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin"
rm -f "$NDK_BIN_DIR"/clang*
rm -f "$NDK_BIN_DIR"/ll*
mv "$PREFIX"/bin/clang* "$NDK_BIN_DIR"/
mv "$PREFIX"/bin/ll* "$NDK_BIN_DIR"/
mv "$PREFIX/bin/yasm" "$NDK_BIN_DIR"/
cp -r "$PREFIX"/lib/clang/* "$NDK_BIN_DIR"/../lib/clang/
"$STRIP_ABS" "$NDK_BIN_DIR"/* || true
([ "${ARCH}" != "x86_64" ] && cd "$NDK_BIN_DIR"/../../ && ln -s "linux-${ARCH}" linux-x86_64) || true
cd "$OUTPUT"
mv android-ndk android-ndk-${ANDROID_NDK_VERSION}
# zip -r -y -9 "${ROOT_DIR}/android-ndk-${ANDROID_NDK_VERSION}-${ARCH}.zip" "android-ndk-${ANDROID_NDK_VERSION}"

tar -cf - "android-ndk-${ANDROID_NDK_VERSION}" \
  | xz -T0 -9 -c > "${ROOT_DIR}/android-ndk-${ANDROID_NDK_VERSION}-${ARCH}.tar.xz"
