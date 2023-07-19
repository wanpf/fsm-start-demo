# FSMxLB 负载均衡测试

本测试已经在 Ubuntu 20.04 下验证.

## 1 网络拓扑

![网络拓扑](topo.jpg)

**注意:**  fsmxlb 这台机器上会启动 fsmxlb 容器, fsmxlb 容器至少需要 4G 内存,所以 fsmxlb 这台机器尽量给多一些内存

## 2 部署负载均衡服务

**在 fsmxlb 上执行:**

### 2.1 安装容器环境

```bash
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt-get remove ${pkg}; done
sudo apt -y update
sudo apt -y install ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${VERSION_CODENAME}) stable"  | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt -y update
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 2.2 配置容器网络

#### 2.2.1 创建连接 client 区网络

```bash
docker network create -d macvlan -o parent=ens32 --subnet 11.11.11.0/24 --gateway 11.11.11.254 --aux-address 'host=11.11.11.253' xlbnet11
```

#### 2.2.2 创建连接 k3s 集群 1 网络

```bash
docker network create -d macvlan -o parent=ens34 --subnet 12.12.12.0/24 --gateway 12.12.12.254 --aux-address 'host=12.12.12.253' xlbnet12
```

#### 2.2.3 创建连接 k3s 集群 2 网络

```bash
docker network create -d macvlan -o parent=ens37 --subnet 13.13.13.0/24 --gateway 13.13.13.254 --aux-address 'host=13.13.13.253' xlbnet13
```

#### 2.2.4 查看容器网络

```bash
docker network ls
```

返回结果类似于:

```bash
NETWORK ID     NAME       DRIVER    SCOPE
2eea9bd536bb   bridge     bridge    local
d22189522805   host       host      local
4691db190a6a   none       null      local
cc7af241434d   xlbnet11   macvlan   local
f2570c3cbcf1   xlbnet12   macvlan   local
7de026084d79   xlbnet13   macvlan   local
```

### 2.3 部署fsmxlb服务容器

#### 2.3.1 启动fsmxlb服务容器

```bash
docker run -u root --cap-add SYS_ADMIN  --restart unless-stopped --privileged -dit -v /dev/log:/dev/log --name fsmxlb cybwan/fsm-xlb:1.0.1
```

#### 2.3.2 配置fsmxlb容器网络

```bash
#连接 client 区网络
docker network connect xlbnet11 fsmxlb --ip=11.11.11.1

#连接 k3s 集群 1 网络
docker network connect xlbnet12 fsmxlb --ip=12.12.12.1

#连接 k3s 集群 2 网络
docker network connect xlbnet13 fsmxlb --ip=13.13.13.1
```

#### 2.3.3 查看fsmxlb容器网络

```bash
docker exec fsmxlb ifconfig
```

返回结果类似于:

```bash
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 172.17.0.2  netmask 255.255.0.0  broadcast 172.17.255.255
        ether 02:42:ac:11:00:02  txqueuelen 0  (Ethernet)
        RX packets 8  bytes 736 (736.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

eth1: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 11.11.11.1  netmask 255.255.255.0  broadcast 11.11.11.255
        ether 02:42:0b:0b:0b:01  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

eth2: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 12.12.12.1  netmask 255.255.255.0  broadcast 12.12.12.255
        ether 02:42:0c:0c:0c:01  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

eth3: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 13.13.13.1  netmask 255.255.255.0  broadcast 13.13.13.255
        ether 02:42:0d:0d:0d:01  txqueuelen 0  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

flb0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        ether 1a:04:d7:a3:aa:bd  txqueuelen 1000  (Ethernet)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0

lo: flags=73<UP,LOOPBACK,RUNNING>  mtu 65536
        inet 127.0.0.1  netmask 255.0.0.0
        loop  txqueuelen 1000  (Local Loopback)
        RX packets 0  bytes 0 (0.0 B)
        RX errors 0  dropped 0  overruns 0  frame 0
        TX packets 0  bytes 0 (0.0 B)
        TX errors 0  dropped 0 overruns 0  carrier 0  collisions 0
```

#### 2.3.4 联通性验证

- **从 client ping 11.11.11.1**

- **从 k3s1 ping 12.12.12.1**

- **从 k3s2 ping 13.13.13.1**

以上操作是为了让 fsmxlb 学习路由.

确认路由已经学到,网络联通:

```
docker exec -it fsmxlb ping 11.11.11.254 -c 3
docker exec -it fsmxlb ping 12.12.12.254 -c 3
docker exec -it fsmxlb ping 13.13.13.254 -c 3
```

## 3 部署配置 k3s 集群 1

**在 k3s1 上执行:**

### 3.1 安装k3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.22.9+k3s1 INSTALL_K3S_EXEC="server --disable metrics-server --disable traefik --disable servicelb --disable-cloud-controller --kubelet-arg cloud-provider=external" sh -

sudo kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized=false:NoSchedule-

#等待 Pod 启动完成
watch -n 2 kubectl get pods -A -o wide
```

### 3.2 部署 fsm-ccm 服务

```bash
export CTR_REGISTRY=cybwan
export CTR_TAG=1.0.1
export fsmxlb_api_server_addr=12.12.12.1
export fsmxlb_external_cidr=122.122.122.0/24
curl https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/fsmxlb/fsm-ccm-k3s.yaml -o /tmp/fsm-ccm-k3s.yaml
cat /tmp/fsm-ccm-k3s.yaml | envsubst | kubectl apply -f -

#等待 Pod 启动完成
watch -n 2 kubectl get pods -A -o wide
```

### 3.3 部署模拟业务

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok-service
spec:
  ports:
    - name: pipy
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: pipy-ok
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pipy-ok
  labels:
    app: pipy-ok
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pipy-ok
  template:
    metadata:
      labels:
        app: pipy-ok
    spec:
      containers:
        - name: pipy
          image: flomesh/pipy:latest
          ports:
            - name: pipy
              containerPort: 8080
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8080)
              .serveHTTP(new Message('Hi, I am pipy-ok from k3s cluster 1.\n'))
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok-loadbalance
spec:
  selector:
    app: pipy-ok
  ports:
    - protocol: TCP
      port: 8080
  type: LoadBalancer
