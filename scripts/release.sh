#!/usr/bin/env bash
# 🚀 Releases kawa. Asks which components (gateway, studio, operator) to release and how to bump each,
# releases them one at a time with their own `make release VERSION=…` and waits for each Release
# workflow to pass. Then pins the released versions in charts/kawa, bumps its version, commits, tags
# kawa-<version> and pushes, which starts .github/workflows/release.yml.
#
#   make release
#
# Component checkouts are expected next to this repo (override with KAWA_ROOT).
# charts/kawa/values.yaml pins each image on one marked line, which is what gets rewritten:
#   tag: "0.1.0"  # kawa-release: gateway
#
# Written for the bash 3.2 that ships with macOS.
set -euo pipefail

# 🎨 colors
BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
YELLOW=$'\033[33m'; BLUE=$'\033[34m'; MAGENTA=$'\033[35m'; CYAN=$'\033[36m'; RESET=$'\033[0m'

die()  { printf '%s❌ %s%s\n' "$RED$BOLD" "$*" "$RESET" >&2; exit 1; }
info() { printf '%s%s%s\n' "$CYAN" "$*" "$RESET"; }

ORG=kawa-platform
COMPONENTS=(gateway studio operator)
CHART=kawa
CHART_DIR=charts/$CHART

# versions <dir> <prefix>: versions of the tags <prefix><x.y.z[-rc.N]>, old -rcN written as -rc.N.
versions() {
  git -C "$1" tag -l "$2*" | sed -n "s/^$2//p" \
    | awk '/^[0-9]+\.[0-9]+\.[0-9]+(-rc\.?[0-9]+)?$/' | sed -E 's/-rc([0-9])/-rc.\1/'
}

# next_version <major|minor|patch|rc> <rc 0|1>, existing versions on stdin.
# Bumps the highest final version (0.0.0 if none). rc gives the next -rc.N of that version.
# Bump "rc" continues the highest release-candidate line instead (0.1.0-rc.2 -> 0.1.0-rc.3).
next_version() {
  local bump=$1 rc=$2 all base maj min pat next n
  all="$(cat)"
  base="$(awk '!/-rc/' <<<"$all" | sort -V | tail -1)"
  IFS=. read -r maj min pat <<<"${base:-0.0.0}"
  case $bump in
    major) next="$((maj + 1)).0.0" ;;
    minor) next="$maj.$((min + 1)).0" ;;
    patch) next="$maj.$min.$((pat + 1))" ;;
    rc)    next="$(awk '/-rc/ { sub(/-.*/, ""); print }' <<<"$all" | sort -V | tail -1)"; rc=1
           [[ -n $next ]] || die "no release candidate to continue" ;;
    *) die "unknown bump: $bump" ;;
  esac
  if [[ $rc == 1 ]]; then
    n="$(awk -v p="$next-rc." 'index($0, p) == 1 { print substr($0, length(p) + 1) }' <<<"$all" | sort -n | tail -1)"
    next="$next-rc.$((${n:-0} + 1))"
  fi
  printf '%s\n' "$next"
}

# unreleased <dir> <tag-glob>: latest matching tag on origin/main (or "none") and the commits after it.
unreleased() {
  local latest
  latest="$(git -C "$1" describe --tags --abbrev=0 --match "$2" origin/main 2>/dev/null || echo none)"
  printf '%s %s\n' "$latest" "$(git -C "$1" rev-list --count "$(since "$latest")")"
}

# since <latest>: the commit range on origin/main after <latest> ("none" means all of it).
since() { if [[ $1 == none ]]; then echo origin/main; else echo "$1..origin/main"; fi; }

# ask <name> <dir> <latest> <unreleased> <can-skip 0|1> [<next-rc-tag>]:
# sets BUMP (major|minor|patch|rc|skip) and RC (0|1).
# [r] is offered when <next-rc-tag> is given and continues that release-candidate line.
# [l]ist prints the unreleased commits and asks again.
ask() {
  local name=$1 dir=$2 latest=$3 count=$4 can_skip=$5 next_rc=${6:-} choices='[M]ajor [m]inor [p]atch' a
  if [[ -n $next_rc ]]; then choices+=" [r]c → $next_rc"; fi
  if [[ $can_skip == 1 ]]; then choices+=' [s]kip'; fi
  choices+=' [l]ist'
  BUMP=; RC=0
  while [[ -z $BUMP ]]; do
    printf '%s📦 %s%s%s %s(latest %s, %s unreleased commits)%s %s: ' \
      "$CYAN$BOLD" "$GREEN" "$name" "$RESET" "$DIM" "$latest" "$count" "$RESET" "$choices"
    read -r a
    case $a in
      M) BUMP=major ;;
      m) BUMP=minor ;;
      p) BUMP=patch ;;
      r) if [[ -n $next_rc ]]; then BUMP=rc; RC=1; return 0; fi ;;
      s) if [[ $can_skip == 1 ]]; then BUMP=skip; return 0; fi ;;
      l) git -C "$dir" --no-pager log --oneline --no-decorate "$(since "$latest")" | sed 's/^/     /'
         continue ;;
    esac
    if [[ -z $BUMP ]]; then printf '%s👉 pick one of the letters%s\n' "$YELLOW" "$RESET"; fi
  done
  printf '   %srelease candidate? [y/N]%s ' "$CYAN" "$RESET"
  read -r a
  if [[ $a == y || $a == Y ]]; then RC=1; fi
}

