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

### 4.2 场景测试一：HTTP Nginx & HTTP Ingress & mTLS Egress

#### 4.2.1 测试指令

流量路径: 

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.2.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Sat, 08 Oct 2022 14:22:35 GMT
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

#### 4.2.3 设置 Ingress 策略

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
  - http:
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

#### 4.2.5 测试指令

流量路径: 

Client --**http**--> Nginx Ingress --**http** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.2.6 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Sat, 08 Oct 2022 14:29:52 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 13
Connection: keep-alive
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-5fc9f7b8b5-txwv8

hello world.
```

#### 4.2.7 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.2.8 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.2.9 创建Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n osm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.2.10 设置Egress目的策略

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

#### 4.2.11 测试指令

流量路径: 

Client --**http**--> Nginx Ingress --**http**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/time
```

#### 4.2.12 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Sat, 08 Oct 2022 14:33:21 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 75
Connection: keep-alive
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg

The current time: 2022-10-08 14:33:21.371498416 +0000 UTC m=+741.549912520
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n osm-system egress-middle-cert
```

### 4.3 场景测试二：HTTP Nginx & mTLS Ingress & mTLS Egress

#### 4.3.1 测试指令

流量路径: 

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.3.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Sat, 08 Oct 2022 14:22:35 GMT
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

#### 4.3.3 设置 Ingress Controller 证书上下文

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"ingress-controller-cert","namespace":"osm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 4.3.4 设置 Ingress 策略

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "middle.egress-middle.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "osm-system/ingress-controller-cert"
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"
spec:
  ingressClassName: nginx
  rules:
  - http:
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

#### 4.3.5 设置 IngressBackend 策略

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
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

#### 4.3.6 测试指令

流量路径: 

Client --**http**--> Nginx Ingress --**mtls** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.3.7 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Sat, 08 Oct 2022 15:14:02 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 13
Connection: keep-alive
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg

hello world.
```

#### 4.3.8 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.3.9 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.3.10 创建Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n osm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.3.11 设置Egress目的策略

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

#### 4.3.12 测试指令

流量路径: 

Client --**http**--> Nginx Ingress --**mtls**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/time
```

#### 4.3.13 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 200 OK
Date: Sat, 08 Oct 2022 15:16:34 GMT
Content-Type: text/plain; charset=utf-8
Content-Length: 76
Connection: keep-alive
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg

The current time: 2022-10-08 15:16:34.382595496 +0000 UTC m=+3336.451711119
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"certificate":{"ingressGateway":null}}}' --type=merge

kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n osm-system egress-middle-cert
```

### 4.4 场景测试三：TLS Nginx & mTLS Ingress & mTLS Egress

#### 4.4.1 测试指令

流量路径: 

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.4.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Sat, 08 Oct 2022 15:22:58 GMT
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

#### 4.4.3 设置 Ingress Controller 证书上下文

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"ingress-controller-cert","namespace":"osm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 4.4.4 创建 Nginx TLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.crt -o nginx.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.key -o nginx.key

kubectl create secret tls -n egress-middle nginx-cert-secret \
  --cert=./nginx.crt \
  --key=./nginx.key 
```

#### 4.4.5 设置 Ingress 策略

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
  annotations:
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "middle.egress-middle.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "osm-system/ingress-controller-cert"
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: middle
            port:
              number: 8080
  tls:
  - hosts:
    - ingress-nginx-controller.ingress-nginx
    secretName: nginx-cert-secret
EOF
```

#### 4.4.6 设置 IngressBackend 策略

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
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

#### 4.4.7 测试指令

流量路径: 

Client --**tls**--> Nginx Ingress --**mtls** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/hello --key /certs/client.key --cert /certs/client.crt
```

#### 4.4.8 测试结果

正确返回结果类似于:

```bash
HTTP/2 200 
date: Sat, 08 Oct 2022 15:46:12 GMT
content-type: text/plain; charset=utf-8
content-length: 13
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg
strict-transport-security: max-age=15724800; includeSubDomains

hello world.
```

#### 4.4.9 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.4.10 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.4.11 创建Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n osm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.4.12 设置Egress目的策略

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

#### 4.4.13 测试指令

流量路径: 

Client --**tls**--> Nginx Ingress --**mtls**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/time --key /certs/client.key --cert /certs/client.crt
```

#### 4.4.14 测试结果

正确返回结果类似于:

```bash
certs/client.key --cert /certs/client.crt
HTTP/2 200 
date: Sat, 08 Oct 2022 15:47:46 GMT
content-type: text/plain; charset=utf-8
content-length: 76
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg
strict-transport-security: max-age=15724800; includeSubDomains

The current time: 2022-10-08 15:47:46.057295899 +0000 UTC m=+5209.495978755
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"certificate":{"ingressGateway":null}}}' --type=merge

kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n osm-system egress-middle-cert
kubectl delete secrets -n egress-middle nginx-cert-secret
```

### 4.5 场景测试四：mTLS Nginx & mTLS Ingress & mTLS Egress

#### 4.5.1 测试指令

流量路径: 

