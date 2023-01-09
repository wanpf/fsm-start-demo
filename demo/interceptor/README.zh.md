

# OSM Edge eBPF 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.8
curl -L https://github.com/cybwan/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz|tar -vxzf -
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
    --set=osm.image.tag=1.3.0-alpha.8 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.enablePermissiveTrafficPolicy=true \
    --set=osm.sidecarLogLevel=debug \
    --set=osm.controllerLogLevel=warn \
    --set=osm.trafficInterceptionMode=ebpf \
    --timeout=900s
```

## 3. eBPF测试

### 3.1 禁用 mTLS

```bash
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"sidecar":{"sidecarDrivers":[{"proxyServerPort":6060,"sidecarDisabledMTLS":true,"sidecarImage":"localhost:5000/flomesh/pipy-nightly:latest","sidecarName":"pipy"}]}}}' --type=merge
```

### 3.2 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace ebpf
osm namespace add ebpf
kubectl apply -n ebpf -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/interceptor/sleep.yaml
kubectl apply -n ebpf -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/interceptor/helloworld.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n ebpf -l app=sleep --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf -l app=helloworld --timeout=180s
```

### 3.3 场景测试一

#### 3.3.1 测试指令

```bash
sleep_client="$(kubectl get pod -n ebpf -l app=sleep -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${sleep_client} -n ebpf -c sleep -- curl -s -v helloworld:5000/hello
kubectl exec ${sleep_client} -n ebpf -c sleep -- curl -s -v helloworld:5000/hello
kubectl exec ${sleep_client} -n ebpf -c sleep -- curl -s -v helloworld-v1:5000/hello
kubectl exec ${sleep_client} -n ebpf -c sleep -- curl -s -v helloworld-v2:5000/hello
```

#### 3.3.2 测试结果

正确返回结果类似于:

```bash
*   Trying 10.96.203.65:5000...
* Connected to helloworld (127.128.0.1) port 5000 (#0)
> GET /hello HTTP/1.1
> Host: helloworld:5000
> User-Agent: curl/7.85.0-DEV
> Accept: */*
> 
Hello version: v2, instance: helloworld-v2-58d9f4669-k8c8v
* Mark bundle as not supporting multiuse
* HTTP 1.0, assume close after body
< HTTP/1.0 200 OK
< content-type: text/html; charset=utf-8
< server: pipy
< date: Thu, 06 Oct 2022 14:58:16 GMT
< x-pipy-upstream-service-time: 98
< content-length: 59
* HTTP/1.0 connection set to keep alive
< connection: keep-alive
< 
{ [59 bytes data]
* Connection #0 to host helloworld left intact
```

