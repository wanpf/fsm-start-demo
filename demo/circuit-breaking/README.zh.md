# OSM Edge 熔断测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.2.1-alpha.1
curl -L https://github.com/flomesh-io/osm-edge/releases/download/${release}/osm-edge-${release}-${system}-${arch}.tar.gz | tar -vxzf -
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
    --set=osm.image.registry=localhost:5000/flomesh \
    --set=osm.image.tag=latest \
    --set=osm.image.pullPolicy=Always \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --set=osm.enablePermissiveTrafficPolicy=true \
    --timeout=900s
```

## 3. 熔断策略测试

### 3.1 技术概念

在 OSM Edge 中支持熔断策略：

- 4 层 TCP 协议：
  - maxConnections：最大连接数
- 7 层 HTTP 协议：
  - maxRequestsPerConnection：最大请求频率
  - 错误调用熔断
    - statTimeWindow：熔断统计时间窗口
    - minRequestAmount：熔断触发的最小请求数，请求数小于该值时即使异常比率超出阈值也不会熔断
    - errorAmountThreshold：错误数量触发阈值
    - errorRatioThreshold：错误比率触发阈值
    - degradedTimeWindow：降级持续时间
    - degradedStatusCode：降级回写状态码
    - degradedResponseContent：降级回写内容
  - 慢调用熔断
    - statTimeWindow：熔断统计时间窗口
    - minRequestAmount：熔断触发的最小请求数，请求数小于该值时即使异常比率超出阈值也不会熔断
    - slowTimeThreshold：慢调用耗时触发阈值
    - slowAmountThreshold：慢调用数量触发阈值
    - slowRatioThreshold：慢调用比率触发阈值
    - degradedTimeWindow：降级持续时间
    - degradedStatusCode：降级回写状态码
    - degradedResponseContent：降级回写内容

### 3.2 部署业务 POD

```bash
kubectl create namespace circuit-breaking
osm namespace add circuit-breaking

#模拟业务服务
kubectl apply -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/circuit-breaking/fortio.yaml -n circuit-breaking

#模拟客户端
kubectl apply -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/main/demo/circuit-breaking/fortio-client.yaml -n circuit-breaking

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n circuit-breaking -l app=fortio --timeout=180s
kubectl wait --for=condition=ready pod -n circuit-breaking -l app=fortio-client --timeout=180s
```

### 3.3 支持7 层 HTTP 协议熔断

#### 3.3.1 场景测试一：最大请求频率熔断

请参见[Circuit breaking for destinations within the mesh](https://docs.openservicemesh.io/docs/demos/circuit_breaking_mesh_internal/)

#### 3.3.2 场景测试二：错误数量触发熔断&降级持续时间

##### 3.3.2.1 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.2.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0010257277 +/- 0.001177 min 0.000505762 max 0.031635265 sum 1.0257277
# target 50% 0.00082647
# target 75% 0.000987146
# target 90% 0.0023662
# target 99% 0.003
# target 99.9% 0.006
Error cases : count 202 avg 0.0010127826 +/- 0.0006731 min 0.000538943 max 0.005187228 sum 0.204582083
# Socket and IP used for each connection:
[0] 203 socket used, resolved to [10.96.150.163:8080] connection timing : count 203 avg 0.0001257911 +/- 5.267e-05 min 5.884e-05 max 0.000599793 sum 0.025535594
Sockets used: 203 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 203
Code 200 : 798 (79.8 %)
Code 511 : 202 (20.2 %)
All done 1000 calls (plus 0 warmup) 1.026 ms avg, 974.6 qps
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 798 (79.8 %)
Code 511 : 202 (20.2 %)
```

##### 3.3.2.3 设置熔断策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.openservicemesh.io/v1alpha1
kind: UpstreamTrafficSetting
metadata:
  name: http-circuit-breaking
  namespace: circuit-breaking
spec:
  host: fortio.circuit-breaking.svc.cluster.local
  connectionSettings:
    http:
      circuitBreaking:                  #7层熔断策略
        statTimeWindow: 1m              #熔断统计时间窗口
        minRequestAmount: 200           #熔断触发的最小请求数
        errorAmountThreshold: 100       #错误触发数量阈值
        degradedTimeWindow: 1m          #降级持续时间
EOF
```

##### 3.3.2.4 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.2.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0014307376 +/- 0.0006165 min 0.000536288 max 0.00606355 sum 1.43073757
# target 50% 0.0013015
# target 75% 0.00176966
# target 90% 0.00222314
# target 99% 0.00296694
# target 99.9% 0.005
Error cases : count 658 avg 0.0016239161 +/- 0.0004515 min 0.000578461 max 0.00606355 sum 1.06853681
# Socket and IP used for each connection:
[0] 658 socket used, resolved to [10.96.150.163:8080] connection timing : count 658 avg 0.000116416 +/- 4.043e-05 min 6.1505e-05 max 0.000642459 sum 0.076601728
Sockets used: 658 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 658
Code 200 : 342 (34.2 %)
Code 409 : 557 (55.7 %)
Code 511 : 101 (10.1 %)
All done 1000 calls (plus 0 warmup) 1.431 ms avg, 698.8 qps
```

