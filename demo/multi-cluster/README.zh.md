# OSM Edge 多集群测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.5
curl -L https://github.com/cybwan/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/osm version
cp ./${system}-${arch}/osm /usr/local/bin/
```

## 2. 下载并安装 kubecm 命令行工具

```bash
https://github.com/sunny0826/kubecm/releases
```

## 3. 部署多集群环境

### 3.1 编译 FSM 控制平面组件

```bash
git clone -b release-v0.2 https://github.com/flomesh-io/fsm.git
cd fsm
make dev
```

### 3.2 部署控制平面集群和两个业务集群

```bash
curl -o kind-with-registry.sh https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/scripts/kind-with-registry.sh
chmod u+x kind-with-registry.sh

#调整为你的 Host 的 IP 地址
MY_HOST_IP=192.168.127.91
export API_SERVER_ADDR=${MY_HOST_IP}

KIND_CLUSTER_NAME=control-plane MAPPING_HOST_PORT=8090 API_SERVER_PORT=6445 ./kind-with-registry.sh
KIND_CLUSTER_NAME=cluster1 MAPPING_HOST_PORT=8091 API_SERVER_PORT=6446 ./kind-with-registry.sh
KIND_CLUSTER_NAME=cluster2 MAPPING_HOST_PORT=8092 API_SERVER_PORT=6447 ./kind-with-registry.sh
KIND_CLUSTER_NAME=cluster3 MAPPING_HOST_PORT=8093 API_SERVER_PORT=6448 ./kind-with-registry.sh
```

### 3.3 部署 FSM 控制平面组件

```bash
curl -o deploy-fsm-control-plane.sh https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/scripts/deploy-fsm-control-plane.sh
chmod u+x deploy-fsm-control-plane.sh

export FSM_NAMESPACE=flomesh
export FSM_VERSION=0.2.0-alpha.10
export FSM_CHART=charts/fsm

KIND_CLUSTER_NAME=control-plane ./deploy-fsm-control-plane.sh
KIND_CLUSTER_NAME=cluster1 ./deploy-fsm-control-plane.sh
KIND_CLUSTER_NAME=cluster2 ./deploy-fsm-control-plane.sh
KIND_CLUSTER_NAME=cluster3 ./deploy-fsm-control-plane.sh
```

### 3.4 集群 1 加入多集群纳管

```bash
kubecm switch kind-control-plane
cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: Cluster
metadata:
  name: cluster1
spec:
  gatewayHost: ${API_SERVER_ADDR}
  gatewayPort: 8091
  kubeconfig: |+
`kind get kubeconfig --name cluster1 | sed 's/^/    /g'`
EOF
```

### 3.5 集群 2 加入多集群纳管

```bash
kubecm switch kind-control-plane
cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: Cluster
metadata:
  name: cluster2
spec:
  gatewayHost: ${API_SERVER_ADDR}
  gatewayPort: 8092
  kubeconfig: |+
`kind get kubeconfig --name cluster2 | sed 's/^/    /g'`
EOF
```

### 3.6 集群 3 加入多集群纳管

```bash
kubecm switch kind-control-plane
cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: Cluster
metadata:
  name: cluster3
spec:
  gatewayHost: ${API_SERVER_ADDR}
  gatewayPort: 8093
  kubeconfig: |+
`kind get kubeconfig --name cluster3 | sed 's/^/    /g'`
EOF
```

## 4. 安装 osm-edge

### 4.1 集群 1 安装 osm-edge

```bash
kubecm switch kind-cluster1
export osm_namespace=osm-system
export osm_mesh_name=osm
dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=cybwan \
    --set=osm.image.tag=1.3.0-alpha.1 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s \
    --set=osm.localDNSProxy.enable=true \
    --set=osm.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}"
```

### 4.2 集群 2 安装 osm-edge

```bash
kubecm switch kind-cluster2
export osm_namespace=osm-system
export osm_mesh_name=osm
dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=cybwan \
    --set=osm.image.tag=1.3.0-alpha.1 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s \
    --set=osm.localDNSProxy.enable=true \
    --set=osm.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}"
