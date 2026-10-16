#!/usr/bin/env bash
# 🚀 Releases a chart: sets its version in Chart.yaml, commits only that file, tags it <chart>-<version>
# and pushes the branch and the tag. The tag starts .github/workflows/release.yml.
#
#   hack/release.sh
set -euo pipefail

# 🎨 colors
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

die() { printf '%s❌ %s%s\n' "$RED$BOLD" "$*" "$RESET" >&2; exit 1; }

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

charts=()
for dir in charts/*/; do
  [[ -f "$dir/Chart.yaml" ]] && charts+=("$(basename "$dir")")
done
[[ ${#charts[@]} -gt 0 ]] || die "no charts found under charts/ 🤷"

printf '\n%s🎯 What do you want to release?%s\n' "$MAGENTA$BOLD" "$RESET"
select chart in "${charts[@]}"; do
  [[ -n "${chart:-}" ]] && break
  printf '%s👉 pick a number from the list%s\n' "$YELLOW" "$RESET"
done

current="$(awk '/^version:/ {print $2}' "charts/$chart/Chart.yaml")"
printf '\n%s🔢 Version for %s%s%s (current: %s%s%s): %s' \
  "$CYAN$BOLD" "$GREEN" "$chart" "$CYAN" "$YELLOW" "$current" "$CYAN" "$RESET"
read -r version

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] \
  || die "not a version: $version (expected e.g. 0.2.0 or 0.2.0-rc.1)"

tag="$chart-$version"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists 🏷️"

branch="$(git branch --show-current)"
printf '\n%s🏷️  Tag: %s%s%s   🌿 Branch: %s%s%s\n' \
  "$BLUE" "$BOLD$GREEN" "$tag" "$RESET$BLUE" "$BOLD" "$branch" "$RESET"
printf '%s🤔 Commit, tag and push to origin? [y/N] %s' "$MAGENTA$BOLD" "$RESET"
read -r ok
[[ "$ok" == y || "$ok" == Y ]] || { printf '%s🛑 cancelled%s\n' "$YELLOW" "$RESET"; exit 1; }

printf '%s✏️  Setting version %s in charts/%s/Chart.yaml...%s\n' "$CYAN" "$version" "$chart" "$RESET"
python3 - "charts/$chart/Chart.yaml" "$version" <<'PY'
import re, sys
path, version = sys.argv[1], sys.argv[2]
text = open(path).read()
new, n = re.subn(r'^version:.*$', f'version: {version}', text, count=1, flags=re.M)
assert n == 1, f"no version line in {path}"
open(path, 'w').write(new)
PY

# 📦 Commit only this file, whatever else is staged or changed in the working tree.
printf '%s📦 Committing...%s\n' "$CYAN" "$RESET"
git commit -q -m "release: $chart $version" -- "charts/$chart/Chart.yaml"

printf '%s🏷️  Tagging %s...%s\n' "$CYAN" "$tag" "$RESET"
git tag -a "$tag" -m "$tag"

printf '%s⬆️  Pushing %s...%s\n' "$CYAN" "$branch" "$RESET"
git push -q origin "$branch"
printf '%s⬆️  Pushing tag %s...%s\n' "$CYAN" "$tag" "$RESET"
git push -q origin "$tag"

printf '\n%s🎉 Released %s! The release workflow is on its way ✨%s\n' "$GREEN$BOLD" "$tag" "$RESET"
