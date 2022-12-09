# OSM Edge PlugIn 测试

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
    --timeout=900s
```

## 3. PlugIn策略测试

### 3.1 技术概念

```
1、通过Plugin导入pjs脚本, 一个Plugin对应一个pjs文件；
2、通过PluginService设置某一Service的Plugin的启用策略, PluginService同Service的namespace和name需一一对应；
3、通过PluginChain设置某一Service的Chain的启用策略, PluginChain同Service的namespace和name需一一对应；
4、默认osm-system 下创建一个全局的osm-mesh-chain, 对所有被osm纳管的Service起作用
```


### 3.2 部署业务 POD

```bash
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/curl.curl.yaml

kubectl create namespace pipy
osm namespace add pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/pipy-ok.pipy.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v2 --timeout=180s
```

### 3.3 场景测试

#### 3.3.1 启用PlugIn策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enablePlugInPolicy":true}}}' --type=merge
```

#### 3.3.2 声明插件策略

```bash
kubectl create namespace plugin
osm namespace add plugin

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-onload-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-onload-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-onload-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-unload-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-unload-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-unload-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-inbound-service-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-outbound-service-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-inbound-service-route-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-route-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-route-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-outbound-service-route-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-route-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-route-demo] receive data size:', dat?.size)
        )
      )
EOF
```

#### 3.3.3 启用流量宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":true}}}' --type=merge
```

#### 3.3.4 设置服务插件策略

```bash
kubectl apply -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: curl-routes
  namespace: curl
spec:
  matches:
  - name: all
    pathRegex: ".*"
EOF

kubectl apply -f - <<EOF
kind: PluginService
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  inbound:
    targetRoutes:
      - kind: HTTPRouteGroup
        name: curl-routes
        matches:
          - all
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-inbound-service-route-demo
    plugins:
      - mountpoint: HTTPFirst
        namespace: plugin
        name: plugin-inbound-service-demo

  outbound:
    targetServices:
      - name: pipy-ok
        namespace: pipy
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-outbound-service-route-demo
    plugins:
      - mountpoint: HTTPLast
        namespace: plugin
        name: plugin-outbound-service-demo
EOF
```

#### 3.3.5 查看 curl.curl 的 codebase

```bash

```

#### 3.3.6 禁用流量宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":false}}}' --type=merge
```

#### 3.3.7 设置 SMI 访问策略

```bash
kubectl apply -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: curl-routes
  namespace: curl
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


kubectl apply -f - <<EOF
kind: TrafficTarget
apiVersion: access.smi-spec.io/v1alpha3
metadata:
  name: pipy-ok-v1-access-curl-routes
  namespace: curl
spec:
  destination:
    kind: ServiceAccount
    name: curl
    namespace: curl
  rules:
  - kind: HTTPRouteGroup
    name: curl-routes
    matches:
      - test
      - demo
      - debug
  sources:
  - kind: ServiceAccount
    name: pipy-ok-v1
    namespace: pipy
EOF
```

#### 3.3.8 查看 curl.curl 的 codebase

```bash

```

#### 3.3.9 设置服务插件策略

```bash
kubectl apply -f - <<EOF
kind: PluginService
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  inbound:
    targetRoutes:
      - kind: HTTPRouteGroup
        name: curl-routes
        matches:
          - test
          - demo
          - debug
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-inbound-service-route-demo
    plugins:
      - mountpoint: HTTPFirst
        namespace: plugin
        name: plugin-inbound-service-demo

  outbound:
    targetServices:
      - name: pipy-ok
        namespace: pipy
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-outbound-service-route-demo
    plugins:
      - mountpoint: HTTPLast
        namespace: plugin
        name: plugin-outbound-service-demo
EOF
```

#### 3.3.10 查看 curl.curl 的 codebase

```bash

```

#### 3.3.11 设置插件链策略

