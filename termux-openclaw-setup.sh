#!/data/data/com.termux/files/usr/bin/bash
# OpenClaw Termux Installer
# Tested on Android 14 / Termux 0.118.3 / Node v24+
# Fork: https://github.com/indistinctchatter604/openclaw
#
# Usage: bash termux-openclaw-setup.sh [--help]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}      $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC}   $*" >&2; }

OPENCLAW_DIR="${HOME}/.openclaw"
STATE_DIR="${OPENCLAW_DIR}/state"
CONFIG_DIR="${OPENCLAW_DIR}/config"
DATA_DIR="${OPENCLAW_DIR}/data"
WORKSPACE_DIR="${OPENCLAW_DIR}/workspace"
CONFIG_FILE="${OPENCLAW_DIR}/openclaw.json"
AUTH_FILE="${STATE_DIR}/agents/main/agent/auth-profiles.json"
FORK_URL="https://github.com/indistinctchatter604/openclaw.git"
CLONE_DIR="${HOME}/git/openclaw"
LAUNCHER="${HOME}/bin/openclaw"
LOG_DIR="${OPENCLAW_DIR}/install-logs"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"

check_termux() {
    if [[ -z "${TERMUX_VERSION:-}" ]] && [[ ! -d "/data/data/com.termux" ]]; then
        log_error "This script must be run inside Termux."
        exit 1
    fi
    log_success "Termux ${TERMUX_VERSION} detected."
}

check_node() {
    if ! command -v node >/dev/null 2>&1; then
        log_error "Node.js not found. Run: pkg install nodejs-lts"
        exit 1
    fi
    local version
    version=$(node --version | sed 's/v//')
    local major
    major=$(echo "$version" | cut -d. -f1)
    if [[ $major -lt 22 ]]; then
        log_error "Node.js >= 22 required. Found: v${version}"
        log_error "Run: pkg install nodejs-lts"
        exit 1
    fi
    log_success "Node.js v${version} OK."
}

install_packages() {
    log_info "Updating package lists..."
    pkg update -y 2>/dev/null | tail -1
    local pkgs=(git nodejs-lts tmux make clang python)
    local missing=()
    for p in "${pkgs[@]}"; do
        if ! pkg list-installed "$p" >/dev/null 2>&1; then
            missing+=("$p")
        fi
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
        log_success "All required packages already installed."
    else
        log_info "Installing: ${missing[*]}"
        pkg install -y "${missing[@]}"
        log_success "Packages installed."
    fi
}

create_directories() {
    log_info "Creating directories..."
    mkdir -p \
        "${LOG_DIR}" \
        "${STATE_DIR}/agents/main/agent" \
        "${STATE_DIR}/agents/main/sessions" \
        "${CONFIG_DIR}" \
        "${DATA_DIR}" \
        "${WORKSPACE_DIR}" \
        "${HOME}/bin" \
        "${HOME}/git" \
        "${PREFIX}/tmp/openclaw"
    log_success "Directories created."
}

clone_repo() {
    if [[ -d "${CLONE_DIR}/.git" ]]; then
        log_info "Repo already cloned. Pulling latest..."
        git -C "${CLONE_DIR}" pull --ff-only 2>/dev/null || log_warn "Pull failed — using existing clone."
    else
        log_info "Cloning OpenClaw fork..."
        git clone "${FORK_URL}" "${CLONE_DIR}"
    fi
    log_success "Repo ready at ${CLONE_DIR}"
}

install_deps() {
    log_info "Installing node_modules (this may take a while)..."
    cd "${CLONE_DIR}"
    if command -v pnpm >/dev/null 2>&1; then
        pnpm install --frozen-lockfile 2>&1 | tail -5 || pnpm install 2>&1 | tail -5
    else
        npm install 2>&1 | tail -5
    fi
    log_success "Dependencies installed."
}

