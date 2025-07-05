#!/usr/bin/env bash
set -euo pipefail

# 1) enable any extra repos
sudo cp repo-files/*.repo /etc/yum.repos.d/

# 2) install dnf packages
sudo dnf install -y $(< pkglist.txt)

# 3) enable modules & groups
xargs -a modules.txt sudo dnf module enable -y
xargs -a groups.txt sudo dnf group install -y

# 4) install flatpaks
while read -r app; do
  flatpak install -y flathub "$app"
done < flatpak-apps.txt

# 5) python & npm
pip3 install --user -r pip3-packages.txt
npm install -g $(jq -r 'keys[]' npm-global.json)

# 6) apply gsettings
while read -r schema key type value; do
  gsettings set "$schema" "$key" "$value"
done < gsettings.conf

# 7) symlink dotfiles
stow --target="$HOME" home

echo "✅ Setup complete!"
