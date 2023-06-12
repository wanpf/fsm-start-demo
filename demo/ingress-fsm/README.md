# FSM Ingress Test

## 1. Download and install the `fsm` command line tool

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. Install `fsm` and `FSM Ingress`

```bash
export fsm_namespace=fsm-system 
export fsm_mesh_name=fsm 

fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=flomesh \
    --set=fsm.image.tag=1.0.0 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.enableEgress=false \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.enabled=true \
    --timeout=900s
```

## 3. Ingress Test

### 3.1 Deploy business POD

```bash
#Simulate business service
kubectl create namespace httpbin
fsm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/ingress-fsm/httpbin.yaml

#Simulate external client
kubectl create namespace ext-curl
kubectl apply -n ext-curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/egress-gateway/curl.yaml

#Wait for the dependent POD to start normally
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n ext-curl -l app=curl --timeout=180s
```

### 3.2 Setting up Ingress Rules

```bash
export fsm_namespace=fsm-system
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbin
  namespace: httpbin
spec:
  ingressClassName: pipy
  rules:
  - host: httpbin.org
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: httpbin
            port:
              number: 14001      
---
kind: IngressBackend
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin
  namespace: httpbin
spec:
  backends:
  - name: httpbin
    port:
      number: 14001 # targetPort of httpbin service
      protocol: http
  sources:
  - kind: Service
    namespace: "$fsm_namespace"
    name: fsm-ingress-pipy-controller
EOF
```

### 3.3 Test commands

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://fsm-ingress-pipy-controller.fsm-system:80/get -H "Host: httpbin.org"
```

### 3.4 Test Results

The correct return result might look similar to :

```bash
HTTP/1.1 200 OK
server: gunicorn/19.9.0
date: Fri, 16 Sep 2022 10:44:13 GMT
content-type: application/json
content-length: 247
access-control-allow-origin: *
access-control-allow-credentials: true
fsm-stats-namespace: httpbin
fsm-stats-kind: Deployment
fsm-stats-name: httpbin
fsm-stats-pod: httpbin-7c6464475-pz5gf
connection: keep-alive
```
