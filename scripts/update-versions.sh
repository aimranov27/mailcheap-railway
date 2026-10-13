#!/usr/bin/env bash
# Pins the Dockerfile to the latest commit on Mailcheap's main branch.
#
# Mailcheap has no releases or tags, so the template follows main. The update
# workflow runs this once a day, which caps "update available" notices for
# template users at one a day, and only when upstream actually changed.
#
# Prints a markdown summary of the change; prints nothing if nothing changed.
set -euo pipefail

DOCKERFILE="$(dirname "$0")/../Dockerfile"
REPO=marclou/mailcheap
BRANCH="${MAILCHEAP_BRANCH:-main}"

old="$(sed -n 's/^ARG MAILCHEAP_REF=//p' "$DOCKERFILE")"
new="$(git ls-remote "https://github.com/$REPO.git" "refs/heads/$BRANCH" | cut -f1)"

[[ "$new" =~ ^[0-9a-f]{40}$ ]] || { echo "Could not read the latest $BRANCH commit of $REPO" >&2; exit 1; }
[ "$old" = "$new" ] && exit 0

sed -i.bak "s/^ARG MAILCHEAP_REF=.*/ARG MAILCHEAP_REF=$new/" "$DOCKERFILE" && rm -f "$DOCKERFILE.bak"
printf -- '- Mailcheap: `%s` → `%s` ([changes](https://github.com/%s/compare/%s...%s))\n' \
  "${old:0:12}" "${new:0:12}" "$REPO" "$old" "$new"
