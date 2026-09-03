#!/usr/bin/env bash
#
# Login onboarding for the devbox. Answers one question on the first terminal of a container:
# "which of the logins this project needs are not set up yet, and what do I type to fix each?"
#
# WHAT IT READS: DEVBOX_AUTH, a comma-separated list of tool NAMES (e.g. "git,gh,docker") set in
# docker-compose.yml when the box is generated. Names only. No secret, token, key, or credential is
# ever passed in, read out, stored, or transmitted by this script - it asks each tool "are you
# signed in?", prints yes or no, and exits. The user then signs in themselves, inside the box.
#
# WHY IT EXISTS: a fresh container has none of the host's logins. Without this, the user finds out
# by hitting a failure mid-task - a push that 403s, a CLI that exits 1 with no explanation. This
# turns that into a checklist on the first terminal, before any work starts.
#
# HOW TO EXTEND: add a case to check() and the matching case to fix(). Keep every check cheap and
# offline-tolerant - this runs on the first terminal of every container, and a check that hangs on
# a network timeout makes the whole editor feel broken.

set -uo pipefail

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; yellow=$'\033[33m'; off=$'\033[0m'

# Three states, because "not installed" and "not signed in" need different handling: a tool this
# image does not carry is not this project's problem and is skipped in silence, while a tool that
# is present but signed out is exactly what the user needs to be told about.
#   0 = signed in
#   1 = installed but not signed in
#   2 = not installed here (skip silently)
check() {
    case "$1" in
        # `gh auth status` exits non-zero when no account is active. Output is suppressed because
        # this function's contract is its exit code; the caller does all the printing.
        gh)      command -v gh >/dev/null || return 2; gh auth status >/dev/null 2>&1 ;;
        glab)    command -v glab >/dev/null || return 2; glab auth status >/dev/null 2>&1 ;;
        # Checked by the PRESENCE of a credentials file, never by reading one. Two paths because
        # the CLI has used both locations.
        claude)  command -v claude >/dev/null || return 2
                 [ -s "${HOME}/.claude/.credentials.json" ] || [ -s "${HOME}/.claude.json" ] ;;
        # Not a login, but the same class of surprise: an unset user.email makes commits land under
        # a machine-generated identity nobody recognises.
        git)     [ -n "$(git config --get user.email 2>/dev/null)" ] ;;
        # `docker info` is the cheapest call that proves the daemon is actually reachable through
        # the mounted socket - a permission question rather than a login question.
        docker)  command -v docker >/dev/null || return 2; docker info >/dev/null 2>&1 ;;
        npm)     command -v npm >/dev/null || return 2; npm whoami >/dev/null 2>&1 ;;
        aws)     command -v aws >/dev/null || return 2; aws sts get-caller-identity >/dev/null 2>&1 ;;
        gcloud)  command -v gcloud >/dev/null || return 2
                 [ -n "$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null)" ] ;;
        # An unknown name is treated as "not installed" rather than as an error: a typo in
        # DEVBOX_AUTH must not break the terminal the user just opened.
        *)       return 2 ;;
    esac
}

# The exact command to run, printed for the user to type themselves. This script never starts a
# login flow on their behalf.
fix() {
    case "$1" in
        gh)      echo "gh auth login" ;;
        glab)    echo "glab auth login" ;;
        claude)  echo "claude  (then /login)" ;;
        git)     echo "git config --global user.email you@example.com  (or mount your ~/.gitconfig)" ;;
        docker)  echo "sudo docker (Docker Desktop hands the socket over root-owned), or check the mount" ;;
        npm)     echo "npm login" ;;
        aws)     echo "aws configure  (or aws sso login)" ;;
        gcloud)  echo "gcloud auth login" ;;
        *)       echo "unknown target" ;;
    esac
}

IFS=',' read -ra targets <<< "${DEVBOX_AUTH:-}"
# Nothing declared means nothing to report. Silence is correct here: plenty of work in the box
# needs no login at all.
[ ${#targets[@]} -eq 0 ] && exit 0

pending=0
for t in "${targets[@]}"; do
    t="$(echo "$t" | tr -d '[:space:]')"
    [ -z "$t" ] && continue
    check "$t"
    case $? in
        0) printf '  %s✓%s %s\n' "$green" "$off" "$t" ;;
        1) printf '  %s✗%s %s %s→ %s%s\n' "$yellow" "$off" "$t" "$dim" "$(fix "$t")" "$off"
           pending=$((pending + 1)) ;;
        *) ;;
    esac
done

[ "$pending" -gt 0 ] && printf '\n%sSign in to the above inside this box%s - credentials created here stay here.\n\n' "$bold" "$off"

# Always succeeds. This is a report, not a gate: a missing login must not make the shell that ran
# it look like it failed.
exit 0
