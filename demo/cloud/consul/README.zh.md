# FSM Consul集成测试

## 1. 下载并安装 fsm cli

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.1
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
export consul_svc_addr="$(kubectl get svc -l name=consul -o jsonpath='{.items[0].spec.clusterIP}')"
fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=cybwan \
    --set=fsm.image.tag=1.0.1 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=debug \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.serviceAccessMode=mixed \
    --set=fsm.featureFlags.enableAutoDefaultRoute=true \
    --set=fsm.deployConsulConnector=true \
    --set=fsm.cloudConnector.deriveNamespace=consul-derive \
    --set=fsm.cloudConnector.consul.httpAddr=$consul_svc_addr:8500 \
    --set=fsm.cloudConnector.consul.passingOnly=false \
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

- Product    9001

- Order       9000

- Gateway  8080

- Customer 9002

- Account    9003


```bash
#模拟业务服务
export DEMO_HOME=https://raw.githubusercontent.com/cybwan/fsm-start-demo/main
kubectl create namespace consul-demo
fsm namespace add consul-demo
kubectl apply -n consul-demo -f $DEMO_HOME/demo/cloud/consul/deployment-product-service.yaml
kubectl apply -n consul-demo -f $DEMO_HOME/demo/cloud/consul/deployment-order-service.yaml
kubectl apply -n consul-demo -f $DEMO_HOME/demo/cloud/consul/deployment-account-service.yml
kubectl apply -n consul-demo -f $DEMO_HOME/demo/cloud/consul/deployment-customer-service.yml
kubectl apply -n consul-demo -f $DEMO_HOME/demo/cloud/consul/deployment-gateway-service.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n consul-demo -l app=product-service --timeout=180s
kubectl wait --for=condition=ready pod -n consul-demo -l app=order-service --timeout=180s
kubectl wait --for=condition=ready pod -n consul-demo -l app=account-service --timeout=180s
kubectl wait --for=condition=ready pod -n consul-demo -l app=customer-service --timeout=180s
kubectl wait --for=condition=ready pod -n consul-demo -l app=gateway-service --timeout=180s
```

### 4.7 测试指令

#### 4.7.1 测试指令 一

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
product=$(kubectl get pod -n consul-demo -l app=product-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$product:9001/test
```

正确返回结果类似于:

```json
Product Service is working properly!
```

#### 4.7.2 测试指令 二

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
order=$(kubectl get pod -n consul-demo -l app=order-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$order:9000/test
```

正确返回结果类似于:

```json
Order Service is working properly!
```

#### 4.7.3 测试指令 三

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
customer=$(kubectl get pod -n consul-demo -l app=customer-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$customer:9002/test
```

正确返回结果类似于:

```json
Costumer Service is working properly!
```

#### 4.7.4 测试指令 四

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
account=$(kubectl get pod -n consul-demo -l app=account-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$account:9003/1
```

正确返回结果类似于:

```json
{"id":1,"number":"1234567890","balance":50000,"customerId":1}
```

#### 4.7.5 测试指令 五

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
gateway=$(kubectl get pod -n consul-demo -l app=gateway-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$gateway/customer/test
```

正确返回结果类似于:

```json
Costumer Service is working properly!
```

#### 4.7.6 测试指令 六

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
gateway=$(kubectl get pod -n consul-demo -l app=gateway-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$gateway/order/test
```

正确返回结果类似于:

```json
Order Service is working properly!
```

#### 4.7.7 测试指令 七

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
gateway=$(kubectl get pod -n consul-demo -l app=gateway-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$gateway/product/test
```

正确返回结果类似于:

```json
Product Service is working properly!
```

#### 4.7.8 测试指令 八

```bash
curl="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items..metadata.name}')"
gateway=$(kubectl get pod -n consul-demo -l app=gateway-service -o jsonpath='{.items[0].status.podIP}')
kubectl exec $curl -n curl -- curl -s http://$gateway/customer/withAccounts/1 | jq
```

正确返回结果类似于:

```json
{
  "id": 1,
  "name": "John Scott",
  "type": "NEW",
  "accounts": [
    {
      "id": 1,
      "number": "1234567890",
      "balance": 50000
    },
    {
      "id": 2,
      "number": "1234567891",
      "balance": 50000
    },
    {
      "id": 3,
      "number": "1234567892",
      "balance": 50000
    }
  ]
}
```
