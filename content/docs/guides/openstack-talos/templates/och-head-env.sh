# och-head-env.sh — the HEAD NODE entry point. Source this one; it finds the rest.
#
#   head$ source ~/och-head-env.sh
#   head$ echo '[ -f ~/och-head-env.sh ] && . ~/och-head-env.sh' >> ~/.bashrc
#
# It loads, in this order, whichever of these exist beside it in $HOME:
#
#   och-head-vars-env.sh        §7.1    the eleven OCH_*, generated on the devbox
#                                      from och-vars-env.sh and scp'd across.
#                                      §7.12 appends OCH_EXT_IF to it
#   och-head-talos-env.sh       §12.3   TALOSCONFIG and KUBECONFIG
#   och-head-inference-env.sh   §16.3a  och_infer, och_ask — the model endpoint
#
# ⚠ EACH IS INERT UNTIL THE SECTION THAT WRITES IT. That is the point of the
# `if [ -f … ]` guards: this file is copied to the head in §7, five sections
# before the first of its dependants exists, and it must not complain about
# files the reader has not reached yet.
#
# ═════════════════════════════════════════════════════════════════════════════
# THE NAMING RULE
# ═════════════════════════════════════════════════════════════════════════════
#
#   och-*         this rig's files, on the DEVBOX      (~/och/)
#   och-head-*    this rig's files, on the HEAD node   (~/)
#   *-env.sh     SOURCE it.  Anything else you RUN.
#
# `ls ~/och-head-*-env.sh` is therefore a complete inventory of what a login
# shell on the head loads. On real hardware these files will sit in a home directory
# next to somebody else's, which is the reason for the prefix.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHY THIS FILE EXISTS SEPARATELY FROM THE VALUES
# ═════════════════════════════════════════════════════════════════════════════
#
# och-head-vars-env.sh is GENERATED (§7.1) and appended to (§7.12). Keeping the
# hooks out of it means it can be regenerated from the devbox at any point
# without losing them — and that §12 and §16 add a file rather than edit one.
#
# Before this split, §16's helper was hooked into §12's file, which was hooked
# into §7's. A three-deep chain works, and it is invisible: the only way to
# know what a login shell actually loads is to open three files in order.
#
# ~ rather than $HOME, because §7.1 writes the head's files from a heredoc on
# the DEVBOX — and a heredoc expands $HOME to the devbox's home directory.

for _och_f in och-head-vars-env.sh och-head-talos-env.sh och-head-inference-env.sh; do
  if [ -f "$HOME/$_och_f" ]; then
    . "$HOME/$_och_f"
  fi
done
unset _och_f

# ⚠ Legacy names, from before the och-head-* convention. A half-done rename
# leaves the old file on disk with nothing sourcing it, and the only symptom is
# an unset variable — `kubectl` saying `localhost:8080` two sections later.
# Interactive shells only: stray stdout in a non-interactive shell breaks the
# `ssh head '…'` commands §§10–16 use.
for _och_old in head-env.sh talos-env.sh och-inference-env.sh; do
  if [ -f "$HOME/$_och_old" ]; then
    case $- in *i*) printf 'och: WARNING — ~/%s is a pre-rename name and is NOT sourced. See §7.1.\n' \
                           "$_och_old" ;; esac
  fi
done
unset _och_old