```

### 4.3 集群 3 安装 osm-edge

```bash
kubecm switch kind-cluster3
export osm_namespace=osm-system
export osm_mesh_name=osm
dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=cybwan \
    --set=osm.image.tag=1.3.0-alpha.1 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s \
    --set=osm.localDNSProxy.enable=true \
    --set=osm.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}"
```

## 5. 多集群测试

### 5.1 部署模拟业务服务

#### 5.1.1 集群 1 部署不被 osm edge 纳管的业务服务

```bash
kubecm switch kind-cluster1
kubectl create namespace pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/multi-cluster/pipy-ok-c1.pipy.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok-c1 --timeout=180s
```

#### 5.1.2 集群 1 部署被 osm edge 纳管的业务服务

```bash
kubecm switch kind-cluster1
kubectl create namespace pipy-osm
osm namespace add pipy-osm
kubectl apply -n pipy-osm -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/multi-cluster/pipy-ok-c1.pipy-osm.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy-osm -l app=pipy-ok-c1 --timeout=180s
```

#### 5.1.3 集群 1 导出任意 SA 业务服务

```bash
kubecm switch kind-cluster1

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok-c1"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c1
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm-c1"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8091/c1/ok
curl -s http://$API_SERVER_ADDR:8091/c1/ok-c1
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm-c1
```

#### 5.1.4 集群 3 部署不被 osm edge 纳管的业务服务

```bash
kubecm switch kind-cluster3
#kubectl create namespace pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/multi-cluster/pipy-ok-c3.pipy.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok-c3 --timeout=180s
```

#### 5.1.5 集群 3 部署被 osm edge 纳管的业务服务

```bash
kubecm switch kind-cluster3
#kubectl create namespace pipy-osm
osm namespace add pipy-osm
kubectl apply -n pipy-osm -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/multi-cluster/pipy-ok-c3.pipy-osm.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy-osm -l app=pipy-ok-c3 --timeout=180s
```

#### 5.1.6 集群 3 导出任意 SA 业务服务

```bash
kubecm switch kind-cluster3

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c3
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok-c3"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c3
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm-c3"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8093/c3/ok
curl -s http://$API_SERVER_ADDR:8093/c3/ok-c3
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm-c3
```

#### 5.1.7 集群 2 导入业务服务

```bash
kubecm switch kind-cluster2
osm namespace add pipy-osm

#创建完 Namespace, 补偿创建ServiceImporI,有延迟,需等待
kubectl get serviceimports.flomesh.io -A
kubectl get serviceimports.flomesh.io -n pipy pipy-ok -o yaml
kubectl get serviceimports.flomesh.io -n pipy pipy-ok-c1 -o yaml
kubectl get serviceimports.flomesh.io -n pipy pipy-ok-c3 -o yaml
kubectl get serviceimports.flomesh.io -n pipy-osm pipy-ok -o yaml
kubectl get serviceimports.flomesh.io -n pipy-osm pipy-ok-c1 -o yaml
kubectl get serviceimports.flomesh.io -n pipy-osm pipy-ok-c3 -o yaml
```

#### 5.1.8 集群 2 部署被 osm edge 纳管的客户端

```bash
kubecm switch kind-cluster2
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/multi-cluster/curl.curl.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 5.2 场景测试一：导入集群不存在同质服务

#### 5.2.1 设置多集群流量负载均衡策略: Locality

如未做设置,多集群流量负载均衡策略默认为: Locality

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c3
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok-c1
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok-c3
spec:
  lbType: Locality
EOF
```

#### 5.2.2 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.2.3 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.2.4 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c1.pipy:8080/
```

#### 5.2.5 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.2.6 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c3.pipy:8080/
```

#### 5.2.7 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.2.8 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy-osm:8080/
```

#### 5.2.9 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.2.10 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c1.pipy-osm:8080/
```

#### 5.2.11 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.2.12 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c3.pipy-osm:8080/
```

#### 5.2.13 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.2.14 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c3
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok-c1
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok-c3
spec:
  lbType: ActiveActive
EOF
```

#### 5.2.15 测试指令

连续执行四次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.2.16 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 2
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 2
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 2
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 2
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
```

#### 5.2.17 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c1.pipy:8080/
```

#### 5.2.18 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !
```

#### 5.2.19 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c3.pipy:8080/
```

#### 5.2.20 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 2
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
```

#### 5.2.21 测试指令

