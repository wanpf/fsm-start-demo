# FSM ClusterSet 测试

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 集群属性设置测试

### 3.1 部署业务 POD

```bash
#模拟客户端
kubectl create namespace curl
fsm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/clusterset/curl.curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s

fsm proxy get config_dump -n curl curl-86d9f68bdf-kdrht | jq .Spec.ClusterSet.ClusterName
```

### 3.2 场景测试一：集群名称设置测试

#### 3.2.1 设置集群名字

```
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"clusterSet":{"properties":[{"name":"ClusterName","value":"dev-cluster-1"}]}}}' --type=merge
```

#### 3.2.4 测试指令

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
fsm proxy get config_dump -n curl "$curl_client" | jq .Spec.ClusterSet.ClusterName
```

#### 3.2.5 测试结果

正确返回结果类似于:

```bash
"dev-cluster-1"
```
