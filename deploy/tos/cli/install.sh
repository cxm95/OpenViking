#!/bin/bash
set -e

# OpenViking CLI Installer (TOS)
# Usage: curl -fsSL http://openviking.tos-cn-beijing.volces.com/cli/install.sh | bash
#
# Environment variables:
#   OV_VERSION=0.3.16     Pin a specific version instead of latest
#   INSTALL_DIR=/path     Override install directory (default: /usr/local/bin)
#   SKIP_CHECKSUM=1       Skip SHA-256 verification

OV_BASE_URL="${OV_BASE_URL:-http://openviking.tos-cn-beijing.volces.com/cli}"
BINARY_NAME="ov"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
SKIP_CHECKSUM="${SKIP_CHECKSUM:-0}"
INSTALL_TARGET="${INSTALL_DIR%/}/${BINARY_NAME}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

detect_platform() {
    case "$(uname -s)" in
        Linux*) OS="linux" ;;
        Darwin*) OS="macos" ;;
        CYGWIN*|MINGW*|MSYS*) OS="windows" ;;
        *) error "Unsupported operating system: $(uname -s)" ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64) ARCH="x86_64" ;;
        arm64|aarch64) ARCH="aarch64" ;;
        *) error "Unsupported architecture: $(uname -m)" ;;
    esac

    ARTIFACT_NAME="${BINARY_NAME}-${OS}-${ARCH}"
    if [[ "$OS" == "windows" ]]; then
        ARTIFACT_NAME="${ARTIFACT_NAME}.exe"
        ARCHIVE_EXT="zip"
    else
        ARCHIVE_EXT="tar.gz"
    fi
}

resolve_version() {
    if [[ -n "${OV_VERSION:-}" ]]; then
        VERSION="$OV_VERSION"
        info "Using pinned version: $VERSION"
    else
        info "Fetching latest version..."
        VERSION=$(curl -fsSL "${OV_BASE_URL}/latest") || error "Failed to fetch latest version from ${OV_BASE_URL}/latest"
        VERSION=$(echo "$VERSION" | tr -d '[:space:]')
        [[ -z "$VERSION" ]] && error "Empty version returned from ${OV_BASE_URL}/latest"
        info "Latest version: $VERSION"
    fi

    DOWNLOAD_URL="${OV_BASE_URL}/v${VERSION}/${ARTIFACT_NAME}.${ARCHIVE_EXT}"
    CHECKSUM_URL="${OV_BASE_URL}/v${VERSION}/${ARTIFACT_NAME}.${ARCHIVE_EXT}.sha256"
}

download_binary() {
    info "Downloading ${ARTIFACT_NAME}.${ARCHIVE_EXT} (v${VERSION})..."
    TEMP_DIR=$(mktemp -d)
    ARCHIVE_FILE="$TEMP_DIR/${ARTIFACT_NAME}.${ARCHIVE_EXT}"
    CHECKSUM_FILE="$TEMP_DIR/${ARTIFACT_NAME}.${ARCHIVE_EXT}.sha256"

    curl -fSL --progress-bar -o "$ARCHIVE_FILE" "$DOWNLOAD_URL" || error "Download failed: $DOWNLOAD_URL"

    if [[ "$SKIP_CHECKSUM" == "1" ]]; then
        warn "Skipping checksum verification (SKIP_CHECKSUM=1)"
    elif curl -fsSL -o "$CHECKSUM_FILE" "$CHECKSUM_URL" 2>/dev/null; then
        info "Verifying checksum..."
        if command -v sha256sum >/dev/null 2>&1; then
            (cd "$TEMP_DIR" && sha256sum -c "${ARTIFACT_NAME}.${ARCHIVE_EXT}.sha256") || error "Checksum verification failed!"
        elif command -v shasum >/dev/null 2>&1; then
            (cd "$TEMP_DIR" && shasum -a 256 -c "${ARTIFACT_NAME}.${ARCHIVE_EXT}.sha256") || error "Checksum verification failed!"
        else
            warn "No checksum utility found, skipping verification"
        fi
    else
        warn "Checksum file not available, skipping verification"
    fi

    info "Extracting..."
    if [[ "$ARCHIVE_EXT" == "tar.gz" ]]; then
        tar -xzf "$ARCHIVE_FILE" -C "$TEMP_DIR" || error "Failed to extract archive"
    elif [[ "$ARCHIVE_EXT" == "zip" ]]; then
        unzip -q "$ARCHIVE_FILE" -d "$TEMP_DIR" || error "Failed to extract archive"
    fi

    TEMP_FILE="$TEMP_DIR/$BINARY_NAME"
    [[ "$OS" == "windows" ]] && TEMP_FILE="${TEMP_FILE}.exe"
    [[ -f "$TEMP_FILE" ]] || error "Binary not found after extraction"
}

