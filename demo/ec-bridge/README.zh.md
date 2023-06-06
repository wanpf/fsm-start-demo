# ErieCanal Net

## 1. 部署 k8s 环境

参考: https://github.com/cybwan/fsm-start-demo/blob/main/demo/interceptor/README.zh.md

## 2. 下载并安装 ecnet 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.1
curl -L https://github.com/cybwan/ErieCanalNet/releases/download/${release}/erie-canal-net-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/ecnet version
cp ./${system}-${arch}/ecnet /usr/local/bin/
```

## 3. 安装 ErieCanal Net

根据k8s 环境使用 cni 选择如下命令之一

### 3.1 flannel

```bash
export ecnet_namespace=ecnet-system
export ecnet_name=ecnet
export dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
ecnet install \
    --ecnet-name "$ecnet_name" \
    --ecnet-namespace "$ecnet_namespace" \
    --set=ecnet.image.registry=cybwan \
    --set=ecnet.image.tag=1.0.1 \
    --set=ecnet.image.pullPolicy=Always \
    --set=ecnet.proxyLogLevel=debug \
    --set=ecnet.controllerLogLevel=warn \
    --set=ecnet.localDNSProxy.enable=true \
    --set=ecnet.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}" \
    --set=ecnet.ecnetBridge.cni.hostCniBridgeEth=cni0 \
    --timeout=900s
```

### 3.2 calico

```bash
export ecnet_namespace=ecnet-system
export ecnet_name=ecnet
export dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
ecnet install \
    --ecnet-name "$ecnet_name" \
    --ecnet-namespace "$ecnet_namespace" \
    --set=ecnet.image.registry=cybwan \
    --set=ecnet.image.tag=1.0.1 \
    --set=ecnet.image.pullPolicy=Always \
    --set=ecnet.proxyLogLevel=debug \
    --set=ecnet.controllerLogLevel=warn \
    --set=ecnet.localDNSProxy.enable=true \
    --set=ecnet.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}" \
    --set=ecnet.ecnetBridge.cni.hostCniBridgeEth=tunl0 \
    --timeout=900s
```

### 3.3 weave

```bash
export ecnet_namespace=ecnet-system
export ecnet_name=ecnet
export dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
ecnet install \
    --ecnet-name "$ecnet_name" \
    --ecnet-namespace "$ecnet_namespace" \
    --set=ecnet.image.registry=cybwan \
    --set=ecnet.image.tag=1.0.1 \
    --set=ecnet.image.pullPolicy=Always \
    --set=ecnet.proxyLogLevel=debug \
    --set=ecnet.controllerLogLevel=warn \
    --set=ecnet.localDNSProxy.enable=true \
    --set=ecnet.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}" \
    --set=ecnet.ecnetBridge.cni.hostCniBridgeEth=weave \
    --timeout=900s
```

## 4. 部署模拟业务

```bash
kubectl create namespace demo
cat <<EOF | kubectl apply -n demo -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sleep
---
apiVersion: v1
kind: Service
metadata:
  name: sleep
  labels:
    app: sleep
    service: sleep
spec:
  ports:
  - port: 80
    name: http
  selector:
    app: sleep
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sleep
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sleep
  template:
    metadata:
      labels:
        app: sleep
    spec:
      terminationGracePeriodSeconds: 0
      serviceAccountName: sleep
      containers:
      - name: sleep
        image: curlimages/curl
        imagePullPolicy: Always
        command: ["/bin/sleep", "infinity"]
      nodeName: node2
EOF

kubectl wait --for=condition=ready pod -n demo -l app=sleep --timeout=180s
```

## 5.模拟导入多集群服务

```
kubectl create namespace pipy

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: ServiceImport
metadata:
  name: pipy-ok
  namespace: pipy
spec:
  ports:
  - endpoints:
    - clusterKey: default/default/default/cluster3
      target:
        host: 3.226.203.163 # httpbin.org
        ip: 3.226.203.163
        path: /
        port: 80
    port: 8080
    protocol: TCP
  serviceAccountName: '*'
  type: ClusterSetIP
EOF

cat <<EOF | kubectl apply -f -
apiVersion: flomesh.io/v1alpha1
kind: GlobalTrafficPolicy
metadata:
  namespace: pipy
  name: pipy-ok
spec:
  lbType: ActiveActive
EOF
```

## 6. 转发 pipy repo 管理端口

```
export ecnet_namespace=ecnet-system
ECNET_POD=$(kubectl get pods -n "$ecnet_namespace" --no-headers  --selector app=ecnet-controller | awk 'NR==1{print $1}')
kubectl port-forward -n "$ecnet_namespace" "$ECNET_POD" 80:6060 --address 0.0.0.0
```

## 7.测试

测试指令:

```bash
sleep_client="$(kubectl get pod -n demo -l app=sleep -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${sleep_client} -n demo -- curl -sI pipy-ok.pipy:8080
```

期望结果:

```bash
HTTP/1.1 200 OK
date: Tue, 28 Mar 2023 01:40:35 GMT
content-type: text/html; charset=utf-8
content-length: 9593
server: gunicorn/19.9.0
access-control-allow-origin: *
access-control-allow-credentials: true
```

