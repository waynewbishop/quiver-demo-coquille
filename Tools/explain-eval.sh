#!/bin/bash
# Copyright 2026 Wayne W Bishop. All rights reserved.
#
# Runs the Explain evaluation and opens its report in the browser.
#
#   Tools/explain-eval.sh                   release: every sentence three times
#   Tools/explain-eval.sh smoke             the first sentence of each category once
#   Tools/explain-eval.sh coverage          every sentence once
#   Tools/explain-eval.sh release E43 E02   only those sentences, three times
#   Tools/explain-eval.sh smoke tense       only the tense sentences, once
#
# An argument like E43 is a case id; any other word is a category. Reports are saved in
# Artifacts/ExplainEvaluation/ with the date in the name, and the newest is also latest.html.
# The report is exported even when the test fails, since a failure (such as a request with
# no answer) is part of what the report shows.

cd "$(dirname "$0")/.." || exit 1

mode="${1:-release}"
case "$mode" in
    smoke|coverage|release) ;;
    *) echo "usage: Tools/explain-eval.sh [smoke|coverage|release] [case ids or categories...]"; exit 2 ;;
esac
[ $# -gt 0 ] && shift

ids=""
categories=""
for arg in "$@"; do
    if [[ "$arg" =~ ^E[0-9]+$ ]]; then ids="${ids:+$ids,}$arg"; else categories="${categories:+$categories,}$arg"; fi
done

derived=.build/ExplainEvaluation
out=Artifacts/ExplainEvaluation
stamp=$(date +%Y-%m-%d-%H%M%S)
bundle="$derived/Results/$stamp-$mode.xcresult"
mkdir -p "$out" "$derived/Results"

echo "Building the evaluation…"
if ! xcodebuild build-for-testing -scheme quiver-demo-coquille -testPlan quiver-demo-coquilleEvaluationTests \
        -destination 'platform=macOS' -derivedDataPath "$derived" -quiet; then
    echo "The build failed, so nothing was evaluated."
    exit 1
fi

# The test plan's settings live in the .xctestrun file the build writes. A copy beside it,
# so its relative paths still work, gets this run's mode, cases and categories.
products="$derived/Build/Products"
template=$(ls "$products"/*_quiver-demo-coquilleEvaluationTests_*.xctestrun 2>/dev/null | grep -v '\.this-run\.xctestrun$' | head -1)
if [ -z "$template" ]; then
    echo "The build didn't produce the evaluation's .xctestrun file in $products."
    exit 1
fi
run="${template%.xctestrun}.this-run.xctestrun"
cp "$template" "$run"
env="TestConfigurations.0.TestTargets.0.EnvironmentVariables"
plutil -replace "$env.COQUILLE_EXPLAIN_MODE" -string "$mode" "$run"
plutil -replace "$env.COQUILLE_EXPLAIN_CASES" -string "$ids" "$run"
plutil -replace "$env.COQUILLE_EXPLAIN_CATEGORY" -string "$categories" "$run"

# Only the evaluation's own lines and the test results, not xcodebuild's whole log.
xcodebuild test-without-building -xctestrun "$run" -destination 'platform=macOS' -resultBundlePath "$bundle" 2>&1 \
    | grep --line-buffered -E '^(\[[0-9]+/[0-9]+\]|Explain evaluation|Checkpoint file|Evaluation finished)|error:|Test Case .*(passed|failed|skipped)'
status=${PIPESTATUS[0]}

# The manifest's keys are in alphabetical order, so each attachment's exported file name
# comes before its suggested name.
exported=$(mktemp -d)
xcrun xcresulttool export attachments --path "$bundle" --output-path "$exported" > /dev/null 2>&1
file=$(awk -F'"' '/"exportedFileName"/ { name = $4 } /"suggestedHumanReadableName" : "ExplainEvaluation/ { print name; exit }' \
    "$exported/manifest.json" 2>/dev/null)

if [ -n "$file" ] && [ -f "$exported/$file" ]; then
    cp "$exported/$file" "$out/$stamp-$mode.html"
    cp "$exported/$file" "$out/latest.html"
    echo "Report: $out/latest.html"
    open "$out/latest.html"
else
    echo "No report was attached, so the evaluation stopped before the end. Finished sentences are in the checkpoint file named above."
fi
rm -rf "$exported"
exit "$status"
