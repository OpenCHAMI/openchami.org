# och-env.sh — the DEVBOX entry point. Source this one; it finds the rest.
#
#   devbox$ mkdir -p ~/och
#   devbox$ cp <this-tutorial>/templates/och-env.sh         ~/och/och-env.sh
#   devbox$ cp <this-tutorial>/templates/och-vars-env.sh    ~/och/och-vars-env.sh
#   devbox$ cp <this-tutorial>/templates/och-helpers-env.sh ~/och/och-helpers-env.sh
#   devbox$ source ~/och/och-env.sh
#
# and once, so it comes back at every login (§3):
#
#   devbox$ echo '[ -f ~/och/och-env.sh ] && . ~/och/och-env.sh' >> ~/.bashrc
#
# ═════════════════════════════════════════════════════════════════════════════
# THE NAMING RULE
# ═════════════════════════════════════════════════════════════════════════════
#
#   och-*         this rig's files, on the DEVBOX      (~/och/)
#   och-head-*    this rig's files, on the HEAD node   (~/)
#   *-env.sh     SOURCE it.  Anything else you RUN — och-status.sh is a script.
#
# So `ls ~/och/*-env.sh` is a complete list of what a login shell loads, and
# nothing outside that list can change your environment behind your back. On a
# shared machine the prefix also says which files are this rig's and which are
# somebody else's.
#
# ═════════════════════════════════════════════════════════════════════════════
# WHICH FILE IS SAFE TO RE-COPY, AND WHICH IS NOT
# ═════════════════════════════════════════════════════════════════════════════
#
#   och-env.sh (this file)   a dispatcher. No values at all.  ALWAYS safe
#   och-helpers-env.sh       only och_* functions.             ALWAYS safe
#   och-vars-env.sh          YOURS — every §3 answer, plus what §6.5 and §6.6
#                           append later.                    NEVER re-copy
#
# 🛑 IF YOU ARE UPGRADING FROM A SINGLE-FILE och-env.sh, RENAME BEFORE YOU COPY.
#    The old och-env.sh held your values; this one does not. Copying this over
#    it destroys §3's answers. The order is: mv first, cp second.
#
#      devbox$ mv ~/och/och-env.sh ~/och/och-vars-env.sh          # your values
#      devbox$ mv ~/och/och-helpers.sh ~/och/och-helpers-env.sh   # if present
#      devbox$ cp <this-tutorial>/templates/och-env.sh ~/och/   # the dispatcher
#      devbox$ source ~/och/och-env.sh && och_check
#
# WHY A DISPATCHER AT ALL. So that adding a file later is a `cp` and not an
# edit to something you have filled in. The head node has the same shape and
# needs it more: §12 and §16 each drop a new file next to och-head-env.sh, and
# neither section has to touch a file that already works.

OCH_DIR="${OCH_DIR:-$HOME/och}"

# Order matters: values first, then the helpers that read them.
for _och_f in och-vars-env.sh och-helpers-env.sh; do
  if [ -f "$OCH_DIR/$_och_f" ]; then
    . "$OCH_DIR/$_och_f"
  else
    # Interactive shells only. This file is sourced from .bashrc, and stray
    # stdout in a NON-interactive shell breaks scp, rsync and `ssh host '…'`
    # in ways that name neither this file nor the shell.
    case $- in *i*) printf 'och: %s/%s not found — cp <this-tutorial>/templates/%s %s/\n' \
                           "$OCH_DIR" "$_och_f" "$_och_f" "$OCH_DIR" ;; esac
  fi
done
unset _och_f

# ⚠ A HALF-DONE RENAME IS THE WORST STATE THIS FILE CAN BE IN: the old file is
# still on disk, nothing sources it, and the only symptom is an unset variable
# three sections later. So say it out loud rather than leave it to be deduced.
for _och_old in och-helpers.sh; do
  if [ -f "$OCH_DIR/$_och_old" ]; then
    case $- in *i*) printf 'och: WARNING — %s/%s is a pre-rename name and is NOT sourced. Delete it.\n' \
                           "$OCH_DIR" "$_och_old" ;; esac
  fi
done
unset _och_old
