#!/usr/bin/env bash
# Builds the image, starts Mailcheap with MongoDB (docker-compose.yml) and checks
# what a template user depends on: the dashboard is locked, login works, the main
# pages load, a reader can subscribe, image uploads work without Vercel Blob,
# sending without SES credentials fails cleanly, and data survives a restart.
# Used locally and by CI. Needs docker, curl, python3 and openssl.
set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPTS="$PWD/scripts"
PORT="${SMOKE_PORT:-39200}"
BASE="http://127.0.0.1:$PORT"
EMAIL=admin@example.com
export SMOKE_PORT="$PORT" SMOKE_ADMIN_EMAIL="$EMAIL"
export SMOKE_ADMIN_PASSWORD="smoke-$(openssl rand -hex 12)"
export SMOKE_SESSION_SECRET="$(openssl rand -hex 32)"
WORK="$(mktemp -d)"
COOKIE=""

compose() { docker compose -p mailcheap-smoke -f docker-compose.yml "$@"; }

cleanup() {
  compose down -v --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  compose logs --tail 60 mailcheap >&2 || true
  exit 1
}

start() {
  compose up -d >/dev/null 2>&1 || { compose logs --tail 60 >&2; fail "containers did not start"; }
  for _ in $(seq 1 120); do
    [ "$(status /login)" = 200 ] && return 0
    sleep 1
  done
  fail "server did not answer /login"
}

# Usage: status [curl options] <path>. Prints the HTTP status code.
status() {
  local path="${!#}" opts=("${@:1:$#-1}")
  curl -s -o /dev/null -w '%{http_code}' ${opts[@]+"${opts[@]}"} "$BASE$path" 2>/dev/null || true
}
get() { curl -fsS -H "Cookie: $COOKIE" "$BASE$1"; }
# Usage: page_has <path> <text>. Saves the page first: grep -q on a pipe would cut curl off.
page_has() { get "$1" >"$WORK/page" && grep -qF "$2" "$WORK/page"; }
mongo() {
  compose exec -T mongodb mongosh --quiet -u mongo -p smoke-mongo-password \
    --authenticationDatabase admin mailcheap --eval "$1"
}

# Submits a server-action form the way a browser does without JavaScript.
# Usage: submit_form <page path> <a field name in the form> <name=value>...
submit_form() {
  local page="$1" field="$2" line
  shift 2
  get "$page" >"$WORK/form.html"
  local args=()
  while IFS= read -r line; do args+=(--form-string "$line"); done \
    < <(python3 -I "$SCRIPTS/form-fields.py" "$WORK/form.html" "$field")
  for line in "$@"; do args+=(--form-string "$line"); done
  curl -sS -D "$WORK/headers" -o "$WORK/body" -H "Origin: $BASE" -H "Cookie: $COOKIE" \
    "${args[@]}" "$BASE$page"
}
response_status() { head -n1 "$WORK/headers" | awk '{print $2}'; }
response_header() { grep -i "^$1:" "$WORK/headers" | head -n1 | sed 's/^[^:]*: *//' | tr -d '\r'; }

# Keeps the session cookie in COOKIE when the login succeeds.
login() {
  COOKIE=""
  submit_form /login email "email=$EMAIL" "password=$1" "next=/"
  COOKIE="$(response_header set-cookie | sed 's/;.*//' || true)"
}

upload() {
  curl -sS -X POST -H "Cookie: $COOKIE" -H "content-type: $1" -H "x-file-name: Smoke Test" \
    --data-binary "@$2" "$BASE/api/uploads" | python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("url", ""))'
}

# 1x1 PNG and GIF. GIF URLs go through Next's proxy, PNG URLs skip it, so both are checked.
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\rIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' >"$WORK/pixel.png"
printf 'GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,\x00\x00\x00\x00\x01\x00\x01\x00\x00\x02\x02D\x01\x00;' >"$WORK/pixel.gif"

if [ -z "${SKIP_BUILD:-}" ]; then
  compose build mailcheap
fi
compose down -v --remove-orphans >/dev/null 2>&1 || true

echo "== first boot"
start
echo "Mailcheap $(compose exec -T mailcheap cat /app/.mailcheap-ref)"
[ "$(compose exec -T mailcheap stat -c %U /proc/1)" = node ] || fail "server is not running as the unprivileged user"

echo "== the dashboard needs a login"
for path in / /contacts /campaigns /newsletters /domains /api-keys; do
  [ "$(status "$path")" = 307 ] || fail "$path is reachable without a login"
done
[ "$(status -X POST -H 'content-type: image/png' --data-binary "@$WORK/pixel.png" /api/uploads)" = 401 ] \
  || fail "uploads work without a login"