连续执行四次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy-osm:8080/
```

#### 5.2.22 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster1 and controlled by OSM !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 5
content-length: 46
connection: keep-alive

Hi, I am from Cluster3 and controlled by OSM !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster1 and controlled by OSM !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 5
content-length: 46
connection: keep-alive

Hi, I am from Cluster3 and controlled by OSM !
```

#### 5.2.23 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c1.pipy-osm:8080/
```

#### 5.2.24 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster1 and controlled by OSM !
```

#### 5.2.25 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok-c3.pipy-osm:8080/
```

#### 5.2.26 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster3 and controlled by OSM !
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubecm switch kind-cluster2
kubectl get globaltrafficpolicies.flomesh.io -A
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok-c1
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok-c3
kubectl delete globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok
kubectl delete globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok-c1
kubectl delete globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok-c3
```

### 5.3 场景测试二：导入集群存在同质无 SA 服务

#### 5.3.1 部署无SA业务服务

```bash
kubecm switch kind-cluster2
osm namespace add pipy
cat <<EOF | kubectl apply -n pipy -f -
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
        - name: pipy-ok
          image: flomesh/pipy:0.50.0-146
          ports:
            - name: pipy
              containerPort: 8080
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8080)
              .serveHTTP(new Message('Hi, I am from Cluster2 !'))
---
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok
spec:
  ports:
    - name: pipy
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: pipy-ok
EOF

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

#### 5.3.2 设置多集群流量负载均衡策略: Locality

如未做设置,多集群流量负载均衡策略默认为: Locality

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: Locality
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

#### 5.3.3 测试指令

连续执行多次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.3.4 测试结果

每次正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 8
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

分析测试结果:请求只有 cluster2 集群的服务响应

#### 5.3.5 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

#### 5.3.6 测试指令

连续执行三次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.3.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
```

分析测试结果:请求被三个集群的服务响应

#### 5.3.8 设置多集群流量负载均衡策略: ActiveActive

导入的集群服务，只允许 cluster1 下的pipy-ok.pipy参与集群间负载均衡

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
  targets:
    - clusterKey: default/default/default/cluster1
      weight: 100
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

#### 5.3.9 测试指令

连续执行四次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.3.10 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !
```

分析测试结果:请求被两个集群的服务响应

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubecm switch kind-cluster2
kubectl delete deployments -n pipy pipy-ok
kubectl delete service -n pipy pipy-ok
kubectl get globaltrafficpolicies.flomesh.io -A
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok
```

### 5.4 场景测试三：导入集群存在同质有 SA 服务

#### 5.4.1 部署有SA业务服务

```bash
kubecm switch kind-cluster2
osm namespace add pipy
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipy
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
      serviceAccountName: pipy
      containers:
        - name: pipy-ok
          image: flomesh/pipy:0.50.0-146
          ports:
            - name: pipy
              containerPort: 8080
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8080)
              .serveHTTP(new Message('Hi, I am from Cluster2 !'))
---
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok
spec:
  ports:
    - name: pipy
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: pipy-ok
EOF

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

#### 5.4.2 设置多集群流量负载均衡策略: Locality

如未做设置,多集群流量负载均衡策略默认为: Locality

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: Locality
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

#### 5.4.3 测试指令

连续执行多次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.4.4 测试结果

每次正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

#### 5.4.5 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

#### 5.4.6 测试指令

连续执行三次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.4.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
```

分析测试结果:请求被三个集群的服务响应

#### 5.4.8 设置多集群流量负载均衡策略: ActiveActive

导入的集群服务，只允许 cluster3 下的pipy-ok.pipy参与集群间负载均衡

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
  targets:
    - clusterKey: default/default/default/cluster3
      weight: 100
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

#### 5.4.9 测试指令

连续执行四次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.3.10 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

