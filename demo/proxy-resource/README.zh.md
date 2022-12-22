# OSM Edge 边车容器限定资源测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.2.2
curl -L https://github.com/flomesh/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 边车容器资源

### 3.1 技术概念

在 OSM Edge 中边车容器所使用的资源有三种限定方式:

- 通过 MeshConfig 来限定所有被 OSM Edge 纳管的 Pod 中边车容器所使用的资源
- 通过 Namespace 的 资源限定 Annotation 来限定该 Namespace 下被 OSM Edge 纳管的 Pod 中边车容器所使用的资源
- 通过 Pod的 资源限定 Annotation 来限定该 Pod 中边车容器所使用的资源

三种限定方式的优先级:

​	**Pod的 Annotation > Namespace 的 Annotation > MeshConfig**

Namespace 和 Pod 所支持的资源限定的 Annotation :

- openservicemesh.io/sidecar-resource-limits-cpu
- openservicemesh.io/sidecar-resource-limits-memory
- openservicemesh.io/sidecar-resource-limits-storage
- openservicemesh.io/sidecar-resource-limits-ephemeral-storage
- openservicemesh.io/sidecar-resource-requests-cpu
- openservicemesh.io/sidecar-resource-requests-memory
- openservicemesh.io/sidecar-resource-requests-storage
- openservicemesh.io/sidecar-resource-requests-ephemeral-storage

### 3.2 部署业务 POD

```bash
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/proxy-resource/curl.curl.yaml

#等待依赖的 POD 正常启动
sleep 2
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 3.3 场景测试

#### 3.3.1 查看当前边车容器的资源限定策略

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl get pod -n curl ${curl_client} -o jsonpath='{.spec.containers[1].resources}' | jq
```

执行结果如下:

```bash
{}
```

#### 3.3.2 使用 MeshConfig 来限定边车容器的资源

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"sidecar":{"resources":{"limits":{"memory":"2048M"},"requests":{"memory":"1024M"}}}}}' --type=merge
```

#### 3.3.3 重启 Pod

```bash
kubectl rollout restart deployment -n curl curl
```

#### 3.3.4 查看当前边车容器的资源限定

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl get pod -n curl ${curl_client} -o jsonpath='{.spec.containers[1].resources}' | jq
```

执行结果如下:

```bash
{
  "limits": {
    "memory": "2048M"
  },
  "requests": {
    "memory": "1024M"
  }
}
```

#### 3.3.5 使用 Namespace 的 资源限定 Annotation

```bash
kubectl patch namespace curl -p '{"metadata":{"annotations":{"openservicemesh.io/sidecar-resource-limits-memory":"1024M","openservicemesh.io/sidecar-resource-requests-memory":"512M"}}}' --type=merge
```

#### 3.3.6 重启 Pod

```bash
kubectl rollout restart deployment -n curl curl
```

#### 3.3.7 查看当前边车容器的资源限定

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl get pod -n curl ${curl_client} -o jsonpath='{.spec.containers[1].resources}' | jq
```

执行结果如下:

```bash
{
  "limits": {
    "memory": "1024M"
  },
  "requests": {
    "memory": "512M"
  }
}
```

#### 3.3.8 使用 Pod 的 资源限定 Annotation

```bash
kubectl patch deployment -n curl curl -p '{"spec": {"template": {"metadata": {"annotations": {"openservicemesh.io/sidecar-resource-limits-memory": "512M","openservicemesh.io/sidecar-resource-requests-memory": "512M"}}}}}' --type=merge
```

#### 3.3.9 查看当前边车容器的资源限定

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl get pod -n curl ${curl_client} -o jsonpath='{.spec.containers[1].resources}' | jq
```

执行结果如下:

```bash
{
  "limits": {
    "memory": "512M"
  },
  "requests": {
    "memory": "512M"
  }
}
```

#### 
