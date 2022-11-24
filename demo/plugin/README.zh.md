# OSM Edge PlugIn 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.2
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
    --set=osm.image.registry=localhost:5000/flomesh \
    --set=osm.image.tag=latest \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. PlugIn策略测试

### 3.1 技术概念


### 3.2 部署业务 POD

```bash
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/curl.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 3.3 场景测试一：白名单插件测试

#### 3.3.1 启用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":true}}}' --type=merge
```

#### 3.3.2 启用PlugIn策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enablePlugInPolicy":true}}}' --type=merge
```

#### 3.3.3 设置插件策略

```bash
export osm_namespace=osm-system
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/domain.json -o domain.json
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/print-http-headers.js -o print-http-headers.js
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/print-data-size.js -o print-data-size.js

kubectl create namespace test
osm namespace add test

kubectl apply -f - <<EOF
kind: PlugIn
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: header-filter
  namespace: test
spec:
  mountPoint:
    phase: INBOUND_HTTP_AFTER_ROUTING
    priority: 1
    targets:
      - kind: Service
        name: curl
        namespace: curl
  entry: print-http-headers.js
  resources:
  - name: domain.json
    content: |+
`cat domain.json | jq | sed 's/^/      /g'`
  - name: print-http-headers.js
    content: |+
`cat print-http-headers.js |sed 's/^/      /g'`
EOF

kubectl apply -f - <<EOF
kind: PlugIn
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: tcp-traffic
  namespace: test
spec:
  mountPoint:
    phase: OUTBOUND_TCP_AFTER_ROUTING
    priority: 1
    targets:
      - kind: Service
        name: curl
        namespace: curl
  entry: print-data-size.js
  resources:
  - name: print-data-size.js
    content: |+
`cat print-data-size.js |sed 's/^/      /g'`
EOF

rm -rf domain.json
rm -rf print-http-headers.js
rm -rf print-data-size.js

kubectl get plugin -A
kubectl get plugin -n test header-filter -o yaml
kubectl get plugin -n test tcp-traffic -o yaml
```

#### 3.3.4 测试指令

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n curl -c curl -- curl -sI httpbin.org
```

#### 3.4.5 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Tue, 22 Nov 2022 01:13:13 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 9593
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```

#### 3.3.6 删除插件策略

```bash
kubectl delete plugin -n test header-filter
kubectl delete plugin -n test tcp-traffic
```

#### 3.3.7 测试指令

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n curl -c curl -- curl -sI httpbin.org
```

#### 3.3.8 测试结果

正确返回结果类似于:

```bash
待补充
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete plugin -n curl ban
```