分析测试结果:请求被两个集群的服务响应

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubecm switch kind-cluster2
kubectl delete deployments -n pipy pipy-ok
kubectl delete service -n pipy pipy-ok
kubectl delete serviceaccount -n pipy pipy
kubectl get globaltrafficpolicies.flomesh.io -A
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok
```

### 5.5 场景测试四：多集群SMI流量策略

#### 5.5.1 禁用流量宽松模式

```bash
kubecm switch kind-cluster2
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":false}}}' --type=merge
```

#### 5.5.2 部署有SA业务服务

```bash
kubecm switch kind-cluster2
osm namespace add pipy
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: pipy
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
      serviceAccountName: pipy
      containers:
        - name: pipy-ok
          image: flomesh/pipy:0.50.0-146
          ports:
            - name: pipy
              containerPort: 8080
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8080)
              .serveHTTP(new Message('Hi, I am from Cluster2 !'))
---
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok
spec:
  ports:
    - name: pipy
      port: 8080
      targetPort: 8080
      protocol: TCP
  selector:
    app: pipy-ok
EOF

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

#### 5.5.3 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.5.4 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 52
```

#### 5.5.5 设置流量策略[curl访问 pipy-ok.pipy]

```
kubecm switch kind-cluster2
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: pipy-ok-service-routes
spec:
  matches:
  - name: pipy-ok
    pathRegex: "/"
    methods:
    - GET
EOF

cat <<EOF | kubectl apply -n pipy -f -
kind: TrafficTarget
apiVersion: access.smi-spec.io/v1alpha3
metadata:
  name: curl-access-pipy-ok
spec:
  destination:
    kind: ServiceAccount
    name: pipy
    namespace: pipy
  rules:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-routes
    matches:
    - pipy-ok
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: curl
EOF
```

#### 5.5.6 设置流量策略[curl访问 pipy-ok.pipy-osm]

```
kubecm switch kind-cluster2
cat <<EOF | kubectl apply -n pipy-osm -f -
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: pipy-ok-service-routes
spec:
  matches:
  - name: pipy-ok
    pathRegex: "/"
    methods:
    - GET
EOF

cat <<EOF | kubectl apply -n pipy-osm -f -
kind: TrafficTarget
apiVersion: access.smi-spec.io/v1alpha3
metadata:
  name: curl-access-pipy-ok-osm
spec:
  destination:
    kind: ServiceAccount
    name: pipy
    namespace: pipy-osm
  rules:
  - kind: HTTPRouteGroup
    name: pipy-ok-service-routes
    matches:
    - pipy-ok
  sources:
  - kind: ServiceAccount
    name: curl
    namespace: curl
EOF
```

#### 5.5.7 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

#### 5.5.8 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

#### 5.5.9 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy-osm:8080/
```

#### 5.5.13 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.5.14 场景测试四-1: 导出服务任意 SA 测试

##### 5.5.14.1 集群 1 导出任意 SA 业务服务

```bash
kubecm switch kind-cluster1

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok-c1"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c1
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm-c1"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8091/c1/ok
curl -s http://$API_SERVER_ADDR:8091/c1/ok-c1
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm-c1
```

##### 5.5.14.2 集群 3 导出任意 SA 业务服务

```bash
kubecm switch kind-cluster3

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c3
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok-c3"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c3
spec:
  serviceAccountName: "*"
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm-c3"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8093/c3/ok
curl -s http://$API_SERVER_ADDR:8093/c3/ok-c3
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm-c3
```

##### 5.5.14.3 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  lbType: ActiveActive
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
kubectl get globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok -o yaml
```

##### 5.5.14.4 测试指令

连续执行三次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.14.5 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
```

##### 5.5.14.6 测试指令

连续执行两次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy-osm:8080/
```

##### 5.5.14.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster1 and controlled by OSM !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 46
connection: keep-alive

Hi, I am from Cluster3 and controlled by OSM !
```

#### 5.5.15 场景测试四-2: 导出服务无 SA 测试

##### 5.5.15.1 集群 1 导出无 SA 业务服务

```bash
kubecm switch kind-cluster1

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  rules:
    - portNumber: 8080
      path: "/c1/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  rules:
    - portNumber: 8080
      path: "/c1/ok-c1"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c1
spec:
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm-c1"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8091/c1/ok
curl -s http://$API_SERVER_ADDR:8091/c1/ok-c1
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm-c1
```

##### 5.5.15.2 集群 3 导出无 SA 业务服务

