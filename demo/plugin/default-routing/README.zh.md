## 加载 HTTP默认路由 插件
**在某些场景下，HTTP请求的 host 设置不正确，导致pipy sidecar 匹配不到服务，为了兼容这种特殊场景需要加载 HTTP默认路由 插件。**

#### 1. 启用Plugin策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enablePluginPolicy":true}}}' --type=merge
```

#### 2 声明插件

```bash

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: inbound-http-default-routing
spec:
  priority: 165
  pipyscript: |+
    ((
      config = pipy.solve('config.js'),

      allMethods = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],

      clusterCache = new algo.Cache(
        (clusterName => (
          (cluster = config?.Inbound?.ClustersConfigs?.[clusterName]) => (
            cluster ? Object.assign({ name: clusterName, Endpoints: cluster }) : null
          )
        )())
      ),

      makeServiceHandler = (portConfig, serviceName) => (
        (
          rules = portConfig?.HttpServiceRouteRules?.[serviceName]?.RouteRules || [],
          tree = {},
        ) => (
          rules.forEach(
            config => (
              (
                matchPath = (
                  (config.Type === 'Regex') && (
                    ((match = null) => (
                      match = new RegExp(config.Path),
                      (path) => match.test(path)
                    ))()
                  ) || (config.Type === 'Exact') && (
                    (path) => path === config.Path
                  ) || (config.Type === 'Prefix') && (
                    (path) => path.startsWith(config.Path)
                  )
                ),
                headerRules = config.Headers ? Object.entries(config.Headers).map(([k, v]) => [k, new RegExp(v)]) : null,
                balancer = new algo.RoundRobinLoadBalancer(config.TargetClusters || {}),
                service = Object.assign({ name: serviceName }, portConfig?.HttpServiceRouteRules?.[serviceName]),
                rule = headerRules ? (
                  (path, headers) => matchPath(path) && headerRules.every(([k, v]) => v.test(headers[k] || '')) && (
                    __route = config,
                    __service = service,
                    __cluster = clusterCache.get(balancer.next()?.id),
                    true
                  )
                ) : (
                  (path) => matchPath(path) && (
                    __route = config,
                    __service = service,
                    __cluster = clusterCache.get(balancer.next()?.id),
                    true
                  )
                ),
                allowedIdentities = config.AllowedServices ? new Set(config.AllowedServices) : [''],
                allowedMethods = config.Methods || allMethods,
              ) => (
                allowedIdentities.forEach(
                  identity => (
                    (
                      methods = tree[identity] || (tree[identity] = {}),
                    ) => (
                      allowedMethods.forEach(
                        method => (methods[method] || (methods[method] = [])).push(rule)
                      )
                    )
                  )()
                )
              )
            )()
          ),

          (method, path, headers) => void (
            (headers.serviceidentity && tree[headers.serviceidentity]?.[method] || tree['']?.[method])?.find?.(rule => rule(path, headers))
            // tree[headers.serviceidentity || '']?.[method]?.find?.(rule => rule(path, headers))
          )
        )
      )(),

      makePortHandler = portConfig => (
        (
          ingressRanges = Object.keys(portConfig?.SourceIPRanges || {}).map(k => new Netmask(k)),

          serviceHandlers = new algo.Cache(
            serviceName => makeServiceHandler(portConfig, serviceName)
          ),

          makeHostHandler = (portConfig, host) => (
            serviceHandlers.get(portConfig?.HttpHostPort2Service?.[host])
          ),

          hostHandlers = new algo.Cache(
            host => makeHostHandler(portConfig, host)
          ),
        ) => (
          ingressRanges.length > 0 ? (
            msg => void (
              (
                ip = __inbound.remoteAddress || '127.0.0.1',
                ingressRange = ingressRanges.find(r => r.contains(ip)),
                head = msg.head,
                headers = head.headers,
                handler = hostHandlers.get(ingressRange ? '*' : headers.host),
              ) => (
                __isIngress = Boolean(ingressRange),
                handler(head.method, head.path, headers)
              )
            )()
          ) : (
            msg => void (
              (
                head = msg.head,
                headers = head.headers,
                handler = hostHandlers.get(headers.host),
              ) => (
                handler(head.method, head.path, headers)
              )
            )()
          )
        )
      )(),

      portHandlers = new algo.Cache(makePortHandler),
    ) => pipy()

    .import({
      __port: 'inbound',
      __isIngress: 'inbound',
      __route: 'inbound-http-routing',
      __service: 'inbound-http-routing',
      __cluster: 'inbound-http-routing',
    })

    .pipeline()
    .branch(
      () => __port && !__service, (
        $=>$.handleMessageStart(
          msg => (
            (
              defaultHost = Object.values(__port.HttpHostPort2Service || {})?.[0],
              originalHost = msg?.head?.headers?.host,
            ) => (
              defaultHost && originalHost && (
                msg.head.headers.host = defaultHost,
                portHandlers.get(__port)(msg),
                msg.head.headers.host = originalHost
              )
            )
          )()
        )
      ),
      (
        $=>$
      )
    )
    .chain()

    )()
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: outbound-http-default-routing
spec:
  priority: 155
  pipyscript: |+
    ((
      config = pipy.solve('config.js'),
      {
        shuffle,
        failover,
      } = pipy.solve('utils.js'),

      allMethods = ['GET', 'HEAD', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],

      clusterCache = new algo.Cache(
        (clusterName => (
          (cluster = config?.Outbound?.ClustersConfigs?.[clusterName]) => (
            cluster ? Object.assign({ name: clusterName }, cluster) : null
          )
        )())
      ),

      makeServiceHandler = (portConfig, serviceName) => (
        (
          rules = portConfig?.HttpServiceRouteRules?.[serviceName]?.RouteRules || [],
          tree = {},
        ) => (
          rules.forEach(
            config => (
              (
                matchPath = (
                  (config.Type === 'Regex') && (
                    ((match = null) => (
                      match = new RegExp(config.Path),
                      (path) => match.test(path)
                    ))()
                  ) || (config.Type === 'Exact') && (
                    (path) => path === config.Path
                  ) || (config.Type === 'Prefix') && (
                    (path) => path.startsWith(config.Path)
                  )
                ),
                headerRules = config.Headers ? Object.entries(config.Headers).map(([k, v]) => [k, new RegExp(v)]) : null,
                balancer = new algo.RoundRobinLoadBalancer(shuffle(config.TargetClusters || {})),
                failoverBalancer = failover(config.TargetClusters),
                service = Object.assign({ name: serviceName }, portConfig?.HttpServiceRouteRules?.[serviceName]),
                rule = headerRules ? (
                  (path, headers) => matchPath(path) && headerRules.every(([k, v]) => v.test(headers[k] || '')) && (
                    __route = config,
                    __service = service,
                    __cluster = clusterCache.get(balancer.next({})?.id),
                    true
                  )
                ) : (
                  (path) => matchPath(path) && (
                    __route = config,
                    __service = service,
                    __cluster = clusterCache.get(balancer.next({})?.id),
                    true
                  )
                ),
                allowedMethods = config.Methods || allMethods,
              ) => (
                allowedMethods.forEach(
                  method => (tree[method] || (tree[method] = [])).push(rule)
                )
              )
            )()
          ),

          (method, path, headers) => void (
            tree[method]?.find?.(rule => rule(path, headers)),
            __service && (
              headers['serviceidentity'] = __service.ServiceIdentity
            )
          )
        )
      )(),

      makePortHandler = (portConfig) => (
        (
          serviceHandlers = new algo.Cache(
            (serviceName) => makeServiceHandler(portConfig, serviceName)
          ),

          hostHandlers = new algo.Cache(
            (host) => serviceHandlers.get(portConfig?.HttpHostPort2Service?.[host])
          ),
        ) => (
          (msg) => (
            (
              head = msg.head,
              headers = head.headers,
            ) => (
              hostHandlers.get(headers.host)(head.method, head.path, headers)
            )
          )()
        )
      )(),

      portHandlers = new algo.Cache(makePortHandler),
    ) => pipy()

    .import({
      __port: 'outbound',
      __route: 'outbound-http-routing',
      __service: 'outbound-http-routing',
      __cluster: 'outbound-http-routing',
    })

    .pipeline()
    .branch(
      () => __port && !__service, (
        $=>$.handleMessageStart(
          msg => (
            (
              defaultHost = Object.values(__port.HttpHostPort2Service || {})?.[0],
              originalHost = msg?.head?.headers?.host,
            ) => (
              defaultHost && originalHost && (
                msg.head.headers.host = defaultHost,
                portHandlers.get(__port)(msg),
                msg.head.headers.host = originalHost
              )
            )
          )()
        )
      ),
      (
        $=>$
      )
    )
    .chain()

    )()
EOF

```


#### 3.  设置插件链

```bash

kubectl apply -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: outbound-http-default-routing-chain
spec:
  chains:
    - name: outbound-http
      plugins:
        - outbound-http-default-routing
  selectors:
    namespaceSelector:
      matchExpressions:
        - key: flomesh.io/monitored-by
          operator: In
          values: ["fsm"]
EOF

kubectl apply -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: inbound-http-default-routing-chain
spec:
  chains:
    - name: inbound-http
      plugins:
        - inbound-http-default-routing
  selectors:
    namespaceSelector:
      matchExpressions:
        - key: flomesh.io/monitored-by
          operator: In
          values: ["fsm"]
EOF

```
