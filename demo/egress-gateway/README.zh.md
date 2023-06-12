# FSM Egress Gateway 测试

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/cybwan/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
    --set=fsm.enableEgress=false \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. Egress Gateway 测试

### 3.1 技术概念

在 FSM 中 Egress 的策略有两类:

- 目的控制策略
  - **宽松模式**：放行所有外部流量
  - **策略模式**：放行显式配置的外部流量
- 出口控制策略
  - **边车透传**：外部流量经边车直接到外部目标
  - **网关代理**：外部流量经边车送到出口网关后到外部目标
    - **全局出口代理网关**
      - http2tunnel 默认
      - Sock5

策略组合，可以满足四种业务场景：

- 目的宽松模式+边车透传
- 目的策略模式+边车透传
- 目的宽松模式+全局出口代理网关
- 目的策略模式+全局出口代理网关

### 3.2 测试环境要求

#### 3.2.1 部署业务 POD

```bash
kubectl create namespace curl
fsm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/egress-gateway/curl.yaml
```

#### 3.2.2 部署全局出口代理网关

##### 3.2.2.1 编译 fsm

```bash
git clone https://github.com/flomesh-io/fsm
cd fsm
make dev
```

##### 3.2.2.2 部署 http2tunnel 模式 Egress Gateway

```bash
helm uninstall --namespace fsm fsm

helm install --namespace fsm --create-namespace \
--set fsm.version=0.2.0-alpha.16 \
--set fsm.logLevel=5 \
--set fsm.egressGateway.enabled=true \
--set fsm.egressGateway.mode=http2tunnel \
--set fsm.egressGateway.logLevel=debug \
fsm charts/fsm 
```

##### 3.2.2.3 部署 sock5 模式 Egress Gateway

```bash
helm uninstall --namespace fsm fsm

helm install --namespace fsm --create-namespace \
--set fsm.version=0.2.0-alpha.16 \
--set fsm.logLevel=5 \
--set fsm.egressGateway.enabled=true \
--set fsm.egressGateway.mode=sock5 \
--set fsm.egressGateway.logLevel=debug \
fsm charts/fsm 
```

**http2tunnel 和 sock5 任选其一部署**

#### 3.2.3 等待依赖的 POD 正常启动

```bash
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n fsm -l app=fsm-egress-gateway --timeout=180s
```

### 3.3 场景测试一：目的宽松模式+边车透传

#### 3.3.1 禁用Egress目的宽松模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 3.3.2 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get
```

#### 3.3.3 测试结果

正确返回结果:

```bash
command terminated with exit code 7
```

#### 3.3.4  启用Egress目的宽松模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":true}}}' --type=merge
```

#### 3.3.5 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get
```

#### 3.3.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Fri, 16 Sep 2022 07:50:40 GMT
Content-Type: application/json
Content-Length: 257
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

### 3.4 场景测试二：目的策略模式+边车透传

#### 3.4.1 启用Egress目的策略模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 3.4.2 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get
```

#### 3.4.3 测试结果

正确返回结果:

```bash
command terminated with exit code 7
```

#### 3.4.4 设置Egress目的策略

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin-80
  namespace: curl
spec:
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: curl
  hosts:
  - httpbin.org
  ports:
  - number: 80
    protocol: http
EOF
```

#### 3.4.5 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get
```

#### 3.4.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
date: Sat, 17 Sep 2022 12:35:42 GMT
content-type: application/json
content-length: 572
server: gunicorn/19.9.0
access-control-allow-origin: *
access-control-allow-credentials: true
connection: keep-alive
```

#### 3.4.7 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://edition.cnn.com?test=4.4.7
```

#### 3.4.8 测试结果

该请求没有对应的目的策略，边车将直接拒绝，正确返回结果类似于:

```bash
HTTP/1.1 403 Forbidden
content-length: 13
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete egress -n curl httpbin-80
```

### 3.5 场景测试三：目的宽松模式+全局出口代理网关

