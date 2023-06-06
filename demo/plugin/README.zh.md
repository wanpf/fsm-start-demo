# FSM PlugIn 测试

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

## 3. PlugIn策略测试


### 3.1 部署业务 POD

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

### 3.2 场景测试

#### 3.2.1 启用Plugin策略

```bash
export fsm_namespace=fsm-system
kubectl patch meshconfig fsm-mesh-config -n "$fsm_namespace" -p '{"spec":{"featureFlags":{"enablePluginPolicy":true}}}' --type=merge
```

#### 3.2.2 声明插件

```bash
kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: token-verifier-1
spec:
  priority: 115
  pipyscript: |+
    (
    pipy({
        _pluginName: '',
        _pluginConfig: null,
        _accessToken: null,
        _valid: false,
    })
    .import({
        __service: 'inbound-http-routing',
    })
    .pipeline()
    .onStart(
        () => void (
            _pluginName = __filename.slice(9, -3),
            _pluginConfig = __service?.Plugins?.[_pluginName],
            _accessToken = _pluginConfig?.AccessToken
        )
    )
    .handleMessageStart(
        msg => _valid = (_accessToken && msg.head.headers['accesstoken'] === _accessToken)
    )
    .branch(
        () => _valid, (
            $ => $.chain()
        ), (
            $ => $.replaceMessage(
            new Message({ status: 403 }, 'token verify failed')
            )
        )
    )
    )
EOF

kubectl apply -f - <<EOF
kind: Plugin
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: token-injector-1
spec:
  priority: 115
  pipyscript: |+
    (
    pipy({
      _pluginName: '',
      _pluginConfig: null,
      _accessToken: null,
    })

    .import({
        __service: 'outbound-http-routing',
    })

    .pipeline()
    .onStart(
        () => void (
            _pluginName = __filename.slice(9, -3),
            _pluginConfig = __service?.Plugins?.[_pluginName],
            _accessToken = _pluginConfig?.AccessToken
        )
    )
    .handleMessageStart(
        msg => _accessToken && (msg.head.headers['accesstoken'] = _accessToken)
    )
    .chain()
    )
EOF
```
**注意:**   
**priority 的范围是(110, 120),  110 < priority < 120, 数字越大优先级越高。**   

#### 3.2.3 设置插件链

```bash
kubectl apply -n curl -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: token-injector-chain-1
spec:
  chains:
    - name: outbound-http
      plugins:
        - token-injector-1
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

kubectl apply -n pipy -f - <<EOF
kind: PluginChain
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: token-verifier-chain-1
spec:
  chains:
    - name: inbound-http
      plugins:
        - token-verifier-1
  selectors:
    podSelector:
      matchLabels:
        app: pipy-ok
      matchExpressions:
        - key: version
          operator: In
          values: ["v1"]
    namespaceSelector:
      matchExpressions:
        - key: openservicemesh.io/monitored-by
          operator: In
          values: ["fsm"]
EOF
```

#### 3.2.4 设置插件配置

```bash
kubectl apply -n curl -f - <<EOF
kind: PluginConfig
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: token-injector-config-1
  namespace: curl
spec:
  config:
    AccessToken: '123456'
  plugin: token-injector-1
  destinationRefs:
    - kind: Service
      name: pipy-ok-v1
      namespace: pipy
EOF

kubectl apply -n pipy -f - <<EOF
kind: PluginConfig
apiVersion: plugin.flomesh.io/v1alpha1
metadata:
  name: token-verifier-config-1
  namespace: pipy
spec:
  config:
    AccessToken: '123456'
  plugin: token-verifier-1
  destinationRefs:
    - kind: Service
      name: pipy-ok-v1
      namespace: pipy
EOF
```

#### 3.3.5 查看 curl.curl 的 config.json

```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
fsm proxy get config_dump -n curl "$curl_client" | jq
```

## 4. 测试 
### 4.1 访问 http://pipy-ok.pipy:8080  
```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"

kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080
```
测试结果：   
1、访问 V1 失败  

```bash
HTTP/1.1 403 Forbidden  
content-length: 19  
connection: keep-alive  

token verify failed  
```

2、访问 V2 成功  

```bash
HTTP/1.1 200 OK  
fsm-stats: pipy,Deployment,pipy-ok-v2,pipy-ok-v2-cf87cc878-7jpnf  
content-length: 20  
connection: keep-alive  

Hi, I am PIPY-OK v2! 
```

### 4.2 访问 http://pipy-ok-v1.pipy:8080  
```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"

kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok-v1.pipy:8080
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok-v1.pipy:8080
```
测试结果：  
访问 V1 成功   

```bash
HTTP/1.1 200 OK  
fsm-stats: pipy,Deployment,pipy-ok-v1,pipy-ok-v1-7645cf6d5d-xk4mv  
content-length: 20  
connection: keep-alive  

Hi, I am PIPY-OK v1!  
```

### 4.3 访问 http://pipy-ok-v2.pipy:8080  
```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"

kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok-v2.pipy:8080
kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok-v2.pipy:8080
```
测试结果：  
访问 V2 成功  

```
HTTP/1.1 200 OK  
fsm-stats: pipy,Deployment,pipy-ok-v2,pipy-ok-v2-cf87cc878-7jpnf  
content-length: 20  
connection: keep-alive  

Hi, I am PIPY-OK v2!  
```
## 5. 文档
*[Pipy sidecar 模块设计与插件开发说明](https://github.com/wanpf/docs/blob/main/plugins/Pipy%20sidecar%20%E6%A8%A1%E5%9D%97%E8%AE%BE%E8%AE%A1%E4%B8%8E%E6%8F%92%E4%BB%B6%E5%BC%80%E5%8F%91%E8%AF%B4%E6%98%8E.pdf)*
