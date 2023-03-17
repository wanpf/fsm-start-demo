### 安装 CNI 插件

在所有的节点上执行下面的命令，下载 CNI 插件。

```shell
sudo mkdir -p /opt/cni/bin
curl -sSL https://github.com/containernetworking/plugins/releases/download/v1.1.1/cni-plugins-linux-amd64-v1.1.1.tgz | sudo tar -zxf - -C /opt/cni/bin
```

### master 节点

获取 master 节点的 IP 地址。

```shell
export MASTER_IP=10.0.2.6
```

安装集群，这里禁用 k3s 的 flannel。

```shell
curl -sfL https://get.k3s.io | sh -s - --disable traefik --disable servicelb --flannel-backend=none --advertise-address $MASTER_IP --write-kubeconfig-mode 644 --write-kubeconfig ~/.kube/config
```

安装 Flannel。**这里注意，Flannel 默认的 Pod CIRD 是 `10.244.0.0/16`，我们将其修改为 k3s 默认的 `10.42.0.0/16`。**

```shell
curl -s https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml | sed 's|10.244.0.0/16|10.42.0.0/16|g' | kubectl apply -f -
```

获取 apiserver 的访问 token。

```shell
sudo cat /var/lib/rancher/k3s/server/node-token
```

### 工作节点

使用 master 节点的 IP 地址以及前面获取的 token。

```shell
export INSTALL_K3S_VERSION=v1.23.8+k3s2
export MASTER_IP=10.0.2.6
export NODE_TOKEN=K107c1890ae060d191d347504740566f9c506b95ea908ba4795a7a82ea2c816e5dc::server:2757787ec4f9975ab46b5beadda446b7
curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -
```

### 下载 osm-edge CLI

```shell
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.3
curl -L https://github.com/flomesh-io/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/osm version
sudo cp ./${system}-${arch}/osm /usr/local/bin/
```

### 安装 osm-edge

```bash
export osm_namespace=osm-system 
export osm_mesh_name=osm 

osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=flomesh \
    --set=osm.image.tag=1.3.3 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.enablePermissiveTrafficPolicy=true \
    --set=osm.sidecarLogLevel=debug \
    --set=osm.controllerLogLevel=warn \
    --set=osm.trafficInterceptionMode=ebpf \
    --set=osm.osmInterceptor.debug=true \
    --timeout=900s
```

### 部署示例应用

```bash
#模拟业务服务
kubectl create namespace ebpf
osm namespace add ebpf
kubectl apply -n ebpf -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/interceptor/curl.yaml
kubectl apply -n ebpf -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/interceptor/pipy-ok.yaml

#让 Pod 分布到不同的 node 上
kubectl patch deployments curl -n ebpf -p '{"spec":{"template":{"spec":{"nodeName":"node1"}}}}'
kubectl patch deployments pipy-ok-v1 -n ebpf -p '{"spec":{"template":{"spec":{"nodeName":"node1"}}}}'
kubectl patch deployments pipy-ok-v2 -n ebpf -p '{"spec":{"template":{"spec":{"nodeName":"node2"}}}}'

sleep 5

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n ebpf -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf -l app=pipy-ok -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf -l app=pipy-ok -l version=v2 --timeout=180s
```

```shell
sudo cat /sys/kernel/debug/tracing/trace_pipe | grep bpf_trace_printk
```

```shell
curl_client="$(kubectl get pod -n ebpf -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n ebpf -c curl -- curl -s pipy-ok:8080
```