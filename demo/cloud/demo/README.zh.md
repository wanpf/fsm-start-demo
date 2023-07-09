# FSM Consul集成测试

## 1. 下载并安装 fsm cli

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.2
curl -L https://github.com/cybwan/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2.部署 Consul 服务

```bash
#部署Consul服务
export DEMO_HOME=https://raw.githubusercontent.com/cybwan/fsm-start-demo/main

curl $DEMO_HOME/demo/cloud/consul/kubernetes-vault/certs/ca.pem -o /tmp/ca.pem
curl $DEMO_HOME/demo/cloud/consul/kubernetes-vault/certs/consul.pem -o /tmp/consul.pem
curl $DEMO_HOME/demo/cloud/consul/kubernetes-vault/certs/consul-key.pem -o /tmp/consul-key.pem
curl $DEMO_HOME/demo/cloud/consul/kubernetes-vault/consul/config.json -o /tmp/config.json

kubectl create secret generic consul \
  --from-literal="gossip-encryption-key=Jjq06uXduWeU8Bk9a/aV8z9QMa2+ADEXhP9yesp/bGg=" \
  --from-file=/tmp/ca.pem \
  --from-file=/tmp/consul.pem \
  --from-file=/tmp/consul-key.pem

kubectl create configmap consul --from-file=/tmp/config.json

kubectl apply -f $DEMO_HOME/demo/cloud/consul/kubernetes-vault/consul/service.yaml
kubectl apply -f $DEMO_HOME/demo/cloud/consul/kubernetes-vault/consul/statefulset.yaml

kubectl wait --for=condition=ready pod -l app=consul --timeout=180s

kubectl port-forward consul-0 8500:8500
```

## 3. 安装 fsm

```bash
export fsm_namespace=fsm-system
export fsm_mesh_name=fsm
export dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
export consul_svc_addr="$(kubectl get svc -l name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=cybwan \
    --set=fsm.image.tag=1.0.2 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.serviceAccessMode=mixed \
    --set=fsm.deployConsulConnector=true \
    --set=fsm.cloudConnector.deriveNamespace=consul-derive \
    --set=fsm.cloudConnector.consul.httpAddr=$consul_svc_addr:8500 \
    --set=fsm.cloudConnector.consul.passingOnly=false \
    --set=fsm.cloudConnector.consul.suffixTag=version \
    --set=fsm.localDNSProxy.enable=true \
    --set=fsm.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}" \
    --timeout=900s

#用于承载转义的consul k8s services 和 endpoints
kubectl create namespace consul-derive
fsm namespace add consul-derive
```

## 4. Consul集成测试


### 4.1 部署模拟客户端

```bash
#模拟外部客户端
kubectl create namespace curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/access-control/curl.yaml

#等待 POD 正常启动
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
```

### 4.2 启用宽松流量模式

**目的: 以便 consul 微服务之间可以相互访问**

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":true}}}'  --type=merge
```

### 4.3 启用外部流量宽松模式

**目的: 以便 consul 微服务可以访问 consul 服务中心**

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":true}}}'  --type=merge
```

### 4.4 启用访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

### 4.5 设置访问控制策略

**目的: 以便模拟客户端和consul 服务中心可以访问 consul 微服务**

```bash
kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  sources:
  - kind: Service
    namespace: curl
    name: curl
  - kind: Service
    namespace: default
    name: consul
EOF
```

### 4.6 部署业务 POD


```bash
export BIZ_HOME=https://raw.githubusercontent.com/cybwan/fsm-start-demo/main

kubectl create namespace consul-demo
fsm namespace add consul-demo

# 一个独立的服务，主要应该是走tiny协议调用接口用，但demo程序启动依赖该服务
kubectl apply -n consul-demo -f $BIZ_HOME/demo/cloud/demo/tiny/tiny-deploy.yaml
# 等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n consul-demo -l app=sc-tiny --timeout=180s

tiny=$(kubectl get pod -n consul-demo -l app=sc-tiny -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $tiny

kubectl apply -n consul-demo -f $BIZ_HOME/demo/cloud/demo/server/server-props.yaml
#kubectl get configmap -n consul-demo server-application-properties -o yaml
# http-port: 8082
# gRPC-port: 9292
kubectl apply -n consul-demo -f $BIZ_HOME/demo/cloud/demo/server/server-deploy.yaml
# 等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n consul-demo -l app=server-demo --timeout=180s

serverDemo=$(kubectl get pod -n consul-demo -l app=server-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $serverDemo

kubectl apply -n consul-demo -f $BIZ_HOME/demo/cloud/demo/client/client-props.yaml
#kubectl get configmap -n consul-demo client-application-properties -o yaml
# 访问端口： 8083
# http-test-api: http://{{HOST}}/api/sc/testHttpApi?msg=111
# grpc-test-api: http://{{HOST}}/api/sc/tetGrpc?param=222
kubectl apply -n consul-demo -f $BIZ_HOME/demo/cloud/demo/client/client-deploy.yaml
# 等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n consul-demo -l app=client-demo --timeout=180s

clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $clientDemo
```

### 4.7 测试指令

#### 4.7.1 测试指令 一

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items[0].status.podIP}')

# 测试 http-test-api: http://{{HOST}}/api/sc/testHttpApi?msg=111
kubectl exec $curl -n curl -- curl -s http://$clientDemo:8083/api/sc/testHttpApi?msg=111
```

正确返回结果类似于:

```json
MTExLC1TdWNjZXNz
```

查看服务日志:

```bash
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $clientDemo
```

#### 4.7.2 测试指令 二

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items[0].status.podIP}')

# 测试 grpc-test-api: http://{{HOST}}/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s http://$clientDemo:8083/api/sc/tetGrpc?param=222
```

正确返回结果类似于:

```json
respTime for param:[222] is [2023-07-08 06:28:31]
```

查看服务日志:

```bash
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $clientDemo
```

### 4.8 分流测试

设置分流策略:

```
kubectl apply -n consul-derive -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: grpc-server-v1
spec:
  matches:
  - name: tag
    headers:
    - "version": "v1"
EOF

kubectl apply -n consul-derive -f - <<EOF
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: grpc-server-split
spec:
  service: grpc-server
  matches:
  - kind: HTTPRouteGroup
    name: grpc-server-v1
  backends:
  - service: grpc-server-v1
    weight: 50
EOF
```

