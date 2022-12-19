# OSM Edge PlugIn 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.6
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
    --set=osm.image.tag=1.3.0-alpha.6 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. PlugIn策略测试


### 3.1 部署业务 POD

```bash
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/curl.curl.yaml

kubectl create namespace pipy
osm namespace add pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/pipy-ok.pipy.yaml

#等待依赖的 POD 正常启动
sleep 2
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v2 --timeout=180s
```

### 3.2 场景测试

#### 3.2.1 启用Plugin策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enablePluginPolicy":true}}}' --type=merge
```

#### 3.2.2 声明插件

```bash
kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: logs-demo-1
spec:
  priority: 1
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[logs-demo-1] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[logs-demo-1] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: logs-demo-2
spec:
  priority: 2
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[logs-demo-2] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[logs-demo-2] receive data size:', dat?.size)
        )
      )
EOF
```

#### 3.2.3 设置插件链

```bash
kubectl apply -n curl -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: logs-demo-chain
spec:
  chains:
    - name: inbound-http
      plugins:
        - logs-demo-1
        - logs-demo-2
    - name: outbound-http
      plugins:
        - logs-demo-1
        - logs-demo-2
  selectors:
    podSelector:
      matchLabels:
        app: curl
      matchExpressions:
        - key: app
          operator: In
          values: ["curl"]
    namespaceSelector:
      matchExpressions:
        - key: openservicemesh.io/monitored-by
          operator: In
          values: ["osm"]
EOF
```

#### 3.2.4 设置插件配置

```bash
kubectl apply -n curl -f - <<EOF
kind: PluginConfig
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl-logs-demo-1
  namespace: curl
spec:
  config:
    http:
    - matches:
      - path: /get
        pathType: Prefix
        method: .*
      request: 3
      unit: minute
      burst: 10
  plugin: logs-demo-1
  destinationRefs:
    - kind: Service
      name: pipy-ok
      namespace: pipy
    - kind: Service
      name: curl
      namespace: curl
EOF
```

#### 3.3.5 查看 curl.curl 的 config.json

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
osm proxy get config_dump -n curl "$curl_client" | jq
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enablePluginPolicy":false}}}' --type=merge

kubectl get pluginconfig -A
kubectl delete pluginconfig -n curl curl-logs-demo-1
kubectl get pluginchain -A
kubectl delete pluginchain -n curl logs-demo-chain
kubectl get plugin -A
kubectl delete plugin logs-demo-1
kubectl delete plugin logs-demo-2
```