patch_dist() {
    log_info "Applying Android compatibility patch to dist files..."
    cd "${CLONE_DIR}"

    python3 << 'PYEOF'
import re, glob

android_check = '''
function isAndroidTermux() {
  return (
    process.env.OPENCLAW_PLATFORM === "android-termux" ||
    process.env.TERMUX_VERSION !== void 0 ||
    process.platform === "android"
  );
}
function resolveAndroidService() {
  const noop = (op) => async (args) => {
    const out = (args && args.stdout) ? args.stdout : process.stdout;
    out.write(`[android-termux] Service '${op}' skipped — use tmux to manage the gateway.\\n`);
  };
  return {
    label: "tmux (android-termux)",
    loadedText: "running",
    notLoadedText: "not running",
    install: noop("install"),
    uninstall: noop("uninstall"),
    stop: noop("stop"),
    restart: noop("restart"),
    isLoaded: async () => false,
    readCommand: async () => null,
    readRuntime: async () => ({ status: "unknown", detail: "Service management not available on android-termux. Use tmux." }),
  };
}
'''

patched = 0
skipped = 0

for filepath in glob.glob('dist/**/*.js', recursive=True) + glob.glob('dist/*.js'):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception:
        continue
    if 'not supported on' not in content:
        continue
    if 'isAndroidTermux' in content:
        skipped += 1
        continue
    pattern = r'(function resolveGatewayService\(\)\s*\{)'
    if not re.search(pattern, content):
        continue
    content = re.sub(pattern, android_check + r'\1', content)
    content = re.sub(
        r'(function resolveGatewayService\(\)\s*\{)',
        r'\1\n  if (isAndroidTermux()) { return resolveAndroidService(); }',
        content
    )
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    patched += 1
    print(f"  Patched: {filepath}")

if skipped > 0:
    print(f"  Already patched: {skipped} file(s)")
print(f"  Total patched: {patched} file(s)")
PYEOF

    log_success "Dist patch complete."
}

create_launcher() {
    log_info "Creating launcher at ${LAUNCHER}..."
    cat > "${LAUNCHER}" << EOF
#!/data/data/com.termux/files/usr/bin/bash
export TMPDIR="\${PREFIX}/tmp"
export TMP="\${TMPDIR}"
export TEMP="\${TMPDIR}"
export OPENCLAW_STATE_DIR="\${HOME}/.openclaw/state"
export OPENCLAW_CONFIG_DIR="\${HOME}/.openclaw/config"
export OPENCLAW_DATA_DIR="\${HOME}/.openclaw/data"
export OPENCLAW_CONFIG_PATH="\${HOME}/.openclaw/openclaw.json"
export OPENCLAW_PLATFORM="android-termux"
export OPENCLAW_DOCKER_ENABLED="false"
export OPENCLAW_SANDBOX_ENABLED="false"

exec node "${CLONE_DIR}/openclaw.mjs" "\$@"
EOF
    chmod +x "${LAUNCHER}"
    log_success "Launcher created."
}

setup_environment() {
    local BASHRC="${HOME}/.bashrc"
    local BLOCK_START="# >>> OPENCLAW TERMUX CONFIG >>>"
    local BLOCK_END="# <<< OPENCLAW TERMUX CONFIG <<<"
    if grep -q "${BLOCK_START}" "${BASHRC}" 2>/dev/null; then
        sed -i "/${BLOCK_START}/,/${BLOCK_END}/d" "${BASHRC}"
    fi
    cat >> "${BASHRC}" << EOF
${BLOCK_START}
export PATH="\${HOME}/bin:\${PATH}"
export TMPDIR="\${PREFIX}/tmp"
export TMP="\${TMPDIR}"
export TEMP="\${TMPDIR}"
export OPENCLAW_STATE_DIR="\${HOME}/.openclaw/state"
export OPENCLAW_CONFIG_DIR="\${HOME}/.openclaw/config"
export OPENCLAW_DATA_DIR="\${HOME}/.openclaw/data"
export OPENCLAW_CONFIG_PATH="\${HOME}/.openclaw/openclaw.json"
export OPENCLAW_PLATFORM="android-termux"
export OPENCLAW_DOCKER_ENABLED="false"
export OPENCLAW_SANDBOX_ENABLED="false"
${BLOCK_END}
EOF
    export PATH="${HOME}/bin:${PATH}"
    export OPENCLAW_CONFIG_PATH="${HOME}/.openclaw/openclaw.json"
    export OPENCLAW_PLATFORM="android-termux"
    log_success "Environment configured in .bashrc"
}

