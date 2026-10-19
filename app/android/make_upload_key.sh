#!/usr/bin/env bash
# Creates Hawk's Play upload key, once, and the key.properties the release
# build reads (see app/build.gradle.kts).
#
#   android/make_upload_key.sh                 # keystore in ~/hawk-keys/
#   android/make_upload_key.sh /path/key.jks   # or wherever you choose
#
# Play re-signs every release with its own app signing key; this key only
# proves an upload came from you. Losing it is recoverable (Play Console →
# App integrity → request upload key reset) but slow, so back up the
# keystore AND its password somewhere that is not this laptop.
#
# Never overwrites: an existing key.properties or keystore stops the script.

set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
props="$here/key.properties"
store="${1:-$HOME/hawk-keys/upload-keystore.jks}"
alias_name="upload"

if [[ -e "$props" ]]; then
  echo "Stopped: $props already exists. Hawk already has an upload key." >&2
  exit 1
fi
if [[ -e "$store" ]]; then
  echo "Stopped: a keystore already exists at $store." >&2
  exit 1
fi

keytool_bin="$(command -v keytool || true)"
studio_keytool="/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool"
if [[ -z "$keytool_bin" && -x "$studio_keytool" ]]; then
  keytool_bin="$studio_keytool"
fi
if [[ -z "$keytool_bin" ]]; then
  echo "Stopped: keytool not found. Install a JDK or Android Studio." >&2
  exit 1
fi

read -rsp "Choose a password for the upload key (8+ characters): " password
echo
read -rsp "Type it again: " again
echo
if [[ "$password" != "$again" ]]; then
  echo "Stopped: the two passwords differ." >&2
  exit 1
fi
if (( ${#password} < 8 )); then
  echo "Stopped: use at least 8 characters." >&2
  exit 1
fi
# key.properties is a Java properties file: a backslash starts an escape and
# would silently change the password Gradle reads.
if [[ "$password" == *\\* ]]; then
  echo "Stopped: the password cannot contain a backslash." >&2
  exit 1
fi

mkdir -p "$(dirname "$store")"
chmod 700 "$(dirname "$store")"

# The password travels by environment, not argv, so it never shows in `ps`.
export HAWK_UPLOAD_PASSWORD="$password"
"$keytool_bin" -genkeypair \
  -keystore "$store" -storetype PKCS12 \
  -alias "$alias_name" -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Hawk" \
  -storepass:env HAWK_UPLOAD_PASSWORD \
  -keypass:env HAWK_UPLOAD_PASSWORD
chmod 600 "$store"

umask 077
cat > "$props" <<EOF
storePassword=$password
keyPassword=$password
keyAlias=$alias_name
storeFile=$store
EOF
chmod 600 "$props"

echo
echo "Upload key created:"
echo "  keystore        $store"
echo "  key.properties  $props"
echo
echo "Fingerprints (public, safe to paste into Firebase):"
"$keytool_bin" -list -v -keystore "$store" -alias "$alias_name" \
  -storepass:env HAWK_UPLOAD_PASSWORD | grep -E "^\s*SHA(1|256):"
unset HAWK_UPLOAD_PASSWORD
echo
echo "Next: back up the keystore and its password, then add both"
echo "fingerprints to Firebase → Project settings → the Android app."
