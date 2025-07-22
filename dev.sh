#!/usr/bin/env bash
set -euo pipefail

# ---------- config ----------
BACKEND_CMD=(go run ./bin/memos/main.go --mode dev --port 8081)
FRONTEND_DIR='web'
FRONTEND_CMD='pnpm install && pnpm dev'
SESSION_NAME='dev'
SPLIT_DIR='h'   # 'h' = side-by-side, 'v' = stacked
# ---------------------------

USE_TMUX=0
NO_COLOR=0

usage() {
    echo "Usage: $0 [--tmux] [--session NAME] [--vertical|--horizontal] [--no-color]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tmux) USE_TMUX=1 ;;
        --session) SESSION_NAME="$2"; shift ;;
        --vertical) SPLIT_DIR='v' ;;
        --horizontal) SPLIT_DIR='h' ;;
        --no-color) NO_COLOR=1 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1" >&2; usage ;;
    esac
    shift
done

# ---------- colors ----------
if [[ $NO_COLOR -eq 0 && -t 1 ]]; then
    RED=$(tput setaf 1); GREEN=$(tput setaf 2); YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 4); MAGENTA=$(tput setaf 5); CYAN=$(tput setaf 6)
    RESET=$(tput sgr0)
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; MAGENTA=''; CYAN=''; RESET=''
fi

colorize_prefix() {
    local name="$1" color="$2"
    awk -v c="$color" -v r="$RESET" -v n="$name" '{print c "[" n "]" r " " $0}'
}

# ---------- tmux mode ----------
if [[ $USE_TMUX -eq 1 ]]; then
    if ! command -v tmux >/dev/null; then
        echo "tmux not found -> falling back to single-window mode." >&2
        USE_TMUX=0
    fi
fi

# ---------- single-window mode ----------
pids=()

cleanup() {
    echo ">>> Shutting down..."
    kill "${pids[@]}" 2>/dev/null || true
    wait || true
}
trap cleanup INT TERM EXIT

run() {
    local name="$1" color="$2"; shift 2
    # Use stdbuf if available; otherwise run plain
    if command -v stdbuf >/dev/null; then
        stdbuf -oL -eL "$@" 2>&1 | colorize_prefix "$name" "$color" &
    else
        "$@" 2>&1 | colorize_prefix "$name" "$color" &
    fi
    pids+=($!)
}

run backend  "$BLUE"   "${BACKEND_CMD[@]}"
run frontend "$GREEN"  bash -lc "cd $FRONTEND_DIR && $FRONTEND_CMD"

# Requires bash >= 5 for wait -n. Fallback below if needed.
if wait -n 2>/dev/null; then
    status=$?
    echo ">>> A process exited (status $status). Stopping the rest..."
    kill "${pids[@]}" 2>/dev/null || true
    wait || true
    exit $status
else
    # Fallback polling loop
    while true; do
        for pid in "${pids[@]}"; do
            if ! kill -0 "$pid" 2>/dev/null; then
                echo ">>> PID $pid died. Stopping the rest..."
                kill "${pids[@]}" 2>/dev/null || true
                wait || true
                exit 1
            fi
        done
        sleep 1
    done
fi
