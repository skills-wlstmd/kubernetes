# 노드 접속 후 
sudo mkdir /tmp/webpage
cd /tmp/webpage
echo "hello world" > index.html

kubectl apply -f pod.yaml

kubectl get pods -o wide

kubectl exec hostpath-pod -- curl localhost # 폴더 생성전에는 403응답이 나옴 폴더 생성 후 200응답이 나옴