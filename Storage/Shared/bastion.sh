# Deploy
kubectl apply -f two-container.yaml

# Response Check
kubectl exec -it two-containers -c nginx-container -- curl localhost
kubectl exec -it two-containers -c nginx-container -- cat /usr/share/nginx/html/index.html