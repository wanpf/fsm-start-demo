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

``` shell
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.1.4
curl -L https://github.com/cybwan/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
sudo cp ./${system}-${arch}/fsm /usr/local/bin/
```

``` 部署 FSM 控制平面

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
