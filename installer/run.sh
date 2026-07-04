#!/bin/sh
#
# ============================================================================
#  HgrmMediaPlayerApp UI colour patcher  --  INSTALL
#  Only compatible with MrWalkman Walkman One firmware
#  Packaged with unknown321/nw-installer
# ============================================================================
#
#  What it does
#  ------------
#   * Backs up the pristine HgrmMediaPlayerApp once (HgrmMediaPlayerApp_BEFORE_COL).
#   * Reads 4 hex colours from /contents/COL/colours.cfg on the internal storage.
#     (Writes a default colours.cfg the first time, if none exists.)
#   * Patches the 4 embedded "#RRGGBB" strings in HgrmMediaPlayerApp in place.
#   * Verifies every write and rolls back from the backup on any failure.
#   * Logs everything to /contents/COL/colours.log.
#
# ============================================================================

# ---- busybox helpers ----------------
BB=/xbin/busybox
CP="${BB} cp"
RM="${BB} rm"
MKDIR="${BB} mkdir"
CHMOD="${BB} chmod"
DD="${BB} dd"
MD5="${BB} md5sum"
AWK="${BB} awk"
PRINTF="${BB} printf"
TR="${BB} tr"
SED="${BB} sed"
GREP="${BB} grep"
CAT="${BB} cat"

# ---- paths -----------------------------------------------------------------
HGRM=/system/vendor/sony/bin/HgrmMediaPlayerApp
BACKUP=/system/vendor/sony/bin/HgrmMediaPlayerApp_BEFORE_COL

CONTENTS=/contents               # internal (PC-visible) storage
COLDIR="${CONTENTS}/COL"         # our folder on the internal storage
CFG="${COLDIR}/colours.cfg"
LOG="${COLDIR}/colours.log"

# The 4 colour string offsets (7-byte #RRGGBB, NUL-terminated, 8 apart) --
# EDIT THESE if you rebase on a firmware with a different layout.
OFFSETS="3983112 3983120 3983128 3983136"

# Stock strings that live at those offsets (reference only)
ORIGINALS="#FFD2B0 #FF6757 #B1CFE5 #AED1B3"

# Defaults written to colours.cfg on first run (Peach/Red/Blue/Green slots)
DEFAULTS="#FF8922 #FFE816 #FF5AE6 #97FF4D"

# ============================================================================

# Pick a log target we can actually write to (prefer /contents, then the
# installer's own log, then /tmp). Never let logging abort the run.
init_log() {
  for t in "${LOG}" "${LOG_FILE}" "/tmp/colours.log"; do
    [ -n "${t}" ] || continue
    ${MKDIR} -p "$(${BB} dirname "${t}")" 2>/dev/null
    if ( echo "" >> "${t}" ) 2>/dev/null; then
      LOG="${t}"
      return 0
    fi
  done
  LOG=/dev/null
}

log() {
  echo "$(date) $1" >> "${LOG}" 2>/dev/null
}

finish() {
  sync
  umount /system 2>/dev/null
}

# Read exactly 7 bytes at a byte offset from a file -> stdout
read7() {
  # $1 = file  $2 = offset
  ${DD} if="$1" bs=1 skip="$2" count=7 2>/dev/null
}

# Confirm all 4 offsets in a file contain a valid "#RRGGBB" string.
# This is our "is this the firmware we know?" guard: on an unexpected binary
# the odds of finding #<6 hex> at all four 8-aligned offsets are practically 
# nil.
validate_layout() {
  src="$1"
  for off in ${OFFSETS}; do
    cur=$(read7 "${src}" "${off}")
    case "${cur}" in
      "#"[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f])
        : ;;
      *)
        log "layout check: offset ${off} holds '${cur}', expected #RRGGBB"
        return 1 ;;
    esac
  done
  return 0
}

# Write the default colours.cfg. Returns non-zero if it can't be written.
write_default_cfg() {
  ${MKDIR} -p "${COLDIR}" 2>/dev/null
  {
    echo "; ==========================================================="
    echo ";  colours.cfg  - Walkman home-screen icon colours"
    echo "; ==========================================================="
    echo ";  This file is used by the firmware installer to overwrite"
    echo ";  the default colours settable via MrWalkman's firmware."
    echo ";"
    echo ";  The four lines under these instructions define new colours"
    echo ";  to map to MrWalkman's COL= setting in"
    echo ";  '/contents/CFW/settings.txt'"    
    echo ";      line 1  ->  COL=1  (Peach slot)"
    echo ";      line 2  ->  COL=2  (Red slot)"
    echo ";      line 3  ->  COL=3  (Blue slot)"
    echo ";      line 4  ->  COL=4  (Green slot)"
    echo ";  COL=0 is the untouched grey default and is NOT changed"
    echo ";  here."
    echo ";"
    echo ";  Each line should specify a colour in #RRGGBB format. (case"
    echo ";  does not matter).  You must specify exactly 4 colours"
    echo ";  otherwise the update will fail.  Lines starting with ';'"
    echo ";  and blank lines are ignored."
    echo ";"
    echo ";  The first time you run the firmware installer, this file"
    echo ";  will be created and a new set of colours will be"
    echo ";  configured:"
    echo ";      COL=1 becomes a Sony Walkman orange (#FF8922)"
    echo ";      COL=2 becomes a bright summery yellow (#FFE816)"
    echo ";      COL=3 becomes a vulgar pink (#FF5AE6)"
    echo ";      COL=4 becomes a toxic green (#97FF4D)"
    echo ";"
    echo ";  If you edit this file to set your own colours, you will"
    echo ";  need to re-run the installer."
    echo ";"
    for c in ${DEFAULTS}; do echo "${c}"; done
  } > "${CFG}" 2>/dev/null
}

