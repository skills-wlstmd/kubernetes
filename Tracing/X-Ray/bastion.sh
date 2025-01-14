# ENV
EKS_CLUSTER_NAME="<CLUSTER_NAME>"
CLUSTER_OIDC=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -c 9-100)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# IRSA (Create the service account for X-Ray.)
eksctl create iamserviceaccount \
  --name xray-daemon \
  --namespace default \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess \
  --override-existing-serviceaccounts \
  --approve 

# Apply a label to the service account
kubectl label serviceaccount xray-daemon app=xray-daemon

# X-Ray DaemonSet
kubectl apply -f xray-k8s-daemonset.yaml
kubectl describe daemonset xray-daemon
kubectl logs -l app=xray-daemon

# X-Ray Sample App
kubectl apply -f https://eksworkshop.com/intermediate/245_x-ray/sample-front.files/x-ray-sample-front-k8s.yml
kubectl apply -f https://eksworkshop.com/intermediate/245_x-ray/sample-back.files/x-ray-sample-back-k8s.yml
kubectl describe deployments x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl describe services x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl get service x-ray-sample-front-k8s -o wide

# Delete
kubectl delete deployments x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl delete services x-ray-sample-front-k8s x-ray-sample-back-k8s
kubectl delete -f xray-k8s-daemonset.yaml
eksctl delete iamserviceaccount --name xray-daemon --cluster $EKS_CLUSTER_NAME
