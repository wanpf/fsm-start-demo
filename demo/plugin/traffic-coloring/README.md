## Traffic coloring 策略插件
**fsm通过此插件，对request/response请求头进行修改，实现流量染色功能**

## 1. 下载并安装 fsm 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.1.4
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
    --set=fsm.image.tag=1.1.4 \
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
  name: traffic-coloring
spec:
  priority: 165
  pipyscript: |+
    ((
      getParameters = path => (
        (
          params = {},
          qsa,
          qs,
          arr,
          kv,
        ) => (
          path && (
            (qsa = path.split('?')[1]) && (
              (qs = qsa.split('#')[0]) && (
                (arr = qs.split('&')) && (
                  arr.forEach(
                    p => (
                      kv = p.split('='),
                      params[kv[0]] = kv[1]
                    )
                  )
                )
              )
            )
          ),
          params
        )
      )(),
    
      makeDictionaryMatches = dictionary => (
        (
          tests = Object.entries(dictionary || {}).map(
            ([type, dict]) => (
              (type === 'Exact') ? (
                Object.keys(dict || {}).map(
                  k => (obj => obj?.[k] === dict[k])
                )
              ) : (
                (type === 'Regex') ? (
                  Object.keys(dict || {}).map(
                    k => (
                      (
                        regex = new RegExp(dict[k])
                      ) => (
                        obj => regex.test(obj?.[k] || '')
                      )
                    )()
                  )
                ) : [() => false]
              )
            )
          )
        ) => (
          (tests.length > 0) && (
            obj => tests.every(a => a.every(f => f(obj)))
          )
        )
      )(),
    
      pathPrefix = (path, prefix) => (
        path.startsWith(prefix) && (
          prefix.endsWith('/') || (
            (
              lastChar = path.charAt(prefix.length),
            ) => (
              lastChar === '' || lastChar === '/'
            )
          )()
        )
      ),
    
      makeHttpMatches = rule => (
        (
          matchPath = (
            (rule?.Path?.Type === 'Regex') && (
              ((match = null) => (
                match = new RegExp(rule?.Path?.Path),
                (path) => match.test(path)
              ))()
            ) || (rule?.Path?.Type === 'Exact') && (
              (path) => path === rule?.Path?.Path
            ) || (rule?.Path?.Type === 'Prefix') && (
              (path) => pathPrefix(path, rule?.Path?.Path)
            ) || rule?.Path?.Type && (
              () => false
            )
          ),
          matchHeaders = makeDictionaryMatches(rule?.Headers),
          matchMethod = (
            rule?.Methods && Object.fromEntries((rule.Methods).map(m => [m, true]))
          ),
          matchParams = makeDictionaryMatches(rule?.QueryParams),
        ) => (
          {
            config: rule,
            match: message => (
              (!matchMethod || matchMethod[message?.head?.method]) && (
                (!matchPath || matchPath(message?.head?.path?.split('?')[0])) && (
                  (!matchHeaders || matchHeaders(message?.head?.headers)) && (
                    (!matchParams || matchParams(getParameters(message?.head?.path)))
                  )
                )
              )
            )
          }
        )
      )(),
    
      makeMatchesHandler = matches => (
        (
          handlers = [],
        ) => (
          handlers = (matches?.Matches || []).map(
            m => makeHttpMatches(m)
          ),
          (handlers.length > 0) && (
            message => (
              handlers.find(
                m => m.match(message)
              )
            )
          )
        )
      )(),
    
      matchesHandlers = new algo.Cache(makeMatchesHandler),
    
      makeModifierHandler = cfg => (
        (
          set = cfg?.Set,
          add = cfg?.Add,
          remove = cfg?.Remove,
        ) => (
          (set || add || remove) && (
            msg => (
              set && set.forEach(
                e => (msg[e.Name] = e.Value)
              ),
              add && add.forEach(
                e => (
                  msg[e.Name] ? (
                    msg[e.Name] = msg[e.Name] + ',' + e.Value
                  ) : (
                    msg[e.Name] = e.Value
                  )
                )
              ),
              remove && remove.forEach(
                e => delete msg[e]
              )
            )
          )
        )
      )(),
    
      makeRequestModifierHandler = cfg => (
        (
          handlers = (cfg?.Filters || []).filter(
            e => e?.Type === 'RequestHeaderModifier'
          ).map(
            e => makeModifierHandler(e.RequestHeaderModifier)
          ).filter(
            e => e
          )
        ) => (
          handlers.length > 0 ? handlers : null
        )
      )(),
    
      requestFilterCache = new algo.Cache(
        match => makeRequestModifierHandler(match?.Filters)
      ),
    
      makeResponseModifierHandler = cfg => (
        (
          handlers = (cfg?.Filters || []).filter(
            e => e?.Type === 'ResponseHeaderModifier'
          ).map(
            e => makeModifierHandler(e.ResponseHeaderModifier)
          ).filter(
            e => e
          )
        ) => (
          handlers.length > 0 ? handlers : null
        )
      )(),
    
      responseFilterCache = new algo.Cache(
        match => makeResponseModifierHandler(match)
      ),
    
    ) => pipy({
      _pluginName: '',
      _pluginConfig: null,
      _messageHandler: null,
      _matchingConfig: null,
      _requestHandlers: null,
      _responseHandlers: null,
    })
    
    .import({
      __service: 'inbound-http-routing',
    })
    
    .pipeline()
    .onStart(
      () => void (
        _pluginName = __filename.slice(9, -3),
        _pluginConfig = __service?.Plugins?.[_pluginName],
        _messageHandler = matchesHandlers.get(_pluginConfig)
      )
    )
    .branch(
      () => _messageHandler, (
        $=>$
        .handleMessageStart(
          msg => (
            _matchingConfig = _messageHandler(msg)?.config
          )
        )
        .branch(
          () => _matchingConfig, (
            $=>$
            .handleMessageStart(
              msg => (
                (_requestHandlers = requestFilterCache.get(_matchingConfig)) && msg?.head?.headers && _requestHandlers.forEach(
                  e => e(msg.head.headers)
                )
              )
            )
            .chain()
            .handleMessageStart(
              msg => (
                (_responseHandlers = responseFilterCache.get(_matchingConfig)) && msg?.head?.headers && _responseHandlers.forEach(
                  e => e(msg.head.headers)
                )
              )
            )
          ), (
            $=>$.chain()
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
  name: traffic-coloring-chain
  namespace: pipy
spec:
  chains:
    - name: inbound-http
      plugins:
        - traffic-coloring
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
        - key: flomesh.io/monitored-by
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
  name: traffic-coloring-config
  namespace: pipy
spec:
  config:
    Matches:
    - Headers:
        Exact:
          x-canary: 'true'
      Filters:
      - Type: ResponseHeaderModifier
        ResponseHeaderModifier:
          Set:
          - Name: x-canary
            Value: 'true'    
  plugin: traffic-coloring
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
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080 -H "x-canary: true"
```
返回结果：  
```bash
HTTP/1.1 200 OK
x-canary: true
content-length: 20
connection: keep-alive

Hi, I am PIPY-OK v2!
```
可以看到，如果请求头带有 x-canary: true， 那么响应头也带有 x-canary: true。  

### 8.2 测试命令二：
```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080
```
返回结果：  
```bash
HTTP/1.1 200 OK
content-length: 20
connection: keep-alive

Hi, I am PIPY-OK v1!
```
可以看到，如果请求头没有 x-canary: true， 那么响应头也没有 x-canary: true。  

