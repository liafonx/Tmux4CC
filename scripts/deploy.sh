#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — deploy tmux4cc config files to local symlinks or remote machines.
#
# Usage: deploy.sh [--all | --tmux | --zsh | --hooks | --cleanup] [--dry-run]
#
# Machine detection:
#   MacBook:   whoami=liafo,    uname -s=Darwin, uname -m=arm64
#   Mac Mini:  whoami=liafonx,  uname -s=Darwin, uname -m=x86_64
#   Linux VPS: whoami=liafonx,  uname -s=Linux

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

# ─── Detect current machine ───────────────────────────────────────────────────

WHOAMI="$(whoami)"
THIS_OS="$(uname -s)"
THIS_ARCH="$(uname -m)"

if [[ "$WHOAMI" == "liafo" && "$THIS_OS" == "Darwin" && "$THIS_ARCH" == "arm64" ]]; then
  MACHINE="macbook"
elif [[ "$WHOAMI" == "liafonx" && "$THIS_OS" == "Darwin" ]]; then
  MACHINE="macmini"
elif [[ "$WHOAMI" == "liafonx" && "$THIS_OS" == "Linux" ]]; then
  MACHINE="linux-vps"
else
  echo "Error: unrecognised machine (whoami=$WHOAMI, os=$THIS_OS, arch=$THIS_ARCH)" >&2
  exit 1
fi

echo "Machine detected: $MACHINE"

# ─── Remote host definitions ──────────────────────────────────────────────────

REMOTE_MACMINI="liafonx@Liafonxs-Mac-mini.local"
REMOTE_LINUX="liafonx@88.151.34.29"

# Overlay file per machine
overlay_for() {
  case "$1" in
    macbook)   echo "zsh/overlays/macbook.zsh" ;;
    macmini)   echo "zsh/overlays/macmini.zsh" ;;
    linux-vps) echo "zsh/overlays/linux-vps.zsh" ;;
  esac
}

# ─── Parse flags ──────────────────────────────────────────────────────────────

DO_TMUX=0
DO_ZSH=0
DO_HOOKS=0
DO_CLEANUP=0
DRY_RUN=0

if [[ $# -eq 0 ]]; then
  echo "Usage: deploy.sh [--all | --tmux | --zsh | --hooks | --cleanup] [--dry-run]" >&2
  exit 1
fi

for arg in "$@"; do
  case "$arg" in
    --all)      DO_TMUX=1; DO_ZSH=1; DO_HOOKS=1; DO_CLEANUP=1 ;;
    --tmux)     DO_TMUX=1 ;;
    --zsh)      DO_ZSH=1 ;;
    --hooks)    DO_HOOKS=1 ;;
    --cleanup)  DO_CLEANUP=1 ;;
    --dry-run)  DRY_RUN=1 ;;
    *)
      echo "Error: unknown flag: $arg" >&2
      echo "Usage: deploy.sh [--all | --tmux | --zsh | --hooks | --cleanup] [--dry-run]" >&2
      exit 1
      ;;
  esac
done

# ─── Helpers ──────────────────────────────────────────────────────────────────

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

run_ssh() {
  local host="$1"
  shift
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] ssh $host -- $*"
  else
    ssh "$host" -- "$@"
  fi
}

run_scp() {
  local src="$1"
  local dst="$2"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] scp -r $src $dst"
  else
    scp -r "$src" "$dst"
  fi
}

# ─── MacBook: local symlinks ──────────────────────────────────────────────────

deploy_macbook() {
  if [[ "$DO_TMUX" -eq 1 ]]; then
    echo "  [tmux] symlinking tmux.conf..."
    run mkdir -p "$HOME/.config/tmux"
    run ln -sfn "${REPO_DIR}/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
    echo "  [tmux] done"
  fi

  if [[ "$DO_ZSH" -eq 1 ]]; then
    echo "  [zsh] symlinking repo as ~/.config/tmux4cc..."
    run mkdir -p "$HOME/.config"
    run ln -sfn "${REPO_DIR}" "$HOME/.config/tmux4cc"
    echo "  [zsh] done"
  fi

  if [[ "$DO_HOOKS" -eq 1 ]]; then
    echo "  [hooks] symlinking notify.sh..."
    run mkdir -p "$HOME/.claude/hooks"
    run ln -sfn "${REPO_DIR}/hooks/notify.sh" "$HOME/.claude/hooks/notify.sh"
    echo "  [hooks] done"
  fi

  if [[ "$DO_CLEANUP" -eq 1 ]]; then
    echo "  [cleanup] symlinking tmux-cleanup.sh..."
    run mkdir -p "$HOME/.tmux"
    run ln -sfn "${REPO_DIR}/scripts/tmux-cleanup.sh" "$HOME/.tmux/cleanup.sh"
    echo "  [cleanup] done"
  fi
}

