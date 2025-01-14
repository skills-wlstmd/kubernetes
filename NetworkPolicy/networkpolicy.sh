kubectl get pod web-pod -n network-policy-demo -o wide

kubectl exec -n network-policy-demo client-pod -- wget -O- --timeout=2 http://10.244.0.3
kubectl exec -n network-policy-demo test-pod -- wget -O- --timeout=2 http://10.244.0.3

# kubectl exec -n network-policy-demo client-pod -- wget -O- --timeout=2 http://web-service

kubectl get networkpolicy -n network-policy-demo
kubectl describe networkpolicy web-allow-same-namespace -n network-policy-demo

kubectl run test-pod --namespace=default --image=alpine --restart=Never --rm -i -- wget -O- --timeout=2 http://web-pod.network-policy-demo