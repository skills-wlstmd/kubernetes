# ENV
CLUSTER_NAME=<CLUSTER_NAME>
AWS_REGION=<REGION_CODE>

# App Mesh 설치 가능 여부 검증
curl -o pre_upgrade_check.sh https://raw.githubusercontent.com/aws/eks-charts/master/stable/appmesh-controller/upgrade/pre_upgrade_check.sh
sh ./pre_upgrade_check.sh

# Repo
helm repo add eks https://aws.github.io/eks-charts

# CRD (CustomerResourceDefinition)
kubectl apply -k "https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master"

# NS
kubectl create ns appmesh-system

# OIDC
eksctl utils associate-iam-oidc-provider \
    --region=$AWS_REGION \
    --cluster $CLUSTER_NAME \
    --approve

# IRSA
eksctl create iamserviceaccount \
    --cluster $CLUSTER_NAME \
    --namespace appmesh-system \
    --name appmesh-controller \
    --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess \
    --override-existing-serviceaccounts \
    --approve

# appmesh-controller 설치
helm upgrade -i appmesh-controller eks/appmesh-controller \
    --namespace appmesh-system \
    --set region=$AWS_REGION \
    --set serviceAccount.create=false \
    --set serviceAccount.name=appmesh-controller

# AWS App Mesh 리소스 배포
kubectl apply -f namespace.yaml 
kubectl apply -f mesh.yaml

# Kubernetes 메시 리소스의 세부 정보 확인
kubectl describe mesh my-mesh

# 컨트롤러가 생성한 App Mesh 서비스 메시에 대한 세부 정보 확인
aws appmesh describe-mesh --mesh-name my-mesh

# Virtual Node
kubectl apply -f virtual-node.yaml
kubectl describe virtualnode my-service-a -n my-apps

# Virtual Router
kubectl apply -f virtual-router.yaml
kubectl describe virtualrouter my-service-a-virtual-router -n my-apps

# Virtual Service
kubectl apply -f virtual-service.yaml
kubectl describe virtualservice my-service-a -n my-apps

# Proxy Auth
cat << EOF > proxy-auth.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "appmesh:StreamAggregatedResources",
      "Resource": [
        "arn:aws:appmesh:ap-northeast-2:362708816803:mesh/my-mesh/virtualNode/my-service-a_my-apps"
      ]
    }
  ]
}
EOF

# Policy 생성
aws iam create-policy --policy-name my-policy --policy-document file://proxy-auth.json

eksctl create iamserviceaccount \
    --cluster $CLUSTER_NAME \
    --namespace my-apps \
    --name my-service-a \
    --attach-policy-arn  arn:aws:iam::362708816803:policy/my-policy \
    --override-existing-serviceaccounts \
    --approve

# Service
kubectl apply -f service.yaml

kubectl -n my-apps get pods

# Delete
kubectl delete namespace my-apps
kubectl delete mesh my-mesh
helm delete appmesh-controller -n appmesh-system
