#!/bin/sh
set -eu
dir="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/olimpia}"
file="$dir/agent-token"
if [ ! -s "$file" ]; then
  mkdir -p "$dir"
  umask 077
  token="olimpia_dev_$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s' "$token" > "$file.$$"
  mv "$file.$$" "$file"
fi
printf '{"Authorization":"Bearer %s","X-Olimpia-Agent":"Claude Code"}' "$(cat "$file")"
