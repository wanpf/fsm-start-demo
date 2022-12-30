#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# desired cluster name; default is "kind"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-osm}"
FSM_NAMESPACE="${FSM_NAMESPACE:-flomesh}"
FSM_VERSION="${FSM_VERSION:-latest}"
FSM_CHART="${FSM_CHART:-fsm/fsm}"

kubecm switch kind-${KIND_CLUSTER_NAME}
sleep 1

helm install --namespace ${FSM_NAMESPACE} --create-namespace --version=${FSM_VERSION} --set fsm.logLevel=5 --set fsm.serviceLB.enabled=true fsm ${FSM_CHART}

sleep 5
kubectl wait --for=condition=ready pod -n flomesh -l app=fsm-ingress-pipy --timeout=180s

sleep 5
selector="servicelb.flomesh.io/svcname=fsm-ingress-pipy-controller"
ingress_cnt=`kubectl wait --for=condition=ready pod -n flomesh -l ${selector} --timeout=180s | wc -l`
while [ ${ingress_cnt} -lt 2 ]
do
  ingress_cnt=`kubectl wait --for=condition=ready pod -n flomesh -l ${selector} --timeout=180s | wc -l`
done
kubectl get pods -A -o wide