# Parse CFG into globals: COLOURS (space-separated, upper-case), COUNT, BADLINE
COLOURS=""; COUNT=0; BADLINE=""
load_colours() {
  COLOURS=""; COUNT=0; BADLINE=""
  ${TR} -d '\r' < "${CFG}" > /tmp/colours.norm 2>/dev/null || return 1
  while IFS= read -r raw || [ -n "${raw}" ]; do
    line=$(${PRINTF} '%s' "${raw}" | ${SED} 's/^[[:space:]]*//; s/[[:space:]]*$//')
    [ -z "${line}" ] && continue
    case "${line}" in ';'*) continue ;; esac        # comment
    up=$(${PRINTF} '%s' "${line}" | ${TR} 'a-f' 'A-F')
    case "${up}" in
      "#"[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F])
        COLOURS="${COLOURS} ${up}"
        COUNT=$((COUNT + 1)) ;;
      *)
        BADLINE="${line}"
        ${RM} -f /tmp/colours.norm 2>/dev/null
        return 1 ;;
    esac
  done < /tmp/colours.norm
  ${RM} -f /tmp/colours.norm 2>/dev/null
  return 0
}

# ============================================================================

mount -t ext4 -o rw /emmc@android /system

init_log
log "==================================================================="
log "colour installer starting"

# --- target must exist ------------------------------------------------------
if [ ! -f "${HGRM}" ]; then
  log "ERROR: ${HGRM} not found. Aborting, nothing changed."
  finish
  exit 0
fi

# --- make sure we're looking at a binary we understand ----------------------
# Only ever back up a validated-good binary, and self-heal a broken one from
# an existing good backup if we have one.
if validate_layout "${HGRM}"; then
  log "current binary layout looks correct"
elif [ -f "${BACKUP}" ] && validate_layout "${BACKUP}"; then
  log "current binary layout is wrong; restoring from ${BACKUP}"
  ${CP} -p "${BACKUP}" "${HGRM}"
  ${CHMOD} 0755 "${HGRM}"
  if ! validate_layout "${HGRM}"; then
    log "ERROR: restore did not produce a valid layout. Aborting."
    finish
    exit 0
  fi
else
  log "ERROR: unrecognised binary and no valid backup to recover from."
  log "This does not look like the firmware these offsets were made for."
  log "Aborting without changes."
  finish
  exit 0
fi

# --- pristine backup (once) -------------------------------------------------
if [ ! -f "${BACKUP}" ]; then
  ${CP} -p "${HGRM}" "${BACKUP}"
  ${CHMOD} 0644 "${BACKUP}"
  log "backed up pristine binary to ${BACKUP}"
else
  log "backup already exists (${BACKUP}); leaving it untouched"
fi

# --- load colours from internal storage -------------------------------------
if [ -f "${CFG}" ]; then
  log "reading colours from ${CFG}"
  if load_colours; then
    log "parsed ${COUNT} colour(s):${COLOURS}"
  else
    log "ERROR: invalid line in colours.cfg: '${BADLINE}'"
    log "Aborting, binary unchanged. Fix the line and re-run."
    finish
    exit 0
  fi
else
  log "no colours.cfg found; writing defaults"
  if write_default_cfg && [ -f "${CFG}" ]; then
    log "wrote default colours.cfg to ${CFG}"
    load_colours
    log "using default colours:${COLOURS}"
  else
    log "WARNING: could not write to ${CONTENTS}; using built-in defaults"
    COLOURS=" ${DEFAULTS}"
    COUNT=4
  fi
fi

if [ "${COUNT}" -ne 4 ]; then
  log "ERROR: expected exactly 4 colours, found ${COUNT}. Aborting, unchanged."
  finish
  exit 0
fi

# --- patch, verifying each write; roll back on any failure ------------------
log "patching ${HGRM}"
set -- ${COLOURS}
patched_ok=1
for off in ${OFFSETS}; do
  col="$1"; shift
  ${PRINTF} '%s' "${col}" > /tmp/colbytes 2>/dev/null
  ${DD} if=/tmp/colbytes of="${HGRM}" bs=1 seek="${off}" conv=notrunc 2>/dev/null
  got=$(read7 "${HGRM}" "${off}")
  if [ "${got}" = "${col}" ]; then
    log "  offset ${off}: wrote ${col} (verified)"
  else
    log "  offset ${off}: VERIFY FAILED (wanted ${col}, got '${got}')"
    patched_ok=0
  fi
done
${RM} -f /tmp/colbytes 2>/dev/null

if [ "${patched_ok}" -eq 1 ]; then
  ${CHMOD} 0755 "${HGRM}"
  log "all 4 colours patched and verified"
else
  log "one or more writes failed; rolling back from ${BACKUP}"
  ${CP} -p "${BACKUP}" "${HGRM}"
  ${CHMOD} 0755 "${HGRM}"
  if validate_layout "${HGRM}"; then
    log "rollback complete; binary restored to original"
  else
    log "CRITICAL: rollback validation failed. Backup is at ${BACKUP}."
  fi
fi

# --- friendly reminder about the COL= selector ------------------------------
SETT=/contents/CFW/settings.txt
if [ -f "${SETT}" ]; then
  colnow=$(${GREP} '^COL=' "${SETT}" 2>/dev/null | ${SED} 's/[[:space:]]*$//')
  log "current selector in settings.txt: ${colnow:-<none>}"
  case "${colnow}" in
    "COL=0"|"") log "note: COL=0 shows the grey default; set COL=1..4 to see your colours" ;;
  esac
fi

log "colour installer finished"
log "==================================================================="

finish
exit 0
