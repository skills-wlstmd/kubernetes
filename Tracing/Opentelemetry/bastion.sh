# ============== ENV ==============
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
EKS_NODE_GROUP_NAME="<NODE_GROUP_NAME>"
NODE_GROUP_ROLE_NAME=$(aws eks describe-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name $EKS_NODE_GROUP_NAME --query "nodegroup.nodeRole" --output text | cut -d'/' -f2-)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# ============== Ready ==============
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.0/cert-manager.crds.yaml
kubectl create ns cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager  \
  --namespace cert-manager \
  --version 1.16.0

kubectl get pods -n cert-manager

kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml

kubectl get pods -n opentelemetry-operator-system

# ============== Grafana Tempo 설치 ==============
cat << EOF > tempo-s3-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": [
                "arn:aws:s3:::skills-tracing-bucket",
                "arn:aws:s3:::skills-tracing-bucket/*"
            ]
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name TempoS3AccessPolicy \
    --policy-document file://tempo-s3-policy.json

aws iam attach-role-policy \
    --role-name $NODE_GROUP_ROLE_NAME \
    --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/TempoS3AccessPolicy

aws iam list-attached-role-policies --role-name $NODE_GROUP_ROLE_NAME --query "AttachedPolicies[].PolicyArn" --output text

cat << EOF > tempo-helm-values.yaml
global_overrides:
  metrics_generator_processors:
  - service-graphs
metricsGenerator:
  config:
    storage:
      remote_write:
      - send_exemplars: true
        url: http://mimir-nginx.mimir.svc:80/api/v1/push
  enabled: true
storage:
  trace:
    backend: s3
    s3:
      bucket: skills-tracing-bucket
      endpoint: s3.ap-northeast-2.amazonaws.com
      prefix: tempo
traces:
  otlp:
    grpc:
      enabled: true
    http:
      enabled: true
EOF

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm upgrade --install tempo grafana/tempo-distributed -n tempo --create-namespace --values tempo-helm-values.yaml
# helm uninstall tempo -n tempo

# ============== OTel Collector 설정 ==============
kubectl create ns otel
cat << EOF > otel-collector-config.yaml
apiVersion: opentelemetry.io/v1alpha1
kind: OpenTelemetryCollector
metadata:
  name: demo-collector
  namespace: otel
spec:
  mode: deployment
  config: |
    exporters:
      prometheusremotewrite:
        endpoint: "http://mimir-nginx.mimir.svc:80/api/v1/push"
      otlp:
        endpoint: tempo-distributor.tempo.svc.cluster.local:4317
        tls:
          insecure: true
    processors:
      batch: {}
      memory_limiter:
        check_interval: 5s
        limit_percentage: 80
        spike_limit_percentage: 25
    receivers:
      otlp:
        protocols:
          http:
          grpc:
    service:
      pipelines:
        traces:
          exporters:
          - otlp
          processors:
          - memory_limiter
          - batch
          receivers:
          - otlp
        metrics:
          exporters:
          - prometheusremotewrite
          processors:
          - memory_limiter
          - batch
          receivers:
          - otlp
EOF
kubectl apply -f otel-collector-config.yaml

# ============== OTel Instrumentation 설정 ==============
cat << EOF > otel-instrumentation.yaml
apiVersion: opentelemetry.io/v1alpha1
kind: Instrumentation
metadata:
  name: demo-instrumentation
  namespace: otel
spec:
  exporter:
    endpoint: http://demo-collector.otel.svc.cluster.local:4317
  propagators:
  - tracecontext
  - baggage
  sampler:
    argument: "1"
    type: parentbased_traceidratio
  java:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:1.32.1
    resources:
      limits:
        cpu: 500m
        memory: 64Mi
      requests:
        cpu: 50m
        memory: 64Mi
  nodejs:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-nodejs:0.46.0
  python:
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-python:0.43b0
EOF
kubectl apply -f otel-instrumentation.yaml

# ============== 애플리케이션에 Instrumentation 적용 ==============
cat << EOF > deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
      annotations:
        instrumentation.opentelemetry.io/inject-java: otel/demo-instrumentation
    spec:
      containers:
      - name: demo-app
        image: 362708816803.dkr.ecr.ap-northeast-2.amazonaws.com/demo:latest
        ports:
        - containerPort: 8080
EOF

kubectl apply -f deployment.yaml

cat << EOF > service.yaml
apiVersion: v1
kind: Service
metadata:
  name: demo-service
  namespace: default
spec:
  selector:
    app: demo-app
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
EOF
kubectl apply -f service.yaml

# ============== Grafana ==============
kubectl create namespace grafana

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana \
    --namespace grafana \
    --set persistence.enabled=false \
    --set adminPassword='admin1234' \
    --set service.type=ClusterIP

http://tempo-query-frontend-discovery.tempo.svc.cluster.local:3100