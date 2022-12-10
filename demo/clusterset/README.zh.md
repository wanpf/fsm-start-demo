# OSM Edge ClusterSet 测试

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

## 3. 集群属性设置测试

### 3.1 部署业务 POD

```bash
#模拟客户端
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/clusterset/curl.curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s

osm proxy get config_dump -n curl curl-86d9f68bdf-kdrht | jq .Spec.ClusterSet.ClusterName
```

### 3.2 场景测试一：集群名称设置测试

#### 3.2.1 设置集群名字

```
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"clusterSet":{"properties":[{"name":"ClusterName","value":"dev-cluster-1"}]}}}' --type=merge
```

#### 3.2.4 测试指令

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
osm proxy get config_dump -n curl "$curl_client" | jq .Spec.ClusterSet.ClusterName
```

#### 3.2.5 测试结果

正确返回结果类似于:

```bash
"dev-cluster-1"
```
