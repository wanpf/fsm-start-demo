# OSM Edge Local DNS Proxy 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.1
curl -L https://github.com/cybwan/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/osm version
cp ./${system}-${arch}/osm /usr/local/bin/
```

## 2. 安装 osm-edge

```bash
export osm_namespace=osm-system
export osm_mesh_name=osm
dns_svc_ip="$(kubectl get svc -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].spec.clusterIP}')"
osm install \
    --mesh-name "$osm_mesh_name" \
    --osm-namespace "$osm_namespace" \
    --set=osm.certificateProvider.kind=tresor \
    --set=osm.image.registry=localhost:5000/flomesh \
    --set=osm.image.tag=latest \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s \
    --set=osm.localDNSProxy.enable=true \
    --set=osm.localDNSProxy.primaryUpstreamDNSServerIPAddr="${dns_svc_ip}" \
#   --set=osm.localDNSProxy.secondaryUpstreamDNSServerIPAddr=8.8.8.8
```

## 3. Local DNS Proxy测试


### 3.2 部署业务 POD

```bash
#模拟外部服务
kubectl create namespace httpbin
osm namespace add httpbin
kubectl apply -n httpbin -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/local-dns-proxy/httpbin.yaml

kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/local-dns-proxy/curl.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n httpbin -l app=httpbin --timeout=180s
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s

#osm verify connectivity --from-pod curl/curl-548c575854-4wbqn --to-pod httpbin/httpbin-77dcf49495-qlwr9 --to-service httpbin
```


