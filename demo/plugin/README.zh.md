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
    phase: OUTBOUND_HTTP_AFTER_ROUTING
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
Date: Thu, 24 Nov 2022 14:24:59 GMT
Content-Type: text/html; charset=utf-8
Content-Length: 9593
Connection: keep-alive
Server: gunicorn/19.9.0
Access-Control-Allow-Origin: *
Access-Control-Allow-Credentials: true
```
#### 3.4.6 查看pod日志命令
```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl logs pod/${curl_client} -n curl -c sidecar | grep "Chains\|->\|TcpTraffic"
```

#### 3.4.7 pod 日志记录
```bash
2022-11-24 14:15:16.398 [INF] inboundL7Chains:
                              ->[inbound-tls-termination.js]
                              ->[inbound-demux-http.js]
                              ->[inbound-http-routing.js]
                              ->[metrics-http.js]
                              ->[inbound-throttle.js]
                              ->[inbound-mux-http.js]
                              ->[metrics-tcp.js]
                              ->[inbound-proxy-tcp.js]
2022-11-24 14:15:16.398 [INF] inboundL4Chains:
                              ->[inbound-tls-termination.js]
                              ->[inbound-tcp-load-balance.js]
                              ->[metrics-tcp.js]
                              ->[inbound-proxy-tcp.js]
2022-11-24 14:15:16.398 [INF] outboundL7Chains:
                              ->[outbound-demux-http.js]
                              ->[outbound-http-routing.js]
                              ->[metrics-http.js]
                              ->[outbound-breaker.js]
                              ->[plugins/test/header-filter/print-http-headers.js]
                              ->[outbound-mux-http.js]
                              ->[metrics-tcp.js]
                              ->[outbound-proxy-tcp.js]
2022-11-24 14:15:16.398 [INF] outboundL4Chains:
                              ->[outbound-tcp-load-balance.js]
                              ->[metrics-tcp.js]
                              ->[plugins/test/tcp-traffic/print-data-size.js]
                              ->[outbound-proxy-tcp.js]
2022-11-24 14:15:19.671 [INF] ==============[TcpTraffic] send data size: 80
2022-11-24 14:15:20.276 [INF] ==============[TcpTraffic] receive data size: 239
```

#### 3.3.6 删除插件策略

```bash
kubectl delete plugin -n test header-filter
kubectl delete plugin -n test tcp-traffic
```
