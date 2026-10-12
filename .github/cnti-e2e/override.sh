#!/usr/bin/env bash
# override.sh: installs the operator from this branch and a MongoDBCommunity
# whose spec.statefulSet sets an exec liveness probe on mongod, and checks that
# the StatefulSet is accepted with only the exec handler and the pods get ready.
set -euo pipefail
summary=${GITHUB_STEP_SUMMARY:-/dev/stdout}
kubectl create namespace mdb
helm install mck helm_chart -n mdb --set registry.operator=local --set operator.version=1.13.0-patched --set registry.pullPolicy=IfNotPresent --wait --timeout 5m
kubectl apply -f .github/cnti-e2e/override/mongodb.yaml
for i in $(seq 1 60); do kubectl get sts mdb -n mdb >/dev/null 2>&1 && break; sleep 5; done
kubectl rollout status sts/mdb -n mdb --timeout=10m
probe=$(kubectl get sts mdb -n mdb -o jsonpath='{.spec.template.spec.containers[?(@.name=="mongod")].livenessProbe}')
startup=$(kubectl get sts mdb -n mdb -o jsonpath='{.spec.template.spec.containers[?(@.name=="mongod")].startupProbe}')
kubectl get pods -n mdb -o wide
{
  echo "### exec liveness override"
  echo '```'
  echo "livenessProbe: $probe"
  echo "startupProbe:  $startup"
  kubectl get pods -n mdb
  echo '```'
} >> "$summary"
echo "$probe" | grep -q '"exec"' || { echo "::error::override exec handler missing"; exit 1; }
if echo "$probe" | grep -q '"tcpSocket"'; then echo "::error::default tcpSocket handler kept next to exec"; exit 1; fi
echo "override accepted: exec only"
