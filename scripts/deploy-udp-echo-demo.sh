#!/bin/bash

set -aueo pipefail

# shellcheck disable=SC1091

export fsm_namespace=fsm-system

kubectl delete namespace udp-demo --ignore-not-found
kubectl create namespace udp-demo

$FSM/bin/fsm namespace --mesh-name "fsm" add udp-demo

kubectl apply -f demo/udp-echo/udp-echo-rbac.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-echo-service.yaml -n udp-demo

kubectl apply -f demo/udp-echo/udp-echo-service-v1.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-echo-deployment-v1.yaml -n udp-demo

kubectl apply -f demo/udp-echo/udp-echo-service-v2.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-echo-deployment-v2.yaml -n udp-demo

kubectl apply -f demo/udp-echo/udp-client-rbac.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-client-deployment.yaml -n udp-demo

kubectl apply -f demo/udp-echo/udp-smi-policy.yaml -n udp-demo

sleep 5

kubectl wait --for=condition=ready pod -n udp-demo -l app=udp-echo --timeout=180s
kubectl wait --for=condition=ready pod -n udp-demo -l app=udp-client --timeout=180s

kubectl logs "$(kubectl get pod -n udp-demo -l app=udp-echo,version=v1 -o jsonpath='{.items..metadata.name}')" -n udp-demo -c udp-echo-server -f