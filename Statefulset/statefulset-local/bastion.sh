kubectl get node  

# 각 노드에 접속 후 폴더 생성
sudo mkdir -p /mnt/common

kubectl apply -f statefulset-local.yaml

# Pod 내부 shell 접속
kubectl exec -it statefulset-demo-0-0 -- /bin/bash

# 마운트된 디렉토리 확인
df -h /usr/share/nginx/html

# 테스트 파일 생성
echo "Hello from Kubernetes!" > /usr/share/nginx/html/index.html

# 노드에 ssh 접속 후
ls -l /tmp/k8s-pv-statefulset-demo
cat /tmp/k8s-pv-statefulset-demo/index.html