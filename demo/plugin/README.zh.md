# OSM Edge PlugIn 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.3.0-alpha.3
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
    --set=osm.image.tag=1.3.0-alpha.3 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. PlugIn策略测试

### 3.1 技术概念

```
1、通过Plugin导入pjs脚本, 一个Plugin对应一个pjs文件；
2、通过PluginService设置某一Service的Plugin的启用策略, PluginService同Service的namespace和name需一一对应；
3、通过PluginChain设置某一Service的Chain的启用策略, PluginChain同Service的namespace和name需一一对应；
4、默认osm-system 下创建一个全局的osm-mesh-chain, 对所有被osm纳管的Service起作用
```


### 3.2 部署业务 POD

```bash
kubectl create namespace curl
osm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/curl.curl.yaml

kubectl create namespace pipy
osm namespace add pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/osm-edge-start-demo/main/demo/plugin/pipy-ok.pipy.yaml

#等待依赖的 POD 正常启动
sleep 3
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v2 --timeout=180s
```

### 3.3 场景测试

#### 3.3.1 启用PlugIn策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enablePlugInPolicy":true}}}' --type=merge
```

#### 3.3.2 声明插件策略

```bash
kubectl create namespace plugin
osm namespace add plugin

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-onload-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-onload-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-onload-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-unload-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-unload-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-unload-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-inbound-service-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-outbound-service-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-inbound-service-route-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-route-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-inbound-service-route-demo] receive data size:', dat?.size)
        )
      )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: plugin-outbound-service-route-demo
  namespace: plugin
spec:
  pipyscript: |+
    pipy({})
      .pipeline()
      // send
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-route-demo] send data size:', dat?.size)
        )
      )
      .chain()
      // receive
      .handleData(
        dat => (
          console.log('==============[plugin-outbound-service-route-demo] receive data size:', dat?.size)
        )
      )
EOF
```

#### 3.3.3 启用流量宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":true}}}' --type=merge
```

#### 3.3.4 设置服务插件策略

```bash
kubectl apply -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: curl-routes
  namespace: curl
spec:
  matches:
  - name: all
    pathRegex: ".*"
EOF

kubectl apply -f - <<EOF
kind: PluginService
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  inbound:
    targetRoutes:
      - kind: HTTPRouteGroup
        name: curl-routes
        matches:
          - all
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-inbound-service-route-demo
    plugins:
      - mountpoint: HTTPFirst
        namespace: plugin
        name: plugin-inbound-service-demo

  outbound:
    targetServices:
      - name: pipy-ok
        namespace: pipy
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-outbound-service-route-demo
    plugins:
      - mountpoint: HTTPLast
        namespace: plugin
        name: plugin-outbound-service-demo
EOF
```

#### 3.3.5 查看 curl.curl 的 codebase

