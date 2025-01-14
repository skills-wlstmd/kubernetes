# 기존 세팅은 Prometheus와 동일함
kubectl create namespace grafana

helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install grafana grafana/grafana \
    --namespace grafana \
    --set persistence.storageClassName="gp2" \
    --set persistence.enabled=true \
    --set adminPassword='admin1234' \
    --values prometheus-source.yaml \
    --set service.type=ClusterIP