# check_repo <dir> <github-repo>: a checkout of <github-repo> with no tracked changes, on origin/main.
check_repo() {
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1 || die "$1 is not a git checkout"
  [[ "$(git -C "$1" remote get-url origin)" == *"$2"* ]] || die "$1: origin is not $2"
  git -C "$1" diff --quiet HEAD || die "$1 has uncommitted changes"
  [[ "$(git -C "$1" rev-parse HEAD)" == "$(git -C "$1" rev-parse origin/main)" ]] \
    || die "$1 is not on origin/main; check out main and pull"
}

# has_tag <dir> <tag>
has_tag() { git -C "$1" rev-parse -q --verify "refs/tags/$2" >/dev/null; }

# wait_release <github-repo> <tag>: waits for the Release run of <tag>; exits if it fails.
wait_release() {
  local id='' i url
  for i in $(seq 1 24); do
    id="$(gh run list -R "$1" -w release.yml --branch "$2" -L 1 --json databaseId -q '.[0].databaseId')"
    if [[ -n $id ]]; then break; fi
    sleep 5
  done
  [[ -n $id ]] || die "no Release run for $2 after 2 minutes; see https://github.com/$1/actions"
  url="https://github.com/$1/actions/runs/$id"
  info "⏳ Waiting for $2: $url"
  gh run watch "$id" -R "$1" --exit-status --interval 15 >/dev/null \
    || die "Release of $2 failed: $url (gh run view $id -R $1 --log-failed). Nothing after it was released."
  printf '%s✅ %s released%s\n' "$GREEN$BOLD" "$2" "$RESET"
  RESULTS+=("$2  $url")
}