```bash
{
 "Ts": "2022-12-09T13:44:14.569952262Z",
 "Version": "7590885254412830379",
 "Spec": {
  "SidecarLogLevel": "error",
  "Traffic": {
   "EnableEgress": true
  },
  "FeatureFlags": {
   "EnableSidecarActiveHealthChecks": false
  },
  "Probes": {},
  "ClusterSet": null
 },
 "Certificate": {
  "CommonName": "curl.curl.cluster.local",
  "Expiration": "2022-12-10 12:46:54",
  "CertChain": "-----BEGIN CERTIFICATE-----\nMIIDqDCCApCgAwIBAgIQHdyhgkdxtQzTbYjiI4MgNzANBgkqhkiG9w0BAQsFADBa\nMQswCQYDVQQGEwJVUzELMAkGA1UEBxMCQ0ExGjAYBgNVBAoTEU9wZW4gU2Vydmlj\nZSBNZXNoMSIwIAYDVQQDExlvc20tY2Eub3BlbnNlcnZpY2VtZXNoLmlvMB4XDTIy\nMTIwOTEzNDI0MloXDTIyMTIxMDEyNDY1NFowPjEaMBgGA1UEChMRT3BlbiBTZXJ2\naWNlIE1lc2gxIDAeBgNVBAMTF2N1cmwuY3VybC5jbHVzdGVyLmxvY2FsMIIBIjAN\nBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA47u/J/cq9+016PbVJIa32gqF33mZ\nNzJCVSgRw3i3M4JqJUUk3RNKhC20i05EdKj7+pwInCM8BEcA6fmlG3yvdmUfUsHu\nRLvNTuHAVyvXrmo+V6/+cb/00qN+jkGcOZowlveUiXaNMzV15LOMXqTnHiDRy7LX\n5Zy/o2CfdJ0GzntEdtcMVyiJ1BlB8XeXWO6gMvER4vk253z+7u4ETaCxgQ6gU8bA\nAahSAdIdzKuRKMMdl7lwuTwt1MkK6dZiLo7ipbQi5AVZ/TkBHp4fTmfaOqZ1ZS9l\nIXwzA/yHsFmrQDO68uFYU9ozzVZUgIr/y/CkyYM8R8QrsH1cespaQBn80QIDAQAB\no4GFMIGCMA4GA1UdDwEB/wQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYB\nBQUHAwEwDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAWgBShvAQDfea+czWGImggEwA1\nYVNDATAiBgNVHREEGzAZghdjdXJsLmN1cmwuY2x1c3Rlci5sb2NhbDANBgkqhkiG\n9w0BAQsFAAOCAQEAESJB7aS7DymEbaeo32GDb/JILq9hthKvk+D8z4asa80vaC3i\nSMaQZqqLcQMQkC9iKfjEGN+FX+XpFgdFxd8R5gjbzkszkfGQeV+GRlLV//ipFjYy\nw3aVtxw3Y4JkcoAaZWqdyTnuqEzp6IrKyIeTTk0SBC9dfj2dC/Uc+EgQmMZjqVUI\nBCVFCAtTpynlBPERJk94sYfHuRGMivHiarvY0X16hKzTYTITeuyeC4CLt6ReZ+Al\n/FU5A/fAtmyZGu+5q0fXpj3rf1gaDLraGlWpu/z17wVh91v8DDmqlP8xhLU6dx4D\ns3WDPlDu8pRql5hll6HlwrO9IYdGnnFsSxslIg==\n-----END CERTIFICATE-----\n",
  "PrivateKey": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDju78n9yr37TXo\n9tUkhrfaCoXfeZk3MkJVKBHDeLczgmolRSTdE0qELbSLTkR0qPv6nAicIzwERwDp\n+aUbfK92ZR9Swe5Eu81O4cBXK9euaj5Xr/5xv/TSo36OQZw5mjCW95SJdo0zNXXk\ns4xepOceINHLstflnL+jYJ90nQbOe0R21wxXKInUGUHxd5dY7qAy8RHi+TbnfP7u\n7gRNoLGBDqBTxsABqFIB0h3Mq5Eowx2XuXC5PC3UyQrp1mIujuKltCLkBVn9OQEe\nnh9OZ9o6pnVlL2UhfDMD/IewWatAM7ry4VhT2jPNVlSAiv/L8KTJgzxHxCuwfVx6\nylpAGfzRAgMBAAECggEBAIuPzGcOp0uHGKmrUxXuZY9/MWmx2H6mE1ailrhHK2aq\nvqgWhq/hGaKFbAaPMY6Y3MtJglFFmos4hEvfTRraP6F7+UU7SezfdsOnv7rsSGJA\nA/KzDWjibYQE5BMEDFyUrMBn+6R+favrUFOW4ShDQMwK6uc9s+eoNx1FopLRhJFW\ne5W4gfUoNbbOLZ4h8jWSs6eNyjdfMjFhnPxkdhcGg9mLundDlVrD6uI8NHlO9tAH\ntTq/YzgVUf01eNK+57xGyTs3XpzYKZHE203W1SB51SQ0znzpychEuC8sgjrWUEqK\n1mKBGw8EQ1gxj/qMuNxkU+L9IFEEahmpX8loYYrSWVECgYEA+XRC3OFk9tgRxKM5\nyFr78e+WOUojP+6cD5ac3VIQFm+mFWYyCJYVnizePwiCaj58sGj0UlhqZ7+MUCEz\nZG0ODiBw8l/2cKHObnIIeH+S4jTr5UG4JQz9dST0Iu314ZoGgM7oz5VArvv3RMry\n32htC+dQzDoF9NtpQivUn41Y5OUCgYEA6bWS2vLt/N0DkRawLpEzh1KSvcsPfJmW\nlF/2hfceSdMEBjOmeHfVvyhTBgOkrGmrYGzkyPg5f3FQPybYtV1qOyLP0hvZyawY\nk7cOZR2Bu52QlEvTC2rhCf2SnJzbJzvGNEYz3crZN/G2t0M9YHw2UrderysafyBF\nFzZI8up2xX0CgYAa3HMKt9aYYgHfy7fAJFP25FanypzrGHWDlDNF/b0vvUwEB+Ih\nXI/tXWV9Ihxw9lOU52hPqaejjlO8mSagjMGzsbiX0M+Hp1TEPdE9sHcPlqVEJYR/\nsNtmDtmfHUKZzW0f16foGmlBrm4c4UGv3t3HJ1xi8WiMykeWUYPuvlixJQKBgQCw\nuiNg+g7JBgAqePOlYxuKGwDoEGOXnzTk4mQzDZmTzcPfRLN/qW6y7LVLePnPfuCf\nO/kNl9cy7eb2ulNpYkhwi3SHt5PLEx5KpUR3ZgaybwXjfisLGTkvKtbxIxP96Q+K\nfAPAliIIUfoPPwNssMELb6pj375bn3VfhidHudEyqQKBgQDDS+EmcnjanMe/QJkL\nCdDuzF21c7Qs/ATQFodtnVH5gSBA0WtraIjiWqoky0s3x0Li374S1cd0LQ6qZHRu\n7aLTr2eLSlq00ihIyytoCjxqtiWBATl5DmGDBrhOj81rCo62k/JqeEsT2+8pZVN7\ntdDoJI5lJQR4n7chXTy+V8HSYQ==\n-----END PRIVATE KEY-----\n",
  "IssuingCA": "-----BEGIN CERTIFICATE-----\nMIIDgTCCAmmgAwIBAgIRANDvM1nSJDG4GG8I4LtcA9owDQYJKoZIhvcNAQELBQAw\nWjELMAkGA1UEBhMCVVMxCzAJBgNVBAcTAkNBMRowGAYDVQQKExFPcGVuIFNlcnZp\nY2UgTWVzaDEiMCAGA1UEAxMZb3NtLWNhLm9wZW5zZXJ2aWNlbWVzaC5pbzAeFw0y\nMjEyMDkxMjQ2MzRaFw0zMjEyMDYxMjQ2MzRaMFoxCzAJBgNVBAYTAlVTMQswCQYD\nVQQHEwJDQTEaMBgGA1UEChMRT3BlbiBTZXJ2aWNlIE1lc2gxIjAgBgNVBAMTGW9z\nbS1jYS5vcGVuc2VydmljZW1lc2guaW8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw\nggEKAoIBAQDL78RqekB/N0SCR7rdCK9zrUdE/j404/fCjm6VFdBzgpYmNva0fqey\nR2/tIloOBo4G4ltLcTakU14wuDrXa74W6N8FOaGBf0KWMM7o+llIFy5HF5V1pdmb\nRQgo3hnkKhABPYPoJjHgBwuA/XJZH7cXQH03FYYuyYzWIIzB6mqlQfsX7Me0MxiI\nKlD+FgtABZEAyDN5i9aYt3sUQmj+Q2dNFiZBOtli16SW3FOelwbcglnrx6p6RCxT\nzIs23za7I6yH4Bw8AOwvA53fB3c/j6QDQIuRjveFjWk0Snabu8kzywXYvD2ipVUL\nLjmPU+nM35DVJQBukPv+nOIPULwCsHQTAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIB\nBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBShvAQDfea+czWGImggEwA1YVND\nATANBgkqhkiG9w0BAQsFAAOCAQEAhRNNAs5KUZ5j7MVypYyW5eK8iO6WEmypFk/8\nX6Nm7n8GlNuuo0gOxzDcolrC8M2Aj2Zq2GC1agRtqfFvj8RAD+ot8jgYSdXqDkGl\n8NuikPHme1KLFLNMx9uZVRdCIZiz75g39NnX+fE3DbL8mwV1d6t9Ggxefdc9AA3Y\n+52dTutdIduXK221zbfmWbO96hkAVM2onsEjdA33v83BtM/YGhOvvWh7z3CQiufn\nyOI2c2iRffsxosxhJoy35BP7CdVy8ozedMOKzCC0R0gMFbv7uLVoARsrtx/3jDe4\nMBf9or15CbC1DKNGh9ClvfedOm3YSNchDjSJdkfL4IJ9NAZGwg==\n-----END CERTIFICATE-----\n"
 },
 "Inbound": {
  "TrafficMatches": {
   "80": {
    "Port": 80,
    "Protocol": "http",
    "SourceIPRanges": null,
    "HttpHostPort2Service": {
     "curl": "curl.curl.svc.cluster.local",
     "curl.curl": "curl.curl.svc.cluster.local",
     "curl.curl.svc": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster.local": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster.local:80": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster:80": "curl.curl.svc.cluster.local",
     "curl.curl.svc:80": "curl.curl.svc.cluster.local",
     "curl.curl:80": "curl.curl.svc.cluster.local",
     "curl:80": "curl.curl.svc.cluster.local"
    },
    "HttpServiceRouteRules": {
     "curl.curl.svc.cluster.local": {
      "RouteRules": [
       {
        "Path": ".*",
        "Type": "Regex",
        "Headers": null,
        "Methods": null,
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": null,
        "RateLimit": null,
        "Plugins": {
         "HTTPAfterDemux": [
          "plugins/plugin-plugin-inbound-service-route-demo.js"
         ]
        }
       }
      ],
      "RateLimit": null,
      "HeaderRateLimits": null
     }
    },
    "TargetClusters": null,
    "AllowedEndpoints": null,
    "Plugins": {
     "HTTPFirst": [
      "plugins/plugin-plugin-inbound-service-demo.js"
     ]
    },
    "RateLimit": null
   }
  },
  "ClustersConfigs": {
   "curl/curl|80|local": {
    "127.0.0.1:80": 100
   }
  }
 },
 "Outbound": {
  "TrafficMatches": {
   "80": [
    {
     "DestinationIPRanges": {
      "10.96.60.171/32": null
     },
     "Port": 80,
     "Protocol": "http",
     "HttpHostPort2Service": {
      "curl": "curl.curl.svc.cluster.local",
      "curl.curl": "curl.curl.svc.cluster.local",
      "curl.curl.svc": "curl.curl.svc.cluster.local",
      "curl.curl.svc.cluster": "curl.curl.svc.cluster.local",
      "curl.curl.svc.cluster.local": "curl.curl.svc.cluster.local",
      "curl.curl.svc.cluster.local:80": "curl.curl.svc.cluster.local",
      "curl.curl.svc.cluster:80": "curl.curl.svc.cluster.local",
      "curl.curl.svc:80": "curl.curl.svc.cluster.local",
      "curl.curl:80": "curl.curl.svc.cluster.local",
      "curl:80": "curl.curl.svc.cluster.local"
     },
     "HttpServiceRouteRules": {
      "curl.curl.svc.cluster.local": {
       "RouteRules": [
        {
         "Path": ".*",
         "Type": "Regex",
         "Headers": null,
         "Methods": null,
         "TargetClusters": {
          "curl/curl|80": 100
         },
         "AllowedServices": null
        }
       ]
      }
     },
     "TargetClusters": null,
     "Plugins": {
      "HTTPLast": [
       "plugins/plugin-plugin-outbound-service-demo.js"
      ]
     },
     "ServiceIdentity": "curl.curl",
     "AllowedEgressTraffic": false,
     "EgressForwardGateway": null
    }
   ],
   "8080": [
    {
     "DestinationIPRanges": {
      "10.96.227.110/32": null
     },
     "Port": 8080,
     "Protocol": "http",
     "HttpHostPort2Service": {
      "pipy-ok-v2.pipy": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy.svc": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy.svc.cluster": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy.svc.cluster.local": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy.svc.cluster.local:8080": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy.svc.cluster:8080": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy.svc:8080": "pipy-ok-v2.pipy.svc.cluster.local",
      "pipy-ok-v2.pipy:8080": "pipy-ok-v2.pipy.svc.cluster.local"
     },
     "HttpServiceRouteRules": {
      "pipy-ok-v2.pipy.svc.cluster.local": {
       "RouteRules": [
        {
         "Path": ".*",
         "Type": "Regex",
         "Headers": null,
         "Methods": null,
         "TargetClusters": {
          "pipy/pipy-ok-v2|8080": 100
         },
         "AllowedServices": null
        }
       ]
      }
     },
     "TargetClusters": null,
     "Plugins": {
      "HTTPLast": [
       "plugins/plugin-plugin-outbound-service-demo.js"
      ]
     },
     "ServiceIdentity": "curl.curl",
     "AllowedEgressTraffic": false,
     "EgressForwardGateway": null
    },
    {
     "DestinationIPRanges": {
      "10.96.154.73/32": null
     },
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
          "pipy/pipy-ok|8080": 100
         },
         "AllowedServices": null
        }
       ]
      }
     },
     "TargetClusters": null,
     "Plugins": {
      "HTTPAfterDemux": [
       "plugins/plugin-plugin-outbound-service-route-demo.js"
      ],
      "HTTPLast": [
       "plugins/plugin-plugin-outbound-service-demo.js"
      ]
     },
     "ServiceIdentity": "curl.curl",
     "AllowedEgressTraffic": false,
     "EgressForwardGateway": null
    },
    {
     "DestinationIPRanges": {
      "10.96.113.0/32": null
     },
     "Port": 8080,
     "Protocol": "http",
     "HttpHostPort2Service": {
      "pipy-ok-v1.pipy": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy.svc": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy.svc.cluster": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy.svc.cluster.local": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy.svc.cluster.local:8080": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy.svc.cluster:8080": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy.svc:8080": "pipy-ok-v1.pipy.svc.cluster.local",
      "pipy-ok-v1.pipy:8080": "pipy-ok-v1.pipy.svc.cluster.local"
     },
     "HttpServiceRouteRules": {
      "pipy-ok-v1.pipy.svc.cluster.local": {
       "RouteRules": [
        {
         "Path": ".*",
         "Type": "Regex",
         "Headers": null,
         "Methods": null,
         "TargetClusters": {
          "pipy/pipy-ok-v1|8080": 100
         },
         "AllowedServices": null
        }
       ]
      }
     },
     "TargetClusters": null,
     "Plugins": {
      "HTTPLast": [
       "plugins/plugin-plugin-outbound-service-demo.js"
      ]
     },
     "ServiceIdentity": "curl.curl",
     "AllowedEgressTraffic": false,
     "EgressForwardGateway": null
    }
   ]
  },
  "ClustersConfigs": {
   "curl/curl|80": {
    "Endpoints": {
     "10.244.2.28:80": {
      "Weight": 100
     }
    }
   },
   "pipy/pipy-ok-v1|8080": {
    "Endpoints": {
     "10.244.1.42:8080": {
      "Weight": 100
     }
    }
   },
   "pipy/pipy-ok-v2|8080": {
    "Endpoints": {
     "10.244.1.43:8080": {
      "Weight": 100
     }
    }
   },
   "pipy/pipy-ok|8080": {
    "Endpoints": {
     "10.244.1.42:8080": {
      "Weight": 100
     },
     "10.244.1.43:8080": {
      "Weight": 100
     }
    }
   }
  }
 },
 "Forward": null,
 "AllowedEndpoints": {
  "10.244.1.42": "pipy.pipy-ok-v1-744bbd6c8c-j6k82",
  "10.244.1.43": "pipy.pipy-ok-v2-5565f9c877-x79d7",
  "10.244.2.28": "curl.curl-7fc45dfbc4-rcr75"
 }
}
```

