#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq unzip
# Pin the newest Hermitcraft Server Pack release from Modrinth into
# modpack.json. Optionally pass a Minecraft version to stay on it, e.g.
# `./update-modpack.sh 26.2`.
set -euo pipefail

cd "$(dirname "$0")"
project=yqI9DldQ # https://modrinth.com/modpack/hermitcraft
gameVersion=${1:-}

filter=(--data-urlencode 'loaders=["fabric"]')
if [ -n "$gameVersion" ]; then
  filter+=(--data-urlencode "game_versions=[\"$gameVersion\"]")
fi
release=$(curl -fsSG "https://api.modrinth.com/v2/project/$project/version" "${filter[@]}" |
  jq -e 'sort_by(.date_published) | last')
version=$(jq -r .version_number <<<"$release")
url=$(jq -r '.files[] | select(.primary) | .url' <<<"$release")

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/pack.mrpack"
unzip -p "$tmp/pack.mrpack" modrinth.index.json >"$tmp/index.json"
minecraft=$(jq -r .dependencies.minecraft "$tmp/index.json")
fabricLoader=$(jq -r '.dependencies["fabric-loader"]' "$tmp/index.json")

# The fetcher is a fixed-output derivation over the *unpacked* pack (mods
# downloaded), so its hash is only known after building it once (with a fake
# hash, which is expected to fail).
packHash=$(nix-build --no-out-link -E "
  let
    sources = import ../../npins;
    pkgs = import sources.nixpkgs {
      overlays = [ (import \"\${sources.nix-minecraft}/overlay.nix\") ];
    };
  in
  pkgs.fetchModrinthModpack { url = \"$url\"; packHash = pkgs.lib.fakeHash; }
" 2>&1 | sed -n 's/^ *got: *//p' || true)
if [ -z "$packHash" ]; then
  echo "failed to determine packHash" >&2
  exit 1
fi

jq -n \
  --arg version "$version" \
  --arg url "$url" \
  --arg packHash "$packHash" \
  --arg minecraft "$minecraft" \
  --arg fabricLoader "$fabricLoader" \
  '$ARGS.named' >modpack.json
cat modpack.json
