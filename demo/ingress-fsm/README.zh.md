# FSM Ingress 测试

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. 安装 fsm&FSM Ingress

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

## 3. Pipy Ingress 测试

### 3.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace httpbin
fsm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/ingress-fsm/httpbin.yaml

#模拟外部客户端
kubectl create namespace ext-curl
kubectl apply -n ext-curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/ingress-fsm/curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n ext-curl -l app=curl --timeout=180s
```

### 3.2 设置 Ingress 策略

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
apiVersion: policy.openservicemesh.io/v1alpha1
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

### 3.3 测试指令

```bash
kubectl exec "$(kubectl get pod -n ext-curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n ext-curl -- curl -sI http://fsm-ingress-pipy-controller.fsm-system:80/get -H "Host: httpbin.org"
```

### 3.4 测试结果

正确返回结果类似于:

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
