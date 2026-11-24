#!/bin/zsh
# Builds one signed .prg per watch into out/.  Usage: ./build.sh [device ...]   (default: all in manifest)
set -e
cd "${0:A:h}"
SDK=$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")
KEY="$HOME/.connectiq-keys/developer_key.der"
TOKF="$HOME/.connectiq-keys/feeds_api_token"
URLF="$HOME/.connectiq-keys/feeds_api_url"   # your Worker URL, one line (not in the repo)
URL="$( [ -f "$URLF" ] && tr -d '\n' < "$URLF" )"
OUTDIR=out
if [ "${RELEASE:-0}" = "1" ]; then URL=""; OUTDIR=out/release; fi

# private config, generated so the token never lives in the source tree
mkdir -p source-private "$OUTDIR"
cat > source-private/Config.mc <<EOF
(:background :glance)
module Config {
    const URL = "$URL";
    const TOKEN = "$( [ -n "$URL" ] && tr -d '\n' < "$TOKF" )";
}
EOF

devices=("$@")
if [ ${#devices} -eq 0 ]; then
  devices=($(grep -h -o 'product id="[^"]*"' manifest.xml manifest-widget.xml | cut -d'"' -f2))
fi
for d in $devices; do
  if [ ! -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Devices/$d" ]; then
    echo "skip $d (device not downloaded in SDK Manager)"; continue
  fi
  echo "== $d"
  J=monkey.jungle; grep -q "product id=\"$d\"" manifest-widget.xml && J=widget.jungle
  "$SDK/bin/monkeyc" -d "$d" -f $J -o "$OUTDIR/Feeds-$d.prg" -y "$KEY" -w
done
ls -la "$OUTDIR"