#### 3.5.1 启用Egress目的宽松模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":true}}}' --type=merge
```

#### 3.5.2 设置全局出口代理网关策略

```bash
kubectl apply -f - <<EOF
kind: EgressGateway
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: global-egress-gateway
  namespace: curl
spec:
  global:
    - service: fsm-egress-gateway
      namespace: fsm
EOF
```

#### 3.5.3 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://edition.cnn.com?test=4.5.3
```

#### 3.5.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 301 Moved Permanently
Server: Varnish
Retry-After: 0
Content-Length: 0
Cache-Control: public, max-age=300
Location: https://edition.cnn.com/?test=4.5.3
Accept-Ranges: bytes
Date: Sat, 17 Sep 2022 11:23:24 GMT
Via: 1.1 varnish
Connection: close
Set-Cookie: countryCode=US; Domain=.cnn.com; Path=/; SameSite=Lax
Set-Cookie: stateCode=CA; Domain=.cnn.com; Path=/; SameSite=Lax
Set-Cookie: geoData=fremont|CA|94539|US|NA|-700|broadband|37.520|-121.930|807; Domain=.cnn.com; Path=/; SameSite=Lax
X-Served-By: cache-pao17462-PAO
X-Cache: HIT
X-Cache-Hits: 0
```

全局出口代理网关流量日志:

```bash
#日志会有延迟(最大15秒)
kubectl logs -n fsm "$(kubectl get pod -n fsm -l app=fsm-egress-gateway -o jsonpath='{.items..metadata.name}')" | grep 'host":"edition.cnn.com' | jq
#流量日志返回
{
  "connection_id": "b2316fbb5ab14034",
  "request_time": "2022-09-17T11:51:33.075Z",
  "source_address": "10.244.1.6",
  "source_port": 42316,
  "host": "edition.cnn.com",
  "path": "/?test=4.5.3",
  "method": "HEAD"
}
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge

kubectl delete egressgateways -n curl global-egress-gateway
```

### 3.6 场景测试四：目的策略模式+全局出口代理网关

#### 3.6.1 禁用Egress目的宽松模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 3.6.2 启用Egress目的策略模式

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 3.6.3 设置Egress目的策略

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: httpbin-80
  namespace: curl
spec:
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: curl
  hosts:
  - httpbin.org
  ports:
  - number: 80
    protocol: http
EOF
```

#### 3.6.4 设置全局出口代理网关策略

```bash
kubectl apply -f - <<EOF
kind: EgressGateway
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: global-egress-gateway
  namespace: curl
spec:
  global:
    - service: fsm-egress-gateway
      namespace: fsm
EOF
```

#### 3.6.5 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://httpbin.org:80/get?test=4.6.5
```

#### 3.6.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
date: Sat, 17 Sep 2022 11:55:20 GMT
content-type: application/json
content-length: 606
server: gunicorn/19.9.0
access-control-allow-origin: *
access-control-allow-credentials: true
connection: keep-alive
```

全局出口代理网关流量日志:

```bash
#日志会有延迟(最大15秒)
kubectl logs -n fsm "$(kubectl get pod -n fsm -l app=fsm-egress-gateway -o jsonpath='{.items..metadata.name}')" | grep 'host":"httpbin.org' | jq
#流量日志返回
{
  "connection_id": "b7afbcab6f284c5c",
  "request_time": "2022-09-17T11:55:20.278Z",
  "source_address": "10.244.1.6",
  "source_port": 41160,
  "host": "httpbin.org",
  "path": "/get?test=4.6.5",
  "method": "HEAD"
}
```

#### 3.6.7 测试指令

```bash
kubectl exec "$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')" -n curl -c curl -- curl -sI http://edition.cnn.com?test=4.5.3
```

#### 3.6.8 测试结果

该请求没有对应的目的策略，边车将直接拒绝，正确返回结果类似于:

```bash
HTTP/1.1 403 Forbidden
content-length: 13
connection: keep-alive
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge

kubectl delete egress -n curl httpbin-80
kubectl delete egressgateways -n curl global-egress-gateway
```
