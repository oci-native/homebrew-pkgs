#!/usr/bin/env bash
# Bump a cask whose artifact comes from a Debian apt repository.
#
# Reads the apt Packages index (which already carries Version + SHA256 for
# every pool file), picks the newest version of the given package, and
# rewrites the cask's `version` and `sha256` stanzas in place. No artifact
# download is needed.
#
# Usage: bump-apt-cask.sh <cask-file> <packages-index-url> <package-name>
#
# When run inside GitHub Actions, appends `updated` and `version` to
# $GITHUB_OUTPUT for downstream steps.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <cask-file> <packages-index-url> <package-name>" >&2
  exit 64
fi

cask_file=$1
packages_url=$2
package=$3

[[ -f "$cask_file" ]] || { echo "error: no such cask file: $cask_file" >&2; exit 66; }

latest=$(curl -fsSL "$packages_url" | awk -v pkg="$package" '
  $1 == "Package:" { in_pkg = ($2 == pkg) }
  in_pkg && $1 == "Version:" { version = $2 }
  in_pkg && $1 == "SHA256:" { print version, $2 }
' | sort -V | tail -n 1)

[[ -n "$latest" ]] || { echo "error: package $package not found in index" >&2; exit 65; }

read -r version sha256 <<<"$latest"
current=$(sed -n 's/^ *version "\(.*\)"$/\1/p' "$cask_file")

emit() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s\n' "updated=$1" "version=$version" >>"$GITHUB_OUTPUT"
  return 0
}

if [[ "$current" == "$version" ]]; then
  echo "$cask_file: up to date ($current)"
  emit false
  exit 0
fi

sed -i \
  -e "s/^\( *version \)\".*\"$/\1\"$version\"/" \
  -e "s/^\( *sha256 \)\".*\"$/\1\"$sha256\"/" \
  "$cask_file"

echo "$cask_file: bumped $current -> $version"
emit true
