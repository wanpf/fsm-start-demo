## Traffic mirroring HTTP流量镜像插件
**通过fsm 给HTTP服务设置镜像流量**

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.0.0
curl -L https://github.com/flomesh-io/fsm/releases/download/${release}/fsm-${release}-${system}-${arch}.tar.gz | tar -vxzf -
./${system}-${arch}/fsm version
cp ./${system}-${arch}/fsm /usr/local/bin/
```

## 2. 安装 fsm

```bash
export fsm_namespace=fsm-system 
export fsm_mesh_name=fsm 

fsm install \
    --mesh-name "$fsm_mesh_name" \
    --fsm-namespace "$fsm_namespace" \
    --set=fsm.certificateProvider.kind=tresor \
    --set=fsm.image.registry=flomesh \
    --set=fsm.image.tag=1.0.0 \
    --set=fsm.image.pullPolicy=Always \
    --set=fsm.sidecarLogLevel=warn \
    --set=fsm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 部署业务 POD
```bash
kubectl create namespace curl
fsm namespace add curl
kubectl apply -n curl -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/plugin/curl.curl.yaml

kubectl create namespace pipy
fsm namespace add pipy
kubectl apply -n pipy -f https://raw.githubusercontent.com/wanpf/fsm-start-demo/main/demo/plugin/traffic-mirror/pipy-ok.pipy.yaml

#等待依赖的 POD 正常启动
sleep 2
kubectl wait --for=condition=ready pod -n curl -l app=curl --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v1 --timeout=180s
kubectl wait --for=condition=ready pod -n pipy -l app=pipy-ok -l version=v2 --timeout=180s
```

