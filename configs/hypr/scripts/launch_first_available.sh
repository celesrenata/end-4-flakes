#!/usr/bin/env bash
# Launch the first available application from a list
for cmd in "$@"; do
    eval "command -v ${cmd%% *}" >/dev/null 2>&1 || continue
    eval "$cmd" &
    exit
done
exit 1
