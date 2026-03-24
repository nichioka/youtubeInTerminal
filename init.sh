#!/usr/bin/env bash

set -euo pipefail

REQUIRED_CMDS=(yt-dlp fzf mpv awk xargs)

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

detect_pkg_manager() {
  if has_cmd apt-get; then
    echo "apt"
  elif has_cmd pacman; then
    echo "pacman"
  elif has_cmd dnf; then
    echo "dnf"
  elif has_cmd yum; then
    echo "yum"
  elif has_cmd zypper; then
    echo "zypper"
  elif has_cmd brew; then
    echo "brew"
  else
    echo ""
  fi
}

install_with_manager() {
  local manager="$1"

  case "$manager" in
    apt)
      sudo apt-get update
      sudo apt-get install -y yt-dlp fzf mpv
      ;;
    pacman)
      sudo pacman -Sy --noconfirm yt-dlp fzf mpv
      ;;
    dnf)
      sudo dnf install -y yt-dlp fzf mpv
      ;;
    yum)
      sudo yum install -y yt-dlp fzf mpv
      ;;
    zypper)
      sudo zypper install -y yt-dlp fzf mpv
      ;;
    brew)
      brew install yt-dlp fzf mpv
      ;;
    *)
      return 1
      ;;
  esac
}

missing=()
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! has_cmd "$cmd"; then
    missing+=("$cmd")
  fi
done

if ((${#missing[@]} == 0)); then
  echo " Todas as dependências já estão instaladas."
else
  echo " Dependências ausentes: ${missing[*]}"
  pkg_manager="$(detect_pkg_manager)"

  if [[ -z "$pkg_manager" ]]; then
    echo "❌ Não foi possível detectar gerenciador de pacotes compatível."
    echo "Instale manualmente: yt-dlp, fzf e mpv"
    exit 1
  fi

  echo " Instalando com: $pkg_manager"
  install_with_manager "$pkg_manager"
fi

chmod +x ./yt.sh ./init.sh

echo "Setup concluído!"
echo "Execute: ./yt.sh \"termo da busca\""