#!/usr/bin/env bash
# demo-driver — CLI interface to the Desktop Demo Driver
# Usage: demo-driver [start|stop|pause|resume|list|speed <N>] [scene-or-category]

set -euo pipefail

QS_CONFIG="ii"
IPC_CMD="quickshell -c $QS_CONFIG ipc call"

case "${1:-start}" in
    start)
        SCENE="${2:-}"
        if [[ -n "$SCENE" ]]; then
            $IPC_CMD demo start "$SCENE"
        else
            $IPC_CMD demo start
        fi
        ;;
    stop)    $IPC_CMD demo stop ;;
    pause)   $IPC_CMD demo pause ;;
    resume)  $IPC_CMD demo resume ;;
    list)    $IPC_CMD demo list ;;
    speed)   $IPC_CMD demo speed "${2:-1.0}" ;;
    *)
        echo "Usage: demo-driver [start|stop|pause|resume|list|speed <N>] [scene-or-category]"
        exit 1
        ;;
esac
