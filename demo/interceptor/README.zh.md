

# OSM Edge eBPF 测试

## 1.部署k8s环境

### 1.1 部署环境准备

- [ ] 部署 3 个 **ubuntu 20.04/22.04** 的虚机，一个作为 master，两个作为 node

- [ ] 主机名分别设置为 master，node1，node2

- [ ] 修改/etc/hosts，使其相互间可以通过主机名互通

- [ ] 更新系统软件包: 

  ```bash
  sudo apt -y update && sudo apt -y upgrade
  ```

- [ ] root身份执行后续部署指令

### 1.2 各虚拟机上部署容器环境

```bash
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-scripts/main/scripts/install-k8s-node-init.sh -O
chmod u+x install-k8s-node-init.sh

system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
./install-k8s-node-init.sh ${arch} ${system}
```

### 1.3 各虚拟机上部署 k8s 工具

```bash
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-scripts/main/scripts/install-k8s-node-init-tools.sh -O
chmod u+x install-k8s-node-init-tools.sh

system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
./install-k8s-node-init-tools.sh ${arch} ${system}

source ~/.bashrc 
```

### 1.4 Master节点启动 k8s 相关服务

```bash
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-scripts/main/scripts/install-k8s-node-master-start.sh -O
chmod u+x install-k8s-node-master-start.sh

#调整为你的 master 的 ip 地址
MASTER_IP=192.168.127.80
#使用 flannel 网络插件
CNI=flannel
./install-k8s-node-master-start.sh ${MASTER_IP} ${CNI}
#耐心等待...
```

### 1.5 Node1&2节点启动 k8s 相关服务

```bash
curl -L https://raw.githubusercontent.com/cybwan/osm-edge-scripts/main/scripts/install-k8s-node-worker-join.sh -O
chmod u+x install-k8s-node-worker-join.sh

#调整为你的 master 的 ip 地址
MASTER_IP=192.168.127.80
./install-k8s-node-worker-join.sh ${MASTER_IP}
```

### 1.6 Master节点查看 k8s 相关服务的启动状态

```bash
kubectl get pods -A -o wide
```

## 2. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.3
curl -L https://github.com/flomesh-io/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/osm version
cp ./${system}-${arch}/osm /usr/local/bin/
```

## 3. 安装 osm-edge

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

## 4. eBPF替代 iptables测试

### 4.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace ebpf
osm namespace add ebpf
kubectl apply -n ebpf -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/interceptor/curl.yaml
kubectl apply -n ebpf -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/interceptor/pipy-ok.yaml

#让 Pod 分布到不同的 node 上
kubectl patch deployments pipy-ok-v1 -n ebpf -p '{"spec":{"template":{"spec":{"nodeName":"node1"}}}}'
kubectl patch deployments pipy-ok-v2 -n ebpf -p '{"spec":{"template":{"spec":{"nodeName":"node2"}}}}'

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n ebpf -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf -l app=pipy-ok -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf -l app=pipy-ok -l version=v2 --timeout=180s
```

### 4.2 场景测试一

#### 4.2.1 在 node1&2 上监测内核日志

```bash
cat /sys/kernel/debug/tracing/trace_pipe|grep bpf_trace_printk
```

#### 4.2.2 测试指令

多次执行:

```bash
curl_client="$(kubectl get pod -n ebpf -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n ebpf -c curl -- curl -s pipy-ok:8080
```

#### 4.2.3 测试结果

正确返回结果类似于:

```bash
Hi, I am pipy ok v1 !
Hi, I am pipy ok v2 !
```