#### 3.3.6 禁用流量宽松模式

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"traffic":{"enablePermissiveTrafficPolicyMode":false}}}' --type=merge
```

#### 3.3.7 设置 SMI 访问策略

```bash
kubectl apply -f - <<EOF
apiVersion: specs.smi-spec.io/v1alpha4
kind: HTTPRouteGroup
metadata:
  name: curl-routes
  namespace: curl
spec:
  matches:
  - name: test
    pathRegex: "/test"
    methods:
    - GET
  - name: demo
    pathRegex: "/demo"
    methods:
    - GET
  - name: debug
    pathRegex: "/debug"
    methods:
    - GET
EOF


kubectl apply -f - <<EOF
kind: TrafficTarget
apiVersion: access.smi-spec.io/v1alpha3
metadata:
  name: pipy-ok-v1-access-curl-routes
  namespace: curl
spec:
  destination:
    kind: ServiceAccount
    name: curl
    namespace: curl
  rules:
  - kind: HTTPRouteGroup
    name: curl-routes
    matches:
      - test
      - demo
      - debug
  sources:
  - kind: ServiceAccount
    name: pipy-ok-v1
    namespace: pipy
EOF
```

#### 3.3.8 查看 curl.curl 的 codebase

```bash
{
 "Ts": "2022-12-09T13:45:07.103997021Z",
 "Version": "16811546687321350747",
 "Spec": {
  "SidecarLogLevel": "error",
  "Traffic": {
   "EnableEgress": true
  },
  "FeatureFlags": {
   "EnableSidecarActiveHealthChecks": false
  },
  "Probes": {},
  "ClusterSet": null
 },
 "Certificate": {
  "CommonName": "curl.curl.cluster.local",
  "Expiration": "2022-12-10 12:46:54",
  "CertChain": "-----BEGIN CERTIFICATE-----\nMIIDqDCCApCgAwIBAgIQHdyhgkdxtQzTbYjiI4MgNzANBgkqhkiG9w0BAQsFADBa\nMQswCQYDVQQGEwJVUzELMAkGA1UEBxMCQ0ExGjAYBgNVBAoTEU9wZW4gU2Vydmlj\nZSBNZXNoMSIwIAYDVQQDExlvc20tY2Eub3BlbnNlcnZpY2VtZXNoLmlvMB4XDTIy\nMTIwOTEzNDI0MloXDTIyMTIxMDEyNDY1NFowPjEaMBgGA1UEChMRT3BlbiBTZXJ2\naWNlIE1lc2gxIDAeBgNVBAMTF2N1cmwuY3VybC5jbHVzdGVyLmxvY2FsMIIBIjAN\nBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA47u/J/cq9+016PbVJIa32gqF33mZ\nNzJCVSgRw3i3M4JqJUUk3RNKhC20i05EdKj7+pwInCM8BEcA6fmlG3yvdmUfUsHu\nRLvNTuHAVyvXrmo+V6/+cb/00qN+jkGcOZowlveUiXaNMzV15LOMXqTnHiDRy7LX\n5Zy/o2CfdJ0GzntEdtcMVyiJ1BlB8XeXWO6gMvER4vk253z+7u4ETaCxgQ6gU8bA\nAahSAdIdzKuRKMMdl7lwuTwt1MkK6dZiLo7ipbQi5AVZ/TkBHp4fTmfaOqZ1ZS9l\nIXwzA/yHsFmrQDO68uFYU9ozzVZUgIr/y/CkyYM8R8QrsH1cespaQBn80QIDAQAB\no4GFMIGCMA4GA1UdDwEB/wQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYB\nBQUHAwEwDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAWgBShvAQDfea+czWGImggEwA1\nYVNDATAiBgNVHREEGzAZghdjdXJsLmN1cmwuY2x1c3Rlci5sb2NhbDANBgkqhkiG\n9w0BAQsFAAOCAQEAESJB7aS7DymEbaeo32GDb/JILq9hthKvk+D8z4asa80vaC3i\nSMaQZqqLcQMQkC9iKfjEGN+FX+XpFgdFxd8R5gjbzkszkfGQeV+GRlLV//ipFjYy\nw3aVtxw3Y4JkcoAaZWqdyTnuqEzp6IrKyIeTTk0SBC9dfj2dC/Uc+EgQmMZjqVUI\nBCVFCAtTpynlBPERJk94sYfHuRGMivHiarvY0X16hKzTYTITeuyeC4CLt6ReZ+Al\n/FU5A/fAtmyZGu+5q0fXpj3rf1gaDLraGlWpu/z17wVh91v8DDmqlP8xhLU6dx4D\ns3WDPlDu8pRql5hll6HlwrO9IYdGnnFsSxslIg==\n-----END CERTIFICATE-----\n",
  "PrivateKey": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDju78n9yr37TXo\n9tUkhrfaCoXfeZk3MkJVKBHDeLczgmolRSTdE0qELbSLTkR0qPv6nAicIzwERwDp\n+aUbfK92ZR9Swe5Eu81O4cBXK9euaj5Xr/5xv/TSo36OQZw5mjCW95SJdo0zNXXk\ns4xepOceINHLstflnL+jYJ90nQbOe0R21wxXKInUGUHxd5dY7qAy8RHi+TbnfP7u\n7gRNoLGBDqBTxsABqFIB0h3Mq5Eowx2XuXC5PC3UyQrp1mIujuKltCLkBVn9OQEe\nnh9OZ9o6pnVlL2UhfDMD/IewWatAM7ry4VhT2jPNVlSAiv/L8KTJgzxHxCuwfVx6\nylpAGfzRAgMBAAECggEBAIuPzGcOp0uHGKmrUxXuZY9/MWmx2H6mE1ailrhHK2aq\nvqgWhq/hGaKFbAaPMY6Y3MtJglFFmos4hEvfTRraP6F7+UU7SezfdsOnv7rsSGJA\nA/KzDWjibYQE5BMEDFyUrMBn+6R+favrUFOW4ShDQMwK6uc9s+eoNx1FopLRhJFW\ne5W4gfUoNbbOLZ4h8jWSs6eNyjdfMjFhnPxkdhcGg9mLundDlVrD6uI8NHlO9tAH\ntTq/YzgVUf01eNK+57xGyTs3XpzYKZHE203W1SB51SQ0znzpychEuC8sgjrWUEqK\n1mKBGw8EQ1gxj/qMuNxkU+L9IFEEahmpX8loYYrSWVECgYEA+XRC3OFk9tgRxKM5\nyFr78e+WOUojP+6cD5ac3VIQFm+mFWYyCJYVnizePwiCaj58sGj0UlhqZ7+MUCEz\nZG0ODiBw8l/2cKHObnIIeH+S4jTr5UG4JQz9dST0Iu314ZoGgM7oz5VArvv3RMry\n32htC+dQzDoF9NtpQivUn41Y5OUCgYEA6bWS2vLt/N0DkRawLpEzh1KSvcsPfJmW\nlF/2hfceSdMEBjOmeHfVvyhTBgOkrGmrYGzkyPg5f3FQPybYtV1qOyLP0hvZyawY\nk7cOZR2Bu52QlEvTC2rhCf2SnJzbJzvGNEYz3crZN/G2t0M9YHw2UrderysafyBF\nFzZI8up2xX0CgYAa3HMKt9aYYgHfy7fAJFP25FanypzrGHWDlDNF/b0vvUwEB+Ih\nXI/tXWV9Ihxw9lOU52hPqaejjlO8mSagjMGzsbiX0M+Hp1TEPdE9sHcPlqVEJYR/\nsNtmDtmfHUKZzW0f16foGmlBrm4c4UGv3t3HJ1xi8WiMykeWUYPuvlixJQKBgQCw\nuiNg+g7JBgAqePOlYxuKGwDoEGOXnzTk4mQzDZmTzcPfRLN/qW6y7LVLePnPfuCf\nO/kNl9cy7eb2ulNpYkhwi3SHt5PLEx5KpUR3ZgaybwXjfisLGTkvKtbxIxP96Q+K\nfAPAliIIUfoPPwNssMELb6pj375bn3VfhidHudEyqQKBgQDDS+EmcnjanMe/QJkL\nCdDuzF21c7Qs/ATQFodtnVH5gSBA0WtraIjiWqoky0s3x0Li374S1cd0LQ6qZHRu\n7aLTr2eLSlq00ihIyytoCjxqtiWBATl5DmGDBrhOj81rCo62k/JqeEsT2+8pZVN7\ntdDoJI5lJQR4n7chXTy+V8HSYQ==\n-----END PRIVATE KEY-----\n",
  "IssuingCA": "-----BEGIN CERTIFICATE-----\nMIIDgTCCAmmgAwIBAgIRANDvM1nSJDG4GG8I4LtcA9owDQYJKoZIhvcNAQELBQAw\nWjELMAkGA1UEBhMCVVMxCzAJBgNVBAcTAkNBMRowGAYDVQQKExFPcGVuIFNlcnZp\nY2UgTWVzaDEiMCAGA1UEAxMZb3NtLWNhLm9wZW5zZXJ2aWNlbWVzaC5pbzAeFw0y\nMjEyMDkxMjQ2MzRaFw0zMjEyMDYxMjQ2MzRaMFoxCzAJBgNVBAYTAlVTMQswCQYD\nVQQHEwJDQTEaMBgGA1UEChMRT3BlbiBTZXJ2aWNlIE1lc2gxIjAgBgNVBAMTGW9z\nbS1jYS5vcGVuc2VydmljZW1lc2guaW8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw\nggEKAoIBAQDL78RqekB/N0SCR7rdCK9zrUdE/j404/fCjm6VFdBzgpYmNva0fqey\nR2/tIloOBo4G4ltLcTakU14wuDrXa74W6N8FOaGBf0KWMM7o+llIFy5HF5V1pdmb\nRQgo3hnkKhABPYPoJjHgBwuA/XJZH7cXQH03FYYuyYzWIIzB6mqlQfsX7Me0MxiI\nKlD+FgtABZEAyDN5i9aYt3sUQmj+Q2dNFiZBOtli16SW3FOelwbcglnrx6p6RCxT\nzIs23za7I6yH4Bw8AOwvA53fB3c/j6QDQIuRjveFjWk0Snabu8kzywXYvD2ipVUL\nLjmPU+nM35DVJQBukPv+nOIPULwCsHQTAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIB\nBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBShvAQDfea+czWGImggEwA1YVND\nATANBgkqhkiG9w0BAQsFAAOCAQEAhRNNAs5KUZ5j7MVypYyW5eK8iO6WEmypFk/8\nX6Nm7n8GlNuuo0gOxzDcolrC8M2Aj2Zq2GC1agRtqfFvj8RAD+ot8jgYSdXqDkGl\n8NuikPHme1KLFLNMx9uZVRdCIZiz75g39NnX+fE3DbL8mwV1d6t9Ggxefdc9AA3Y\n+52dTutdIduXK221zbfmWbO96hkAVM2onsEjdA33v83BtM/YGhOvvWh7z3CQiufn\nyOI2c2iRffsxosxhJoy35BP7CdVy8ozedMOKzCC0R0gMFbv7uLVoARsrtx/3jDe4\nMBf9or15CbC1DKNGh9ClvfedOm3YSNchDjSJdkfL4IJ9NAZGwg==\n-----END CERTIFICATE-----\n"
 },
 "Inbound": {
  "TrafficMatches": {
   "80": {
    "Port": 80,
    "Protocol": "http",
    "SourceIPRanges": null,
    "HttpHostPort2Service": {
     "curl": "curl.curl.svc.cluster.local",
     "curl.curl": "curl.curl.svc.cluster.local",
     "curl.curl.svc": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster.local": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster.local:80": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster:80": "curl.curl.svc.cluster.local",
     "curl.curl.svc:80": "curl.curl.svc.cluster.local",
     "curl.curl:80": "curl.curl.svc.cluster.local",
     "curl:80": "curl.curl.svc.cluster.local"
    },
    "HttpServiceRouteRules": {
     "curl.curl.svc.cluster.local": {
      "RouteRules": [
       {
        "Path": "/debug",
        "Type": "Regex",
        "Headers": null,
        "Methods": [
         "GET"
        ],
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": [
         "pipy-ok-v1.pipy"
        ],
        "RateLimit": null,
        "Plugins": null
       },
       {
        "Path": "/demo",
        "Type": "Regex",
        "Headers": null,
        "Methods": [
         "GET"
        ],
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": [
         "pipy-ok-v1.pipy"
        ],
        "RateLimit": null,
        "Plugins": null
       },
       {
        "Path": "/test",
        "Type": "Regex",
        "Headers": null,
        "Methods": [
         "GET"
        ],
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": [
         "pipy-ok-v1.pipy"
        ],
        "RateLimit": null,
        "Plugins": null
       }
      ],
      "RateLimit": null,
      "HeaderRateLimits": null
     }
    },
    "TargetClusters": null,
    "AllowedEndpoints": {
     "10.244.1.42": "pipy-ok-v1.pipy"
    },
    "Plugins": {
     "HTTPFirst": [
      "plugins/plugin-plugin-inbound-service-demo.js"
     ]
    },
    "RateLimit": null
   }
  },
  "ClustersConfigs": {
   "curl/curl|80|local": {
    "127.0.0.1:80": 100
   }
  }
 },
 "Outbound": null,
 "Forward": null,
 "AllowedEndpoints": {
  "10.244.1.42": "pipy.pipy-ok-v1-744bbd6c8c-j6k82",
  "10.244.1.43": "pipy.pipy-ok-v2-5565f9c877-x79d7",
  "10.244.2.28": "curl.curl-7fc45dfbc4-rcr75"
 }
}
```

#### 3.3.9 设置服务插件策略

```bash
kubectl apply -f - <<EOF
kind: PluginService
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  inbound:
    targetRoutes:
      - kind: HTTPRouteGroup
        name: curl-routes
        matches:
          - test
          - demo
          - debug
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-inbound-service-route-demo
    plugins:
      - mountpoint: HTTPFirst
        namespace: plugin
        name: plugin-inbound-service-demo

  outbound:
    targetServices:
      - name: pipy-ok
        namespace: pipy
        plugins:
          - mountpoint: HTTPAfterDemux
            namespace: plugin
            name: plugin-outbound-service-route-demo
    plugins:
      - mountpoint: HTTPLast
        namespace: plugin
        name: plugin-outbound-service-demo
