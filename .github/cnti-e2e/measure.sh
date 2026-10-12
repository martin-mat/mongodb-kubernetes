#!/usr/bin/env bash
# measure.sh <baseline|patched>: installs the operator and a MongoDBCommunity
# replica set as one CNF and runs the CNTi Test Suite's essential tests.
set -uo pipefail
variant=$1
root=$(pwd)
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
mkdir -p work && cd work
cnti-testsuite setup >/dev/null
cnti-testsuite cnf_install --cnf-config "$root/.github/cnti-e2e/cnf-$variant/cnti-testsuite.yaml" --timeout 900 || { echo "::error::cnf_install failed"; exit 1; }
kubectl get pods -n mdb -o wide
cnti-testsuite cert > cert.log 2>&1
rc=$?
results=$(ls -t cnti/results/cnti-testsuite-results-*.yml | head -1)
{
  echo "### $variant: $(grep -a -o -E "Cert: [A-Z]+ \([0-9]+ of [0-9]+ essential tests passed, threshold [0-9]+\)" cert.log | tail -1)"
  echo
  echo "| Test | Verdict |"
  echo "|---|---|"
  yq -r '.items[] | "| `" + .name + "` | " + .status + " |"' "$results"
  echo
  echo '```'
  grep -a "impacted:" cert.log | sed 's/^ *//' | head -40
  echo '```'
} >> "$summary"
mkdir -p "$root/results-$variant" && cp "$results" cert.log "$root/results-$variant/"
echo "cnti-testsuite cert exited with $rc"