# ─── Remote: SCP + symlinks + reload ─────────────────────────────────────────

deploy_remote() {
  local host="$1"
  local target_machine="$2"
  local overlay_src
  overlay_src="$(overlay_for "$target_machine")"

  echo "  Deploying to $host..."

  # Create directory structure on remote (parent dirs; scp creates leaf dirs)
  run_ssh "$host" 'mkdir -p ~/.config/tmux4cc ~/.config/tmux4cc/zsh ~/.config/tmux4cc/hooks ~/.config/tmux4cc/scripts ~/.config/tmux ~/.claude/hooks ~/.tmux'

  if [[ "$DO_TMUX" -eq 1 ]]; then
    echo "  [tmux] copying tmux/ to remote..."
    # No trailing slash on source: scp copies the dir itself into destination
    run_scp "${REPO_DIR}/tmux" "${host}:~/.config/tmux4cc/"
    run_ssh "$host" 'ln -sfn ~/.config/tmux4cc/tmux/tmux.conf ~/.config/tmux/tmux.conf'
    # Reload tmux on remote if a session exists
    run_ssh "$host" 'SKIP_TMUX=1 tmux source ~/.config/tmux/tmux.conf 2>/dev/null || true'
    echo "  [tmux] done"
  fi

  if [[ "$DO_ZSH" -eq 1 ]]; then
    echo "  [zsh] copying zsh/shared/ and overlay to remote..."
    # No trailing slash on source: scp copies the dir itself into parent
    run_scp "${REPO_DIR}/zsh/shared" "${host}:~/.config/tmux4cc/zsh/"
    if [[ -f "${REPO_DIR}/${overlay_src}" ]]; then
      run_scp "${REPO_DIR}/${overlay_src}" "${host}:~/.config/tmux4cc/zsh/overlay.zsh"
    else
      echo "  [zsh] warning: overlay not found at ${overlay_src}, skipping"
    fi
    echo "  [zsh] done"
  fi

  if [[ "$DO_HOOKS" -eq 1 ]]; then
    echo "  [hooks] copying notify.sh to remote..."
    run_scp "${REPO_DIR}/hooks/notify.sh" "${host}:~/.config/tmux4cc/hooks/notify.sh"
    run_ssh "$host" 'chmod +x ~/.config/tmux4cc/hooks/notify.sh && ln -sfn ~/.config/tmux4cc/hooks/notify.sh ~/.claude/hooks/notify.sh'
    echo "  [hooks] done"
  fi

  if [[ "$DO_CLEANUP" -eq 1 ]]; then
    echo "  [cleanup] copying tmux-cleanup.sh to remote..."
    run_scp "${REPO_DIR}/scripts/tmux-cleanup.sh" "${host}:~/.config/tmux4cc/scripts/tmux-cleanup.sh"
    run_ssh "$host" 'chmod +x ~/.config/tmux4cc/scripts/tmux-cleanup.sh && ln -sfn ~/.config/tmux4cc/scripts/tmux-cleanup.sh ~/.tmux/cleanup.sh'
    echo "  [cleanup] done"
  fi

  echo "  Deploy to $host complete."
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────
# deploy.sh is designed to run from MacBook (the machine with the repo).
# It deploys local symlinks on MacBook, then SCPs to both remotes.

case "$MACHINE" in
  macbook)
    echo "Deploying locally (MacBook)..."
    deploy_macbook
    echo "Pushing to Mac Mini..."
    deploy_remote "$REMOTE_MACMINI" "macmini"
    echo "Pushing to Linux VPS..."
    deploy_remote "$REMOTE_LINUX" "linux-vps"
    echo "Deploy complete."
    ;;
  macmini|linux-vps)
    echo "Error: deploy.sh should be run from MacBook (the machine with the repo)." >&2
    echo "SSH to MacBook and run scripts/deploy.sh from there." >&2
    exit 1
    ;;
esac