EOF
```

#### 3.3.10 查看 curl.curl 的 codebase

```bash
{
 "Ts": "2022-12-09T13:45:34.027356517Z",
 "Version": "11401058896540840856",
 "Spec": {
  "SidecarLogLevel": "error",
  "Traffic": {
   "EnableEgress": true
  },
  "FeatureFlags": {
   "EnableSidecarActiveHealthChecks": false
  },
  "Probes": {},
  "ClusterSet": null
 },
 "Certificate": {
  "CommonName": "curl.curl.cluster.local",
  "Expiration": "2022-12-10 12:46:54",
  "CertChain": "-----BEGIN CERTIFICATE-----\nMIIDqDCCApCgAwIBAgIQHdyhgkdxtQzTbYjiI4MgNzANBgkqhkiG9w0BAQsFADBa\nMQswCQYDVQQGEwJVUzELMAkGA1UEBxMCQ0ExGjAYBgNVBAoTEU9wZW4gU2Vydmlj\nZSBNZXNoMSIwIAYDVQQDExlvc20tY2Eub3BlbnNlcnZpY2VtZXNoLmlvMB4XDTIy\nMTIwOTEzNDI0MloXDTIyMTIxMDEyNDY1NFowPjEaMBgGA1UEChMRT3BlbiBTZXJ2\naWNlIE1lc2gxIDAeBgNVBAMTF2N1cmwuY3VybC5jbHVzdGVyLmxvY2FsMIIBIjAN\nBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA47u/J/cq9+016PbVJIa32gqF33mZ\nNzJCVSgRw3i3M4JqJUUk3RNKhC20i05EdKj7+pwInCM8BEcA6fmlG3yvdmUfUsHu\nRLvNTuHAVyvXrmo+V6/+cb/00qN+jkGcOZowlveUiXaNMzV15LOMXqTnHiDRy7LX\n5Zy/o2CfdJ0GzntEdtcMVyiJ1BlB8XeXWO6gMvER4vk253z+7u4ETaCxgQ6gU8bA\nAahSAdIdzKuRKMMdl7lwuTwt1MkK6dZiLo7ipbQi5AVZ/TkBHp4fTmfaOqZ1ZS9l\nIXwzA/yHsFmrQDO68uFYU9ozzVZUgIr/y/CkyYM8R8QrsH1cespaQBn80QIDAQAB\no4GFMIGCMA4GA1UdDwEB/wQEAwIFoDAdBgNVHSUEFjAUBggrBgEFBQcDAgYIKwYB\nBQUHAwEwDAYDVR0TAQH/BAIwADAfBgNVHSMEGDAWgBShvAQDfea+czWGImggEwA1\nYVNDATAiBgNVHREEGzAZghdjdXJsLmN1cmwuY2x1c3Rlci5sb2NhbDANBgkqhkiG\n9w0BAQsFAAOCAQEAESJB7aS7DymEbaeo32GDb/JILq9hthKvk+D8z4asa80vaC3i\nSMaQZqqLcQMQkC9iKfjEGN+FX+XpFgdFxd8R5gjbzkszkfGQeV+GRlLV//ipFjYy\nw3aVtxw3Y4JkcoAaZWqdyTnuqEzp6IrKyIeTTk0SBC9dfj2dC/Uc+EgQmMZjqVUI\nBCVFCAtTpynlBPERJk94sYfHuRGMivHiarvY0X16hKzTYTITeuyeC4CLt6ReZ+Al\n/FU5A/fAtmyZGu+5q0fXpj3rf1gaDLraGlWpu/z17wVh91v8DDmqlP8xhLU6dx4D\ns3WDPlDu8pRql5hll6HlwrO9IYdGnnFsSxslIg==\n-----END CERTIFICATE-----\n",
  "PrivateKey": "-----BEGIN PRIVATE KEY-----\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDju78n9yr37TXo\n9tUkhrfaCoXfeZk3MkJVKBHDeLczgmolRSTdE0qELbSLTkR0qPv6nAicIzwERwDp\n+aUbfK92ZR9Swe5Eu81O4cBXK9euaj5Xr/5xv/TSo36OQZw5mjCW95SJdo0zNXXk\ns4xepOceINHLstflnL+jYJ90nQbOe0R21wxXKInUGUHxd5dY7qAy8RHi+TbnfP7u\n7gRNoLGBDqBTxsABqFIB0h3Mq5Eowx2XuXC5PC3UyQrp1mIujuKltCLkBVn9OQEe\nnh9OZ9o6pnVlL2UhfDMD/IewWatAM7ry4VhT2jPNVlSAiv/L8KTJgzxHxCuwfVx6\nylpAGfzRAgMBAAECggEBAIuPzGcOp0uHGKmrUxXuZY9/MWmx2H6mE1ailrhHK2aq\nvqgWhq/hGaKFbAaPMY6Y3MtJglFFmos4hEvfTRraP6F7+UU7SezfdsOnv7rsSGJA\nA/KzDWjibYQE5BMEDFyUrMBn+6R+favrUFOW4ShDQMwK6uc9s+eoNx1FopLRhJFW\ne5W4gfUoNbbOLZ4h8jWSs6eNyjdfMjFhnPxkdhcGg9mLundDlVrD6uI8NHlO9tAH\ntTq/YzgVUf01eNK+57xGyTs3XpzYKZHE203W1SB51SQ0znzpychEuC8sgjrWUEqK\n1mKBGw8EQ1gxj/qMuNxkU+L9IFEEahmpX8loYYrSWVECgYEA+XRC3OFk9tgRxKM5\nyFr78e+WOUojP+6cD5ac3VIQFm+mFWYyCJYVnizePwiCaj58sGj0UlhqZ7+MUCEz\nZG0ODiBw8l/2cKHObnIIeH+S4jTr5UG4JQz9dST0Iu314ZoGgM7oz5VArvv3RMry\n32htC+dQzDoF9NtpQivUn41Y5OUCgYEA6bWS2vLt/N0DkRawLpEzh1KSvcsPfJmW\nlF/2hfceSdMEBjOmeHfVvyhTBgOkrGmrYGzkyPg5f3FQPybYtV1qOyLP0hvZyawY\nk7cOZR2Bu52QlEvTC2rhCf2SnJzbJzvGNEYz3crZN/G2t0M9YHw2UrderysafyBF\nFzZI8up2xX0CgYAa3HMKt9aYYgHfy7fAJFP25FanypzrGHWDlDNF/b0vvUwEB+Ih\nXI/tXWV9Ihxw9lOU52hPqaejjlO8mSagjMGzsbiX0M+Hp1TEPdE9sHcPlqVEJYR/\nsNtmDtmfHUKZzW0f16foGmlBrm4c4UGv3t3HJ1xi8WiMykeWUYPuvlixJQKBgQCw\nuiNg+g7JBgAqePOlYxuKGwDoEGOXnzTk4mQzDZmTzcPfRLN/qW6y7LVLePnPfuCf\nO/kNl9cy7eb2ulNpYkhwi3SHt5PLEx5KpUR3ZgaybwXjfisLGTkvKtbxIxP96Q+K\nfAPAliIIUfoPPwNssMELb6pj375bn3VfhidHudEyqQKBgQDDS+EmcnjanMe/QJkL\nCdDuzF21c7Qs/ATQFodtnVH5gSBA0WtraIjiWqoky0s3x0Li374S1cd0LQ6qZHRu\n7aLTr2eLSlq00ihIyytoCjxqtiWBATl5DmGDBrhOj81rCo62k/JqeEsT2+8pZVN7\ntdDoJI5lJQR4n7chXTy+V8HSYQ==\n-----END PRIVATE KEY-----\n",
  "IssuingCA": "-----BEGIN CERTIFICATE-----\nMIIDgTCCAmmgAwIBAgIRANDvM1nSJDG4GG8I4LtcA9owDQYJKoZIhvcNAQELBQAw\nWjELMAkGA1UEBhMCVVMxCzAJBgNVBAcTAkNBMRowGAYDVQQKExFPcGVuIFNlcnZp\nY2UgTWVzaDEiMCAGA1UEAxMZb3NtLWNhLm9wZW5zZXJ2aWNlbWVzaC5pbzAeFw0y\nMjEyMDkxMjQ2MzRaFw0zMjEyMDYxMjQ2MzRaMFoxCzAJBgNVBAYTAlVTMQswCQYD\nVQQHEwJDQTEaMBgGA1UEChMRT3BlbiBTZXJ2aWNlIE1lc2gxIjAgBgNVBAMTGW9z\nbS1jYS5vcGVuc2VydmljZW1lc2guaW8wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAw\nggEKAoIBAQDL78RqekB/N0SCR7rdCK9zrUdE/j404/fCjm6VFdBzgpYmNva0fqey\nR2/tIloOBo4G4ltLcTakU14wuDrXa74W6N8FOaGBf0KWMM7o+llIFy5HF5V1pdmb\nRQgo3hnkKhABPYPoJjHgBwuA/XJZH7cXQH03FYYuyYzWIIzB6mqlQfsX7Me0MxiI\nKlD+FgtABZEAyDN5i9aYt3sUQmj+Q2dNFiZBOtli16SW3FOelwbcglnrx6p6RCxT\nzIs23za7I6yH4Bw8AOwvA53fB3c/j6QDQIuRjveFjWk0Snabu8kzywXYvD2ipVUL\nLjmPU+nM35DVJQBukPv+nOIPULwCsHQTAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIB\nBjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBShvAQDfea+czWGImggEwA1YVND\nATANBgkqhkiG9w0BAQsFAAOCAQEAhRNNAs5KUZ5j7MVypYyW5eK8iO6WEmypFk/8\nX6Nm7n8GlNuuo0gOxzDcolrC8M2Aj2Zq2GC1agRtqfFvj8RAD+ot8jgYSdXqDkGl\n8NuikPHme1KLFLNMx9uZVRdCIZiz75g39NnX+fE3DbL8mwV1d6t9Ggxefdc9AA3Y\n+52dTutdIduXK221zbfmWbO96hkAVM2onsEjdA33v83BtM/YGhOvvWh7z3CQiufn\nyOI2c2iRffsxosxhJoy35BP7CdVy8ozedMOKzCC0R0gMFbv7uLVoARsrtx/3jDe4\nMBf9or15CbC1DKNGh9ClvfedOm3YSNchDjSJdkfL4IJ9NAZGwg==\n-----END CERTIFICATE-----\n"
 },
 "Inbound": {
  "TrafficMatches": {
   "80": {
    "Port": 80,
    "Protocol": "http",
    "SourceIPRanges": null,
    "HttpHostPort2Service": {
     "curl": "curl.curl.svc.cluster.local",
     "curl.curl": "curl.curl.svc.cluster.local",
     "curl.curl.svc": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster.local": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster.local:80": "curl.curl.svc.cluster.local",
     "curl.curl.svc.cluster:80": "curl.curl.svc.cluster.local",
     "curl.curl.svc:80": "curl.curl.svc.cluster.local",
     "curl.curl:80": "curl.curl.svc.cluster.local",
     "curl:80": "curl.curl.svc.cluster.local"
    },
    "HttpServiceRouteRules": {
     "curl.curl.svc.cluster.local": {
      "RouteRules": [
       {
        "Path": "/debug",
        "Type": "Regex",
        "Headers": null,
        "Methods": [
         "GET"
        ],
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": [
         "pipy-ok-v1.pipy"
        ],
        "RateLimit": null,
        "Plugins": {
         "HTTPAfterDemux": [
          "plugins/plugin-plugin-inbound-service-route-demo.js"
         ]
        }
       },
       {
        "Path": "/demo",
        "Type": "Regex",
        "Headers": null,
        "Methods": [
         "GET"
        ],
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": [
         "pipy-ok-v1.pipy"
        ],
        "RateLimit": null,
        "Plugins": {
         "HTTPAfterDemux": [
          "plugins/plugin-plugin-inbound-service-route-demo.js"
         ]
        }
       },
       {
        "Path": "/test",
        "Type": "Regex",
        "Headers": null,
        "Methods": [
         "GET"
        ],
        "TargetClusters": {
         "curl/curl|80|local": 100
        },
        "AllowedServices": [
         "pipy-ok-v1.pipy"
        ],
        "RateLimit": null,
        "Plugins": {
         "HTTPAfterDemux": [
          "plugins/plugin-plugin-inbound-service-route-demo.js"
         ]
        }
       }
      ],
      "RateLimit": null,
      "HeaderRateLimits": null
     }
    },
    "TargetClusters": null,
    "AllowedEndpoints": {
     "10.244.1.42": "pipy-ok-v1.pipy"
    },
    "Plugins": {
     "HTTPFirst": [
      "plugins/plugin-plugin-inbound-service-demo.js"
     ]
    },
    "RateLimit": null
   }
  },
  "ClustersConfigs": {
   "curl/curl|80|local": {
    "127.0.0.1:80": 100
   }
  }
 },
 "Outbound": null,
 "Forward": null,
 "AllowedEndpoints": {
  "10.244.1.42": "pipy.pipy-ok-v1-744bbd6c8c-j6k82",
  "10.244.1.43": "pipy.pipy-ok-v2-5565f9c877-x79d7",
  "10.244.2.28": "curl.curl-7fc45dfbc4-rcr75"
 }
}
```

#### 3.3.11 设置插件链策略

```bash
kubectl apply -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: curl
  namespace: curl
