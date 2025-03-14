kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.16.3/cert-manager.yaml

kubectl create namespace observability

kubectl apply -f https://github.com/jaegertracing/jaeger-operator/releases/download/v1.65.0/jaeger-operator.yaml -n observability

kubectl get all -n observability 

kubectl apply -f jaeger-operator-simple-prod.yaml

kubectl port-forward svc/simple-prod-query 16686:16686 --address 0.0.0.0