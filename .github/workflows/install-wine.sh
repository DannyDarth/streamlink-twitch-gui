#!/usr/bin/env bash
set -e

[[ "${CI}" ]] || exit 1

set -x

source /etc/os-release

# The Azure Ubuntu mirror on hosted runners has repeatedly downloaded Wine's
# i386 packages at extremely low speeds. Prefer Ubuntu's primary archive.
# Ubuntu 24.04 stores its default sources in ubuntu.sources.
for sources in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do
    if [[ -f "$sources" ]]; then
        sudo sed -i 's|http://azure.archive.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' "$sources"
    fi
done

# add i386 architecture
sudo dpkg --add-architecture i386

# install wine-stable from the regular Ubuntu package repositories
sudo apt-get update
sudo apt-get install --no-install-recommends wine-stable wine32:i386

# boot wine prefix without install popup
WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -i
wineserver --wait

# manually download+install wine-mono (would otherwise hang due to Xvfb)
# more recent versions of wine-mono will break anolis-resourcer which is used by nw-builder
# for replacing the application's embedded icon bitmaps in the executable
curl -SLO https://dl.winehq.org/wine/wine-mono/5.0.0/wine-mono-5.0.0-x86.msi
sha256sum -c <<< "17da208645a82a5e45e84fc75c73a8440acda484411cb8fae8e9b72db9886cd5  wine-mono-5.0.0-x86.msi"
wine msiexec /i wine-mono-5.0.0-x86.msi
wineserver --wait
rm -f wine-mono-5.0.0-x86.msi
