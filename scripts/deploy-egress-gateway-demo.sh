#!/bin/bash

set -aueo pipefail

# shellcheck disable=SC1091

export fsm_namespace=fsm-system

kubectl delete namespace curl --ignore-not-found
kubectl delete namespace egress-gateway --ignore-not-found

kubectl create namespace egress-gateway

kubectl apply -n egress-gateway -f demo/egress-gateway/global-egress-gateway-rbac.yaml
kubectl apply -n egress-gateway -f demo/egress-gateway/global-egress-gateway-service.yaml
kubectl apply -n egress-gateway -f demo/egress-gateway/global-egress-gateway-configmap.yaml
kubectl apply -n egress-gateway -f demo/egress-gateway/global-egress-gateway-deployment.yaml

kubectl apply -n egress-gateway -f demo/egress-gateway/custom-egress-gateway-rbac.yaml
kubectl apply -n egress-gateway -f demo/egress-gateway/custom-egress-gateway-service.yaml
kubectl apply -n egress-gateway -f demo/egress-gateway/custom-egress-gateway-configmap.yaml
kubectl apply -n egress-gateway -f demo/egress-gateway/custom-egress-gateway-deployment.yaml

kubectl create namespace curl
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
$FSM/bin/fsm namespace add curl

# Deploy curl client in the curl namespace
kubectl apply -f demo/egress-gateway/curl.yaml -n curl
kubectl apply -f demo/egress-gateway/egress-policy.yaml
kubectl apply -f demo/egress-gateway/egress-gateway-policy.yaml

kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=60s
kubectl wait --for=condition=ready pod -n egress-gateway -l app=global-egress-gateway --timeout=60s
kubectl wait --for=condition=ready pod -n egress-gateway -l app=custom-egress-gateway --timeout=60s

sleep 10
echo kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get