create_config() {
    if [[ -f "${CONFIG_FILE}" ]]; then
        log_info "Config already exists — skipping."
        return 0
    fi
    log_info "Writing default config..."
    cat > "${CONFIG_FILE}" << EOF
{
  "logging": {
    "level": "info",
    "file": "${PREFIX}/tmp/openclaw/openclaw-%DATE%.log"
  },
  "agents": {
    "defaults": {
      "workspace": "${WORKSPACE_DIR}",
      "compaction": {
        "reserveTokensFloor": 4000
      }
    }
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto"
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback"
  },
  "plugins": {
    "entries": {}
  }
}
EOF
    log_success "Default config written."
}

create_auth_scaffold() {
    if [[ -f "${AUTH_FILE}" ]]; then
        log_info "Auth file already exists — skipping."
        return 0
    fi
    log_info "Writing auth file scaffold..."
    cat > "${AUTH_FILE}" << 'EOF'
{
  "version": 1,
  "profiles": {
    "default": {
      "type": "api_key",
      "provider": "anthropic",
      "key": "REPLACE_WITH_YOUR_API_KEY"
    }
  }
}
EOF
    log_success "Auth scaffold written."
}

create_gateway_script() {
    local SCRIPT="${HOME}/bin/openclaw-gateway"
    cat > "${SCRIPT}" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
SESSION="openclaw"
if tmux has-session -t "${SESSION}" 2>/dev/null; then
    echo "Gateway already running. Attach with: tmux attach -t ${SESSION}"
    exit 0
fi
export PATH="${HOME}/bin:${PATH}"
export OPENCLAW_CONFIG_PATH="${HOME}/.openclaw/openclaw.json"
tmux new-session -d -s "${SESSION}" \
    "export PATH=${HOME}/bin:${PATH}; \
     export OPENCLAW_CONFIG_PATH=${HOME}/.openclaw/openclaw.json; \
     ${HOME}/bin/openclaw gateway; \
     echo 'Gateway exited. Press Enter.'; read"
echo "Gateway started. Attach with: tmux attach -t ${SESSION}"
echo "Detach with: Ctrl+B then D"
EOF
    chmod +x "${SCRIPT}"
    log_success "Gateway launcher created."
}

print_summary() {
    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}  OpenClaw Termux Installation Complete ${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Next steps:${NC}"
    echo ""
    echo "1. Add your API key:"
    echo "   nano ${AUTH_FILE}"
    echo "   Replace: REPLACE_WITH_YOUR_API_KEY"
    echo ""
    echo "   Providers (pick one):"
    echo "   - Anthropic:  console.anthropic.com"
    echo "   - OpenRouter: openrouter.ai  (recommended, many models)"
    echo "   - Groq:       console.groq.com (free tier, limited)"
    echo ""
    echo "   For OpenRouter change provider to 'openrouter' and set model:"
    echo "   openclaw config set agents.defaults.model.primary 'openrouter/deepseek/deepseek-chat-v3-0324'"
    echo ""
    echo "2. Reload shell:  source ~/.bashrc"
    echo "3. Run doctor:    openclaw doctor"
    echo "4. Start gateway: openclaw-gateway"
    echo "5. Onboard:       openclaw onboard"
    echo ""
    echo -e "${YELLOW}Note:${NC} 'Missing requirements: 47' in doctor is expected."
    echo "      Those are macOS/desktop skills that don't apply to Android."
    echo ""
    echo "Log: ${LOG_FILE}"
}

main() {
    mkdir -p "${LOG_DIR}"
    exec > >(tee -a "${LOG_FILE}") 2>&1
    clear
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}   OpenClaw Termux Installer             ${NC}"
    echo -e "${BLUE}   Fork: indistinctchatter604/openclaw   ${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    check_termux
    check_node
    install_packages
    create_directories
    clone_repo
    install_deps
    patch_dist
    create_launcher
    setup_environment
    create_config
    create_auth_scaffold
    create_gateway_script
    print_summary
}

main "$@"