[ "$(status -X POST -H 'content-type: application/json' -d '{}' /api/v1/contacts)" = 401 ] \
  || fail "the contacts API works without an API key"

echo "== login"
login wrong-password-123
grep -q 'Wrong email or password' "$WORK/body" || fail "a wrong password was not refused"
[ -z "$COOKIE" ] || fail "a wrong password got a session cookie"
login "$SMOKE_ADMIN_PASSWORD"
[ "$(response_status)" = 303 ] || fail "login with the configured password failed (HTTP $(response_status))"
case "$COOKIE" in __Host-mailcheap_session=*) ;; *) fail "login did not set the session cookie" ;; esac

echo "== dashboard pages load"
for path in / /contacts /campaigns /newsletters /newsletters/new /domains /api-keys; do
  [ "$(status -H "Cookie: $COOKIE" "$path")" = 200 ] || fail "$path did not load after login"
done

echo "== create a newsletter"
submit_form /newsletters/new slug "name=Smoke Weekly" slug=smoke-weekly fromName=Smoke \
  fromEmail=news@example.com "postalAddress=1 Test Street" archiveEnabled=on socialLinks= \
  welcomeEnabled=on "welcomeSubject=Welcome" "welcomePreviewText=" "welcomeMarkdown=Thanks for subscribing."
[ "$(response_status)" = 303 ] || fail "creating a newsletter failed (HTTP $(response_status))"
response_header location | grep -Eq '^/newsletters/[0-9a-f]{24}$' || fail "no redirect to the new newsletter"

echo "== a reader subscribes on the public archive"
COOKIE_SAVED="$COOKIE"
COOKIE=""
[ "$(status /archive/smoke-weekly)" = 200 ] || fail "the public archive did not load"
submit_form /archive/smoke-weekly newsletter newsletter=smoke-weekly website= email=reader@example.com
grep -q 'You&#x27;re in' "$WORK/body" || fail "subscribing did not succeed"
COOKIE="$COOKIE_SAVED"
[ "$(mongo 'db.contacts.countDocuments({ email: "reader@example.com", status: "active" })')" = 1 ] \
  || fail "the subscriber was not saved in MongoDB"
page_has /contacts 'reader@example.com' || fail "the subscriber is not listed on the contacts page"

echo "== sending without SES credentials fails cleanly"
page_has /domains 'Could not reach SES' || fail "the domains page did not report the missing SES credentials"
for _ in $(seq 1 30); do
  [ "$(mongo 'db.messages.countDocuments({ kind: "welcome", status: "failed" })')" = 1 ] && break
  sleep 1
done
[ "$(mongo 'db.messages.countDocuments({ kind: "welcome", status: "failed" })')" = 1 ] \
  || fail "the welcome email was not recorded as failed"
[ "$(status /login)" = 200 ] || fail "the server stopped answering after a failed send"

echo "== image uploads use the volume"
png_url="$(upload image/png "$WORK/pixel.png")"
gif_url="$(upload image/gif "$WORK/pixel.gif")"
case "$png_url" in "$BASE/uploads/images/smoke-test-"*.png) ;; *) fail "PNG upload failed: '$png_url'" ;; esac
case "$gif_url" in "$BASE/uploads/images/smoke-test-"*.gif) ;; *) fail "GIF upload failed: '$gif_url'" ;; esac
for url in "$png_url" "$gif_url"; do
  curl -fsS -o "$WORK/download" "$url" || fail "$url is not public"
  cmp -s "$WORK/download" "$WORK/pixel.${url##*.}" || fail "$url returned different bytes"
done
[ "$(status /uploads/images/missing-0000.png)" = 404 ] || fail "a missing upload did not return 404"
[ "$(status '/uploads/images/..%2F..%2F..%2Fetc%2Fpasswd')" = 404 ] || fail "upload paths can escape the folder"

echo "== restart keeps the data"
compose down >/dev/null 2>&1
start
[ "$(status -H "Cookie: $COOKIE" /)" = 200 ] || fail "the session did not survive a restart"
login "$SMOKE_ADMIN_PASSWORD"
[ "$(response_status)" = 303 ] || fail "login failed after restart"
[ "$(mongo 'db.contacts.countDocuments({ email: "reader@example.com", status: "active" })')" = 1 ] \
  || fail "the subscriber is gone from MongoDB after restart"
page_has /contacts 'reader@example.com' || fail "the subscriber is not listed after restart"
[ "$(status /archive/smoke-weekly)" = 200 ] || fail "the archive is gone after restart"
for url in "$png_url" "$gif_url"; do
  curl -fsS -o "$WORK/download" "$url" || fail "$url is gone after restart"
  cmp -s "$WORK/download" "$WORK/pixel.${url##*.}" || fail "$url changed after restart"
done

echo "PASS"
