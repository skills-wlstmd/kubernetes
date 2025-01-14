helm repo add kedacore https://kedacore.github.io/charts
helm repo update
kubectl create namespace keda
helm install keda kedacore/keda --namespace keda

kubectl apply -f scaledobject.yaml
kubectl apply -f deployment.yaml

kubectl get scaledobject
kubectl describe scaledobject