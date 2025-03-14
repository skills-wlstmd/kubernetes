# install Calico
helm repo add projectcalico https://docs.tigera.io/calico/charts
kubectl create namespace tigera-operator
helm install calico projectcalico/tigera-operator --version v3.29.1 --namespace tigera-operator
# helm install calico projectcalico/tigera-operator --version v3.29.1 -f values.yaml --namespace tigera-operator

# install Calicoctl
curl -L https://github.com/projectcalico/calico/releases/download/v3.29.1/calicoctl-linux-amd64 -o kubectl-calico
chmod +x kubectl-calico
sudo mv kubectl-calico /usr/local/bin/calicoctl

kubectl apply -f networkpolicy.yaml

kubectl apply -f a-pod.yaml && kubectl apply -f b-pod.yaml && kubectl apply -f c-pod.yaml

kubectl exec -it a-pod -- curl <b-pod-ip>
kubectl exec -it c-pod -- curl <c-pod-ip>