## 4. 启用Plugin策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enablePluginPolicy":true}}}' --type=merge
```

## 5. 声明插件

```bash
kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: traffic-mirror
spec:
  priority: 115
  pipyscript: |+
    ((
      config = pipy.solve('config.js'),
      clusterCache = new algo.Cache(
        (clusterName => (
          (cluster = config?.Outbound?.ClustersConfigs?.[clusterName]) => (
            cluster ? Object.assign({ name: clusterName }, cluster) : null
          )
        )())
      ),
      hexChar = { '0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, 'a': 10, 'b': 11, 'c': 12, 'd': 13, 'e': 14, 'f': 15 },
      randomInt63 = () => (
        algo.uuid().substring(0, 18).replaceAll('-', '').split('').reduce((calc, char) => (calc * 16) + hexChar[char], 0) / 2
      ),
      samplingRange = fraction => (fraction > 0 ? fraction : 0) * Math.pow(2, 63),
      configCache = new algo.Cache(
        pluginConfig => pluginConfig && (
          {
            samplingRange: pluginConfig?.percentage?.value > 0 ? samplingRange(pluginConfig.percentage.value) : 0,
            clusterName: pluginConfig?.namespace + '/' + pluginConfig?.service + '|' + pluginConfig?.port,
            namespace: pluginConfig?.namespace,
            service: pluginConfig?.service,
            port: pluginConfig?.port,
          }
        )
      ),
    ) => pipy({
      _pluginName: '',
      _pluginConfig: null,
      _mirrorConfig: null,
      _randomVal: 0,
      _mirrorCluster: undefined,
    })
    .import({
      __service: 'outbound-http-routing',
      __cluster: 'outbound-http-routing',
    })
    .pipeline()
    .onStart(
      () => void (
        _pluginName = __filename.slice(9, -3),
        _pluginConfig = __service?.Plugins?.[_pluginName],
        (_mirrorConfig = configCache.get(_pluginConfig)) && (
          _mirrorCluster = clusterCache.get(_mirrorConfig.clusterName)
        )
      )
    )
    .handleMessageStart(
      () => (
        _mirrorCluster && (
          _randomVal = randomInt63(),
          (_randomVal < _mirrorConfig.samplingRange) || (
            _mirrorCluster = undefined
          )
        )
      )
    )
    .branch(
      () => _mirrorCluster, (
        $=>$
        .fork().to('mirror-cluster')
        .chain()
      ), (
        $=>$.chain()
      )
    )
    
    .pipeline('mirror-cluster')
    .replaceMessage(
      msg => (
        (
          mirrorMsg = new Message(Object.assign({}, msg.head), msg.body),
          hostParts = msg.head.headers.host.split('.'),
        ) => (
          __cluster = _mirrorCluster,
          hostParts?.length > 0 && (
            hostParts[0] = _mirrorConfig.service,
            mirrorMsg.head.headers = Object.assign({}, msg.head.headers),
            mirrorMsg.head.headers.host = hostParts.join('.')
          ),
          mirrorMsg
        )
      )()
    )
    .chain([
      'modules/outbound-http-load-balancing.js',
      'modules/outbound-http-default.js',
    ])
    .dummy()
    )()
EOF
```

 
## 6. 设置插件链
**针对服务名，设置加载插件**
```bash
kubectl apply -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: traffic-mirror-chain
  namespace: pipy
spec:
  chains:
    - name: outbound-http
      plugins:
        - traffic-mirror
  selectors:
    podSelector:
      matchLabels:
        app: curl
      matchExpressions:
        - key: app
          operator: In
          values: ["curl"]
    namespaceSelector:
      matchExpressions:
        - key: openservicemesh.io/monitored-by
          operator: In
          values: ["fsm"]
EOF
```

## 7. 设置插件配置
**设置插件配置信息**
```bash
kubectl apply -f - <<EOF
kind: PluginConfig
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: traffic-mirror-config
  namespace: curl
spec:
  config:
    namespace: pipy
    service: pipy-ok-v2
    port: 8080
    percentage:
      value: 1.0
  plugin: traffic-mirror
  destinationRefs:
    - kind: Service
      name: pipy-ok-v1
      namespace: pipy
EOF
```

## 8. 测试
测试命令：  
 ```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok-v1.pipy:8080 
```
### 8.1 查看 pipy-ok-v1 服务的日志：  
```bash
pipy_ok_v1="$(kubectl get pod -n pipy -l app=pipy-ok,version=v1 -o jsonpath='{.items[0].metadata.name}')"
kubectl logs pod/${pipy_ok_v1} -n pipy -c pipy
```
pipy-ok-v1的日志：  
```bash
[2023-03-29 08:41:04 +0000] [1] [INFO] Starting gunicorn 19.9.0
[2023-03-29 08:41:04 +0000] [1] [INFO] Listening at: http://0.0.0.0:8080 (1)
[2023-03-29 08:41:04 +0000] [1] [INFO] Using worker: sync
[2023-03-29 08:41:04 +0000] [14] [INFO] Booting worker with pid: 14
127.0.0.6 - - [29/Mar/2023:08:45:35 +0000] "GET / HTTP/1.1" 200 9593 "-" "curl/7.85.0-DEV"
```
### 8.2 查看 pipy-ok-v2 服务的日志：  
```bash
pipy_ok_v2="$(kubectl get pod -n pipy -l app=pipy-ok,version=v2 -o jsonpath='{.items[0].metadata.name}')"
kubectl logs pod/${pipy_ok_v2} -n pipy -c pipy
```
pipy-ok-v2的日志：  
```bash
[2023-03-29 08:41:09 +0000] [1] [INFO] Starting gunicorn 19.9.0
[2023-03-29 08:41:09 +0000] [1] [INFO] Listening at: http://0.0.0.0:8080 (1)
[2023-03-29 08:41:09 +0000] [1] [INFO] Using worker: sync
[2023-03-29 08:41:09 +0000] [15] [INFO] Booting worker with pid: 15
127.0.0.6 - - [29/Mar/2023:08:45:35 +0000] "GET / HTTP/1.1" 200 9593 "-" "curl/7.85.0-DEV"
```
### 8.3 测试结果
访问 pipy-ok-v1 服务，在 pipy-ok-v1 和 pipy-ok-v2 的日志里都出现了访问日志记录。  
实现了：将访问 pipy-ok-v1 的请求镜像到 pipy-ok-v2。