EOF

#等待 Pod 启动完成
watch -n 2 kubectl get pods -A -o wide
```

### 3.4 查看服务状态

```bash
sudo kubectl get svc
```

返回结果类似于:

```
NAME                  TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)          AGE
kubernetes            ClusterIP      10.43.0.1       <none>          443/TCP          67m
pipy-ok-service       ClusterIP      10.43.128.151   <none>          8080/TCP         52m
pipy-ok-loadbalance   LoadBalancer   10.43.37.16     122.122.122.1   8080:32411/TCP   52m
```

**pipy-ok-loadbalance服务的外部 IP 为 122.122.122.1**

### 3.5 添加到客户区路由

```
sudo ip r add 11.11.11.0/24 via 12.12.12.1
```

## 4 部署配置 k3s 集群 2

**在 k3s2 上执行:**

### 4.1 安装k3s

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.22.9+k3s1 INSTALL_K3S_EXEC="server --disable metrics-server --disable traefik --disable servicelb --disable-cloud-controller --kubelet-arg cloud-provider=external" sh -

sudo kubectl taint nodes --all node.cloudprovider.kubernetes.io/uninitialized=false:NoSchedule-

#等待 Pod 启动完成
watch -n 2 kubectl get pods -A -o wide
```

### 4.2 部署 fsm-ccm 服务

```bash
export CTR_REGISTRY=cybwan
export CTR_TAG=1.0.1
export fsmxlb_api_server_addr=13.13.13.1
export fsmxlb_external_cidr=133.133.133.0/24
curl https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/fsmxlb/fsm-ccm-k3s.yaml -o /tmp/fsm-ccm-k3s.yaml
cat /tmp/fsm-ccm-k3s.yaml | envsubst | kubectl apply -f -

#等待 Pod 启动完成
watch -n 2 kubectl get pods -A -o wide
```

### 4.3 部署模拟业务

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok-service
spec:
  ports:
    - name: pipy
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: pipy-ok
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pipy-ok
  labels:
    app: pipy-ok
spec:
  replicas: 1
  selector:
    matchLabels:
      app: pipy-ok
  template:
    metadata:
      labels:
        app: pipy-ok
    spec:
      containers:
        - name: pipy
          image: flomesh/pipy:latest
          ports:
            - name: pipy
              containerPort: 8080
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8080)
              .serveHTTP(new Message('Hi, I am pipy-ok from k3s cluster 2.\n'))
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok-loadbalance
spec:
  selector:
    app: pipy-ok
  ports:
    - protocol: TCP
      port: 8080
  type: LoadBalancer
EOF

#等待 Pod 启动完成
watch -n 2 kubectl get pods -A -o wide
```

### 4.4 查看服务状态

```bash
sudo kubectl get svc
```

返回结果类似于:

```
NAME                  TYPE           CLUSTER-IP    EXTERNAL-IP     PORT(S)          AGE
kubernetes            ClusterIP      10.43.0.1     <none>          443/TCP          6m8s
pipy-ok-service       ClusterIP      10.43.44.54   <none>          8080/TCP         4m15s
pipy-ok-loadbalance   LoadBalancer   10.43.34.0    133.133.133.1   8080:30970/TCP   4m14s
```

**pipy-ok-loadbalance服务的外部 IP 为 133.133.133.1**

### 4.5 添加到客户区路由

```
sudo ip r add 11.11.11.0/24 via 13.13.13.1
```

## 5 访问测试

**在 client 上执行:**

### 5.1 添加k3s1虚服务网段122.122.122.0/24的路由

```bash
ip r add 122.122.122.0/24 via 11.11.11.1
```

## 5.2 访问 k3s1 集群下的服务

```bash
curl http://122.122.122.1:8080
```

返回结果类似于:

```
Hi, I am pipy-ok from k3s cluster 1.
```

### 5.3 添加k3s2虚服务网段133.133.133.0/24的路由

```bash
ip r add 133.133.133.0/24 via 11.11.11.1
```

## 5.4 访问 k3s1 集群下的服务

```bash
curl http://133.133.133.1:8080
```

返回结果类似于:

```
Hi, I am pipy-ok from k3s cluster 2.
```
