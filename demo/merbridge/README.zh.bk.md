

# OSM Edge eBPF 测试

## 1. 下载并安装 osm-edge 命令行工具

```bash
system=$(uname -s | tr [:upper:] [:lower:])
arch=$(dpkg --print-architecture)
release=v1.2.0
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
    --set=osm.image.tag=1.2.1-alpha.2 \
    --set=osm.image.pullPolicy=Always \
    --set=osm.enablePermissiveTrafficPolicy=true \
    --set=osm.sidecarLogLevel=error \
    --set=osm.controllerLogLevel=warn \
    --timeout=900s
```

## 3. 安装 MerBridge

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
      - image: "cybwan/osm-edge-merbridge:latest"
        imagePullPolicy: Always
        name: merbridge
        args:
        - /app/mbctl
        - -m
        - osm
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
```

## 4. eBPF测试

### 4.1 技术概念

## [Merbridge 如何改变连接关系](https://merbridge.io/zh/docs/overview/#merbridge-%E5%A6%82%E4%BD%95%E6%94%B9%E5%8F%98%E8%BF%9E%E6%8E%A5%E5%85%B3%E7%B3%BB)

### 4.1 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace ebpf-test
osm namespace add ebpf-test
kubectl apply -n ebpf-test -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/merbridge/sleep.yaml
kubectl apply -n ebpf-test -f https://raw.githubusercontent.com/cybwan/osm-edge-v1.2-demo/merbridge/helloworld.yaml

#等待依赖的 POD 正常启动
kubectl wait --for=condition=ready pod -n ebpf-test -l app=sleep --timeout=180s
kubectl wait --for=condition=ready pod -n ebpf-test -l app=helloworld --timeout=180s
```

### 3.3 场景测试一：基于服务的访问控制

#### 3.3.1 启用访问控制策略

```bash
export osm_namespace=osm-system
kubectl patch meshconfig osm-mesh-config -n "$osm_namespace" -p '{"spec":{"featureFlags":{"enableAccessControlPolicy":true}}}'  --type=merge
```

#### 3.3.2 设置基于服务的访问控制策略

```bash
sleep_client="$(kubectl get pod -n ebpf-test -l app=sleep -o jsonpath='{.items[0].metadata.name}')"
kubectl exec ${sleep_client} -n ebpf-test -c sleep -- curl -s -v helloworld:5000/hello

kubectl rollout restart deployment -n ebpf-test helloworld-v1
kubectl rollout restart deployment -n ebpf-test helloworld-v2

kubectl rollout restart DaemonSet -n osm-system osm-merbridge

export osm_namespace=osm-system
kubectl logs -n "${osm_namespace}" "$(kubectl get pod -n osm-system -l app=osm-merbridge -o jsonpath='{.items[0].metadata.name}')"

kubectl logs -f -n osm-system osm-merbridge-qvbqm

```

