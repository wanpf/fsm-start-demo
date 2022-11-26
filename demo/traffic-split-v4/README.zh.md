# OSM Edge Traffic Split v4 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.3
curl -L https://github.com/cybwan/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
    --set=osm.image.tag=1.3.0-alpha.3 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --set=osm.enableEgress=false \
    --set=osm.enablePermissiveTrafficPolicy=false \
    --timeout=900s
```

## 3. 分流策略测试

### 3.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace pipy
osm namespace add pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/traffic-split-v4/pipy-ok.pipy.yaml

#模拟客户端
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/traffic-split-v4/curl.curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 3.2 场景测试一：分流策略测试

#### 3.2.1 设置流量策略

```
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: pipy-ok-service-all-routes
spec:
  matches:
  - name: test
    pathRegex: "/test"
    methods:
    - GET
  - name: demo
    pathRegex: "/demo"
    methods:
    - GET
  - name: debug
    pathRegex: "/debug"
    methods:
    - GET
EOF

cat <<EOF | kubectl apply -n pipy -f -
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: pipy-ok-service-test-route
spec:
  matches:
  - name: test
    pathRegex: "/test"
    methods:
    - GET
EOF

cat <<EOF | kubectl apply -n pipy -f -
kind: TrafficTarget
apiVersion: access.smi-spec.io/v1alpha3
metadata:
  name: curl-access-pipy-ok-v1-all-routes
spec:
  destination:
    kind: ServiceAccount
    name: pipy-ok-v1
    namespace: pipy
  rules:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-all-routes
    matches:
    - test
    - demo
    - debug
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: curl
EOF

cat <<EOF | kubectl apply -n pipy -f -
kind: TrafficTarget
apiVersion: access.smi-spec.io/v1alpha3
metadata:
  name: curl-access-pipy-ok-v2-all-routes
spec:
  destination:
    kind: ServiceAccount
    name: pipy-ok-v2
    namespace: pipy
  rules:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-all-routes
    matches:
    - test
    - demo
    - debug
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: curl
EOF
```

#### 3.2.2 服务可用性测试

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok-v1.pipy:8080/test
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok-v1.pipy:8080/demo
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok-v1.pipy:8080/debug

kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok-v2.pipy:8080/test
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok-v2.pipy:8080/demo
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok-v2.pipy:8080/debug


kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/test
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/demo
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/debug
```

#### 3.2.3 设置分流策略

```
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: pipy-ok-split
spec:
  service: pipy-ok
  matches:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-test-route
  backends:
  - service: pipy-ok-v1
    weight: 25
  - service: pipy-ok-v2
    weight: 75
EOF
```

#### 3.2.4 测试指令

连续执行四次:

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/test
```

#### 3.2.5 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 12
connection: keep-alive

Hi, I am v1!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 12
connection: keep-alive

Hi, I am v2!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 12
connection: keep-alive

Hi, I am v2!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 12
connection: keep-alive

Hi, I am v2!
```

25%流量送 pipy-ok-v1，75%流量送 pipy-ok-v2

#### 3.2.6 测试指令

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/demo
```

#### 3.2.7 测试结果

正确返回结果类似于:

```bash
应该服务拒绝或 404,但当前返回
HTTP/1.1 200 OK
content-length: 0
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl get trafficsplits.split.smi-spec.io -A
kubectl delete trafficsplits.split.smi-spec.io -n pipy pipy-ok-split
kubectl get traffictargets.access.smi-spec.io -A
kubectl delete traffictargets.access.smi-spec.io -n pipy curl-access-pipy-ok-v1-all-routes
kubectl delete traffictargets.access.smi-spec.io -n pipy curl-access-pipy-ok-v2-all-routes
kubectl get httproutegroups.specs.smi-spec.io -A
kubectl delete httproutegroups.specs.smi-spec.io -n pipy pipy-ok-service-all-routes
kubectl delete httproutegroups.specs.smi-spec.io -n pipy pipy-ok-service-test-route
```