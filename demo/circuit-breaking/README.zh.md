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

#### 3.3.1 场景测试一：最大连接数&最大请求频率熔断

请参见[Circuit breaking for destinations within the mesh](https://docs.openservicemesh.io/docs/demos/circuit_breaking_mesh_internal/)

#### 3.3.2 场景测试二：错误数量触发熔断&降级持续时间

##### 3.3.2.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.2.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0045255084 +/- 0.005122 min 0.001021667 max 0.028708983 sum 4.52550837
# target 99.99% 0.0286997
Error cases : count 207 avg 0.0044615688 +/- 0.004851 min 0.001191759 max 0.028532052 sum 0.923544736
# Socket and IP used for each connection:
...
Sockets used: 215 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.87.0:8080: 215
Code 200 : 793 (79.3 %)
Code 511 : 207 (20.7 %)
All done 1000 calls (plus 0 warmup) 4.526 ms avg, 199.8 qps
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 793 (79.3 %)
Code 511 : 207 (20.7 %)
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

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.2.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0043351281 +/- 0.003974 min 0.000536762 max 0.028909329 sum 4.3351281
# target 99.99% 0.0288898
Error cases : count 541 avg 0.0043278259 +/- 0.002677 min 0.000536762 max 0.028844903 sum 2.34135383
# Socket and IP used for each connection:
...
Sockets used: 541 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.87.0:8080: 541
Code 200 : 459 (45.9 %)
Code 409 : 441 (44.1 %)
Code 511 : 100 (10.0 %)
All done 1000 calls (plus 0 warmup) 4.335 ms avg, 199.8 qps
```

如上测试结果，100次错误(511)后，发生熔断(409):

```bash
Code 200 : 459 (45.9 %)
Code 409 : 441 (44.1 %)
Code 511 : 100 (10.0 %)
```

查看 sidecar 日志:

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl logs -n circuit-breaking "$fortio_client" -c sidecar | grep circuit_breaker
```

如sidecar 日志所示，560 个请求中，100 个错误请求，断路器状态为open:

```bash
2022-09-30 07:29:27.371 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (open)  report circuit-breaking/fortio|8080 3 0 true 560 0 100
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

 1 分钟后，查看 sidecar 日志，断路器状态为close:

```bash
2022-09-30 07:30:47.245 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (close) timer circuit-breaking/fortio|8080 0 61 false 0 0 0
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.3 场景测试三：错误数量触发熔断&降级持续时间&状态回写

##### 3.3.3.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.3.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0044694945 +/- 0.005717 min 0.001249496 max 0.031661934 sum 4.46949448
# target 99.99% 0.0316481
Error cases : count 194 avg 0.0054058262 +/- 0.007397 min 0.001441669 max 0.031488709 sum 1.04873028
# Socket and IP used for each connection:
...
Sockets used: 202 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 202
Code 200 : 806 (80.6 %)
Code 511 : 194 (19.4 %)
All done 1000 calls (plus 0 warmup) 4.469 ms avg, 199.8 qps
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 806 (80.6 %)
Code 511 : 194 (19.4 %)
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

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.3.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0042405899 +/- 0.004346 min 0.000620785 max 0.031013001 sum 4.24058986
# target 99.99% 0.0310003
Error cases : count 602 avg 0.0037588412 +/- 0.002148 min 0.000620785 max 0.030396153 sum 2.2628224
# Socket and IP used for each connection:
...
Sockets used: 602 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 602
Code 200 : 398 (39.8 %)
Code 511 : 100 (10.0 %)
Code 520 : 502 (50.2 %)
All done 1000 calls (plus 0 warmup) 4.241 ms avg, 199.8 qps
```

如上测试结果，100次错误(511)后，发生熔断，回写状态码为 520:

```bash
Code 200 : 398 (39.8 %)
Code 511 : 100 (10.0 %)
Code 520 : 502 (50.2 %)
```

查看 sidecar 日志:

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl logs -n circuit-breaking "$fortio_client" -c sidecar | grep circuit_breaker
```

如sidecar 日志所示，498 个请求中，100 个错误请求，断路器状态为open:

```bash
2022-09-30 07:52:14.811 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (open)  report circuit-breaking/fortio|8080 7 0 true 498 0 100
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

 1 分钟后，查看 sidecar 日志，断路器状态为close:

```bash
2022-09-30 07:53:15.325 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (close) timer circuit-breaking/fortio|8080 0 61 false 0 0 0
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.4 场景测试四：错误比率触发熔断&降级持续时间

##### 3.3.4.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.4.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0042703046 +/- 0.005218 min 0.001273563 max 0.030518256 sum 4.27030457
# target 99.99% 0.0305053
Error cases : count 218 avg 0.0047364847 +/- 0.005942 min 0.001315971 max 0.030019118 sum 1.03255367
# Socket and IP used for each connection:
...
Sockets used: 226 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 226
Code 200 : 782 (78.2 %)
Code 511 : 218 (21.8 %)
All done 1000 calls (plus 0 warmup) 4.270 ms avg, 199.8 qps
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 782 (78.2 %)
Code 511 : 218 (21.8 %)
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

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.4.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0040698366 +/- 0.002399 min 0.000560022 max 0.02748693 sum 4.06983656
# target 99.99% 0.0274558
Error cases : count 846 avg 0.0040857423 +/- 0.00165 min 0.000560022 max 0.02748693 sum 3.45653795
# Socket and IP used for each connection:
...
Sockets used: 846 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 846
Code 200 : 154 (15.4 %)
Code 409 : 800 (80.0 %)
Code 511 : 46 (4.6 %)
All done 1000 calls (plus 0 warmup) 4.070 ms avg, 199.7 qps
```

如上测试结果，46次错误(511)后，发生熔断(409):

```bash
Code 200 : 154 (15.4 %)
Code 409 : 800 (80.0 %)
Code 511 : 46 (4.6 %)
```

查看 sidecar 日志:

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl logs -n circuit-breaking "$fortio_client" -c sidecar | grep circuit_breaker
```

如sidecar 日志所示，200 个请求中，46 个错误请求，断路器状态为open:

```bash
2022-09-30 08:00:07.564 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (open)  check circuit-breaking/fortio|8080 37 0 true 200 0 46
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

 1 分钟后，查看 sidecar 日志，断路器状态为close:

```bash
2022-09-30 08:01:07.990 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (close) timer circuit-breaking/fortio|8080 0 61 false 0 0 0
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.5 场景测试五：错误比率触发熔断&降级持续时间&状态回写

##### 3.3.5.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.5.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0042064067 +/- 0.005582 min 0.00116919 max 0.031039157 sum 4.20640669
# target 99.99% 0.0310288
Error cases : count 194 avg 0.0041424246 +/- 0.005388 min 0.001286147 max 0.029640087 sum 0.803630366
# Socket and IP used for each connection:
...
Sockets used: 203 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 203
Code 200 : 806 (80.6 %)
Code 511 : 194 (19.4 %)
All done 1000 calls (plus 0 warmup) 4.206 ms avg, 199.8 qps
```

如上测试结果，近似 20%的错误率:

```bash
Code 200 : 806 (80.6 %)
Code 511 : 194 (19.4 %)
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

##### 3.3.5.4 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的错误率，错误码 511：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 99.99 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
```

##### 3.3.5.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?status=511:20
Aggregated Function Time : count 1000 avg 0.0038476405 +/- 0.002339 min 0.000431594 max 0.026835408 sum 3.84764049
# target 99.99% 0.0268092
Error cases : count 835 avg 0.0038289783 +/- 0.001207 min 0.000431594 max 0.025951398 sum 3.19719688
# Socket and IP used for each connection:
...
Sockets used: 835 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 835
Code 200 : 165 (16.5 %)
Code 511 : 35 (3.5 %)
Code 520 : 800 (80.0 %)
All done 1000 calls (plus 0 warmup) 3.848 ms avg, 199.8 qps
```

如上测试结果，35次错误(511)后，发生熔断，回写状态码为 520:

```bash
Code 200 : 165 (16.5 %)
Code 511 : 35 (3.5 %)
Code 520 : 800 (80.0 %)
```

查看 sidecar 日志:

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl logs -n circuit-breaking "$fortio_client" -c sidecar | grep circuit_breaker
```

如sidecar 日志所示，200个请求中，35 个错误请求，断路器状态为open:

```bash
2022-09-30 08:05:37.362 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (open)  timer circuit-breaking/fortio|8080 26 0 true 200 0 35
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

 1 分钟后，查看 sidecar 日志，断路器状态为close:

```bash
2022-09-30 08:06:38.348 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (close) timer circuit-breaking/fortio|8080 0 61 false 0 0 0
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.6 场景测试六：慢调用数量触发熔断&降级持续时间

##### 3.3.6.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.6.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
Aggregated Sleep Time : count 990 avg -0.24941776 +/- 0.2837 min -1.208026088 max 0.04953001 sum -246.923585
# range, mid point, percentile, count
>= -1.20803 <= -0.001 , -0.604513 , 73.64, 729
> 0.007 <= 0.008 , 0.0075 , 73.84, 2
> 0.017 <= 0.019 , 0.018 , 73.94, 1
> 0.019 <= 0.024 , 0.0215 , 74.14, 2
> 0.024 <= 0.029 , 0.0265 , 74.95, 8
> 0.029 <= 0.034 , 0.0315 , 75.45, 5
> 0.034 <= 0.039 , 0.0365 , 76.16, 7
> 0.039 <= 0.044 , 0.0415 , 78.18, 20
> 0.044 <= 0.049 , 0.0465 , 99.29, 209
> 0.049 <= 0.04953 , 0.049265 , 100.00, 7
# target 50% -0.388973
WARNING 73.64% of sleep were falling behind
Aggregated Function Time : count 1000 avg 0.041801059 +/- 0.08028 min 0.000604005 max 0.221155809 sum 41.8010588
# target 50% 0.00150606
# target 78% 0.0045
# target 79% 0.011
# target 80% 0.03
# target 81% 0.201058
# target 82% 0.202116
# target 90% 0.210578
# target 95% 0.215867
Error cases : count 0 avg 0 +/- 0 min 0 max 0 sum 0
# Socket and IP used for each connection:
...
Sockets used: 10 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 10
Code 200 : 1000 (100.0 %)
All done 1000 calls (plus 0 warmup) 41.801 ms avg, 173.1 qps
```

如上测试结果，请求全部成功，约20%的请求响应时间大于200 毫秒:

```bash
# target 50% 0.00150606
# target 78% 0.0045
# target 79% 0.011
# target 80% 0.03
# target 81% 0.201058
# target 82% 0.202116
# target 90% 0.210578
# target 95% 0.215867

Code 200 : 1000 (100.0 %)
```

##### 3.3.6.3 设置熔断策略

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
        slowTimeThreshold: 200ms        #慢调用耗时触发阈值
        slowAmountThreshold: 100        #慢调用数量触发阈值
        degradedTimeWindow: 1m          #降级持续时间
EOF
```

##### 3.3.6.4 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.6.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
Aggregated Sleep Time : count 990 avg -0.057674106 +/- 0.1538 min -0.762971791 max 0.049646898 sum -57.0973645
# range, mid point, percentile, count
>= -0.762972 <= -0.001 , -0.381986 , 42.42, 420
> 0.009 <= 0.01 , 0.0095 , 42.53, 1
> 0.013 <= 0.015 , 0.014 , 42.73, 2
> 0.019 <= 0.024 , 0.0215 , 42.83, 1
> 0.024 <= 0.029 , 0.0265 , 44.04, 12
> 0.029 <= 0.034 , 0.0315 , 44.44, 4
> 0.034 <= 0.039 , 0.0365 , 45.05, 6
> 0.039 <= 0.044 , 0.0415 , 51.41, 63
> 0.044 <= 0.049 , 0.0465 , 99.60, 477
> 0.049 <= 0.0496469 , 0.0493234 , 100.00, 4
# target 50% 0.0428889
WARNING 42.42% of sleep were falling behind
Aggregated Function Time : count 1000 avg 0.023931795 +/- 0.06118 min 0.000264648 max 0.206229814 sum 23.9317947
# target 50% 0.00287179
# target 78% 0.00495139
# target 79% 0.00504167
# target 80% 0.00518056
# target 81% 0.00531944
# target 82% 0.00545833
# target 90% 0.200297
# target 95% 0.203263
Error cases : count 428 avg 0.0040187461 +/- 0.001318 min 0.000264648 max 0.007829652 sum 1.72002334
# Socket and IP used for each connection:
...
Sockets used: 428 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 428
Code 200 : 572 (57.2 %)
Code 409 : 428 (42.8 %)
All done 1000 calls (plus 0 warmup) 23.932 ms avg, 199.7 qps
```

如上测试结果，428个请求错误码 409，发生熔断:

```bash
Code 200 : 572 (57.2 %)
Code 409 : 428 (42.8 %)
```

查看 sidecar 日志:

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl logs -n circuit-breaking "$fortio_client" -c sidecar | grep circuit_breaker
```

如sidecar 日志所示，572个请求中，100个慢响应，断路器状态为open:

```bash
2022-09-30 08:47:52.076 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (open)  report circuit-breaking/fortio|8080 14 0 true 572 100 0
```

降级持续时间 1 分钟，期间再次执行，返回结果:

```bash
Code 409 : 1000 (100.0 %)
```

 1 分钟后，查看 sidecar 日志，断路器状态为close:

```bash
2022-09-30 08:48:52.202 [INF] [circuit_breaker] tick/delay/degraded/total/slowAmount/errorAmount (close) timer circuit-breaking/fortio|8080 0 61 false 0 2 0
```

本业务场景测试完毕，清理策略，以避免影响后续测试

```bash
kubectl delete upstreamtrafficsettings -n circuit-breaking http-circuit-breaking
```

#### 3.3.7 场景测试七：慢调用数量触发熔断&降级持续时间&状态回写

##### 3.3.7.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.7.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
Aggregated Sleep Time : count 990 avg -0.26957866 +/- 0.2409 min -1.350640842 max 0.049064266 sum -266.882877
# range, mid point, percentile, count
>= -1.35064 <= -0.001 , -0.67582 , 84.34, 835
> 0.006 <= 0.007 , 0.0065 , 84.44, 1
> 0.013 <= 0.015 , 0.014 , 84.55, 1
> 0.015 <= 0.017 , 0.016 , 84.65, 1
> 0.019 <= 0.024 , 0.0215 , 84.75, 1
> 0.024 <= 0.029 , 0.0265 , 85.66, 9
> 0.029 <= 0.034 , 0.0315 , 86.16, 5
> 0.034 <= 0.039 , 0.0365 , 86.77, 6
> 0.039 <= 0.044 , 0.0415 , 87.98, 12
> 0.044 <= 0.049 , 0.0465 , 99.90, 118
> 0.049 <= 0.0490643 , 0.0490321 , 100.00, 1
# target 50% -0.551213
WARNING 84.34% of sleep were falling behind
Aggregated Function Time : count 1000 avg 0.048305338 +/- 0.08487 min 0.000578655 max 0.206959475 sum 48.3053384
# target 50% 0.00148691
# target 78% 0.200388
# target 79% 0.200687
# target 80% 0.200986
# target 81% 0.201284
# target 82% 0.201583
# target 90% 0.203973
# target 95% 0.205466
Error cases : count 0 avg 0 +/- 0 min 0 max 0 sum 0
# Socket and IP used for each connection:
...
Sockets used: 10 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 10
Code 200 : 1000 (100.0 %)
All done 1000 calls (plus 0 warmup) 48.305 ms avg, 157.4 qps
```

如上测试结果，请求全部成功，约20%的请求响应时间大于200 毫秒:

```bash
# target 50% 0.00148691
# target 78% 0.200388
# target 79% 0.200687
# target 80% 0.200986
# target 81% 0.201284
# target 82% 0.201583
# target 90% 0.203973
# target 95% 0.205466

Code 200 : 1000 (100.0 %)
```

##### 3.3.7.3 设置熔断策略

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

##### 3.3.7.4 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.7.5 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
Aggregated Sleep Time : count 990 avg -0.19152577 +/- 0.258 min -1.23236586 max 0.049224197 sum -189.610511
# range, mid point, percentile, count
>= -1.23237 <= -0.001 , -0.616683 , 71.92, 712
> 0.011 <= 0.013 , 0.012 , 72.02, 1
> 0.017 <= 0.019 , 0.018 , 72.12, 1
> 0.024 <= 0.029 , 0.0265 , 73.23, 11
> 0.029 <= 0.034 , 0.0315 , 73.64, 4
> 0.034 <= 0.039 , 0.0365 , 74.04, 4
> 0.039 <= 0.044 , 0.0415 , 76.97, 29
> 0.044 <= 0.049 , 0.0465 , 99.80, 226
> 0.049 <= 0.0492242 , 0.0491121 , 100.00, 2
# target 50% -0.376818
WARNING 71.92% of sleep were falling behind
Aggregated Function Time : count 1000 avg 0.041241291 +/- 0.07994 min 0.000569982 max 0.227691209 sum 41.2412906
# target 50% 0.00154639
# target 78% 0.00294545
# target 79% 0.005
# target 80% 0.0278571
# target 81% 0.200984
# target 82% 0.20239
# target 90% 0.213635
# target 95% 0.220663
Error cases : count 0 avg 0 +/- 0 min 0 max 0 sum 0
# Socket and IP used for each connection:
...
Sockets used: 10 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 10
Code 200 : 1000 (100.0 %)
All done 1000 calls (plus 0 warmup) 41.241 ms avg, 166.5 qps
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

#### 3.3.8 场景测试八：慢调用比率触发熔断&降级持续时间

##### 3.3.8.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.8.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
Aggregated Sleep Time : count 990 avg -0.14824273 +/- 0.1789 min -0.720912436 max 0.049244595 sum -146.760305
# range, mid point, percentile, count
>= -0.720912 <= -0.001 , -0.360956 , 71.72, 710
> 0.019 <= 0.024 , 0.0215 , 71.92, 2
> 0.024 <= 0.029 , 0.0265 , 73.03, 11
> 0.029 <= 0.034 , 0.0315 , 73.84, 8
> 0.034 <= 0.039 , 0.0365 , 75.05, 12
> 0.039 <= 0.044 , 0.0415 , 77.17, 21
> 0.044 <= 0.049 , 0.0465 , 99.70, 223
> 0.049 <= 0.0492446 , 0.0491223 , 100.00, 3
# target 50% -0.219309
WARNING 71.72% of sleep were falling behind
Aggregated Function Time : count 1000 avg 0.039156439 +/- 0.07829 min 0.000610457 max 0.226153842 sum 39.1564394
# target 50% 0.00135783
# target 78% 0.003
# target 79% 0.005
# target 80% 0.01
# target 81% 0.0241667
# target 82% 0.200979
# target 90% 0.212168
# target 95% 0.219161
Error cases : count 0 avg 0 +/- 0 min 0 max 0 sum 0
# Socket and IP used for each connection:
...
Sockets used: 10 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 10
Code 200 : 1000 (100.0 %)
All done 1000 calls (plus 0 warmup) 39.156 ms avg, 182.8 qps
```

如上测试结果，请求全部成功，约20%的请求响应时间大于200 毫秒:

```bash
# target 50% 0.00135783
# target 78% 0.003
# target 79% 0.005
# target 80% 0.01
# target 81% 0.0241667
# target 82% 0.200979
# target 90% 0.212168
# target 95% 0.219161

Code 200 : 1000 (100.0 %)
```

##### 3.3.8.3 设置熔断策略

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

##### 3.3.8.4 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.8.5 测试结果

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

#### 3.3.9 场景测试九：慢调用比率触发熔断&降级持续时间&状态回写

##### 3.3.9.1 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.9.2 测试结果

正确返回结果类似于:

```bash
Fortio 1.38.0 running at 200 queries per second, 8->8 procs, for 1000 calls: http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
Aggregated Sleep Time : count 990 avg -0.14824273 +/- 0.1789 min -0.720912436 max 0.049244595 sum -146.760305
# range, mid point, percentile, count
>= -0.720912 <= -0.001 , -0.360956 , 71.72, 710
> 0.019 <= 0.024 , 0.0215 , 71.92, 2
> 0.024 <= 0.029 , 0.0265 , 73.03, 11
> 0.029 <= 0.034 , 0.0315 , 73.84, 8
> 0.034 <= 0.039 , 0.0365 , 75.05, 12
> 0.039 <= 0.044 , 0.0415 , 77.17, 21
> 0.044 <= 0.049 , 0.0465 , 99.70, 223
> 0.049 <= 0.0492446 , 0.0491223 , 100.00, 3
# target 50% -0.219309
WARNING 71.72% of sleep were falling behind
Aggregated Function Time : count 1000 avg 0.039156439 +/- 0.07829 min 0.000610457 max 0.226153842 sum 39.1564394
# target 50% 0.00135783
# target 78% 0.003
# target 79% 0.005
# target 80% 0.01
# target 81% 0.0241667
# target 82% 0.200979
# target 90% 0.212168
# target 95% 0.219161
Error cases : count 0 avg 0 +/- 0 min 0 max 0 sum 0
# Socket and IP used for each connection:
...
Sockets used: 10 (for perfect keepalive, would be 10)
Uniform: false, Jitter: false
IP addresses distribution:
10.96.144.44:8080: 10
Code 200 : 1000 (100.0 %)
All done 1000 calls (plus 0 warmup) 39.156 ms avg, 182.8 qps
```

如上测试结果，请求全部成功，约20%的请求响应时间大于200 毫秒:

```bash
# target 50% 0.00135783
# target 78% 0.003
# target 79% 0.005
# target 80% 0.01
# target 81% 0.0241667
# target 82% 0.200979
# target 90% 0.212168
# target 95% 0.219161

Code 200 : 1000 (100.0 %)
```

##### 3.3.9.3 设置熔断策略

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

##### 3.3.9.4 测试指令

10个连接，1000次请求，每秒 200 个请求， 20%的请求耗时大于200毫秒：

```bash
fortio_client="$(kubectl get pod -n circuit-breaking -l app=fortio-client -o jsonpath='{.items[0].metadata.name}')"
kubectl exec "$fortio_client" -n circuit-breaking -c fortio-client -- fortio load -quiet -c 10 -n 1000 -qps 200 -p 50,78,79,80,81,82,90,95 http://fortio.circuit-breaking.svc.cluster.local:8080/echo?delay=200ms:20
```

##### 3.3.9.5 测试结果

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



