kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.6.1/aio/deploy/recommended.yaml

kubectl proxy &

ssh -i <your-key-file.pem> -L 8001:127.0.0.1:8001 ec2-user@<your-ec2-public-ip>

kubectl apply -f admin-user-config.yaml

kubectl -n kubernetes-dashboard create token admin-user

http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/