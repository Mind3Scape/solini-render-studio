#!/bin/zsh
# Integrate the four ACCEPTED collection films into the app (run only after Codex's visual approval).
#   tools/integrate_films.sh            # dry run: prints every change
#   tools/integrate_films.sh --apply    # copies files, rewrites the four release entries, excludes
#                                       # the previous films/posters from the bundle, bumps build 9,
#                                       # regenerates the Xcode project. No build, test, commit, upload.
set -eu
here=${0:A:h}
root=${here:h:h:h}
cand=$root/tmp/higgsfield-loop/round2/candidates
mode=(); [[ ${1:-} == --apply ]] && mode=(--apply --exclude-old)
typeset -A cut version source
cut=(ninfea $cand/ninfea-tone aria $cand/aria-tone opera $cand/opera greca $cand/greca)
version=(ninfea v4 aria v2 opera v2 greca v2)
source=(
  ninfea "Kling 3.0 Pro open take ninfea-source-v1 (sha256 d8541094…) frames 77–223 + Kling bridge ea7a6e59-b313-4e9f-a84b-fa8a3c852321, tone-matched"
  aria   "Kling 3.0 Pro open take aria-source-v1 (sha256 5b949a50…) frames 76–221 + Kling bridge 52472280-8c84-413b-89c2-5688eb0e3c54, tone-matched"
  opera  "Kling 3.0 Pro start=end opera-closed-source-v1 (sha256 8bd166e7…), rotated from frame 48"
  greca  "Kling 3.0 Pro start=end greca-closed-source-v1 (sha256 c8673f73…), whole clip rotated from frame 46"
)
for n in ninfea aria opera greca; do
  python3 $here/adopt_release.py --collection $n --cut ${cut[$n]} --version ${version[$n]} --source "${source[$n]}" $mode
done
if (( ${#mode} )); then
  sed -i '' "s/CURRENT_PROJECT_VERSION: '8'/CURRENT_PROJECT_VERSION: '9'/" $root/ios/project.yml
  grep -n "CURRENT_PROJECT_VERSION" $root/ios/project.yml
  (cd $root/ios && xcodegen generate --spec project.yml)
else
  echo "dry run: build stays $(grep CURRENT_PROJECT_VERSION $root/ios/project.yml | tr -d ' ')"
fi
