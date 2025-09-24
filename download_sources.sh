#!/bin/bash

DOWNLOAD_DIR="${ROOT_DIR}/downloads"
LOCK_FILE="${ROOT_DIR}/git-sources.lock"

# Version definitions
ZLIB_VERSION="zlib-1.3.1"
XZ_VERSION="xz-5.8.1"
LIBFFI_VERSION="libffi-3.5.2"
NCURSES_VERSION="ncurses-6.5"

# URL definitions for direct downloads
ZLIB_URL="https://zlib.net/${ZLIB_VERSION}.tar.gz"
XZ_URL="https://github.com/tukaani-project/xz/releases/download/v5.8.1/${XZ_VERSION}.tar.gz"
LIBFFI_URL="https://github.com/libffi/libffi/releases/download/v3.5.2/${LIBFFI_VERSION}.tar.gz"
NCURSES_URL="https://ftp.gnu.org/gnu/ncurses/${NCURSES_VERSION}.tar.gz"

# GitHub repos that will be cloned with --depth 1
declare -A GITHUB_REPOS=(
    ["libxml2"]="https://github.com/GNOME/libxml2.git"
	["llvm-project"]="https://github.com/llvm/llvm-project.git"
	["zstd"]="https://github.com/facebook/zstd.git"
	["lz4"]="https://github.com/lz4/lz4.git"
)

PARALLEL_DOWNLOADS=${PARALLEL_DOWNLOADS:-8}

# simple lock file functions
read_lock_file() {
    declare -gA LOCKED_COMMITS
    if [ -f "$LOCK_FILE" ]; then
        echo "Reading lock file: $LOCK_FILE"
        while IFS='=' read -r repo commit; do
            if [ -n "$repo" ] && [ -n "$commit" ] && [[ "$commit" =~ ^[a-f0-9]{40}$ ]]; then
                LOCKED_COMMITS["$repo"]="$commit"
            fi
        done <"$LOCK_FILE"
    fi
}

write_lock_entry() {
    local repo_name="$1"
    local commit="$2"
    echo "${repo_name}=${commit}" >>"$LOCK_FILE"
}

# Function to download a single file
download_file() {
    local url="$1"
    local output="$2"

    if [ ! -f "$output" ]; then
        echo "Downloading: $output"
        if ! curl -L --fail --retry 3 --retry-delay 2 "$url" -o "$output"; then
            echo "Failed to download: $output"
            return 1
        fi
    else
        echo "Already exists: $output"
    fi
    return 0
}

clone_repo_with_lock() {
    local repo_name="$1"
    local repo_url="$2"
    local recursive="$3"

    if [ -d "$repo_name" ]; then
        echo "Already exists: $repo_name"
        return 0
    fi

    local locked_commit="${LOCKED_COMMITS[$repo_name]}"

    if [ -n "$locked_commit" ]; then
        echo "Cloning $repo_name (locked to $locked_commit)"
        if [ "$recursive" = "true" ]; then
            git clone --recursive "$repo_url" "$repo_name"
        else
            git clone "$repo_url" "$repo_name"
        fi

        (cd "$repo_name" && git checkout "$locked_commit")
        if [ $? -ne 0 ]; then
            echo "Warning: Failed to checkout commit $locked_commit for $repo_name, using HEAD"
        fi
    else
        echo "Cloning $repo_name (latest)"
        if [ "$recursive" = "true" ]; then
            git clone --depth 1 --recursive "$repo_url" "$repo_name"
        else
            git clone --depth 1 "$repo_url" "$repo_name"
        fi

        local current_commit
        current_commit=$(cd "$repo_name" && git rev-parse HEAD 2>/dev/null || echo "")
        if [ -n "$current_commit" ]; then
            write_lock_entry "$repo_name" "$current_commit"
            echo "Locked $repo_name to commit: $current_commit"
        fi
    fi
}

download_sources() {
    mkdir -p "$DOWNLOAD_DIR"
    read_lock_file

    cd "$DOWNLOAD_DIR" || exit 1
    echo "Downloading source archives..."
    {
        download_file "$ZLIB_URL" "zlib.tar.gz" &
        download_file "$XZ_URL" "xz.tar.gz" &
        download_file "$LIBFFI_URL" "libffi.tar.gz" &
        download_file "$NCURSES_URL" "ncurses.tar.gz" &
        wait
    }

    echo "Cloning GitHub repositories..."
    for repo_name in "${!GITHUB_REPOS[@]}"; do
        local repo_url="${GITHUB_REPOS[$repo_name]}"
        clone_repo_with_lock "$repo_name" "$repo_url" "false"
    done

    rm -f "${LOCK_FILE}.lock"

    echo "All downloads completed to: $DOWNLOAD_DIR"
    if [ -f "$LOCK_FILE" ]; then
        echo "Lock file created/used: $LOCK_FILE"
    fi
}

prepare_sources() {
    local arch_build_dir="${BUILD_DIR}"
    mkdir -p "$arch_build_dir"
    cd "$arch_build_dir" || exit 1
    [ ! -d zlib ] && tar -xf "${DOWNLOAD_DIR}/zlib.tar.gz" && mv "$ZLIB_VERSION" zlib
    [ ! -d xz ] && tar -xf "${DOWNLOAD_DIR}/xz.tar.gz" && mv "$XZ_VERSION" xz
    [ ! -d libffi ] && tar -xf "${DOWNLOAD_DIR}/libffi.tar.gz" && mv "$LIBFFI_VERSION" libffi
    [ ! -d ncurses ] && tar -xf "${DOWNLOAD_DIR}/ncurses.tar.gz" && mv "$NCURSES_VERSION" ncurses

    for repo_name in "${!GITHUB_REPOS[@]}"; do
        [ ! -d "$repo_name" ] && [ -d "${DOWNLOAD_DIR}/$repo_name" ] && cp -r "${DOWNLOAD_DIR}/$repo_name" .
    done

    echo "Sources prepared for architecture: $arch in $arch_build_dir"
}
