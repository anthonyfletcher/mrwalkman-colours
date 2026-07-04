#!/bin/sh
#
# ============================================================================
#  HgrmMediaPlayerApp UI colour patcher  --  UNINSTALL
#  Packaged with unknown321/nw-installer
# ============================================================================
#
#  Restores the original HgrmMediaPlayerApp saved by the installer:
#    1. Checks HgrmMediaPlayerApp_BEFORE_COL exists and looks sane.
#    2. Saves the current (patched) binary as HgrmMediaPlayerApp_BEFORE_COL_UNINSTALL.
#    3. Removes the current binary and restores the pristine backup.
#    4. Verifies the restore, then tidies up the backups.
#    5. Logs to /contents/COL/colours.log.
#
#  colours.cfg and colours.log are left in place.
# ============================================================================

BB=/xbin/busybox
CP="${BB} cp"
RM="${BB} rm"
CHMOD="${BB} chmod"
MKDIR="${BB} mkdir"
DD="${BB} dd"
PRINTF="${BB} printf"
SED="${BB} sed"

HGRM=/system/vendor/sony/bin/HgrmMediaPlayerApp
BACKUP=/system/vendor/sony/bin/HgrmMediaPlayerApp_BEFORE_COL
CURBACK=/system/vendor/sony/bin/HgrmMediaPlayerApp_BEFORE_COL_UNINSTALL

CONTENTS=/contents
COLDIR="${CONTENTS}/COL"
LOG="${COLDIR}/colours.log"

OFFSETS="3983112 3983120 3983128 3983136"

init_log() {
  for t in "${LOG}" "${LOG_FILE}" "/tmp/colours.log"; do
    [ -n "${t}" ] || continue
    ${MKDIR} -p "$(${BB} dirname "${t}")" 2>/dev/null
    if ( echo "" >> "${t}" ) 2>/dev/null; then LOG="${t}"; return 0; fi
  done
  LOG=/dev/null
}
log()    { echo "$(date) $1" >> "${LOG}" 2>/dev/null; }
finish() { sync; umount /system 2>/dev/null; }
read7()  { ${DD} if="$1" bs=1 skip="$2" count=7 2>/dev/null; }

validate_layout() {
  for off in ${OFFSETS}; do
    cur=$(read7 "$1" "${off}")
    case "${cur}" in
      "#"[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) : ;;
      *) return 1 ;;
    esac
  done
  return 0
}

# ============================================================================

mount -t ext4 -o rw /emmc@android /system

init_log
log "==================================================================="
log "colour uninstaller starting"

# --- must have a backup to restore ------------------------------------------
if [ ! -f "${BACKUP}" ]; then
  log "no backup (${BACKUP}) found; nothing to restore. Leaving binary as-is."
  finish
  exit 0
fi

# --- refuse to restore a backup that doesn't match this firmware's layout ----
# (guards against a backup left over from a different base firmware)
if ! validate_layout "${BACKUP}"; then
  log "WARNING: ${BACKUP} does not contain the expected colour layout."
  log "It may be from a different firmware. Aborting to avoid a mismatched"
  log "restore. If you are sure, delete ${BACKUP} by hand and reinstall."
  finish
  exit 0
fi

# --- save the current patched state, then restore ---------------------------
if [ -f "${HGRM}" ]; then
  ${CP} -p "${HGRM}" "${CURBACK}"
  log "saved current (patched) binary to ${CURBACK}"
  ${RM} -f "${HGRM}"
  log "removed patched ${HGRM}"
fi

${CP} -p "${BACKUP}" "${HGRM}"
${CHMOD} 0755 "${HGRM}"
log "restored original binary from ${BACKUP}"

# --- verify and tidy up -----------------------------------------------------
if validate_layout "${HGRM}"; then
  log "restore verified"
  ${RM} -f "${BACKUP}"  && log "removed ${BACKUP}"
  ${RM} -f "${CURBACK}" && log "removed ${CURBACK}"
  log "uninstall complete"
else
  log "ERROR: restored binary failed validation."
  log "Keeping ${BACKUP} and ${CURBACK} for safety. Do not reboot into the"
  log "player until this is resolved."
fi

log "colour uninstaller finished"
log "==================================================================="

finish
exit 0