如上测试结果，近似 100次错误后，发生熔断:

```bash
Code 200 : 342 (34.2 %)
Code 409 : 557 (55.7 %)
Code 511 : 101 (10.1 %)
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

1分钟后执行，返回结果:

```bash
Code 200 : 396 (39.6 %)
Code 409 : 503 (50.3 %)
Code 511 : 101 (10.1 %)
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.3 场景测试三：错误数量触发熔断&降级持续时间&状态回写

##### 3.3.3.1 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.3.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.00098462243 +/- 0.000789 min 0.000506667 max 0.015732066 sum 0.984622429
# target 50% 0.000823085
# target 75% 0.000981611
# target 90% 0.00229771
# target 99% 0.00298473
# target 99.9% 0.005
Error cases : count 200 avg 0.001170558 +/- 0.001232 min 0.000566454 max 0.015732066 sum 0.234111609
# Socket and IP used for each connection:
[0] 201 socket used, resolved to [10.96.150.163:8080] connection timing : count 201 avg 0.00012459086 +/- 4.717e-05 min 6.3066e-05 max 0.000477904 sum 0.025042763
Sockets used: 201 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 201
Code 200 : 800 (80.0 %)
Code 511 : 200 (20.0 %)
All done 1000 calls (plus 0 warmup) 0.985 ms avg, 1015.3 qp
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 800 (80.0 %)
Code 511 : 200 (20.0 %)
```

##### 3.3.3.3 设置熔断策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.openservicemesh.io/v1alpha1
kind: UpstreamTrafficSetting
metadata:
  name: http-circuit-breaking
  namespace: circuit-breaking
spec:
  host: fortio.circuit-breaking.svc.cluster.local
  connectionSettings:
    http:
      circuitBreaking:                  #7层熔断策略
        statTimeWindow: 1m              #熔断统计时间窗口
        minRequestAmount: 200           #熔断触发的最小请求数
        errorAmountThreshold: 100       #错误触发数量阈值
        degradedTimeWindow: 1m          #降级持续时间
        degradedStatusCode: 520         #降级回写状态码
EOF
```

##### 3.3.3.4 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.3.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0013628777 +/- 0.0006277 min 0.000541009 max 0.00479157 sum 1.36287773
# target 50% 0.00120215
# target 75% 0.00173978
# target 90% 0.0022377
# target 99% 0.00297541
# target 99.9% 0.00452771
Error cases : count 588 avg 0.0016197162 +/- 0.0004588 min 0.000604428 max 0.004763581 sum 0.952393106
# Socket and IP used for each connection:
[0] 588 socket used, resolved to [10.96.150.163:8080] connection timing : count 588 avg 0.00011578365 +/- 3.81e-05 min 5.3573e-05 max 0.000454821 sum 0.068080784
Sockets used: 588 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 588
Code 200 : 412 (41.2 %)
Code 511 : 101 (10.1 %)
Code 520 : 487 (48.7 %)
All done 1000 calls (plus 0 warmup) 1.363 ms avg, 733.6 qps
```

如上测试结果，近似100次错误后，发生熔断，状态码回写 409为 520:

```bash
Code 200 : 412 (41.2 %)
Code 511 : 101 (10.1 %)
Code 520 : 487 (48.7 %)
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 520 : 1000 (100.0 %)
```

1分钟后执行，返回结果:

```bash
Code 200 : 388 (38.8 %)
Code 511 : 101 (10.1 %)
Code 520 : 511 (51.1 %)
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.4 场景测试四：错误比率触发熔断&降级持续时间

##### 3.3.4.1 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.4.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.00099189489 +/- 0.0006398 min 0.000504815 max 0.004780717 sum 0.991894887
# target 50% 0.000820796
# target 75% 0.000979103
# target 90% 0.00231618
# target 99% 0.00297794
# target 99.9% 0.00452048
Error cases : count 200 avg 0.0010457005 +/- 0.0006665 min 0.000590193 max 0.004308139 sum 0.209140105
# Socket and IP used for each connection:
[0] 201 socket used, resolved to [10.96.150.163:8080] connection timing : count 201 avg 0.00012012314 +/- 3.68e-05 min 6.7658e-05 max 0.000298295 sum 0.024144751
Sockets used: 201 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 201
Code 200 : 800 (80.0 %)
Code 511 : 200 (20.0 %)
All done 1000 calls (plus 0 warmup) 0.992 ms avg, 1007.9 qps
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 800 (80.0 %)
Code 511 : 200 (20.0 %)
```

##### 3.3.4.3 设置熔断策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.openservicemesh.io/v1alpha1
kind: UpstreamTrafficSetting
metadata:
  name: http-circuit-breaking
  namespace: circuit-breaking
spec:
  host: fortio.circuit-breaking.svc.cluster.local
  connectionSettings:
    http:
      circuitBreaking:                  #7层熔断策略
        statTimeWindow: 1m              #熔断统计时间窗口
        minRequestAmount: 200           #熔断触发的最小请求数
        errorRatioThreshold: 0.10       #错误比率触发阈值
        degradedTimeWindow: 1m          #降级持续时间
EOF
```

