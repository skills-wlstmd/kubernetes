# Istio
curl -L https://istio.io/downloadIstio | sh -
cd istio-1.23.2
export PATH=$PWD/bin:$PATH
istioctl version

# Istio 삭제
kubectl delete namespaces istio-system

# Istio Operator
istioctl operator init
kubectl create namespace istio-system
kubectl apply -f istio-operator.yaml

# Istio 사이드카 프록시 주입
kubectl label namespace default istio-injection=enabled --overwrite
kubectl label namespace default istio-injection-

# Bookinfo Sample App
kubectl create namespace bookinfo
kubectl label namespace bookinfo istio-injection=enabled
kubectl get namespace -L istio-injection
kubectl get ns bookinfo --show-labels

# Sample App
kubectl -n bookinfo apply -f bookinfo.yaml
kubectl -n bookinfo get pod,svc

# Gateway & Virtual Service
kubectl -n bookinfo apply -f bookinfo-gateway.yaml
kubectl -n bookinfo get gateways,virtualservices
kubectl -n istio-system get services

# URL
export GATEWAY_URL=$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "http://${GATEWAY_URL}/productpage"

# istio flow 파악
kubectl -n istio-system get pods -o wide

# NodePort확인을 위해서 EKS WorkerNode에 접속
# 80 port 확인
iptables -t nat -nvL KUBE-SERVICES | grep 80
#istio-gateway endpoint
iptables -t nat -nvL KUBE-SVC-xxxxxxxxx

# 각 노드들은 Kubernetes Service로 유입되는 80포트를 IPTable의 체인으로 보냅니다. 
[root@ip-10-11-12-72 bin]# iptables -t nat -nvL KUBE-SERVICES | grep dpt:80
0     0 KUBE-SVC-G6D3V5KS3PXPUEDS  tcp  --  *      *       0.0.0.0/0            172.20.26.89         /* istio-system/istio-ingressgateway:http2 cluster IP */ tcp dpt:80

# 해당 체인은 Endpoint로 포워딩 합니다
[root@ip-10-11-12-72 bin]# iptables -t nat -nvL KUBE-SVC-G6D3V5KS3PXPUEDS
Chain KUBE-SVC-G6D3V5KS3PXPUEDS (2 references)
pkts bytes target     prot opt in     out     source               destination         
0     0 KUBE-SEP-HL5XEYN4N2XIE3Z4  all  --  *      *       0.0.0.0/0            0.0.0.0/0            /* istio-system/istio-ingressgateway:http2 */

# 해당 Endpoint는 Ingress Gateway 입니다. 
[root@ip-10-11-12-72 bin]#  iptables -t nat -nvL KUBE-SEP-HL5XEYN4N2XIE3Z4
Chain KUBE-SEP-HL5XEYN4N2XIE3Z4 (1 references)
pkts bytes target     prot opt in     out     source               destination         
0     0 KUBE-MARK-MASQ  all  --  *      *       10.11.88.41          0.0.0.0/0            /* istio-system/istio-ingressgateway:http2 */
0     0 DNAT       tcp  --  *      *       0.0.0.0/0            0.0.0.0/0            /* istio-system/istio-ingressgateway:http2 */ tcp to:10.11.88.41:8080