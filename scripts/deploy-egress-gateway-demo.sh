#!/bin/bash

set -aueo pipefail

# shellcheck disable=SC1091

export osm_namespace=osm-system

kubectl delete namespace curl --ignore-not-found
kubectl delete namespace egress-gateway --ignore-not-found

kubectl create namespace egress-gateway
kubectl apply -f demo/egress-gateway/egress-gateway-rbac.yaml -n egress-gateway
kubectl apply -f demo/egress-gateway/egress-gateway-service.yaml -n egress-gateway
kubectl apply -f demo/egress-gateway/egress-gateway-configmap.yaml -n egress-gateway
kubectl apply -f demo/egress-gateway/egress-gateway-deployment.yaml -n egress-gateway

kubectl create namespace curl
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
$OSM/bin/osm namespace add curl

# Deploy curl client in the curl namespace
kubectl apply -f demo/egress-gateway/curl.yaml -n curl
kubectl apply -f demo/egress-gateway/egress-policy.yaml
kubectl apply -f demo/egress-gateway/egress-gateway-policy.yaml

kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=60s
kubectl wait --for=condition=ready pod -n egress-gateway -l app=egress-gateway --timeout=60s

sleep 10
echo kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get