#!/bin/sh
# Runs during the Docker build. Replaces Vercel Blob with files on the volume:
#   - lib/blob.js writes uploads to $UPLOADS_DIR and returns APP_URL/uploads/...
#   - app/uploads/[...path]/route.js serves them
#   - proxy.js lets /uploads/ through without a session, like Blob's public CDN
# Each step checks that upstream still looks the way the patch expects and
# fails the build otherwise, so a breaking upstream change never ships.
set -eu

SRC="$1"
HERE="$(cd "$(dirname "$0")" && pwd)"

fail() { echo "patches/apply.sh: $*" >&2; echo "patches/apply.sh: upstream changed, update the patch" >&2; exit 1; }

grep -qF 'export async function putImage(pathname, bytes, contentType)' "$SRC/lib/blob.js" \
  || fail "lib/blob.js no longer exports putImage(pathname, bytes, contentType)"
grep -qF 'import { putImage } from "@/lib/blob";' "$SRC/app/api/uploads/route.js" \
  || fail "app/api/uploads/route.js no longer uses putImage from lib/blob"
grep -qF 'putImage(`images/${name}.${type.extension}`' "$SRC/app/api/uploads/route.js" \
  || fail "app/api/uploads/route.js changed how it names uploads"
grep -q '^const PUBLIC_PATHS = \[$' "$SRC/proxy.js" \
  || fail "proxy.js no longer has a PUBLIC_PATHS list"
[ ! -e "$SRC/app/uploads" ] || fail "upstream now has its own app/uploads"

cp "$HERE/lib/blob.js" "$SRC/lib/blob.js"
mkdir -p "$SRC/app/uploads/[...path]"
cp "$HERE/app/uploads/[...path]/route.js" "$SRC/app/uploads/[...path]/route.js"
sed -i 's|^const PUBLIC_PATHS = \[$|&\n\t/^\\/uploads\\//,|' "$SRC/proxy.js"

grep -qF '/^\/uploads\//,' "$SRC/proxy.js" || fail "could not add /uploads/ to PUBLIC_PATHS in proxy.js"
echo "patches/apply.sh: image uploads now use the volume"