spec:
  InboundChains:
    L4:
      TCPFirst:
        - type: plugin
          name: demo
          namespace: demo
      TCPAfterTLS:
        - type: system
          name: inbound-tls-termination.js
      TCPAfterRouting:
        - type: system
          name: inbound-tcp-load-balance.js
        - type: system
          name: metrics-tcp.js
      TCPLast:
        - type: system
          name: inbound-proxy-tcp.js
    L7:
      HTTPFirst:
      HTTPAfterTLS:
        - type: system
          name: inbound-tls-termination.js
      HTTPAfterDemux:
        - type: system
          name: inbound-demux-http.js
      HTTPAfterRouting:
        - type: system
          name: inbound-http-routing.js
        - type: system
          name: metrics-http.js
        - type: system
          name: inbound-throttle.js
      HTTPAfterMux:
        - type: system
          name: inbound-mux-http.js
        - type: system
          name: metrics-tcp.js
      HTTPLast:
        - type: system
          name: inbound-proxy-tcp.js
  OutboundChains:
    L4:
      TCPFirst:
      TCPAfterRouting:
        - type: system
          name: outbound-tcp-load-balance.js
        - type: system
          name: metrics-tcp.js
      TCPLast:
        - type: system
          name: outbound-proxy-tcp.js
    L7:
      HTTPFirst:
      HTTPAfterDemux:
        - type: system
          name: outbound-demux-http.js
      HTTPAfterRouting:
        - type: system
          name: outbound-http-routing.js
        - type: system
          name: metrics-http.js
        - type: system
          name: outbound-breaker.js
      HTTPAfterMux:
        - type: system
          name: outbound-mux-http.js
        - type: system
          name: metrics-tcp.js
      HTTPLast:
        - type: system
          name: outbound-proxy-tcp.js