##### 3.3.4.4 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:10
```

##### 3.3.4.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:10
Aggregated Function Time : count 1000 avg 0.0016429267 +/- 0.0004358 min 0.000533189 max 0.00474449 sum 1.64292672
# target 50% 0.00149561
# target 75% 0.00180928
# target 90% 0.00199749
# target 99% 0.00297778
# target 99.9% 0.00437225
Error cases : count 894 avg 0.0017435252 +/- 0.0002813 min 0.000554536 max 0.004430205 sum 1.55871156
# Socket and IP used for each connection:
[0] 894 socket used, resolved to [10.96.150.163:8080] connection timing : count 894 avg 0.00011459571 +/- 4.073e-05 min 6.3708e-05 max 0.000751849 sum 0.102448566
Sockets used: 894 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 894
Code 200 : 106 (10.6 %)
Code 409 : 883 (88.3 %)
Code 511 : 11 (1.1 %)
All done 1000 calls (plus 0 warmup) 1.643 ms avg, 608.5 qps
```

~~如上测试结果，近似 10%的错误率(100次错误)后，发生熔断:~~

```bash
Code 200 : 106 (10.6 %)
Code 409 : 883 (88.3 %)
Code 511 : 11 (1.1 %)
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

1分钟后执行，返回结果:

```bash
Code 200 : 51 (5.1 %)
Code 409 : 938 (93.8 %)
Code 511 : 11 (1.1 %)
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.5 场景测试五：错误比率触发熔断&降级持续时间&状态回写

##### 3.3.5.1 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.5.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.00098462243 +/- 0.000789 min 0.000506667 max 0.015732066 sum 0.984622429
# target 50% 0.000823085
# target 75% 0.000981611
# target 90% 0.00229771
# target 99% 0.00298473
# target 99.9% 0.005
Error cases : count 200 avg 0.001170558 +/- 0.001232 min 0.000566454 max 0.015732066 sum 0.234111609
# Socket and IP used for each connection:
[0] 201 socket used, resolved to [10.96.150.163:8080] connection timing : count 201 avg 0.00012459086 +/- 4.717e-05 min 6.3066e-05 max 0.000477904 sum 0.025042763
Sockets used: 201 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 201
Code 200 : 800 (80.0 %)
Code 511 : 200 (20.0 %)
All done 1000 calls (plus 0 warmup) 0.985 ms avg, 1015.3 qp
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 800 (80.0 %)
Code 511 : 200 (20.0 %)
```

##### 3.3.5.3 设置熔断策略

```bash
kubectl apply -f - <<EOF
apiVersion: policy.openservicemesh.io/v1alpha1
kind: UpstreamTrafficSetting
metadata:
  name: http-circuit-breaking
  namespace: circuit-breaking
spec:
  host: fortio.circuit-breaking.svc.cluster.local
  connectionSettings:
    http:
      circuitBreaking:                  #7层熔断策略
        statTimeWindow: 1m              #熔断统计时间窗口
        minRequestAmount: 200           #熔断触发的最小请求数
        errorRatioThreshold: 0.10       #错误比率触发阈值
        degradedTimeWindow: 1m          #降级持续时间
        degradedStatusCode: 520         #降级回写状态码
EOF
```

##### 3.3.3.4 测试指令

单连接，1000 次请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -qps 0 -c 1 -n 1000 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.5.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 0 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0013628777 +/- 0.0006277 min 0.000541009 max 0.00479157 sum 1.36287773
# target 50% 0.00120215
# target 75% 0.00173978
# target 90% 0.0022377
# target 99% 0.00297541
# target 99.9% 0.00452771
Error cases : count 588 avg 0.0016197162 +/- 0.0004588 min 0.000604428 max 0.004763581 sum 0.952393106
# Socket and IP used for each connection:
[0] 588 socket used, resolved to [10.96.150.163:8080] connection timing : count 588 avg 0.00011578365 +/- 3.81e-05 min 5.3573e-05 max 0.000454821 sum 0.068080784
Sockets used: 588 (for perfect keepalive, would be 1)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.150.163:8080: 588
Code 200 : 412 (41.2 %)
Code 511 : 101 (10.1 %)
Code 520 : 487 (48.7 %)
All done 1000 calls (plus 0 warmup) 1.363 ms avg, 733.6 qps
```

如上测试结果，近似 10%的错误率(100次错误)后，发生熔断，状态码回写 409为 520:

```bash
Code 200 : 412 (41.2 %)
Code 511 : 101 (10.1 %)
Code 520 : 487 (48.7 %)
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 520 : 1000 (100.0 %)
```

1分钟后执行，返回结果:

```bash
Code 200 : 388 (38.8 %)
Code 511 : 101 (10.1 %)
Code 520 : 511 (51.1 %)
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```



