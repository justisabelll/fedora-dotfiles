#!/usr/bin/env bash
#
# A robust, idempotent script to configure a fresh Fedora Workstation install.
#
# To use:
# 1. Place this script in a directory with your config files and dotfiles.
# 2. Make it executable: `chmod +x bootstrap.sh`
# 3. Run it: `./bootstrap.sh`
#

# --- Rigorous Error Handling ---
# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Pipelines return the exit code of the last command to exit with a non-zero status.
set -euo pipefail

# --- Helper Functions ---

# Prints a formatted section header.
section_header() {
  echo -e "\n\e[1;34m--- $1 ---\e[0m"
}

# Ensures a command is available, installing the package if not.
# Usage: ensure_command "stow" "stow"
ensure_command() {
  local cmd="$1"
  local pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo "› Command '$cmd' not found. Installing '$pkg'..."
    sudo dnf install -y "$pkg"
  else
    echo "› Command '$cmd' is already available."
  fi
}

# --- Main Execution ---

# Ensure the script is run from its own directory
cd "$(dirname "$0")"

# Prompt for sudo password at the beginning
sudo -v
# Keep sudo session alive
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

section_header "System Preparation & Prerequisite Checks"
# Copy custom repository files if they exist
if [ -d "repo-files" ] && [ "$(ls -A repo-files)" ]; then
  echo "› Copying custom repository files..."
  sudo cp repo-files/*.repo /etc/yum.repos.d/
else
  echo "› No custom repository files found to copy."
fi

echo "› Forcing a refresh of DNF metadata..."
sudo dnf makecache

echo "› Verifying essential tools are installed..."
ensure_command "stow" "stow"
ensure_command "jq" "jq"
ensure_command "flatpak" "flatpak"
ensure_command "pip3" "python3-pip"
ensure_command "npm" "npm"

section_header "Installing DNF Packages"
if [ -f "pkglist.txt" ]; then
  echo "› Installing packages from pkglist.txt..."
  # xargs is robust for passing a list of arguments from a file
  # --allowerasing helps resolve potential package conflicts automatically
  xargs -a pkglist.txt sudo dnf install -y --allowerasing
else
  echo "› No pkglist.txt found, skipping DNF package installation."
fi

section_header "Installing Flatpak Applications"
if [ -f "flatpak-apps.txt" ]; then
  echo "› Installing applications from flatpak-apps.txt..."
  while read -r app || [[ -n "$app" ]]; do
    # Idempotency check: only install if not already present
    if ! flatpak info "$app" &>/dev/null; then
      echo "  - Installing $app..."
      flatpak install -y flathub "$app"
    else
      echo "  - $app is already installed, skipping."
    fi
  done <"flatpak-apps.txt"
else
  echo "› No flatpak-apps.txt found, skipping Flatpak installation."
fi

section_header "Installing Developer Tooling (Pip & NPM)"
if [ -f "pip3-packages.txt" ]; then
  echo "› Installing pip packages for user..."
  pip3 install --user -r pip3-packages.txt
else
  echo "› No pip3-packages.txt found, skipping pip installation."
fi

if [ -f "npm-global.json" ]; then
  echo "› Installing global npm packages..."
  # Use jq to parse the json output from 'npm list' and install
  jq -r '.dependencies | keys | .[]' npm-global.json | xargs sudo npm install -g
else
  echo "› No npm-global.json found, skipping npm installation."
fi

section_header "Applying GNOME Settings"
if [ -f "gsettings.conf" ]; then
  echo "› Loading gsettings from gsettings.conf..."
  # This is naturally idempotent
  while read -r line; do
    # Skip empty lines or comments
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    # Gsettings format is typically "schema key value"
    gsettings set $line
  done <"gsettings.conf"
else
  echo "› No gsettings.conf found, skipping."
fi

section_header "Creating Dotfile Symlinks"
if [ -d "home" ]; then
  echo "› Creating dotfile symlinks using Stow..."
  # The --restow flag is idempotent: it unlinks and relinks if needed.
  stow --restow --target="$HOME" home
  echo "› Symlinks are up to date."
else
  echo "› 'home' directory not found, skipping symlink creation."
fi

section_header "Setup Complete"
echo -e "\e[1;32m✅ Your Fedora environment has been configured.\e[0m"
echo "   You may need to reboot for all changes to take effect."