[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0   # sourced (for testing the functions): stop here

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
KAWA_ROOT="${KAWA_ROOT:-$(cd "$root/.." && pwd)}"

gh auth status >/dev/null 2>&1 || die "gh is not logged in; run gh auth login"
[[ -f $CHART_DIR/Chart.yaml ]] || die "$CHART_DIR/Chart.yaml not found; the umbrella chart is needed first"
for c in "${COMPONENTS[@]}"; do
  grep -Eq "^[[:space:]]*tag:[[:space:]]*\"[^\"]*\"[[:space:]]*# kawa-release: $c\$" "$CHART_DIR/values.yaml" \
    || die "$CHART_DIR/values.yaml has no pin line for $c (expected: tag: \"x.y.z\"  # kawa-release: $c)"
done

info "🔄 Fetching tags..."
git fetch -q origin main --tags
for c in "${COMPONENTS[@]}"; do
  dir="$KAWA_ROOT/kawa-$c"
  [[ -d $dir ]] || die "no checkout of kawa-$c at $dir (set KAWA_ROOT)"
info "🔄 Fetching ${c} tags..."
  git -C "$dir" fetch -q origin main --tags
done

# 🎯 Ask what to release.
printf '\n%s🎯 What do you want to release?%s\n' "$MAGENTA$BOLD" "$RESET"
SELECTED=(); NEXT=(); LATEST=()
for c in "${COMPONENTS[@]}"; do
  dir="$KAWA_ROOT/kawa-$c"
  read -r latest count <<<"$(unreleased "$dir" 'v[0-9]*')"
  next_rc=''
  if [[ $latest == *-rc* ]]; then next_rc="v$(versions "$dir" v | next_version rc 1)"; fi
  ask "$c" "$dir" "$latest" "$count" 1 "$next_rc"
  if [[ $BUMP == skip ]]; then continue; fi
  SELECTED+=("$c"); LATEST+=("$latest")
  NEXT+=("$(versions "$dir" v | next_version "$BUMP" "$RC")")
done

read -r latest count <<<"$(unreleased . "$CHART-[0-9]*")"
next_rc=''
if [[ $latest == *-rc* ]]; then next_rc="$CHART-$(versions . "$CHART-" | next_version rc 1)"; fi
ask "$CHART chart" . "$latest" "$count" 0 "$next_rc"
chart_latest=$latest
chart_next="$(versions . "$CHART-" | next_version "$BUMP" "$RC")"
chart_tag="$CHART-$chart_next"

# 🧪 Check everything before pushing anything.
check_repo "$root" "$ORG/kawa-charts"
for ((i = 0; i < ${#SELECTED[@]}; i++)); do
  dir="$KAWA_ROOT/kawa-${SELECTED[$i]}"
  check_repo "$dir" "$ORG/kawa-${SELECTED[$i]}"
  if has_tag "$dir" "v${NEXT[$i]}"; then die "tag v${NEXT[$i]} already exists in kawa-${SELECTED[$i]}"; fi
done
if has_tag . "$chart_tag"; then die "tag $chart_tag already exists"; fi

# below <dir> <prefix> <version>: a warning when <version>'s x.y.z is lower than the highest tag's.
below() {
  local top
  top="$(versions "$1" "$2" | sed 's/-.*//' | sort -V | tail -1)"
  if [[ -n $top && ${3%%-*} != "$top" && "$(printf '%s\n%s\n' "${3%%-*}" "$top" | sort -V | tail -1)" == "$top" ]]; then
    printf '  %s⚠️  lower than existing %s%s' "$YELLOW" "$top" "$RESET"
  fi
}

# 📋 Plan.
printf '\n%s📋 Release plan%s\n' "$MAGENTA$BOLD" "$RESET"
for ((i = 0; i < ${#SELECTED[@]}; i++)); do
  printf '   %-14s %s → %s%s%s%s\n' "kawa-${SELECTED[$i]}" "${LATEST[$i]}" "$GREEN$BOLD" "v${NEXT[$i]}" "$RESET" \
    "$(below "$KAWA_ROOT/kawa-${SELECTED[$i]}" v "${NEXT[$i]}")"
done
printf '   %-14s %s → %s%s%s%s\n' "chart $CHART" "$chart_latest" "$GREEN$BOLD" "$chart_tag" "$RESET" \
  "$(below . "$CHART-" "$chart_next")"
printf '\n%s🤔 Tag and push all of this to origin? [y/N] %s' "$MAGENTA$BOLD" "$RESET"
read -r ok
[[ $ok == y || $ok == Y ]] || { printf '%s🛑 cancelled, nothing pushed%s\n' "$YELLOW" "$RESET"; exit 1; }

# 🚢 Components first, one at a time, each waiting for its Release workflow.
RESULTS=()
for ((i = 0; i < ${#SELECTED[@]}; i++)); do
  c="${SELECTED[$i]}"
  printf '\n%s🏷️  Releasing kawa-%s v%s%s\n' "$BLUE$BOLD" "$c" "${NEXT[$i]}" "$RESET"
  make -s -C "$KAWA_ROOT/kawa-$c" release VERSION="${NEXT[$i]}"
  wait_release "$ORG/kawa-$c" "v${NEXT[$i]}"
done

# 📌 Then the chart: pin what was released, bump its version, tag and push.
printf '\n%s📌 Releasing chart %s%s\n' "$BLUE$BOLD" "$chart_tag" "$RESET"
pins=()
for ((i = 0; i < ${#SELECTED[@]}; i++)); do pins+=("${SELECTED[$i]}=${NEXT[$i]}"); done
python3 - "$CHART_DIR" "$chart_next" ${pins[@]+"${pins[@]}"} <<'PY'
import re, sys
chart_dir, version, pins = sys.argv[1], sys.argv[2], sys.argv[3:]

path = f"{chart_dir}/Chart.yaml"
text = open(path).read()
text, n = re.subn(r'^version:.*$', f'version: {version}', text, count=1, flags=re.M)
assert n == 1, f"no version line in {path}"
open(path, 'w').write(text)

path = f"{chart_dir}/values.yaml"
text = open(path).read()
for pin in pins:
    name, tag = pin.split('=', 1)
    pattern = rf'^(\s*tag:\s*)"[^"]*"(\s*# kawa-release: {re.escape(name)})$'
    text, n = re.subn(pattern, rf'\g<1>"{tag}"\g<2>', text, flags=re.M)
    assert n == 1, f"expected one pin line for {name} in {path}, found {n}"
open(path, 'w').write(text)
PY

# 📦 Commit only the chart files, whatever else is changed in the working tree.
git commit -q -m "release: $CHART $chart_next" -- "$CHART_DIR/Chart.yaml" "$CHART_DIR/values.yaml"
git tag -a "$chart_tag" -m "$chart_tag"
git push -q origin main
git push -q origin "$chart_tag"
wait_release "$ORG/kawa-charts" "$chart_tag"

printf '\n%s🎉 Released%s\n' "$GREEN$BOLD" "$RESET"
for r in "${RESULTS[@]}"; do printf '   %s\n' "$r"; done