```bash
kubecm switch kind-cluster3

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  rules:
    - portNumber: 8080
      path: "/c3/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c3
spec:
  rules:
    - portNumber: 8080
      path: "/c3/ok-c3"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c3
spec:
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm-c3"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8093/c3/ok
curl -s http://$API_SERVER_ADDR:8093/c3/ok-c3
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm-c3
```

##### 5.5.15.3 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  lbType: ActiveActive
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
kubectl get globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok -o yaml
```

##### 5.5.15.4 测试指令

连续执行多次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.15.5 测试结果

每次正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 1
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

##### 5.5.15.6 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy-osm:8080/
```

##### 5.5.15.7 测试结果

正确返回结果类似于:

```bash
command terminated with exit code 7
```

#### 5.5.16 场景测试四-3: 导出服务特定 SA 测试

##### 5.5.16.1 集群 1 导出特定 SA 业务服务

```bash
kubecm switch kind-cluster1

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c1/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c1/ok-c1"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c1
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c1/ok-osm-c1"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8091/c1/ok
curl -s http://$API_SERVER_ADDR:8091/c1/ok-c1
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm
curl -s http://$API_SERVER_ADDR:8091/c1/ok-osm-c1
```

##### 5.5.16.2 集群 3 导出特定 SA 业务服务

```bash
kubecm switch kind-cluster3

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c3/ok"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy
  name: pipy-ok-c3
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c3/ok-c3"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm"
      pathType: Prefix
---
apiVersion: flomesh.io/v1alpha1
kind: ServiceExport
metadata:
  namespace: pipy-osm
  name: pipy-ok-c3
spec:
  serviceAccountName: pipy
  rules:
    - portNumber: 8080
      path: "/c3/ok-osm-c3"
      pathType: Prefix
EOF

kubectl get serviceexports.flomesh.io -A
curl -s http://$API_SERVER_ADDR:8093/c3/ok
curl -s http://$API_SERVER_ADDR:8093/c3/ok-c3
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm
curl -s http://$API_SERVER_ADDR:8093/c3/ok-osm-c3
```

##### 5.5.16.3 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy-osm
  name: pipy-ok
spec:
  lbType: ActiveActive
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
kubectl get globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok -o yaml
```

##### 5.5.16.4 测试指令

连续执行三次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.16.5 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !
```

##### 5.5.16.6 测试指令

连续执行两次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy-osm:8080/
```

##### 5.5.16.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster1 and controlled by OSM !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 46
connection: keep-alive

Hi, I am from Cluster3 and controlled by OSM !
```

#### 5.5.17 场景测试四-4: 多集群流量负载均衡权重测试

##### 5.5.17.1 设置多集群流量负载均衡权重策略

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
  targets:
    - clusterKey: default/default/default/cluster1
      weight: 50
    - clusterKey: default/default/default/cluster3
      weight: 50
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
```

本集群服务默认权重为 100，故 50%流量送 cluster2，25%流量送 cluster1，25%流量送 cluster3

##### 5.5.17.2 测试指令

连续执行四次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.17.3 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 6
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

#### 5.5.18 场景测试四-5: 分流测试

##### 5.5.18.1 设置多集群流量负载均衡策略: ActiveActive

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  lbType: ActiveActive
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok-c1 -o yaml
```

##### 5.5.18.2 设置分流策略[pipy-ok.pipy]

```
kubecm switch kind-cluster2
cat <<EOF | kubectl apply -n pipy -f -
apiVersion: split.smi-spec.io/v1alpha2
kind: TrafficSplit
metadata:
  name: pipy-ok-split
spec:
  service: pipy-ok
  backends:
  - service: pipy-ok
    weight: 75
  - service: pipy-ok-c1
    weight: 25
EOF
```

三个集群都有 pipy-ok 服务，故均分权重 75，每个权重 25；只有 cluster1 有pipy-ok-c1，独占权重 25

故 50%流量送 cluster1，25%流量送 cluster2，25%流量送 cluster3

##### 5.5.18.3 测试指令

连续执行四次:

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.18.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 3
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 4
content-length: 24
connection: keep-alive

Hi, I am from Cluster3 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 10
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !

HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 5
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

#### 5.5.19 场景测试四-6.1: 多集群流量FailOver测试

