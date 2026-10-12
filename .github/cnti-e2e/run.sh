#!/usr/bin/env bash
# run.sh <baseline|patched>: installs the operator, a two-member
# MongoDBCommunity replica set with an arbiter, and reports the processes'
# ids, the replica set's state and the CNTi Test Suite's non_root_containers
# verdict. Fork-only test for #1629.
set -uo pipefail
variant=$1
root=$(pwd)
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
kubectl create namespace mdb
if [[ "$variant" == baseline ]]; then
  helm repo add mongodb https://mongodb.github.io/helm-charts >/dev/null
  helm install op mongodb/mongodb-kubernetes --version 1.13.0 -n mdb-op --create-namespace \
    --set operator.watchNamespace=mdb --wait --timeout 5m
else
  helm install op ./helm_chart -n mdb-op --create-namespace --set operator.watchNamespace=mdb \
    --set registry.operator=local --set operator.version=1.13.0-rungroup --set registry.pullPolicy=IfNotPresent \
    --wait --timeout 5m
fi
mkdir -p work && cd work
cnti-testsuite setup >/dev/null
cnti-testsuite cnf_install --cnf-config "$root/.github/cnti-e2e/cnf/cnti-testsuite.yaml"
kubectl -n mdb wait mongodbcommunity/mdb --for=jsonpath='{.status.phase}'=Running --timeout=12m
rs=""
for i in $(seq 1 12); do
  rs=$(kubectl -n mdb exec mdb-0 -c mongod -- mongosh --quiet -u app -p test-only-password --authenticationDatabase admin \
    --eval 'rs.status().members.map(m => m.name.split(".")[0] + " " + m.stateStr).join(", ")' 2>&1 | tail -1)
  [[ "$rs" == *PRIMARY* ]] && break
  sleep 10
done
cnti-testsuite non_root_containers > nonroot.log 2>&1
verdict=$(grep -a -o -E "(PASSED|FAILED|SKIPPED|ERROR): \[non_root_containers\][^🔓]*" nonroot.log | head -1)
{
  echo "### $variant operator"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| operator image | \`$(kubectl -n mdb-op get deploy mongodb-kubernetes-operator -o jsonpath='{.spec.template.spec.containers[0].image}')\` |"
  echo "| operator process | \`$(kubectl -n mdb-op exec deploy/mongodb-kubernetes-operator -- id 2>&1 | tail -1)\` |"
  echo "| mdb-0 mongod | \`$(kubectl -n mdb exec mdb-0 -c mongod -- id 2>&1 | tail -1)\` |"
  echo "| mdb-0 mongodb-agent | \`$(kubectl -n mdb exec mdb-0 -c mongodb-agent -- id 2>&1 | tail -1)\` |"
  echo "| mdb-arb-0 mongod | \`$(kubectl -n mdb exec mdb-arb-0 -c mongod -- id 2>&1 | tail -1)\` |"
  echo "| pod securityContext | \`$(kubectl -n mdb get sts mdb -o jsonpath='{.spec.template.spec.securityContext}')\` |"
  echo "| replica set | $rs |"
  echo "| CNTi non_root_containers | $verdict |"
  echo
  echo '```'
  grep -a "impacted:" nonroot.log | sed 's/^ *//' | head -12
  echo '```'
} >> "$summary"
cat nonroot.log | grep -a -E "PASSED|FAILED|impacted" | head -20
if [[ "$variant" == patched ]]; then
  [[ "$verdict" == PASSED* && "$rs" == *PRIMARY*SECONDARY*ARBITER* ]] || { echo "::error::patched: expected a healthy replica set and non_root_containers PASSED"; exit 1; }
else
  [[ "$verdict" == FAILED* ]] || echo "::warning::baseline: expected non_root_containers FAILED, got: $verdict"
fi