install_binary() {
    info "Installing to ${INSTALL_TARGET}..."

    if [[ ! -d "$INSTALL_DIR" ]]; then
        mkdir -p "$INSTALL_DIR" 2>/dev/null || sudo mkdir -p "$INSTALL_DIR"
    fi

    if [[ -w "$INSTALL_DIR" ]]; then
        cp "$TEMP_FILE" "$INSTALL_TARGET"
        chmod +x "$INSTALL_TARGET"
    else
        info "Requesting sudo privileges..."
        sudo cp "$TEMP_FILE" "$INSTALL_TARGET"
        sudo chmod +x "$INSTALL_TARGET"
    fi

    rm -rf "$TEMP_DIR"
}

find_ov_paths() {
    local old_ifs="$IFS"
    local dir candidate seen
    IFS=':'
    for dir in $PATH; do
        [[ -z "$dir" ]] && dir="."
        candidate="${dir%/}/${BINARY_NAME}"
        if [[ -x "$candidate" ]]; then
            case ":$seen:" in
                *":$candidate:"*) ;;
                *)
                    echo "$candidate"
                    seen="${seen:+$seen:}$candidate"
                    ;;
            esac
        fi
    done
    IFS="$old_ifs"
}

print_path_diagnostics() {
    local resolved path version target_on_path=false count=0
    local paths=()

    while IFS= read -r path; do
        paths+=("$path")
        count=$((count + 1))
        [[ "$path" == "$INSTALL_TARGET" ]] && target_on_path=true
    done < <(find_ov_paths)

    if $target_on_path; then
        info "Install target is on PATH: $INSTALL_TARGET"
    else
        warn "Install target is not on PATH: $INSTALL_TARGET"
        warn "Add ${INSTALL_DIR%/} to PATH or invoke $INSTALL_TARGET directly."
    fi

    resolved=$(command -v "$BINARY_NAME" 2>/dev/null || true)
    if [[ -n "$resolved" && "$resolved" != "$INSTALL_TARGET" ]]; then
        warn "Your shell resolves '$BINARY_NAME' to $resolved before $INSTALL_TARGET"
    fi

    if [[ "$count" -gt 1 ]]; then
        warn "Multiple '$BINARY_NAME' executables found on PATH:"
        for path in "${paths[@]}"; do
            version=$("$path" --version 2>/dev/null | head -n 1 || true)
            [[ -z "$version" ]] && version="<version unavailable>"
            warn "  $path -> $version"
        done
    fi
}

verify_installation() {
    if [[ -x "$INSTALL_TARGET" ]]; then
        VERSION_OUTPUT=$("$INSTALL_TARGET" --version 2>/dev/null || true)
        info "Installed target version: ${VERSION_OUTPUT:-$INSTALL_TARGET}"
    else
        error "Installation failed - $INSTALL_TARGET is not executable"
    fi

    print_path_diagnostics
}

main() {
    info "OpenViking CLI Installer"
    echo ""
    detect_platform
    info "Platform: ${OS}/${ARCH}"
    resolve_version
    download_binary
    install_binary
    verify_installation
    echo ""
    info "Done! Run 'ov --help' to get started."
}

main "$@"
