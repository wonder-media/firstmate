# shellcheck shell=bash
# Durable secondmate dormancy record helpers. Source only.
#
# state/<id>.dormant is intentionally separate from state/<id>.meta so the
# endpoint identity, spawn, and teardown metadata contracts remain unchanged.
# The record is both the explicit lifecycle state and the durable proof that
# tracked-file plus inherited-local-material convergence is owed on wake.

fm_secondmate_dormant_path() { # <state-dir> <id>
  local state=$1 id=$2
  case "$id" in *[!/A-Za-z0-9._-]*|''|*/*) return 1 ;; esac
  printf '%s/%s.dormant\n' "$state" "$id"
}

fm_secondmate_dormant_present() { # <state-dir> <id>
  local marker
  marker=$(fm_secondmate_dormant_path "$1" "$2") || return 1
  [ -f "$marker" ] && [ ! -L "$marker" ]
}

fm_secondmate_dormant_write() { # <state-dir> <id> <reason>
  local state=$1 id=$2 reason=$3 marker tmp
  case "$reason" in ''|*$'\n'*|*$'\r'*) return 1 ;; esac
  [ -d "$state" ] && [ ! -L "$state" ] || return 1
  marker=$(fm_secondmate_dormant_path "$state" "$id") || return 1
  [ ! -L "$marker" ] || return 1
  tmp=$(umask 077; mktemp "$state/.dormant-$id.XXXXXX" 2>/dev/null) || return 1
  {
    printf 'v1\n'
    printf 'id=%s\n' "$id"
    printf 'set_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'reason=%s\n' "$reason"
    printf 'pending_tracked_sync=1\n'
    printf 'pending_inherited_material=1\n'
  } > "$tmp" || { rm -f -- "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$marker" || { rm -f -- "$tmp"; return 1; }
}

fm_secondmate_dormant_clear() { # <state-dir> <id>
  local marker
  marker=$(fm_secondmate_dormant_path "$1" "$2") || return 1
  if [ -e "$marker" ] || [ -L "$marker" ]; then
    [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
    rm -f -- "$marker"
  fi
}
