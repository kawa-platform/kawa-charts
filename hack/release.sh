#!/usr/bin/env bash
# Releases a chart: sets its version in Chart.yaml, commits only that file, tags it <chart>-<version>
# and pushes the branch and the tag. The tag starts .github/workflows/release.yml.
#
#   hack/release.sh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

charts=()
for dir in charts/*/; do
  [[ -f "$dir/Chart.yaml" ]] && charts+=("$(basename "$dir")")
done
[[ ${#charts[@]} -gt 0 ]] || { echo "no charts found under charts/" >&2; exit 1; }

echo "What do you want to release?"
select chart in "${charts[@]}"; do
  [[ -n "${chart:-}" ]] && break
  echo "pick a number from the list"
done

current="$(awk '/^version:/ {print $2}' "charts/$chart/Chart.yaml")"
read -r -p "Version for $chart (current: $current): " version

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "not a version: $version (expected e.g. 0.2.0 or 0.2.0-rc.1)" >&2
  exit 1
fi

tag="$chart-$version"
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "tag $tag already exists" >&2
  exit 1
fi

branch="$(git branch --show-current)"
read -r -p "Commit, tag $tag and push $branch to origin? [y/N] " ok
[[ "$ok" == y || "$ok" == Y ]] || { echo "cancelled"; exit 1; }

python3 - "charts/$chart/Chart.yaml" "$version" <<'PY'
import re, sys
path, version = sys.argv[1], sys.argv[2]
text = open(path).read()
new, n = re.subn(r'^version:.*$', f'version: {version}', text, count=1, flags=re.M)
assert n == 1, f"no version line in {path}"
open(path, 'w').write(new)
PY

# Commit only this file, whatever else is staged or changed in the working tree.
git commit -m "release: $chart $version" -- "charts/$chart/Chart.yaml"
git tag -a "$tag" -m "$tag"
git push origin "$branch"
git push origin "$tag"
echo "pushed $tag"
