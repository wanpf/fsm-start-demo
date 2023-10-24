https://github.com/flomesh-io/fsm/tree/main/docs/tests/gateway-api

## 部署 ELB

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.12.1/manifests/metallb.yaml

kubectl get pods -n metallb-system --watch

docker network inspect -f '{{.IPAM.Config}}' kind

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 172.19.255.200-172.19.255.250
EOF
```

### 部署 Consul

``` shell
export DEMO_HOME=https://raw.githubusercontent.com/addozhang/springboot-bookstore-demo/single
kubectl apply -n default -f ${DEMO_HOME}/manifests/consul.yaml
```

### 部署 FSM

安装 FSM CLI

``` shell
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.1.1
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
sudo cp ./${system}-${arch}/fsm /usr/local/bin/
```

``` shell
export fsm_namespace=fsm-system
export fsm_mesh_name=fsm
export consul_svc_addr="$(kubectl get svc -l name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.image.registry=localhost:5000/flomesh \
    --set=fsm.image.tag=latest \
    --set=fsm.image.pullPolicy=Always \
    --set fsm.fsmIngress.enabled=false \
    --set fsm.fsmGateway.enabled=true \
    --set=fsm.controllerLogLevel=debug \
    --set=fsm.serviceAccessMode=mixed \
    --set=fsm.deployConsulConnector=true \
    --set=fsm.cloudConnector.consul.deriveNamespace=consul-derive \
    --set=fsm.cloudConnector.consul.httpAddr=$consul_svc_addr:8500 \
    --set=fsm.cloudConnector.consul.passingOnly=false \
    --set=fsm.cloudConnector.consul.suffixTag=version \
    --timeout=900s

kubectl create namespace consul-derive
fsm namespace add consul-derive
kubectl patch namespace consul-derive -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"consul"}}}'  --type=merge
fsm namespace remove default --disable-sidecar-injection
```

## 部署网关

```bash
export fsm_namespace=fsm-system
cat <<EOF | kubectl apply -n "$fsm_namespace" -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: consul-gw
spec:
  gatewayClassName: fsm-gateway-cls
  listeners:
    - protocol: HTTP
      port: 10080
      name: http
    - protocol: TCP
      port: 20090
      name: tcp
EOF
```

### 配置访问控制策略

这里需要开启访问控制策略特性并配置访问控制策略，执行下面的命令开始访问控制策略特性。

``` shell
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

设置访问控制策略，允许 Consul 访问网格中的微服务，进行健康检查。

``` shell
kubectl apply -n consul-derive -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: consul
spec:
  sources:
  - kind: Service
    namespace: default
    name: consul
EOF
```

### 部署应用

创建命名空间

``` shell
kubectl create namespace bookstore
kubectl create namespace bookbuyer
kubectl create namespace bookthief
kubectl create namespace bookwarehouse
```

将命名空间加入网格

``` shell
fsm namespace add bookstore bookbuyer bookthief bookwarehouse
```

部署应用

``` shell
export DEMO_HOME=https://raw.githubusercontent.com/addozhang/springboot-bookstore-demo/single
kubectl apply -n bookwarehouse -f ${DEMO_HOME}/manifests/bookwarehouse.yaml
kubectl apply -n bookstore -f ${DEMO_HOME}/manifests/bookstore.yaml
kubectl apply -n bookbuyer -f ${DEMO_HOME}/manifests/bookbuyer.yaml
kubectl apply -n bookthief -f ${DEMO_HOME}/manifests/bookthief.yaml
```

## 

```
kubectl port-forward "$(kubectl get pod -n default -l app=consul -o jsonpath='{.items..metadata.name}')" 8500:8500
```

