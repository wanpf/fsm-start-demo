# FSM Eureka集成测试

## 1. 下载并安装 fsm cli

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.1.1
curl -L https://github.com/cybwan/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2.部署 Eureka 服务

```bash
#部署Eureka服务
export DEMO_HOME=https://raw.githubusercontent.com/cybwan/fsm-start-demo/main
curl $DEMO_HOME/demo/cloud/eureka/eureka.yml -o /tmp/eureka.yml

kubectl create namespace disco
kubectl apply -n disco -f /tmp/eureka.yml

kubectl wait --for=condition=ready pod -n disco -l app=eureka-service --timeout=180s

POD=$(kubectl get pods --selector app=eureka-service -n disco --no-headers | grep 'Running' | awk 'NR==1{print $1}')
kubectl port-forward "$POD" -n disco 8761:8761 --address 0.0.0.0
```

## 3. 安装 fsm

```bash
export fsm_namespace=fsm-system
export fsm_mesh_name=fsm
export eureka_svc_addr="$(kubectl get svc -n disco --field-selector metadata.name=eureka-service -o jsonpath='{.items[0].spec.clusterIP}')"
fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=cybwan \
    --set=fsm.image.tag=1.1.1 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=debug \
    --set=fsm.controllerLogLevel=warn \
    --set=fsm.serviceAccessMode=mixed \
    --set=fsm.featureFlags.enableAutoDefaultRoute=true \
    --set=fsm.deployEurekaConnector=true \
    --set=fsm.cloudConnector.eureka.deriveNamespace=eureka-derive \
    --set=fsm.cloudConnector.eureka.httpAddr=http://$eureka_svc_addr:8761/eureka \
    --set=fsm.cloudConnector.eureka.passingOnly=false \
    --timeout=900s

#用于承载转义的consul k8s services 和 endpoints
kubectl create namespace eureka-derive
fsm namespace add eureka-derive
kubectl patch namespace eureka-derive -p '{"metadata":{"annotations":{"flomesh.io/mesh-service-sync":"eureka"}}}'  --type=merge
```

## 4. Eureka集成测试

### 4.1 启用宽松流量模式

**目的: 以便 eureka 微服务之间可以相互访问**

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":true}}}'  --type=merge
```

### 4.2 启用外部流量宽松模式

**目的: 以便 eureka 微服务可以访问 eureka 服务中心**

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"traffic":{"enableEgress":true}}}'  --type=merge
```

### 4.3 启用访问控制策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

### 4.4 设置访问控制策略

**目的: 以便eureka 服务中心可以访问 eureka 微服务**

```bash
kubectl apply -f - <<EOF
kind: AccessControl
apiVersion: policy.flomesh.io/v1alpha1
metadata:
  name: eureka-service
  namespace: disco
spec:
  sources:
  - kind: Service
    namespace: disco
    name: eureka-service
EOF
```

### 4.5 部署业务 POD


```bash
#模拟业务服务
export DEMO_HOME=https://raw.githubusercontent.com/cybwan/fsm-start-demo/main
kubectl create namespace eureka-demo
fsm namespace add eureka-demo

curl $DEMO_HOME/demo/cloud/eureka/provider1.yml -o /tmp/provider1.yml
curl $DEMO_HOME/demo/cloud/eureka/provider2.yml -o /tmp/provider2.yml
curl $DEMO_HOME/demo/cloud/eureka/consumer.yml -o /tmp/consumer.yml
curl $DEMO_HOME/demo/cloud/eureka/curl.yml -o /tmp/curl.yml

kubectl apply -n eureka-demo -f /tmp/provider1.yml
kubectl apply -n eureka-demo -f /tmp/provider2.yml
kubectl apply -n eureka-demo -f /tmp/consumer.yml
kubectl apply -n eureka-demo -f /tmp/curl.yml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n eureka-demo -l app=provider1 --timeout=180s
kubectl wait --for=condition=ready pod -n eureka-demo -l app=provider2 --timeout=180s
kubectl wait --for=condition=ready pod -n eureka-demo -l app=consumer --timeout=180s
kubectl wait --for=condition=ready pod -n eureka-demo -l app=curl --timeout=180s
```

### 4.6 测试指令

多次执行:

```bash
NS=cloud
POD=$(kubectl get pod -n eureka-demo -l app=curl -o jsonpath='{.items..metadata.name}')
kubectl exec "$POD" -n eureka-demo -c curl -- curl -s http://consumer:8001/hello
```

正确返回结果类似于:

```text
I`m provider 1 ,Hello consumer!
I`m provider 2 ,Hello consumer!
I`m provider 1 ,Hello consumer!
I`m provider 2 ,Hello consumer!
```