Client --**http**--> Nginx Ingress Controller

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -si http://ingress-nginx-controller.ingress-nginx/hello
```

#### 4.5.2 测试结果

正确返回结果类似于:

```bash
HTTP/1.1 404 Not Found
Date: Sat, 08 Oct 2022 15:58:00 GMT
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

#### 4.5.3 设置 Ingress Controller 证书上下文

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"certificate":{"ingressGateway":{"secret":{"name":"ingress-controller-cert","namespace":"osm-system"},"subjectAltNames":["ingress-nginx.ingress-nginx.cluster.local"],"validityDuration":"24h"}}}}' --type=merge
```

#### 4.5.4 创建 Nginx CA Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt

kubectl create secret generic -n egress-middle nginx-ca-secret \
  --from-file=ca.crt=./ca.crt 
```

#### 4.5.5 创建 Nginx TLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.crt -o nginx.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/nginx.key -o nginx.key

kubectl create secret tls -n egress-middle nginx-cert-secret \
  --cert=./nginx.crt \
  --key=./nginx.key 
```

#### 4.5.6 设置 Ingress 策略

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: egress-middle
  namespace: egress-middle
  annotations:
    nginx.ingress.kubernetes.io/auth-tls-pass-certificate-to-upstream: "false"
    nginx.ingress.kubernetes.io/auth-tls-secret: egress-middle/nginx-ca-secret
    nginx.ingress.kubernetes.io/auth-tls-verify-client: "on"
    nginx.ingress.kubernetes.io/auth-tls-verify-depth: "1"
    nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    # proxy_ssl_name for a service is of the form <service-account>.<namespace>.cluster.local
    nginx.ingress.kubernetes.io/configuration-snippet: |
      proxy_ssl_name "middle.egress-middle.cluster.local";
    nginx.ingress.kubernetes.io/proxy-ssl-secret: "osm-system/ingress-controller-cert"
    nginx.ingress.kubernetes.io/proxy-ssl-verify: "on"
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: middle
            port:
              number: 8080
  tls:
  - hosts:
    - ingress-nginx-controller.ingress-nginx
    secretName: nginx-cert-secret
EOF
```

#### 4.5.7 设置 IngressBackend 策略

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
      protocol: https
    tls:
      skipClientCertValidation: false
  sources:
  - kind: Service
    namespace: ingress-nginx
    name: ingress-nginx-controller
  - kind: AuthenticatedPrincipal
    name: ingress-nginx.ingress-nginx.cluster.local
EOF
```

#### 4.5.8 测试指令

流量路径: 

Client --**mtls**--> Nginx Ingress --**mtls** --> sidecar --> Middle

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/hello  --cacert /certs/ca.crt --key /certs/client.key --cert /certs/client.crt
```

#### 4.5.9 测试结果

正确返回结果类似于:

```bash
HTTP/2 200 
date: Sat, 08 Oct 2022 16:01:28 GMT
content-type: text/plain; charset=utf-8
content-length: 13
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg
strict-transport-security: max-age=15724800; includeSubDomains

hello world.
```

#### 4.5.10 禁用Egress目的宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enableEgress":false}}}' --type=merge
```

#### 4.5.11 启用Egress目的策略模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableEgressPolicy":true}}}'  --type=merge
```

#### 4.5.12 创建Egress mTLS Secret

```bash
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/ca.crt -o ca.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.crt -o middle.crt
curl https://raw.githubusercontent.com/cybwan/mtls-time-demo/main/certs/middle.key -o middle.key

kubectl create secret generic -n osm-system egress-middle-cert \
  --from-file=ca.crt=./ca.crt \
  --from-file=tls.crt=./middle.crt \
  --from-file=tls.key=./middle.key 
```

#### 4.5.13 设置Egress目的策略

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

#### 4.5.14 测试指令

流量路径: 

Client --**mtls**--> Nginx Ingress --**mtls**--> sidecar --> Middle --> sidecar --**egress mtls**--> Server

```bash
kubectl exec "$(kubectl get pod -n egress-client -l app=client -o jsonpath='{.items..metadata.name}')" -n egress-client -- curl -ksi https://ingress-nginx-controller.ingress-nginx/time --cacert /certs/ca.crt --key /certs/client.key --cert /certs/client.crt
```

#### 4.5.15 测试结果

正确返回结果类似于:

```bash
HTTP/2 200 
date: Sat, 08 Oct 2022 16:02:56 GMT
content-type: text/plain; charset=utf-8
content-length: 76
osm-stats-namespace: egress-middle
osm-stats-kind: Deployment
osm-stats-name: middle
osm-stats-pod: middle-6c5bf6f9b6-m2hcg
strict-transport-security: max-age=15724800; includeSubDomains

The current time: 2022-10-08 16:02:56.636227534 +0000 UTC m=+6120.696021528
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"certificate":{"ingressGateway":null}}}' --type=merge

kubectl delete ingress -n egress-middle egress-middle
kubectl delete ingressbackend -n egress-middle egress-middle
kubectl delete egress -n egress-middle server-8443
kubectl delete secrets -n osm-system egress-middle-cert
kubectl delete secrets -n egress-middle nginx-cert-secret
kubectl delete secrets -n egress-middle nginx-ca-secret
```