EOF

kubectl get pluginchains.plugin.flomesh.io -n curl curl -o yaml
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl get traffictargets.access.smi-spec.io -A
kubectl delete traffictargets.access.smi-spec.io -n curl pipy-ok-v1-access-curl-routes
kubectl get httproutegroups.specs.smi-spec.io -A
kubectl delete httproutegroups.specs.smi-spec.io -n curl curl-routes
kubectl get pluginchains.plugin.flomesh.io -A
kubectl delete pluginchains.plugin.flomesh.io -n curl curl
kubectl get pluginservices.plugin.flomesh.io -A
kubectl delete pluginservices.plugin.flomesh.io -n curl curl
kubectl get plugins.plugin.flomesh.io -A
kubectl delete plugins.plugin.flomesh.io -n plugin plugin-inbound-service-demo
kubectl delete plugins.plugin.flomesh.io -n plugin plugin-inbound-service-route-demo
kubectl delete plugins.plugin.flomesh.io -n plugin plugin-onload-demo
kubectl delete plugins.plugin.flomesh.io -n plugin plugin-outbound-service-demo
kubectl delete plugins.plugin.flomesh.io -n plugin plugin-outbound-service-route-demo
kubectl delete plugins.plugin.flomesh.io -n plugin plugin-unload-demo
```

## 4. 参考资料

```bash
plugins = {
inboundL7Chains: [
{ 'INBOUND_HTTP_FIRST': [] },
{ 'INBOUND_HTTP_AFTER_TLS': ['inbound-tls-termination.js'] },
{ 'INBOUND_HTTP_AFTER_DEMUX': ['inbound-demux-http.js'] },
{ 'INBOUND_HTTP_AFTER_ROUTING': ['inbound-http-routing.js', 'metrics-http.js', 'inbound-throttle.js'] },
{ 'INBOUND_HTTP_AFTER_MUX': ['inbound-mux-http.js', 'metrics-tcp.js'] },
{ 'INBOUND_HTTP_LAST': ['inbound-proxy-tcp.js'] }
],
inboundL4Chains: [
{ 'INBOUND_TCP_FIRST': [] },
{ 'INBOUND_TCP_AFTER_TLS': ['inbound-tls-termination.js'] },
{ 'INBOUND_TCP_AFTER_ROUTING': ['inbound-tcp-load-balance.js', 'metrics-tcp.js'] },
{ 'INBOUND_TCP_LAST': ['inbound-proxy-tcp.js'] }
],
outboundL7Chains: [
{ 'OUTBOUND_HTTP_FIRST': [] },
{ 'OUTBOUND_HTTP_AFTER_DEMUX': ['outbound-demux-http.js'] },
{ 'OUTBOUND_HTTP_AFTER_ROUTING': ['outbound-http-routing.js', 'metrics-http.js', 'outbound-breaker.js'] },
{ 'OUTBOUND_HTTP_AFTER_MUX': ['outbound-mux-http.js', 'metrics-tcp.js'] },
{ 'OUTBOUND_HTTP_LAST': ['outbound-proxy-tcp.js'] }
],
outboundL4Chains: [
{ 'OUTBOUND_TCP_FIRST': [] },
{ 'OUTBOUND_TCP_AFTER_ROUTING': ['outbound-tcp-load-balance.js', 'metrics-tcp.js'] },
{ 'OUTBOUND_TCP_LAST': ['outbound-proxy-tcp.js'] }
]
}
```

#### 

