# OSM Edge Bidirectional mTLS 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.2.1-alpha.2
curl -L https://github.com/cybwan/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/osm version
cp ./${system}-${arch}/osm /usr/local/bin/
```

## 2. 安装 osm-edge

```bash
export osm_namespace=osm-system 
export osm_mesh_name=osm 

osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=cybwan \
    --set=osm.image.tag=1.2.1-alpha.2 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 安装 Nginx Ingress

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm search repo ingress-nginx

kubectl create namespace ingress-nginx
helm install -n ingress-nginx ingress-nginx ingress-nginx/ingress-nginx --version=4.0.18 -f - <<EOF
{
  "controller": {
    "hostPort": {
      "enabled": true,
		},
		"service":  {
		  "type": "NodePort",
		},
	},
}
EOF

kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=ingress-nginx \
  --timeout=180s
```

## 4. mTLS Egress 测试

### 4.1 部署业务 POD

```bash
#模拟时间服务
kubectl create namespace egress-server
kubectl apply -n egress-server -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/bidirection-mtls-nginx/server.yaml

#模拟中间件服务
kubectl create namespace egress-middle
osm namespace add egress-middle
kubectl apply -n egress-middle -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/bidirection-mtls-nginx/middle.yaml

#模拟外部客户端
kubectl create namespace egress-client
kubectl apply -n egress-client -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/bidirection-mtls-nginx/client.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n egress-server -l app=server --timeout=180s
kubectl wait --for=condition=ready pod -n egress-middle -l app=middle --timeout=180s
kubectl wait --for=condition=ready pod -n egress-client -l app=client --timeout=180s
```

### 4.2 HTTP Ingress&mTLS Egress测试

#### 4.2.1 测试指令

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx:80/time -H "Host: middle.egress-middle.svc.cluster.local"
```

#### 4.2.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Sat, 08 Oct 2022 08:46:17 GMT
Content-Type: text/html
Content-Length: 146
Connection: keep-alive

<html>
<head><title>404 Not Found</title></head>
<body>
<center><h1>404 Not Found</h1></center>
<hr><center>nginx</center>
</body>
</html>
```

#### 3.2.3 设置 Ingress 策略

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  ingressClassName: nginx
  rules:
  - host: middle.egress-middle.svc.cluster.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: middle
            port:
              number: 8080      
EOF
```

#### 4.2.4 设置 IngressBackend 策略

```bash
kubectl apply -f - <<EOF
kind: IngressBackend
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: egress-middle
  namespace: egress-middle
spec:
  backends:
  - name: middle
    port:
      number: 8080 # targetPort of middle service
      protocol: http
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
EOF
```

#### 4.2.5 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.2.6 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.2.7 启用Egress目的策略模式

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n osm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.2.8 设置Egress目的策略

```bash
kubectl apply -f - <<EOF
kind: Egress
apiVersion: policy.openservicemesh.io/v1alpha1
metadata:
  name: server-8443
  namespace: egress-middle
spec:
  sources:
  - kind: ServiceAccount
    name: middle
    namespace: egress-middle
    mtls:
      sn: 1
      expiration: 2030-1-1 00:00:00
      secret:
        name: egress-middle-cert
        namespace: osm-system
  hosts:
  - server.egress-server.svc.cluster.local
  ports:
  - number: 8443
    protocol: http
EOF
```

#### 4.2.9 测试指令

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx:80/time -H "Host: middle.egress-middle.svc.cluster.local"
```

#### 4.2.10 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Sat, 08 Oct 2022 08:47:37 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 74
Connection: keep-alive
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-784fdbdd94-pjkjp

The current time: 2022-10-08 08:47:37.12731441 +0000 UTC m=+483.534068147
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n osm-system egress-middle-cert
```