```bash
kubectl apply -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  InboundChains:
    L4:
      TCPFirst:
        - type: plugin
          name: demo
          namespace: demo
      TCPAfterTLS:
        - type: system
          name: inbound-tls-termination.js
      TCPAfterRouting:
        - type: system
          name: inbound-tcp-load-balance.js
        - type: system
          name: metrics-tcp.js
      TCPLast:
        - type: system
          name: inbound-proxy-tcp.js
    L7:
      HTTPFirst:
      HTTPAfterTLS:
        - type: system
          name: inbound-tls-termination.js
      HTTPAfterDemux:
        - type: system
          name: inbound-demux-http.js
      HTTPAfterRouting:
        - type: system
          name: inbound-http-routing.js
        - type: system
          name: metrics-http.js
        - type: system
          name: inbound-throttle.js
      HTTPAfterMux:
        - type: system
          name: inbound-mux-http.js
        - type: system
          name: metrics-tcp.js
      HTTPLast:
        - type: system
          name: inbound-proxy-tcp.js
  OutboundChains:
    L4:
      TCPFirst:
      TCPAfterRouting:
        - type: system
          name: outbound-tcp-load-balance.js
        - type: system
          name: metrics-tcp.js
      TCPLast:
        - type: system
          name: outbound-proxy-tcp.js
    L7:
      HTTPFirst:
      HTTPAfterDemux:
        - type: system
          name: outbound-demux-http.js
      HTTPAfterRouting:
        - type: system
          name: outbound-http-routing.js
        - type: system
          name: metrics-http.js
        - type: system
          name: outbound-breaker.js
      HTTPAfterMux:
        - type: system
          name: outbound-mux-http.js
        - type: system
          name: metrics-tcp.js
      HTTPLast:
        - type: system
          name: outbound-proxy-tcp.js
EOF

kubectl get pluginchains.plugin.flomesh.io -n curl curl -o yaml
```

## 4. 参考资料

```bash
plugins = {
inboundL7Chains: [
{ 'INBOUND_HTTP_FIRST': [] },
{ 'INBOUND_HTTP_AFTER_TLS': ['inbound-tls-termination.js'] },
{ 'INBOUND_HTTP_AFTER_DEMUX': ['inbound-demux-http.js'] },
{ 'INBOUND_HTTP_AFTER_ROUTING': ['inbound-http-routing.js', 'metrics-http.js', 'inbound-throttle.js'] },
{ 'INBOUND_HTTP_AFTER_MUX': ['inbound-mux-http.js', 'metrics-tcp.js'] },
{ 'INBOUND_HTTP_LAST': ['inbound-proxy-tcp.js'] }
],
inboundL4Chains: [
{ 'INBOUND_TCP_FIRST': [] },
{ 'INBOUND_TCP_AFTER_TLS': ['inbound-tls-termination.js'] },
{ 'INBOUND_TCP_AFTER_ROUTING': ['inbound-tcp-load-balance.js', 'metrics-tcp.js'] },
{ 'INBOUND_TCP_LAST': ['inbound-proxy-tcp.js'] }
],
outboundL7Chains: [
{ 'OUTBOUND_HTTP_FIRST': [] },
{ 'OUTBOUND_HTTP_AFTER_DEMUX': ['outbound-demux-http.js'] },
{ 'OUTBOUND_HTTP_AFTER_ROUTING': ['outbound-http-routing.js', 'metrics-http.js', 'outbound-breaker.js'] },
{ 'OUTBOUND_HTTP_AFTER_MUX': ['outbound-mux-http.js', 'metrics-tcp.js'] },
{ 'OUTBOUND_HTTP_LAST': ['outbound-proxy-tcp.js'] }
],
outboundL4Chains: [
{ 'OUTBOUND_TCP_FIRST': [] },
{ 'OUTBOUND_TCP_AFTER_ROUTING': ['outbound-tcp-load-balance.js', 'metrics-tcp.js'] },
{ 'OUTBOUND_TCP_LAST': ['outbound-proxy-tcp.js'] }
]
}
```

#### 

