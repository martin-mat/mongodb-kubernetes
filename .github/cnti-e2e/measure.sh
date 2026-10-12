#!/usr/bin/env bash
# measure.sh <baseline|patched> [label]: installs the operator and a MongoDBCommunity
# replica set as one CNF and runs the CNTi Test Suite's essential tests.
set -uo pipefail
config=$1
variant=${2:-$1}
root=$(pwd)
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
mkdir -p work && cd work
cnti-testsuite setup >/dev/null
cnti-testsuite cnf_install --cnf-config "$root/.github/cnti-e2e/cnf-$config/cnti-testsuite.yaml" --timeout 900 || { echo "::error::cnf_install failed"; exit 1; }
kubectl get pods -n mdb -o wide
# The database pods: the mongod probes and restarts before the tests start.
{
  echo "### $variant: database pods"
  echo '```'
  kubectl get pods -n mdb -l app=mdb-svc -o jsonpath='{range .items[*]}{.metadata.name} restarts={.status.containerStatuses[*].restartCount}{"\n"}{end}' 2>/dev/null
  kubectl get sts -n mdb -o jsonpath='{range .items[*]}{.metadata.name}: mongod liveness={.spec.template.spec.containers[?(@.name=="mongod")].livenessProbe.tcpSocket.port} startup={.spec.template.spec.containers[?(@.name=="mongod")].startupProbe.tcpSocket.port}{"\n"}{end}'
  echo '```'
} >> "$summary"
# The operator pod: its probes and whether it became Ready without restarts.
op='app.kubernetes.io/name=mongodb-kubernetes-operator'
{
  echo "### $variant: operator pod"
  echo '```'
  kubectl get pods -n mdb -l "$op" -o jsonpath='{range .items[*]}{.metadata.name} ready={.status.containerStatuses[0].ready} restarts={.status.containerStatuses[0].restartCount}{"\n"}liveness={.spec.containers[0].livenessProbe.httpGet.path} readiness={.spec.containers[0].readinessProbe.httpGet.path}{"\n"}{end}'
  echo '```'
} >> "$summary"
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