##### 5.5.19.1 设置多集群流量负载均衡策略: FailOver

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: FailOver
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok-c1 -o yaml
```

##### 5.5.19.2 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.19.3 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 1
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

##### 5.5.19.4 部署返回错误的业务服务

```bash
kubecm switch kind-cluster2
osm namespace add pipy
cat <<EOF | kubectl apply -n pipy -f -
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
      serviceAccountName: pipy
      containers:
        - name: pipy-ok
          image: flomesh/pipy:0.50.0-146
          ports:
            - name: pipy
              containerPort: 8080
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8080)
              .serveHTTP(new Message({status: 403}, 'Access denied'))
EOF

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

##### 5.5.19.5 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.19.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 1
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !
```

#### 5.5.20 场景测试四-6.2: 多集群流量FailOver测试

##### 5.5.20.1 部署有SA业务服务

服务目标端口和控制网关暴露端口相同

```bash
kubecm switch kind-cluster2
osm namespace add pipy
cat <<EOF | kubectl apply -n pipy -f -
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
      serviceAccountName: pipy
      containers:
        - name: pipy-ok
          image: flomesh/pipy:0.50.0-146
          ports:
            - name: pipy
              containerPort: 8091
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8091)
              .serveHTTP(new Message('Hi, I am from Cluster2 !'))
---
apiVersion: v1
kind: Service
metadata:
  name: pipy-ok
spec:
  ports:
    - name: pipy
      port: 8080
      targetPort: 8091
      protocol: TCP
  selector:
    app: pipy-ok
EOF

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

##### 5.5.20.2 设置多集群流量负载均衡策略: FailOver

```bash
kubecm switch kind-cluster2

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok-c1
spec:
  lbType: Locality
---
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: FailOver
  targets:
    - clusterKey: default/default/default/cluster1
      weight: 100
EOF

kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok -o yaml
kubectl get globaltrafficpolicies.flomesh.io -n pipy pipy-ok-c1 -o yaml
```

##### 5.5.20.3 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.20.4 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 1
content-length: 24
connection: keep-alive

Hi, I am from Cluster2 !
```

##### 5.5.20.5 部署返回错误的业务服务

服务目标端口和控制网关暴露端口相同

```bash
kubecm switch kind-cluster2
osm namespace add pipy
cat <<EOF | kubectl apply -n pipy -f -
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
      serviceAccountName: pipy
      containers:
        - name: pipy-ok
          image: flomesh/pipy:0.50.0-146
          ports:
            - name: pipy
              containerPort: 8091
          command:
            - pipy
            - -e
            - |
              pipy()
              .listen(8091)
              .serveHTTP(new Message({status: 403}, 'Access denied'))
EOF

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

##### 5.5.20.6 测试指令

```bash
kubecm switch kind-cluster2
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "${curl_client}" -n curl -c curl -- curl -si http://pipy-ok.pipy:8080/
```

##### 5.5.20.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
server: pipy
x-pipy-upstream-service-time: 1
content-length: 24
connection: keep-alive

Hi, I am from Cluster1 !
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubecm switch kind-cluster2
kubectl get trafficsplits.split.smi-spec.io -A
kubectl delete trafficsplits.split.smi-spec.io -n pipy pipy-ok-split
kubectl get traffictargets.access.smi-spec.io -A
kubectl delete traffictargets.access.smi-spec.io -n pipy curl-access-pipy-ok
kubectl delete traffictargets.access.smi-spec.io -n pipy-osm curl-access-pipy-ok-osm
kubectl get httproutegroups.specs.smi-spec.io -A
kubectl delete httproutegroups.specs.smi-spec.io -n pipy pipy-ok-service-routes
kubectl delete httproutegroups.specs.smi-spec.io -n pipy-osm pipy-ok-service-routes
kubectl get globaltrafficpolicies.flomesh.io -A
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok
kubectl delete globaltrafficpolicies.flomesh.io -n pipy pipy-ok-c1
kubectl delete globaltrafficpolicies.flomesh.io -n pipy-osm pipy-ok
kubectl delete deployments -n pipy pipy-ok
kubectl delete service -n pipy pipy-ok
kubectl delete serviceaccount -n pipy pipy
```

## 6. 多集群卸载

```
kind delete cluster --name control-plane
kind delete cluster --name cluster1
kind delete cluster --name cluster2
kind delete cluster --name cluster3
```