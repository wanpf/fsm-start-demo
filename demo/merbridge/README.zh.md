

# OSM Edge访问控制策略测试

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
      - image: "localhost:5000/flomesh/osm-edge-merbridge:latest"
        imagePullPolicy: Always
        name: merbridge
        args:
        - /app/mbctl
        - -m
        - istio
        - --use-reconnect=true
        - --cni-mode=false
        - --debug
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

## 3. 访问控制策略测试

### 3.1 技术概念

在 OSM Edge 中从未被 OSM Edge 纳管的区域访问被 OSM Edge 纳管的区域，有两种方法：

- Ingress，目前支持的 Ingress Controller：
  - FSM Pipy Ingress
  - Nginx Ingress
- Access Control，支持两种访问源类型：
  - Service
  - IPRange

### 3.2 部署业务 POD

```bash
#模拟业务服务
kubectl create namespace ebpf-test
osm namespace add ebpf-test
kubectl apply -n ebpf-test -f demo/merbridge/sleep.yaml
kubectl apply -n ebpf-test -f demo/merbridge/helloworld.yaml

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


kubectl rollout restart DaemonSet -n osm-system osm-merbridge

kubectl logs -n osm-system osm-merbridge-
```

