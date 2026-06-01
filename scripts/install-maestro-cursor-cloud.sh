#!/usr/bin/env bash
# Install Maestro CLI and Maestro Studio for Cursor Cloud (Linux).
# - Maestro CLI via https://get.maestro.mobile.dev
# - Maestro Studio AppImage with FUSE + extraction fallback
# - PATH entries for maestro and maestro-studio launcher

set -euo pipefail

MAESTRO_CLI_INSTALL_URL="${MAESTRO_CLI_INSTALL_URL:-https://get.maestro.mobile.dev}"
MAESTRO_STUDIO_URL="${MAESTRO_STUDIO_URL:-https://studio.maestro.dev/MaestroStudio.AppImage}"
MAESTRO_STUDIO_DIR="${MAESTRO_STUDIO_DIR:-/opt/maestro-studio}"
MAESTRO_STUDIO_APPIMAGE="${MAESTRO_STUDIO_DIR}/MaestroStudio.AppImage"
MAESTRO_STUDIO_EXTRACTED="${MAESTRO_STUDIO_DIR}/extracted"
PROFILE_SNIPPET="/etc/profile.d/maestro.sh"
MAESTRO_STUDIO_BIN="/usr/local/bin/maestro-studio"

log() {
  echo "[install-maestro] $*"
}

