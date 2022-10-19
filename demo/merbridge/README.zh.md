

# OSM Edge eBPF 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.2.0
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
    --set=osm.image.registry=flomesh \
    --set=osm.image.tag=1.2.0 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.enablePermissiveTrafficPolicy=true \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. eBPF测试

### 3.1 技术概念

#### [Merbridge 如何改变连接关系](https://merbridge.io/zh/docs/overview/#merbridge-%E5%A6%82%E4%BD%95%E6%94%B9%E5%8F%98%E8%BF%9E%E6%8E%A5%E5%85%B3%E7%B3%BB)

### 3.2 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace ebpf-test
osm namespace add ebpf-test
kubectl apply -n ebpf-test -f https://raw.githubusercontent.com/flomesh-io/osm-edge-v1.2-demo/main/demo/merbridge/sleep.yaml
kubectl apply -n ebpf-test -f https://raw.githubusercontent.com/flomesh-io/osm-edge-v1.2-demo/main/demo/merbridge/helloworld.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n ebpf-test -l app=sleep --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf-test -l app=helloworld --timeout=180s
```

### 3.3 场景测试一：eBPF 改变连接关系

#### 3.3.1 测试指令

```bash
sleep_client="$(kubectl get pod -n ebpf-test -l app=sleep -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${sleep_client} -n ebpf-test -c sleep -- curl -s -v helloworld:5000/hello
```

#### 3.3.2 测试结果

正确返回结果类似于:

```bash
*   Trying 10.96.203.65:5000...
* Connected to helloworld (10.96.203.65) port 5000 (#0)
> GET /hello HTTP/1.1
> Host: helloworld:5000
> User-Agent: curl/7.85.0-DEV
> Accept: */*
> 
* Mark bundle as not supporting multiuse
* HTTP 1.0, assume close after body
< HTTP/1.0 200 OK
< content-type: text/html; charset=utf-8
< server: pipy
< date: Thu, 06 Oct 2022 14:51:43 GMT
< x-pipy-upstream-service-time: 94
< content-length: 60
* HTTP/1.0 connection set to keep alive
< connection: keep-alive
< 
{ [60 bytes data]
* Hello version: v1, instance: helloworld-v1-54658c85f7-9j9lx
Connection #0 to host helloworld left intact
```

#### 3.3.3 安装 MerBridge(istio)

##### 3.3.3.1 ServiceAccount

```bash
export osm_namespace=osm-system

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: osm-merbridge
  namespace: ${osm_namespace}
  labels:
    app: osm-merbridge
EOF
```

##### 3.3.3.2 ClusterRole

```bash
export osm_namespace=osm-system

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: osm-merbridge
  labels:
    app: osm-merbridge
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - list
  - get
  - watch
EOF
```

##### 3.3.3.3 ClusterRoleBinding

```bash
export osm_namespace=osm-system

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: osm-merbridge
  labels:
    app: osm-merbridge
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: osm-merbridge
subjects:
- kind: ServiceAccount
  name: osm-merbridge
  namespace: ${osm_namespace}
EOF
```

##### 3.3.3.4 DaemonSet

```bash
export osm_namespace=osm-system
export osm_merbridge_mode=istio

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: osm-merbridge
  namespace: ${osm_namespace}
  labels:
    app: osm-merbridge
spec:
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: osm-merbridge
  template:
    metadata:
      labels:
        app: osm-merbridge
    spec:
      hostNetwork: true
      containers:
      - image: "flomesh-io/osm-edge-merbridge:latest"
        imagePullPolicy: Always
        name: merbridge
        args:
        - /app/mbctl
        - -m
        - ${osm_merbridge_mode}
        - --use-reconnect=true
        - --cni-mode=false
        - --debug=true
        lifecycle:
          preStop:
            exec:
              command:
              - make
              - -k
              - clean
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            cpu: 300m
            memory: 200Mi
        securityContext:
          privileged: true
        volumeMounts:
          - mountPath: /sys/fs/cgroup
            name: sys-fs-cgroup
          - mountPath: /host/opt/cni/bin
            name: cni-bin-dir
          - mountPath: /host/etc/cni/net.d
            name: cni-config-dir
          - mountPath: /host/proc
            name: host-proc
          - mountPath: /host/var/run
            name: host-var-run
            mountPropagation: Bidirectional
      dnsPolicy: ClusterFirst
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-node-critical
      restartPolicy: Always
      serviceAccount: osm-merbridge
      serviceAccountName: osm-merbridge
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - operator: Exists
      volumes:
      - hostPath:
          path: /sys/fs/cgroup
        name: sys-fs-cgroup
      - hostPath:
          path: /proc
        name: host-proc
      - hostPath:
          path: /opt/cni/bin
        name: cni-bin-dir
      - hostPath:
          path: /etc/cni/net.d
        name: cni-config-dir
      - hostPath:
          path: /var/run
        name: host-var-run
EOF

#等待启动完成
```

#### 3.3.4 测试指令

```bash
sleep_client="$(kubectl get pod -n ebpf-test -l app=sleep -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${sleep_client} -n ebpf-test -c sleep -- curl -s -v helloworld:5000/hello
```

#### 3.3.5 测试结果

正确返回结果类似于:**(因为以 istio 模式运行,无法识别被 osm 纳管的 pod,故不通)**

```bash
*   Trying 10.96.203.65:5000...
* Connected to helloworld (127.128.0.16) port 5000 (#0)
> GET /hello HTTP/1.1
> Host: helloworld:5000
> User-Agent: curl/7.85.0-DEV
> Accept: */*
> 
* Mark bundle as not supporting multiuse
< HTTP/1.1 502 Bad Gateway
< server: pipy
< x-pipy-upstream-service-time: 1
< content-length: 0
< connection: keep-alive
< 
* Connection #0 to host helloworld left intact
```

#### 3.3.6 安装 MerBridge(osm)

##### 3.3.6.1 DaemonSet

```bash
export osm_namespace=osm-system
export osm_merbridge_mode=osm

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: osm-merbridge
  namespace: ${osm_namespace}
  labels:
    app: osm-merbridge
spec:
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      app: osm-merbridge
  template:
    metadata:
      labels:
        app: osm-merbridge
    spec:
      hostNetwork: true
      containers:
      - image: "flomesh-io/osm-edge-merbridge:latest"
        imagePullPolicy: Always
        name: merbridge
        args:
        - /app/mbctl
        - -m
        - ${osm_merbridge_mode}
        - --use-reconnect=true
        - --cni-mode=false
        - --debug=true
        lifecycle:
          preStop:
            exec:
              command:
              - make
              - -k
              - clean
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            cpu: 300m
            memory: 200Mi
        securityContext:
          privileged: true
        volumeMounts:
          - mountPath: /sys/fs/cgroup
            name: sys-fs-cgroup
          - mountPath: /host/opt/cni/bin
            name: cni-bin-dir
          - mountPath: /host/etc/cni/net.d
            name: cni-config-dir
          - mountPath: /host/proc
            name: host-proc
          - mountPath: /host/var/run
            name: host-var-run
            mountPropagation: Bidirectional
      dnsPolicy: ClusterFirst
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-node-critical
      restartPolicy: Always
      serviceAccount: osm-merbridge
      serviceAccountName: osm-merbridge
      tolerations:
      - key: CriticalAddonsOnly
        operator: Exists
      - operator: Exists
      volumes:
      - hostPath:
          path: /sys/fs/cgroup
        name: sys-fs-cgroup
      - hostPath:
          path: /proc
        name: host-proc
      - hostPath:
          path: /opt/cni/bin
        name: cni-bin-dir
      - hostPath:
          path: /etc/cni/net.d
        name: cni-config-dir
      - hostPath:
          path: /var/run
        name: host-var-run
EOF

#等待启动完成
```

#### 3.3.7 查看日志

```bash
export osm_namespace=osm-system
kubectl logs -n "${osm_namespace}" "$(kubectl get pod -n osm-system -l app=osm-merbridge -o jsonpath='{.items[0].metadata.name}')"
#如无返回,请确认查询的 osm-merbridge 是否运行在 osm-worker 节点上
```

正确日志返回结果类似于:

```bash
2022-10-06T14:57:42.376384Z     warn    OS CA Cert could not be found for agent
[ -f bpf/mb_connect.c ] && make -C bpf load || make -C bpf load-from-obj
make[1]: Entering directory '/app/bpf'
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_connect.c -o mb_connect.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_get_sockopts.c -o mb_get_sockopts.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_redir.c -o mb_redir.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_sockops.c -o mb_sockops.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_bind.c -o mb_bind.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_sendmsg.c -o mb_sendmsg.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_recvmsg.c -o mb_recvmsg.o
clang -O2 -g  -Wall -target bpf -I/usr/include/x86_64-linux-gnu  -DMESH=4 -DDEBUG -DUSE_RECONNECT -c mb_tc.c -o mb_tc.o
sudo mount -t bpf bpf /sys/fs/bpf
sudo mkdir -p /sys/fs/bpf/tc/globals
[ -f /sys/fs/bpf/cookie_original_dst ] || sudo bpftool map create /sys/fs/bpf/cookie_original_dst type lru_hash key 8 value 12 entries 65535 name cookie_original_dst
[ -f /sys/fs/bpf/tc/globals/local_pod_ips ] || sudo bpftool map create /sys/fs/bpf/tc/globals/local_pod_ips type hash key 4 value 244 entries 1024 name local_pod_ips
[ -f /sys/fs/bpf/process_ip ] || sudo bpftool map create /sys/fs/bpf/process_ip type lru_hash key 4 value 4 entries 1024 name process_ip
[ -f /sys/fs/bpf/mark_pod_ips_map ] || sudo bpftool map create /sys/fs/bpf/mark_pod_ips_map type hash key 4 value 4 entries 65535 name mark_pod_ips_map
sudo bpftool -m prog load mb_connect.o /sys/fs/bpf/connect \
        map name cookie_original_dst pinned /sys/fs/bpf/cookie_original_dst \
        map name local_pod_ips pinned /sys/fs/bpf/tc/globals/local_pod_ips \
        map name mark_pod_ips_map pinned /sys/fs/bpf/mark_pod_ips_map \
        map name process_ip pinned /sys/fs/bpf/process_ip
libbpf: maps section in mb_connect.o: "local_pod_ips" has unrecognized, non-zero options
libbpf: maps section in mb_connect.o: "pair_original_dst" has unrecognized, non-zero options
[ -f /sys/fs/bpf/tc/globals/pair_original_dst ] || sudo bpftool map create /sys/fs/bpf/tc/globals/pair_original_dst type lru_hash key 12 value 12 entries 65535 name pair_original_dst
[ -f /sys/fs/bpf/sock_pair_map ] || sudo bpftool map create /sys/fs/bpf/sock_pair_map type sockhash key 12 value 4 entries 65535 name sock_pair_map
sudo bpftool -m prog load mb_sockops.o /sys/fs/bpf/sockops \
        map name cookie_original_dst pinned /sys/fs/bpf/cookie_original_dst \
        map name process_ip pinned /sys/fs/bpf/process_ip \
        map name pair_original_dst pinned /sys/fs/bpf/tc/globals/pair_original_dst \
        map name sock_pair_map pinned /sys/fs/bpf/sock_pair_map
libbpf: maps section in mb_sockops.o: "local_pod_ips" has unrecognized, non-zero options
libbpf: maps section in mb_sockops.o: "pair_original_dst" has unrecognized, non-zero options
sudo bpftool -m prog load mb_get_sockopts.o /sys/fs/bpf/get_sockopts \
        map name pair_original_dst pinned /sys/fs/bpf/tc/globals/pair_original_dst
libbpf: maps section in mb_get_sockopts.o: "local_pod_ips" has unrecognized, non-zero options
libbpf: maps section in mb_get_sockopts.o: "pair_original_dst" has unrecognized, non-zero options
sudo bpftool -m prog load mb_redir.o /sys/fs/bpf/redir \
        map name sock_pair_map pinned /sys/fs/bpf/sock_pair_map
libbpf: maps section in mb_redir.o: "local_pod_ips" has unrecognized, non-zero options
libbpf: maps section in mb_redir.o: "pair_original_dst" has unrecognized, non-zero options
sudo bpftool -m prog load mb_bind.o /sys/fs/bpf/bind
sudo bpftool -m prog load mb_sendmsg.o /sys/fs/bpf/sendmsg \
        map name cookie_original_dst pinned /sys/fs/bpf/cookie_original_dst
libbpf: maps section in mb_sendmsg.o: "local_pod_ips" has unrecognized, non-zero options
libbpf: maps section in mb_sendmsg.o: "pair_original_dst" has unrecognized, non-zero options
sudo bpftool -m prog load mb_recvmsg.o /sys/fs/bpf/recvmsg \
        map name cookie_original_dst pinned /sys/fs/bpf/cookie_original_dst
libbpf: maps section in mb_recvmsg.o: "local_pod_ips" has unrecognized, non-zero options
libbpf: maps section in mb_recvmsg.o: "pair_original_dst" has unrecognized, non-zero options
make[1]: Leaving directory '/app/bpf'
time="2022-10-06T14:57:43Z" level=info msg="Pod Watcher Ready" func="localip.RunLocalIPController()" file="localip.go:53"
make -C bpf attach
make[1]: Entering directory '/app/bpf'
time="2022-10-06T14:57:44Z" level=debug msg="got pod updated ebpf-test/helloworld-v2-58d9f4669-k8c8v" func="localip.addFunc()" file="localip.go:124"
time="2022-10-06T14:57:44Z" level=info msg="update local_pod_ips with ip: 10.244.1.4" func="localip.addFunc()" file="localip.go:127"
sudo bpftool cgroup attach /sys/fs/cgroup connect4 pinned /sys/fs/bpf/connect
sudo bpftool cgroup attach /sys/fs/cgroup sock_ops pinned /sys/fs/bpf/sockops
sudo bpftool cgroup attach /sys/fs/cgroup getsockopt pinned /sys/fs/bpf/get_sockopts
sudo bpftool prog attach pinned /sys/fs/bpf/redir msg_verdict pinned /sys/fs/bpf/sock_pair_map
sudo bpftool cgroup attach /sys/fs/cgroup bind4 pinned /sys/fs/bpf/bind
sudo bpftool cgroup attach /sys/fs/cgroup sendmsg4 pinned /sys/fs/bpf/sendmsg
sudo bpftool cgroup attach /sys/fs/cgroup recvmsg4 pinned /sys/fs/bpf/recvmsg
make[1]: Leaving directory '/app/bpf'
```

其中日志表示将被 osm 纳管的 pod 的 IP 进行 eBPF 的处理:

```bash
time="2022-10-06T14:57:44Z" level=debug msg="got pod updated ebpf-test/helloworld-v2-58d9f4669-k8c8v" func="localip.addFunc()" file="localip.go:124"
time="2022-10-06T14:57:44Z" level=info msg="update local_pod_ips with ip: 10.244.1.4" func="localip.addFunc()" file="localip.go:127"
```

#### 3.3.8 测试指令

```bash
sleep_client="$(kubectl get pod -n ebpf-test -l app=sleep -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${sleep_client} -n ebpf-test -c sleep -- curl -s -v helloworld:5000/hello
```

#### 3.3.9 测试结果

正确返回结果类似于:

```bash
*   Trying 10.96.203.65:5000...
* Connected to helloworld (127.128.0.1) port 5000 (#0)
> GET /hello HTTP/1.1
> Host: helloworld:5000
> User-Agent: curl/7.85.0-DEV
> Accept: */*
> 
Hello version: v2, instance: helloworld-v2-58d9f4669-k8c8v
* Mark bundle as not supporting multiuse
* HTTP 1.0, assume close after body
< HTTP/1.0 200 OK
< content-type: text/html; charset=utf-8
< server: pipy
< date: Thu, 06 Oct 2022 14:58:16 GMT
< x-pipy-upstream-service-time: 98
< content-length: 59
* HTTP/1.0 connection set to keep alive
< connection: keep-alive
< 
{ [59 bytes data]
* Connection #0 to host helloworld left intact
```

#### 
