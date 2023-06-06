## Cors policy 策略插件
**通过fsm 给服务设置 cors 策略**

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
kubectl apply -n pipy -f https://raw.githubusercontent.com/cybwan/fsm-start-demo/main/demo/plugin/pipy-ok.pipy.yaml

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
  name: cors-policy
spec:
  priority: 165
  pipyscript: |+
    ((
      cacheTTL = val => (
        val?.indexOf('s') > 0 && (
        val.replace('s', '')
        ) ||
        val?.indexOf('m') > 0 && (
        val.replace('m', '') * 60
        ) ||
        val?.indexOf('h') > 0 && (
        val.replace('h', '') * 3600
        ) ||
        val?.indexOf('d') > 0 && (
        val.replace('d', '') * 86400
        ) ||
        0
      ),
      originMatch = origin => (
        (origin || []).map(
        o => (
          o?.exact && (
            url => url === o.exact
          ) ||
          o?.prefix && (
            url => url.startsWith(o.prefix)
          ) ||
          o?.regex && (
            (match = new RegExp(o.regex)) => (
            url => match.test(url)
            )
          )()
        )
        )
      ),
      configCache = new algo.Cache(
        pluginConfig => (
        (originHeaders = {}, optionsHeaders = {}) => (
          pluginConfig?.allowCredentials && (
            originHeaders['access-control-allow-credentials'] = 'true'
          ),
          pluginConfig?.exposeHeaders && (
            originHeaders['access-control-expose-headers'] = pluginConfig.exposeHeaders.join()
          ),
          pluginConfig?.allowMethods && (
            optionsHeaders['access-control-allow-methods'] = pluginConfig.allowMethods.join()
          ),
          pluginConfig?.allowHeaders && (
            optionsHeaders['access-control-allow-headers'] = pluginConfig.allowHeaders.join()
          ),
          pluginConfig?.maxAge && (cacheTTL(pluginConfig?.maxAge) > 0) && (
            optionsHeaders['access-control-max-age'] = cacheTTL(pluginConfig?.maxAge)
          ),
          {
            originHeaders,
            optionsHeaders,
            matchingMap: originMatch(pluginConfig?.allowOrigins)
          }
        )
        )()
      ),
    ) => pipy({
      _pluginName: '',
      _pluginConfig: null,
      _corsHeaders: null,
      _matchingMap: null,
      _matching: false,
      _isOptions: false,
      _origin: undefined,
    })
    .import({
      __service: 'inbound-http-routing',
    })
    .pipeline()
    .onStart(
      () => void (
        _pluginName = __filename.slice(9, -3),
        _pluginConfig = __service?.Plugins?.[_pluginName],
        _corsHeaders = configCache.get(_pluginConfig),
        _matchingMap = _corsHeaders?.matchingMap
      )
    )
    .branch(
      () => _matchingMap, (
        $=>$
        .handleMessageStart(
        msg => (
          (_origin = msg?.head?.headers?.origin) && (_matching = _matchingMap.find(o => o(_origin))) && (
            _isOptions = (msg?.head?.method === 'OPTIONS')
          )
        )
        )
      ), (
        $=>$
      )
    )
    .branch(
      () => _matching, (
        $=>$.branch(
        () => _isOptions, (
          $=>$.replaceMessage(
            () => (
            new Message({ status: 200, headers: { ..._corsHeaders.originHeaders, ..._corsHeaders.optionsHeaders, 'access-control-allow-origin': _origin } })
            )
          )
        ), (
          $=>$
          .chain()
          .handleMessageStart(
            msg => (
            Object.keys(_corsHeaders.originHeaders).forEach(
              key => msg.head.headers[key] = _corsHeaders.originHeaders[key]
            ),
            msg.head.headers['access-control-allow-origin'] = _origin
            )
          )
        )
        )
      ), (
        $=>$.chain()
      )
    )
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
  name: cors-policy-chain
  namespace: pipy
spec:
  chains:
    - name: inbound-http
      plugins:
        - cors-policy
  selectors:
    podSelector:
      matchLabels:
        app: pipy-ok
      matchExpressions:
        - key: app
          operator: In
          values: ["pipy-ok"]
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
  name: cors-policy-config
  namespace: pipy
spec:
  config:
    allowCredentials: true
    allowHeaders:
    - X-Foo-Bar-1
    allowMethods:
    - POST
    - GET
    - PATCH
    - DELETE
    allowOrigins:
    - regex: http.*://www.test.cn
    - exact: http://www.aaa.com
    - prefix: http://www.bbb.com
    exposeHeaders:
    - Content-Encoding
    - Kuma-Revision
    maxAge: 24h
  plugin: cors-policy
  destinationRefs:
    - kind: Service
      name: pipy-ok
      namespace: pipy
EOF
```

## 8. 测试
### 8.1 测试命令一：
 ```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080 -H "Origin: http://www.bbb.com"
```
返回结果：  
```bash
HTTP/1.1 200 OK
access-control-allow-credentials: true
access-control-expose-headers: Content-Encoding,Kuma-Revision
access-control-allow-origin: http://www.bbb.com
content-length: 20
connection: keep-alive

Hi, I am PIPY-OK v1!
```
### 8.2 测试命令二：
```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080 -H "Origin: http://www.bbb.com" -X OPTIONS
```
返回结果：  
```bash
HTTP/1.1 200 OK
access-control-allow-origin: http://www.bbb.com
access-control-allow-credentials: true
access-control-expose-headers: Content-Encoding,Kuma-Revision
access-control-allow-methods: POST,GET,PATCH,DELETE
access-control-allow-headers: X-Foo-Bar-1
access-control-max-age: 86400
content-length: 0
connection: keep-alive
```
