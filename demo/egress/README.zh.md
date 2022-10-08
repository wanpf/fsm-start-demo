# OSM Edge Egress 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.2.1-alpha.1
curl -L https://github.com/flomesh-io/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/osm version
cp ./${system}-${arch}/osm /usr/local/bin/
```

## 2. 安装 osm-edge

```bash
export osm_namespace=osm-system 
export osm_mesh_name=osm 

osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=cybwan \
    --set=osm.image.tag=1.2.1-alpha.2 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. Egress策略测试

### 3.1 技术概念

在 OSM Edge 中Egress策略：

- 支持的源类型：
  - ServiceAccount
- 支持的目的类型：
  - 基于域名，支持的协议：
    - http
    - tcp
  - 基于IP范围，支持的协议：
    - tcp

### 3.2 部署业务 POD

```bash
#模拟外部服务
kubectl create namespace egress-server
kubectl apply -n egress-server -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/egress/httpbin.yaml
kubectl apply -n egress-server -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/bidirection-mtls-nginx/server.yaml

#模拟业务服务
kubectl create namespace egress-client
osm namespace add egress-client
kubectl apply -n egress-client -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/bidirection-mtls-nginx/client.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n egress-server -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n egress-server -l app=server --timeout=180s
kubectl wait --for=condition=ready pod -n egress-client -l app=client --timeout=180s
```

### 3.3 场景测试一：基于域名的外部访问

### 3.3.1 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

### 3.3.2 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

### 3.3.3 测试指令

```bash
curl_client="$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n egress-client -c client -- curl -sI httpbin.egress-server.svc.cluster.local:14001
```

### 3.4.4 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 52
```

### 3.4.5 设置Egress目的策略

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: httpbin-14001
  namespace: egress-client
spec:
  sources:
  - kind: ServiceAccount
    name: client
    namespace: egress-client
  hosts:
  - httpbin.egress-server.svc.cluster.local
  ports:
  - number: 14001
    protocol: http
EOF
```

### 3.3.6 测试指令

```bash
curl_client="$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n egress-client -c client -- curl -sI httpbin.egress-server.svc.cluster.local:14001
```

### 3.3.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
date: Sat, 08 Oct 2022 23:38:14 GMT
content-type: text/html; charset=utf-8
content-length: 9593
access-control-allow-origin: *
access-control-allow-credentials: true
x-pipy-upstream-service-time: 3
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete egress -n egress-client httpbin-14001
```

### 3.4 场景测试二：基于 IP 范围的外部访问

### 3.4.1 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

### 3.4.2 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

### 3.4.3 测试指令

```bash
httpbin_pod_ip="$(kubectl get pod -n egress-server -l app=httpbin -o jsonpath='{.items[0].status.podIP}')"
curl_client="$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n egress-client -c client -- curl -sI ${httpbin_pod_ip}:14001
```

### 3.4.4 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 52
```

### 3.4.5 设置Egress目的策略

```bash
httpbin_pod_ip="$(kubectl get pod -n egress-server -l app=httpbin -o jsonpath='{.items[0].status.podIP}')"
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: httpbin-14001
  namespace: egress-client
spec:
  sources:
  - kind: ServiceAccount
    name: client
    namespace: egress-client
  ipAddresses:
  - ${httpbin_pod_ip}/32
  ports:
  - number: 14001
    protocol: tcp
EOF
```

### 3.4.6 测试指令

```bash
httpbin_pod_ip="$(kubectl get pod -n egress-server -l app=httpbin -o jsonpath='{.items[0].status.podIP}')"
curl_client="$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n egress-client -c client -- curl -sI ${httpbin_pod_ip}:14001
```

### 3.4.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Server: gunicorn/19.9.0
Date: Sat, 08 Oct 2022 23:41:39 GMT
Connection: keep-alive
Content-Type: text/html; charset=utf-8
Content-Length: 9593
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete egress -n egress-client httpbin-14001
```