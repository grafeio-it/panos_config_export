#!/usr/bin/env bash
set -euo pipefail

# ------ Configuration -----
FW="https://192.168.0.11"
KEY_FILE="./key_192.168.0.11.key"
BACKUP_DIR="./backups"
# --------------------------

# -------- Settings --------
RETENTION_UNIT="minutes"  # minutes|hours|days
RETENTION_VALUE=2
KEEP_LAST=3               # keep at least last N backups
COLOR="auto"              # auto|on|off  (NO_COLOR=1 disables)
# -------------------------







#############################
### DON'T EDIT BELOW HERE ###
#############################

mkdir -p "$BACKUP_DIR"
OS="$(uname -s)"

# ---- Color handling ----
use_color=0
if [[ -n "${NO_COLOR:-}" ]]; then
  use_color=0
else
  case "$COLOR" in
    on)   use_color=1 ;;
    off)  use_color=0 ;;
    auto) [[ -t 1 ]] && use_color=1 || use_color=0 ;;
    *)    use_color=0 ;;
  esac
fi

if (( use_color )); then
  if command -v tput >/dev/null 2>&1; then
    C_RESET="$(tput sgr0)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_CYAN="$(tput setaf 6)"
    C_BOLD="$(tput bold)"
  else
    C_RESET=$'\033[0m'
    C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'
    C_YELLOW=$'\033[33m'
    C_CYAN=$'\033[36m'
    C_BOLD=$'\033[1m'
  fi
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_CYAN=""; C_BOLD=""
fi

log_saved()   { printf "%b✅ SAVED%b   %s\n"   "$C_GREEN$C_BOLD" "$C_RESET" "$1"; }
log_deleted() { printf "%b🧹 DELETED%b %s\n"   "$C_RED$C_BOLD"   "$C_RESET" "$1"; }
log_info()    { printf "%bℹ️  INFO%b    %s\n"  "$C_CYAN$C_BOLD"  "$C_RESET" "$1"; }
log_warn()    { printf "%b⚠️  WARN%b    %s\n"  "$C_YELLOW$C_BOLD""$C_RESET" "$1"; }
log_error()   { printf "%b❌ ERROR%b   %s\n"   "$C_RED$C_BOLD"   "$C_RESET" "$1" >&2; }

# ---- Retention seconds ----
case "$RETENTION_UNIT" in
  minutes) RETENTION_SECONDS=$((RETENTION_VALUE * 60)) ;;
  hours)   RETENTION_SECONDS=$((RETENTION_VALUE * 3600)) ;;
  days)    RETENTION_SECONDS=$((RETENTION_VALUE * 86400)) ;;
  *)
    log_error "RETENTION_UNIT must be one of: minutes|hours|days"
    exit 2
    ;;
esac

# ---- stat mtime epoch for file, per OS ----
file_mtime_epoch() {
  local f="$1"
  if [[ "$OS" == "Darwin" ]]; then
    stat -f %m "$f" 2>/dev/null
  else
    stat -c %Y "$f" 2>/dev/null
  fi
}

# ---- Read API key ----
KEY="$(tr -d '\r\n' < "$KEY_FILE")"

TS="$(date +'%Y-%m-%d_%H-%M-%S')"
OUT="$BACKUP_DIR/${TS}_running-config.xml"

# ---- Export config ----
curl -skG "$FW/api/" \
  --data-urlencode "type=export" \
  --data-urlencode "category=configuration" \
  --data-urlencode "key=$KEY" \
  -o "$OUT"

# ---- Basic plausibility checks ----
if [[ ! -s "$OUT" ]]; then
  log_error "Backup file is empty: $OUT"
  exit 1
fi

if grep -q '<response[^>]*status="error"' "$OUT"; then
  log_error "PAN-OS API returned status=error (not running retention cleanup)."
  log_warn "Inspect the file: $OUT"
  exit 1
fi

if ! grep -q '<config' "$OUT"; then
  log_warn "Backup does not contain <config>. It may still be valid depending on platform/version."
fi

log_saved "$OUT"
log_info "OS=$OS | retention=${RETENTION_VALUE} ${RETENTION_UNIT} | keep_last=$KEEP_LAST | color=$COLOR"

# ---- Cleanup ----
NOW_EPOCH="$(date +%s)"
CUTOFF_EPOCH=$((NOW_EPOCH - RETENTION_SECONDS))

# Collect backups sorted newest->oldest by filename (TS prefix makes it sortable)
# (Avoid mapfile for macOS bash 3.2)
ALL_BACKUPS="$(ls -1 "$BACKUP_DIR"/*_running-config.xml 2>/dev/null | sort -r || true)"

if [[ -z "$ALL_BACKUPS" ]]; then
  log_deleted "(none)"
  exit 0
fi

deleted_count=0
protected_count=0
idx=0

# Iterate line-by-line safely (filenames have no spaces in our pattern)
echo "$ALL_BACKUPS" | while IFS= read -r f; do
  [[ -z "$f" ]] && continue

  # protect newest KEEP_LAST
  if (( idx < KEEP_LAST )); then
    protected_count=$((protected_count + 1))
    idx=$((idx + 1))
    continue
  fi
  idx=$((idx + 1))

  # never delete the file we just wrote
  if [[ "$f" == "$OUT" ]]; then
    continue
  fi

  mtime="$(file_mtime_epoch "$f" || echo 0)"
  if [[ "$mtime" -le "$CUTOFF_EPOCH" ]]; then
    rm -f -- "$f"
    deleted_count=$((deleted_count + 1))
    printf "  %b- %s%b\n" "$C_RED" "$f" "$C_RESET"
  fi
done

# NOTE: counts inside the while run in a subshell in bash 3.2 when piped.
# So we print a simple summary without relying on those counters:
log_deleted "cleanup complete (see list above for deleted files, if any)"
