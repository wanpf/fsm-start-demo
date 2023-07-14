# FSM Consul集成测试

## 1. 下载并安装 fsm cli

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.1
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
export consul_svc_addr="$(kubectl get svc -l name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=flomesh \
    --set=fsm.image.tag=1.0.1 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=error \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.serviceAccessMode=mixed \
    --set=fsm.deployConsulConnector=true \
    --set=fsm.cloudConnector.deriveNamespace=consul-derive \
    --set=fsm.cloudConnector.consul.httpAddr=$consul_svc_addr:8500 \
    --set=fsm.cloudConnector.consul.passingOnly=false \
    --set=fsm.cloudConnector.consul.suffixTag=version \
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
curl $BIZ_HOME/demo/cloud/demo/tiny/tiny-deploy.yaml -o /tmp/tiny-deploy.yaml
kubectl apply -n consul-demo -f /tmp/tiny-deploy.yaml
# 等待依赖的 POD 正常启动
sleep 5
kubectl wait --for=condition=ready pod -n consul-demo -l app=sc-tiny --timeout=180s

tiny=$(kubectl get pod -n consul-demo -l app=sc-tiny -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $tiny

export consul_svc_cluster_ip=consul.default.svc.cluster.local
#export consul_svc_cluster_ip="$(kubectl get svc -n default -l name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
export tiny_svc_cluster_ip=sc-tiny.consul-demo.svc.cluster.local
#export tiny_svc_cluster_ip="$(kubectl get svc -n consul-demo -l app=tiny -o jsonpath='{.items[0].spec.clusterIP}')"

curl $BIZ_HOME/demo/cloud/demo/server/server-props-v1.yaml -o /tmp/server-props-v1.yaml
cat /tmp/server-props-v1.yaml | envsubst | kubectl apply -n consul-demo -f -
# http-port: 8082
# gRPC-port: 9292
curl $BIZ_HOME/demo/cloud/demo/server/server-deploy-v1.yaml -o /tmp/server-deploy-v1.yaml
kubectl apply -n consul-demo -f /tmp/server-deploy-v1.yaml
# 等待依赖的 POD 正常启动
sleep 5
kubectl wait --for=condition=ready pod -n consul-demo -l app=server-demo -l version=v1 --timeout=180s
serverDemoV1=$(kubectl get pod -n consul-demo -l app=server-demo -l version=v1 -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $serverDemoV1

curl $BIZ_HOME/demo/cloud/demo/server/server-props-v2.yaml -o /tmp/server-props-v2.yaml
cat /tmp/server-props-v2.yaml | envsubst | kubectl apply -n consul-demo -f -
# http-port: 8082
# gRPC-port: 9292
curl $BIZ_HOME/demo/cloud/demo/server/server-deploy-v2.yaml -o /tmp/server-deploy-v2.yaml
kubectl apply -n consul-demo -f /tmp/server-deploy-v2.yaml
# 等待依赖的 POD 正常启动
sleep 5
kubectl wait --for=condition=ready pod -n consul-demo -l app=server-demo -l version=v2 --timeout=180s
serverDemoV2=$(kubectl get pod -n consul-demo -l app=server-demo -l version=v2 -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $serverDemoV2

export server_demo_pod_ip=$(kubectl get pod -n consul-demo -l app=server-demo -o jsonpath='{.items[0].status.podIP}')

curl $BIZ_HOME/demo/cloud/demo/client/client-props.yaml -o /tmp/client-props.yaml
cat /tmp/client-props.yaml | envsubst | kubectl apply -n consul-demo -f -
# 访问端口： 8083
# http-test-api: http://{{HOST}}/api/sc/testHttpApi?msg=111
# grpc-test-api: http://{{HOST}}/api/sc/tetGrpc?param=222
curl $BIZ_HOME/demo/cloud/demo/client/client-deploy.yaml -o /tmp/client-deploy.yaml
cat /tmp/client-deploy.yaml | envsubst | kubectl apply -n consul-demo -f -
# 等待依赖的 POD 正常启动
sleep 5
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
kubectl exec $curl -n curl -- curl -s http://$clientDemo:8083/api/sc/testHttpApi?msg=111
```

正确返回结果类似于:

```json
111,-Success:v2
111,-Success:v1
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
kubectl exec $curl -n curl -- curl -s -H "versiontag:v1" http://$clientDemo:8083/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v1" http://$clientDemo:8083/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v2" http://$clientDemo:8083/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v2" http://$clientDemo:8083/api/sc/tetGrpc?param=222
```

正确返回结果类似于(Robin):

```json
respTime for param:[222] is [2023-07-13 15:42:01]:v2
respTime for param:[222] is [2023-07-13 15:42:02]:v1
respTime for param:[222] is [2023-07-13 15:42:18]:v2
respTime for param:[222] is [2023-07-13 15:42:19]:v1
```

查看服务日志:

```bash
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $clientDemo
```

### 4.8 分流测试

#### 4.8.1 设置分流策略:

```
kubectl apply -n consul-derive -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: server-v1
spec:
  matches:
  - name: tag
    headers:
    - "versiontag": "v1"
EOF

kubectl apply -n consul-derive -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: server-v2
spec:
  matches:
  - name: tag
    headers:
    - "versiontag": "v2"
EOF

kubectl apply -n consul-derive -f - <<EOF
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: grpc-server-split-v1
spec:
  service: grpc-server
  matches:
  - kind: HTTPRouteGroup
    name: server-v1
  backends:
  - service: grpc-server-v1
    weight: 100
EOF

kubectl apply -n consul-derive -f - <<EOF
apiVersion: split.smi-spec.io/v1alpha4
kind: TrafficSplit
metadata:
  name: grpc-server-split-v2
spec:
  service: grpc-server
  matches:
  - kind: HTTPRouteGroup
    name: server-v2
  backends:
  - service: grpc-server-v2
    weight: 100
EOF
```

#### 4.8.2 测试指令 一

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items[0].status.podIP}')

# 测试 http-test-api: http://{{HOST}}/api/sc/testHttpApi?msg=111
kubectl exec $curl -n curl -- curl -s -H "versiontag:v1" http://$clientDemo:8083/api/sc/testHttpApi?msg=111
kubectl exec $curl -n curl -- curl -s -H "versiontag:v1" http://$clientDemo:8083/api/sc/testHttpApi?msg=111
kubectl exec $curl -n curl -- curl -s -H "versiontag:v2" http://$clientDemo:8083/api/sc/testHttpApi?msg=111
kubectl exec $curl -n curl -- curl -s -H "versiontag:v2" http://$clientDemo:8083/api/sc/testHttpApi?msg=111
```

正确返回结果类似于:

```json
111,v1-Success:v1
111,v1-Success:v
111,v2-Success:v2
111,v2-Success:v2
```

查看服务日志:

```bash
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $clientDemo
```

#### 4.8.3 测试指令 二

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items[0].status.podIP}')

# 测试 grpc-test-api: http://{{HOST}}/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v1" http://$clientDemo:8083/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v1" http://$clientDemo:8083/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v2" http://$clientDemo:8083/api/sc/tetGrpc?param=222
kubectl exec $curl -n curl -- curl -s -H "versiontag:v2" http://$clientDemo:8083/api/sc/tetGrpc?param=222
```

正确返回结果类似于:

```json
respTime for param:[222] is [2023-07-13 15:42:01]:v1
respTime for param:[222] is [2023-07-13 15:42:02]:v1
respTime for param:[222] is [2023-07-13 15:42:18]:v2
respTime for param:[222] is [2023-07-13 15:42:19]:v2
```

查看服务日志:

```bash
clientDemo=$(kubectl get pod -n consul-demo -l app=client-demo -o jsonpath='{.items..metadata.name}')
kubectl logs -n consul-demo $clientDemo
```
