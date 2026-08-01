#!/usr/bin/env bash
set -euo pipefail
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libsecret-1-dev libjsoncpp-dev libmpv-dev mpv ffmpeg
printf 'Linux Flutter build dependencies installed.\n'
