## HTTP Fault Injection 插件
**通过fsm 给服务设置 故障注入(响应延时、返回指定HTTP状态码) 策略**

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
  name: http-fault-injection
spec:
  priority: 165
  pipyscript: |+
    ((
      seconds = val => (
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
      hexChar = { '0': 0, '1': 1, '2': 2, '3': 3, '4': 4, '5': 5, '6': 6, '7': 7, '8': 8, '9': 9, 'a': 10, 'b': 11, 'c': 12, 'd': 13, 'e': 14, 'f': 15 },    
      randomInt63 = () => (
        algo.uuid().substring(0, 18).replaceAll('-', '').split('').reduce((calc, char) => (calc * 16) + hexChar[char], 0) / 2
      ),    
      samplingRange = fraction => (fraction > 0 ? fraction : 0) * Math.pow(2, 63),    
      configCache = new algo.Cache(
        pluginConfig => pluginConfig && (
          {
            delaySamplingRange: pluginConfig?.delay?.percentage?.value > 0 ? samplingRange(pluginConfig.delay.percentage.value) : 0,
            fixedDelay: seconds(pluginConfig?.delay?.fixedDelay),
            abortSamplingRange: pluginConfig?.abort?.percentage?.value > 0 && pluginConfig?.abort?.httpStatus > 0 ? (
              samplingRange(pluginConfig.abort.percentage.value)
            ) : 0,
            httpStatus: pluginConfig?.abort?.httpStatus,
          }
        )
      ),      
    ) => pipy({
      _pluginName: '',
      _pluginConfig: null,
      _faultConfig: null,
      _randomVal: 0,
      _delayFlag: false,
      _abortFlag: false,
    })
    .import({
      __service: 'inbound-http-routing',
    })
    .pipeline()
    .onStart(
      () => void (
        _pluginName = __filename.slice(9, -3),
        _pluginConfig = __service?.Plugins?.[_pluginName],
        _faultConfig = configCache.get(_pluginConfig)
      )
    )
    .handleMessageStart(
      () => (
        _faultConfig && (
          _randomVal = randomInt63(),
          _faultConfig.delaySamplingRange && (_randomVal < _faultConfig.delaySamplingRange) && (     
            _delayFlag = true
          ),
          _faultConfig.abortSamplingRange && (_randomVal < _faultConfig.abortSamplingRange) && (
            _abortFlag = true
          )
        )
      )
    )
    .branch(
      () => _delayFlag, (
        $=>$.replay({ delay: () => _faultConfig.fixedDelay }).to(
          $=>$.branch(
            () => _delayFlag && (_delayFlag = false, true), (
              $=>$.replaceMessageStart(
                () => new StreamEnd('Replay')
              )
            ), (
              $=>$
            )
          )
        )
      ), (
        $=>$
      )
    )
    .branch(
      () => _abortFlag, (
        $=>$.replaceMessage(
          () => (
            new Message({ status: _faultConfig.httpStatus })
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
  name: http-fault-injection-chain
  namespace: pipy
spec:
  chains:
    - name: inbound-http
      plugins:
        - http-fault-injection
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
  name: http-fault-injection-config
  namespace: pipy
spec:
  config:
    delay:
      percentage:
        value: 0.5
      fixedDelay: 5s
    abort:
      percentage:
        value: 0.5
      httpStatus: 400
  plugin: http-fault-injection
  destinationRefs:
    - kind: Service
      name: pipy-ok
      namespace: pipy
EOF
```
以上配置内容，delay、abort 至少需要包含一项。  

## 8. 测试
测试命令：  
 ```bash
curl_client="$(kubectl get pod -n curl -l app=curl -o jsonpath='{.items[0].metadata.name}')"
date; kubectl exec ${curl_client} -n curl -c curl -- curl -ksi http://pipy-ok.pipy:8080 ; echo ""; date
```
多访问几次，大概 50% 的概率返回如下结果 （HTTP状态码为 400，并且延时了 5秒钟）  
返回结果：  
```bash
Mon Mar 27 17:11:20 HKT 2023
HTTP/1.1 400 Bad Request
content-length: 0
connection: keep-alive


Mon Mar 27 17:11:25 HKT 2023
```
