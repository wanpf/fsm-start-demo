# FSM Traffic Split v4 测试

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. 安装 fsm

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
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.enableEgress=false \
    --set=fsm.enablePermissiveTrafficPolicy=false \
    --timeout=900s
```

## 3. 分流策略测试

### 3.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace pipy
fsm namespace add pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/traffic-split-v4/pipy-ok.pipy.yaml

#模拟客户端
kubectl create namespace curl
fsm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/traffic-split-v4/curl.curl.yaml

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

#### 3.2.3 仅设置Traffic Split v2策略

```
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: pipy-ok-split-v2
spec:
  service: pipy-ok
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

#### 3.2.6 仅设置Traffic Split v4策略

```
kubectl delete trafficsplits.split.smi-spec.io -n pipy pipy-ok-split-v2

cat <<EOF | kubectl apply -n pipy -f -
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: pipy-ok-split-v4
spec:
  service: pipy-ok
  matches:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-test-route
  backends:
  - service: pipy-ok-v1
    weight: 40
  - service: pipy-ok-v2
    weight: 60
EOF
```

#### 3.2.7 测试指令

连续执行五次:

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/test
```

#### 3.2.8 测试结果

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
```

40%流量送 pipy-ok-v1，60%流量送 pipy-ok-v2

#### 3.2.9 测试指令

连续执行四次:

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/demo
```

#### 3.2.10 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v2!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v1!
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v2!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v1!
```

50%流量送 pipy-ok-v1，50%流量送 pipy-ok-v2

#### 3.2.11 混合设置Traffic Split v2&v4策略

```
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: pipy-ok-split-v4
spec:
  service: pipy-ok
  matches:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-test-route
  backends:
  - service: pipy-ok-v1
    weight: 40
  - service: pipy-ok-v2
    weight: 60
EOF

cat <<EOF | kubectl apply -n pipy -f -
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: pipy-ok-split-v2
spec:
  service: pipy-ok
  backends:
  - service: pipy-ok-v1
    weight: 25
  - service: pipy-ok-v2
    weight: 75
EOF
```

#### 3.2.12 测试指令

连续执行五次:

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/test
```

#### 3.2.13 测试结果

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

Hi, I am v1!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 12
connection: keep-alive

Hi, I am v2!
```

40%流量送 pipy-ok-v1，60%流量送 pipy-ok-v2

#### 3.2.14 测试指令

连续执行四次:

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$curl_client" -n curl -c curl -- curl -si pipy-ok.pipy:8080/demo
```

#### 3.2.15 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v1!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v2!
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v2!

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 12
connection: keep-alive

Hi, I am v2!
```

25%流量送 pipy-ok-v1，75%流量送 pipy-ok-v2

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl get trafficsplits.split.smi-spec.io -A
kubectl delete trafficsplits.split.smi-spec.io -n pipy pipy-ok-split-v2
kubectl delete trafficsplits.split.smi-spec.io -n pipy pipy-ok-split-v4
kubectl get traffictargets.access.smi-spec.io -A
kubectl delete traffictargets.access.smi-spec.io -n pipy curl-access-pipy-ok-v1-all-routes
kubectl delete traffictargets.access.smi-spec.io -n pipy curl-access-pipy-ok-v2-all-routes
kubectl get httproutegroups.specs.smi-spec.io -A
kubectl delete httproutegroups.specs.smi-spec.io -n pipy pipy-ok-service-all-routes
kubectl delete httproutegroups.specs.smi-spec.io -n pipy pipy-ok-service-test-route
```