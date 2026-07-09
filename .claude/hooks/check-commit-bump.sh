#!/usr/bin/env bash
# Okanvil release guard (PreToolUse / Bash / `git commit`).
#
# Every push to main cuts a release, and the bump level comes from a keyword in the
# commit message. Two mistakes are silent and expensive, so we catch them here:
#
#   1. A docs/CI-only commit with no [skip]   -> ships a pointless version + Discord ping.
#   2. A hand-edited `## Version:` in the .toc -> the tag is the source of truth; the
#      Action overwrites it anyway, so the edit only makes local builds lie.
#
# "No keyword" is the VALID DEFAULT (patch), so we never block for a missing keyword.
# We only block the two cases above, and we say exactly how to fix it.
#
# NOTE: this machine has no `jq` (verified) -- we use python for JSON in and out.
#
# Exit 0 with no output = allow. JSON with permissionDecision "deny" = block.

set -uo pipefail

PY="$(command -v python || command -v python3 || true)"
[ -z "$PY" ] && exit 0

payload="$(cat)"

# Pull .tool_input.command out of the hook payload without jq.
cmd="$(printf '%s' "$payload" | "$PY" -c 'import sys,json
try: print(json.load(sys.stdin).get("tool_input",{}).get("command",""))
except Exception: print("")')"

# Only care about an actual commit (the `if` filter should already ensure this).
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

# Amend/fixup rewrites don't create a new release on their own -- let them through.
case "$cmd" in
  *--amend*|*--fixup*) exit 0 ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -z "$repo_root" ] && exit 0
cd "$repo_root" || exit 0

deny() {
  REASON="$1" "$PY" -c 'import os,json
print(json.dumps({"hookSpecificOutput":{
  "hookEventName":"PreToolUse",
  "permissionDecision":"deny",
  "permissionDecisionReason":os.environ["REASON"]}}))'
  exit 0
}

# ---- 1. .toc version hand-edited? -------------------------------------------
if ! git diff --cached --quiet -- Okanvil/Okanvil.toc 2>/dev/null; then
  if git diff --cached -U0 -- Okanvil/Okanvil.toc 2>/dev/null | grep -qE '^[+-]## Version:'; then
    deny "This commit edits '## Version:' in Okanvil/Okanvil.toc. The git tag is the single source of truth -- the GitHub Action stamps the .toc at build time. Hand-editing it only makes local builds report the wrong version. Restore that line (git checkout HEAD -- Okanvil/Okanvil.toc) and commit again."
  fi
fi

# ---- 2. docs/CI-only commit without [skip]? ---------------------------------
staged="$(git diff --cached --name-only 2>/dev/null || true)"
[ -z "$staged" ] && exit 0   # nothing staged; git will complain on its own

ships_code=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    docs/*|README.md|CLAUDE.md|.github/*|.claude/*|.gitignore|*.md) ;;
    *) ships_code=1; break ;;
  esac
done <<< "$staged"

[ "$ships_code" -eq 1 ] && exit 0   # real code -> any bump level is fine

msg="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"
case "$msg" in
  *"[skip"*|*"[no-release]"*) exit 0 ;;
esac

deny "This commit touches only docs/CI (nothing under Okanvil/), but the message has no [skip] keyword. Every push to main cuts a release, so this would publish a pointless version bump and ping Discord. Add [skip] to the commit message. See CLAUDE.md -> 'Commit messages control the release'."
