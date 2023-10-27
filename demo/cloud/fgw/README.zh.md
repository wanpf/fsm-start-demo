## 参考文档

https://github.com/flomesh-io/fsm/tree/main/docs/tests/gateway-api

## 部署拓扑

```bash
Consul：
192.168.10.91

K3d：
192.168.10.49
```

## 部署 FSM

### 安装 FSM CLI

``` bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.1.4
curl -L https://github.com/cybwan/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
sudo cp ./${system}-${arch}/fsm /usr/local/bin/
```

### 部署 FSM 控制平面

**Connector 同 FGW 的集成:**

1. Connector 只同 FSM 控制平面下的 Gateway 自动集成
2. Connector 同 Gateway 集成当前仅支持 HTTPRoute 和 GRP Route
3. Connector 同 Gateway 集成, 优先前缀匹配listener的name, 其次完全匹配 listener 的 protocol

```bash
export fsm_namespace=fsm-system
export fsm_mesh_name=fsm
fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.image.registry=cybwan \
    --set=fsm.image.tag=1.1.4 \
    --set=fsm.image.pullPolicy=Always \
    --set fsm.fsmIngress.enabled=false \
    --set fsm.fsmGateway.enabled=true \
    --set fsm.featureFlags.enableValidateHTTPRouteHostnames=false \
    --set fsm.featureFlags.enableValidateGRPCRouteHostnames=false \
    --set fsm.featureFlags.enableValidateTLSRouteHostnames=false \
    --set fsm.featureFlags.enableValidateGatewayListenerHostname=false \
    --set=fsm.controllerLogLevel=debug \
    --set=fsm.serviceAccessMode=mixed \
    --set=fsm.deployConsulConnector=true \
    --set=fsm.cloudConnector.consul.deriveNamespace=consul-derive \
    --set=fsm.cloudConnector.consul.httpAddr=192.168.10.91:8500 \
    --set=fsm.cloudConnector.consul.passingOnly=false \
    --set=fsm.cloudConnector.consul.suffixTag=version \
    --timeout=900s

kubectl create namespace consul-derive
fsm namespace add consul-derive
kubectl patch namespace consul-derive -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}' --type=merge
```

## 部署Consul网关

```bash
export fsm_namespace=fsm-system
cat <<EOF | kubectl apply -n "$fsm_namespace" -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: consul-gw
spec:
  gatewayClassName: fsm-gateway-cls
  listeners:
    - protocol: HTTP
      port: 10080
      name: http
    - protocol: HTTP
      port: 10090
      name: grpc
EOF
```

## 部署Nginx网关

```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: nginx-gw
spec:
  gatewayClassName: fsm-gateway-cls
  listeners:
    - protocol: HTTP
      port: 18080
      name: nginx
EOF

kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: HTTPRoute
metadata:
  name: nginx-gw
spec:
  parentRefs:
  - name: nginx-gw
    namespace: default
    port: 18080
  hostnames:
  - "2.2.2.2"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: poc-demo-http-server
      namespace: consul-derive
      port: 8181
EOF
```

## 备注

### 关于延迟

延迟由如下几个阶段构成:
1. consul -> connector -> resource
2. resource -> config.json -> codebase
3. codebase reload period

关于第一阶段,这个可以认为是准实时的,技术原理,参见 https://consul.docs.apiary.io/#introduction/blocking-queries
WaitTime,咱们设置的是5s, wait block发生在consul服务端,即服务端自己判断index如无变化,则进入wait/blocking,wait的时间是5s,如果这期间index有变化,即终止wait,响应给client

关于第二阶段,延迟时间由 k8s informer sync period 和 gateway update sliding window 构成,期中
k8s informer sync period默认时间是1 秒
gateway update sliding window 是 2~10 秒

关于第三阶段 codebase reload的检查周期是5 秒

综上,最小的延迟时间是2 秒,最大的延迟时间是16 秒

### 关于passingOnly

fsm.cloudConnector.consul.passingOnly这个参数
为true时,只从consul取那些通过健康检查的service;否则取所有注册的service,包括未通过健康检查的

部署时要不要设置,原则是不设置,即使用默认值true

什么时候可能会用到?
consul的特点是,服务注册很快,但健康检查很慢,服务注销很慢
如果consul服务重启,想加速connector的发现速度,这时可以设置为true

### 关于 connector 重启

在业务端处于稳定状态时,connector可以任意重启,不影响已经完成k8s注册的服务的业务连续行
