#!/bin/bash
# ================================================================
#  NGS Pipeline — Dependency Installer
#  Supports: Ubuntu/Debian | Fedora/RHEL
#  Author  : Vamsi Krishna Seerla
#  GitHub  : https://github.com/devilfrute
# ================================================================

BOLD='\033[1m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
DIM='\033[2m'
NC='\033[0m'

echo -e "${BOLD}${CYAN}"
cat << 'EOF'
  ╔══════════════════════════════════════════════════════════════╗
  ║         NGS PIPELINE — DEPENDENCY INSTALLER                 ║
  ╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# ── DETECT OS ───────────────────────────────────────────────────
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo -e "${RED}  Cannot detect OS. Exiting.${NC}"
    exit 1
fi

echo -e "${DIM}  Detected OS: ${OS}${NC}"
echo ""

# ── INSTALL FUNCTION ────────────────────────────────────────────
install_pkg() {
    local pkg=$1
    case "$OS" in
        ubuntu|debian|linuxmint|pop)
            sudo apt install -y "$pkg"
            ;;
        fedora|rhel|centos|rocky)
            sudo dnf install -y "$pkg"
            ;;
        *)
            echo -e "${RED}  Unsupported OS: ${OS}${NC}"
            exit 1
            ;;
    esac
}

check_and_install() {
    local cmd=$1
    local pkg=$2
    if command -v "$cmd" &>/dev/null; then
        echo -e "${GREEN}  PASS  ${NC}${cmd} already installed"
    else
        echo -e "${CYAN}  INST  ${NC}Installing ${pkg}..."
        install_pkg "$pkg"
        echo -e "${GREEN}  PASS  ${NC}${pkg} installed"
    fi
}

# ── SYSTEM PACKAGES ─────────────────────────────────────────────
echo -e "${BOLD}  System Dependencies:${NC}"
echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"

check_and_install "wget"    "wget"
check_and_install "git"     "git"
check_and_install "bc"      "bc"
check_and_install "mpg123"  "mpg123"

echo ""

# ── MINICONDA ───────────────────────────────────────────────────
echo -e "${BOLD}  Miniconda:${NC}"
echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"

if command -v conda &>/dev/null; then
    echo -e "${GREEN}  PASS  ${NC}conda already installed"
else
    echo -e "${CYAN}  INST  ${NC}Downloading and installing Miniconda..."
    wget -q --show-progress \
        https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
        -O /tmp/miniconda.sh
    bash /tmp/miniconda.sh -b -p "$HOME/miniconda3"
    echo 'export PATH="$HOME/miniconda3/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    rm /tmp/miniconda.sh
    echo -e "${GREEN}  PASS  ${NC}Miniconda installed"
fi

echo ""

# ── CONDA NGS ENVIRONMENT ───────────────────────────────────────
echo -e "${BOLD}  NGS Conda Environment:${NC}"
echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"

if conda env list | grep -q "^ngs"; then
    echo -e "${GREEN}  PASS  ${NC}ngs environment already exists"
else
    if [ -f ~/ngs_practice/ngs_environment.yml ]; then
        echo -e "${CYAN}  INST  ${NC}Creating ngs environment from yml..."
        conda env create -f ~/ngs_practice/ngs_environment.yml
        echo -e "${GREEN}  PASS  ${NC}ngs environment created"
    else
        echo -e "${RED}  FAIL  ${NC}ngs_environment.yml not found in ~/ngs_practice/"
        echo -e "${DIM}         Clone the repo first: git clone https://github.com/devilfrute/ecoli-variant-calling-pipeline.git ~/ngs_practice${NC}"
    fi
fi

echo ""

# ── ASSETS FOLDER ───────────────────────────────────────────────
echo -e "${BOLD}  Pipeline Assets:${NC}"
echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"

mkdir -p ~/ngs_practice/assets

if [ -f ~/ngs_practice/assets/complete.mp3 ]; then
    echo -e "${GREEN}  PASS  ${NC}Completion sound found"
else
    echo -e "${DIM}  INFO  ${NC}No completion sound found"
    echo -e "${DIM}         Add an mp3 file at: ~/ngs_practice/assets/complete.mp3${NC}"
    echo -e "${DIM}         Download free sounds from: https://freesound.org${NC}"
fi

echo ""

# ── SUMMARY ─────────────────────────────────────────────────────
echo -e "${DIM}  ──────────────────────────────────────────────────────${NC}"
echo ""
echo -e "${BOLD}  Installation complete.${NC}"
echo ""
echo -e "${DIM}  Next steps:${NC}"
echo -e "${DIM}  1. conda activate ngs${NC}"
echo -e "${DIM}  2. bash ~/ngs_practice/pipeline.sh${NC}"
echo ""
