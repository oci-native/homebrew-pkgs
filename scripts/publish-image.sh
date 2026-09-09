#!/usr/bin/env bash
# Build and push the OCI image for one containerized app.
#
# The image tag comes from the app's cask `version` stanza, so a cask bump
# and an image publish always agree on the version.
#
# Usage: publish-image.sh <app> [--push]
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <app> [--push]" >&2
  exit 64
fi

app=$1
push=${2:-}
registry=${REGISTRY:-8gcr.container-registry.dev/oci-native}

containerfile="containers/$app/Containerfile"
[[ -f "$containerfile" ]] || { echo "error: no $containerfile" >&2; exit 66; }

cask_file=$(find Casks -name "$app.rb" | head -n 1)
[[ -n "$cask_file" ]] || { echo "error: no cask for $app" >&2; exit 66; }
version=$(sed -n 's/^ *version "\(.*\)"$/\1/p' "$cask_file")
[[ -n "$version" ]] || { echo "error: no version in $cask_file" >&2; exit 65; }

if command -v podman >/dev/null 2>&1; then engine=podman; else engine=docker; fi

context=$(mktemp -d)
trap 'rm -rf "$context"' EXIT
cp "containers/$app/Containerfile" "$context/"
if [[ -x "containers/$app/prepare.sh" ]]; then
  "containers/$app/prepare.sh" "$version" "$context"
fi

image="$registry/$app"
"$engine" build -t "$image:$version" -t "$image:latest" "$context"
echo "built $image:$version"

if [[ "$push" == "--push" ]]; then
  "$engine" push "$image:$version"
  "$engine" push "$image:latest"
  echo "pushed $image:$version and :latest"
fi
