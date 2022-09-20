

# OSM Edge访问控制策略测试

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
    --set=osm.image.registry=flomesh \
    --set=osm.image.tag=1.2.1-alpha.1 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.enableEgress=false \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 访问控制策略测试

### 3.1 技术概念

在 OSM Edge 中从未被 OSM Edge 纳管的区域访问被 OSM Edge 纳管的区域，有两种方法：

- Ingress，目前支持的 Ingress Controller：
  - FSM Pipy Ingress
  - Nginx Ingress
- Access Control，支持两种访问源类型：
  - Service
  - IPRange

### 3.2 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace httpbin
osm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/access-control/httpbin.yaml

#模拟外部客户端
kubectl create namespace curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/access-control/curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 3.3 场景测试一：基于服务的访问控制

#### 3.3.1 启用访问控制策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.3.2 设置基于服务的访问控制策略

```bash
export osm_namespace=osm-system
kubectl apply -f - <<EOF
kind: AccessControl
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
    namespace: curl
    name: curl
EOF
```

#### 3.3.3 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -sI http://httpbin.httpbin:14001/get
```

#### 3.3.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: gunicorn/19.9.0
date: Sun, 18 Sep 2022 01:47:58 GMT
content-type: application/json
content-length: 267
access-control-allow-origin: *
access-control-allow-credentials: true
osm-stats-namespace: httpbin
osm-stats-kind: Deployment
osm-stats-name: httpbin
osm-stats-pod: httpbin-7c6464475-cf4qc
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubeexport osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
```

### 3.4 场景测试二：基于IP范围的访问控制

#### 3.4.1 启用访问控制策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.4.2 设置基于IP范围的访问控制策略

```bash
export osm_namespace=osm-system
kubectl apply -f - <<EOF
kind: AccessControl
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
  - kind: IPRange
    name: 10.244.1.4/32
EOF
```

#### 3.4.3 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -- curl -sI http://httpbin.httpbin:14001/get
```

#### 3.4.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: gunicorn/19.9.0
date: Sun, 18 Sep 2022 02:36:00 GMT
content-type: application/json
content-length: 267
access-control-allow-origin: *
access-control-allow-credentials: true
osm-stats-namespace: httpbin
osm-stats-kind: Deployment
osm-stats-name: httpbin
osm-stats-pod: httpbin-7c6464475-cf4qc
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubeexport osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":false}}}'  --type=merge
kubectl delete accesscontrol -n httpbin httpbin
```

