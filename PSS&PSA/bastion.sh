export AWS_REGION=ap-northeast-2
export CLUSTER_NAME=skills-eks-cluster

kubectl get pod -A -o jsonpath='{range .items[?(@.metadata.annotations.kubernetes.io/psp)]}{.metadata.name}{"t"}{.metadata.annotations.kubernetes.io/psp}{"t"}{.metadata.namespace}{"n"}'

eksctl utils update-cluster-logging --enable-types=all --region=$AWS_REGION \
  --cluster=$CLUSTER_NAME \
  --approve

chmod +x test.sh

kubectl delete ns policy-test 2>&1
