#!/bin/bash

set -aueo pipefail

# shellcheck disable=SC1091

export osm_namespace=osm-system

kubectl delete namespace udp-demo --ignore-not-found
kubectl create namespace udp-demo

$OSM/bin/osm namespace --mesh-name "osm" add udp-demo

kubectl apply -f demo/udp-echo/udp-echo-rbac.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-echo-service.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-echo-deployment.yaml -n udp-demo

kubectl apply -f demo/udp-echo/udp-client-rbac.yaml -n udp-demo
kubectl apply -f demo/udp-echo/udp-client-deployment.yaml -n udp-demo

sleep 5

kubectl wait --for=condition=ready pod -n udp-demo -l app=udp-echo --timeout=180s
kubectl wait --for=condition=ready pod -n udp-demo -l app=udp-client --timeout=180s

kubectl logs "$(kubectl get pod -n udp-demo -l app=udp-echo -o jsonpath='{.items..metadata.name}')" -n udp-demo -c udp-echo-server -f