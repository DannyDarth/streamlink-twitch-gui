#!/usr/bin/env bash
set -e

[[ "${CI}" ]] || exit 1

set -x

source /etc/os-release

# Explicitly replace the runner's Ubuntu mirror configuration. Some GitHub
# images use sources files outside the two usual paths.
sudo find /etc/apt -type f -name '*.sources' \
    -exec sed -i \
    -e 's|http://azure.archive.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    -e 's|https://azure.archive.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    {} +
sudo find /etc/apt -type f -name '*.list' \
    -exec sed -i \
    -e 's|http://azure.archive.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    -e 's|https://azure.archive.ubuntu.com/ubuntu|http://archive.ubuntu.com/ubuntu|g' \
    {} +
# Fail early rather than silently falling back to the problematic mirror.
if sudo grep -R -E 'https?://azure.archive.ubuntu.com/ubuntu' \
    /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    echo "Azure Ubuntu mirror is still configured" >&2
    exit 1
fi

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