require_root_for_system_paths() {
  if [[ "${EUID}" -ne 0 ]] && { [[ "${MAESTRO_STUDIO_DIR}" == /opt/* ]] || [[ "${PROFILE_SNIPPET}" == /etc/* ]] || [[ "${MAESTRO_STUDIO_BIN}" == /usr/local/* ]]; }; then
    log "Re-running with sudo for system-wide install paths..."
    exec sudo -E bash "$0" "$@"
  fi
}

ensure_java() {
  if ! command -v java >/dev/null 2>&1; then
    log "Installing OpenJDK 17 (Maestro requires Java 17+)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openjdk-17-jdk
  fi
  local java_version
  java_version="$(java -version 2>&1 | head -1)"
  log "Java: ${java_version}"
}

target_user_home() {
  if [[ "${EUID}" -eq 0 ]] && id ubuntu &>/dev/null; then
    echo "/home/ubuntu"
  else
    echo "${HOME}"
  fi
}

install_maestro_cli() {
  local target_home
  target_home="$(target_user_home)"
  local maestro_bin="${target_home}/.maestro/bin"

  if [[ -x "${maestro_bin}/maestro" ]]; then
    log "Maestro CLI already installed at ${maestro_bin}/maestro"
    return 0
  fi

  log "Installing Maestro CLI for ${target_home}..."
  if [[ "${EUID}" -eq 0 ]] && [[ "${target_home}" != "${HOME}" ]]; then
    local target_user
    target_user="$(basename "${target_home}")"
    runuser -u "${target_user}" -- bash -c "curl -fsSL '${MAESTRO_CLI_INSTALL_URL}' | bash"
  else
    curl -fsSL "${MAESTRO_CLI_INSTALL_URL}" | bash
  fi

  [[ -x "${maestro_bin}/maestro" ]] || {
    log "ERROR: Maestro CLI missing after install (expected ${maestro_bin}/maestro)" >&2
    exit 1
  }
  log "Maestro CLI installed at ${maestro_bin}/maestro"
}

install_fuse_deps() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get not available; ensure libfuse2 is installed for AppImage FUSE support"
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq libfuse2 fuse3 curl ca-certificates
}

install_maestro_studio_appimage() {
  mkdir -p "${MAESTRO_STUDIO_DIR}"
  if [[ ! -f "${MAESTRO_STUDIO_APPIMAGE}" ]]; then
    log "Downloading Maestro Studio AppImage..."
    curl -fsSL "${MAESTRO_STUDIO_URL}" -o "${MAESTRO_STUDIO_APPIMAGE}"
    chmod +x "${MAESTRO_STUDIO_APPIMAGE}"
  else
    log "Maestro Studio AppImage already present at ${MAESTRO_STUDIO_APPIMAGE}"
  fi

  if [[ ! -x "${MAESTRO_STUDIO_EXTRACTED}/AppRun" ]]; then
    log "Extracting AppImage for FUSE-less fallback (${MAESTRO_STUDIO_EXTRACTED})..."
    (
      cd "${MAESTRO_STUDIO_DIR}"
      ./MaestroStudio.AppImage --appimage-extract
      rm -rf extracted
      mv squashfs-root extracted
    )
    chmod -R a+rX "${MAESTRO_STUDIO_EXTRACTED}"
  else
    log "Extracted AppImage fallback already present"
  fi
}

write_maestro_studio_launcher() {
  cat > "${MAESTRO_STUDIO_BIN}" <<'LAUNCHER'
#!/usr/bin/env bash
# Launch Maestro Studio on Cursor Cloud (AppImage with FUSE / extraction fallback).
set -euo pipefail

MAESTRO_STUDIO_DIR="${MAESTRO_STUDIO_DIR:-/opt/maestro-studio}"
APPIMAGE="${MAESTRO_STUDIO_DIR}/MaestroStudio.AppImage"
EXTRACTED="${MAESTRO_STUDIO_DIR}/extracted"
EXTRA_ARGS=("--no-sandbox")

run_extracted() {
  export APPDIR="${EXTRACTED}"
  export APPIMAGE="${APPIMAGE}"
  export PATH="${APPDIR}:${APPDIR}/usr/sbin:${PATH}"
  export LD_LIBRARY_PATH="${APPDIR}/usr/lib:${LD_LIBRARY_PATH:-}"
  exec "${EXTRACTED}/maestro-studio" "${EXTRA_ARGS[@]}" "$@"
}

fuse_available() {
  [[ -e /dev/fuse ]] && { command -v fusermount3 >/dev/null 2>&1 || command -v fusermount >/dev/null 2>&1; }
}

if [[ -x "${EXTRACTED}/maestro-studio" ]] && [[ "${MAESTRO_STUDIO_USE_EXTRACTED:-}" == "1" ]]; then
  run_extracted "$@"
fi

if [[ -x "${APPIMAGE}" ]]; then
  if fuse_available; then
    exec "${APPIMAGE}" "${EXTRA_ARGS[@]}" "$@"
  fi
  # FUSE unavailable: use runtime extract-and-run or pre-extracted tree.
  exec "${APPIMAGE}" --appimage-extract-and-run "${EXTRA_ARGS[@]}" "$@"
fi

if [[ -x "${EXTRACTED}/maestro-studio" ]]; then
  run_extracted "$@"
fi

echo "Maestro Studio not found. Run scripts/install-maestro-cursor-cloud.sh" >&2
exit 1
LAUNCHER
  chmod +x "${MAESTRO_STUDIO_BIN}"
  log "Installed launcher: ${MAESTRO_STUDIO_BIN}"
}

write_profile_snippet() {
  local maestro_home="${HOME}"
  if [[ "${EUID}" -eq 0 ]] && id ubuntu &>/dev/null; then
    maestro_home="/home/ubuntu"
  fi

  cat > "${PROFILE_SNIPPET}" <<EOF
# Maestro CLI and Studio (Cursor Cloud)
export MAESTRO_HOME="${maestro_home}/.maestro"
export PATH="\${PATH}:\${MAESTRO_HOME}/bin"
export MAESTRO_STUDIO_DIR="${MAESTRO_STUDIO_DIR}"
EOF
  chmod 644 "${PROFILE_SNIPPET}"
  log "Wrote ${PROFILE_SNIPPET}"
}

append_user_path_if_needed() {
  local marker='# Maestro CLI (Cursor Cloud)'
  local target_home
  target_home="$(target_user_home)"
  for rc in "${target_home}/.bashrc" "${target_home}/.zshrc"; do
    [[ -f "${rc}" ]] || continue
    if grep -qF "${marker}" "${rc}" 2>/dev/null; then
      continue
    fi
    cat >> "${rc}" <<EOF

${marker}
export PATH="\${PATH}:\${HOME}/.maestro/bin"
export MAESTRO_STUDIO_DIR="${MAESTRO_STUDIO_DIR}"
EOF
    log "Updated ${rc}"
  done
}

verify_install() {
  local target_home
  target_home="$(target_user_home)"
  [[ -x "${target_home}/.maestro/bin/maestro" ]]
  [[ -x "${MAESTRO_STUDIO_BIN}" ]]
  [[ -f "${MAESTRO_STUDIO_APPIMAGE}" ]]
  [[ -x "${MAESTRO_STUDIO_EXTRACTED}/AppRun" ]]
  if id ubuntu &>/dev/null; then
    sudo -u ubuntu bash -lc 'source /etc/profile.d/maestro.sh && maestro --version' >/dev/null
  fi
  log "Verification OK: CLI=${target_home}/.maestro/bin/maestro, studio=${MAESTRO_STUDIO_BIN}"
}

main() {
  require_root_for_system_paths "$@"
  ensure_java
  install_fuse_deps
  install_maestro_cli
  install_maestro_studio_appimage
  write_maestro_studio_launcher
  write_profile_snippet
  append_user_path_if_needed
  verify_install
  log "Done. Open a new shell or: source ${PROFILE_SNIPPET}"
  log "  maestro --help"
  log "  maestro-studio   # GUI via VNC desktop when display is available"
}

main "$@"
