

# ErieCanal Bridge测试

## 1. 下载并安装 ec-bridge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v0.0.1-ec.1
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
    --set=osm.image.registry=cybwan \
    --set=osm.image.tag=0.0.1-ec.1 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 部署业务服务

```bash
kubectl create namespace pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/ec-bridge/pipy-ok.pipy.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok --timeout=180s
```

## 4.模拟导入多集群服务

```
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
        host: 192.168.127.91
        ip: 192.168.127.91
        path: /c3/ok
        port: 8093
    - clusterKey: default/default/default/cluster1
      target:
        host: 192.168.127.91
        ip: 192.168.127.91
        path: /c1/ok
        port: 8091
    name: pipy
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

## 5. 转发 pipy repo 管理端口

```
export osm_namespace=osm-system
OSM_POD=$(kubectl get pods -n "$osm_namespace" --no-headers  --selector app=osm-controller | awk 'NR==1{print $1}')

kubectl port-forward -n "$osm_namespace" "$OSM_POD" 6060:6060 --address 0.0.0.0
```

## 6.config.json样例

```json
{
 "Ts": "2023-03-21T06:33:13.67955152Z",
 "Version": "3532027475660608080",
 "Spec": {
  "SidecarLogLevel": "error",
  "Probes": {
   "ReadinessProbes": [
    {
     "httpGet": {
      "path": "/health/ready",
      "port": 9091,
      "scheme": "HTTP"
     },
     "initialDelaySeconds": 1,
     "timeoutSeconds": 5,
     "periodSeconds": 10,
     "successThreshold": 1,
     "failureThreshold": 3
    }
   ],
   "LivenessProbes": [
    {
     "httpGet": {
      "path": "/health/alive",
      "port": 9091,
      "scheme": "HTTP"
     },
     "initialDelaySeconds": 1,
     "timeoutSeconds": 5,
     "periodSeconds": 10,
     "successThreshold": 1,
     "failureThreshold": 3
    }
   ]
  }
 },
 "Outbound": {
  "TrafficMatches": {
   "8080": [
    {
     "Port": 8080,
     "Protocol": "http",
     "HttpHostPort2Service": {
      "pipy-ok.pipy": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy.svc": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy.svc.cluster": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy.svc.cluster.local": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy.svc.cluster.local:8080": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy.svc.cluster:8080": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy.svc:8080": "pipy-ok.pipy.svc.cluster.local",
      "pipy-ok.pipy:8080": "pipy-ok.pipy.svc.cluster.local"
     },
     "HttpServiceRouteRules": {
      "pipy-ok.pipy.svc.cluster.local": {
       "RouteRules": [
        {
         "Path": ".*",
         "Type": "Regex",
         "Headers": null,
         "Methods": null,
         "TargetClusters": {
          "pipy/pipy-ok|8080": 100,
          "pipy/pipy-ok|8091": 100,
          "pipy/pipy-ok|8093": 100
         }
        }
       ]
      }
     },
     "TcpServiceRouteRules": null
    }
   ]
  },
  "ClustersConfigs": {
   "pipy/pipy-ok|8080": {
    "Endpoints": {
     "10.244.2.3:8080": {
      "Weight": 100
     }
    }
   },
   "pipy/pipy-ok|8091": {
    "Endpoints": {
     "192.168.127.91:8091": {
      "Weight": 100,
      "Key": "default/default/default/cluster1",
      "Path": "/c1/ok"
     }
    }
   },
   "pipy/pipy-ok|8093": {
    "Endpoints": {
     "192.168.127.91:8093": {
      "Weight": 100,
      "Key": "default/default/default/cluster3",
      "Path": "/c3/ok"
     }
    }
   }
  }
 },
 "Chains": {
  "inbound-http": [
   "modules/inbound-tls-termination.js",
   "modules/inbound-http-routing.js",
   "modules/inbound-metrics-http.js",
   "modules/inbound-tracing-http.js",
   "modules/inbound-logging-http.js",
   "modules/inbound-throttle-service.js",
   "modules/inbound-throttle-route.js",
   "modules/inbound-http-load-balancing.js",
   "modules/inbound-http-default.js"
  ],
  "inbound-tcp": [
   "modules/inbound-tls-termination.js",
   "modules/inbound-tcp-routing.js",
   "modules/inbound-tcp-load-balancing.js",
   "modules/inbound-tcp-default.js"
  ],
  "outbound-http": [
   "modules/outbound-http-routing.js",
   "modules/outbound-metrics-http.js",
   "modules/outbound-tracing-http.js",
   "modules/outbound-logging-http.js",
   "modules/outbound-circuit-breaker.js",
   "modules/outbound-http-load-balancing.js",
   "modules/outbound-http-default.js"
  ],
  "outbound-tcp": [
   "modules/outbound-tcp-routing.js",
   "modules/outbound-tcp-load-balancing.js",
   "modules/outbound-tcp-default.js"
  ]
 }
}
```

