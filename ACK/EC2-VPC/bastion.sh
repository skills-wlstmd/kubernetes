# 변수 지정
export SERVICE=ec2
export AWS_REGION=ap-northeast-2
export EKS_CLUSTER_NAME=skills-eks-cluster

# HELM 차트 Install
export RELEASE_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/$SERVICE-controller/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | cut -c 2-)
helm pull oci://public.ecr.aws/aws-controllers-k8s/$SERVICE-chart --version=$RELEASE_VERSION
tar xzvf $SERVICE-chart-$RELEASE_VERSION.tgz

# ACK EC2-Controller 설치
helm install -n ack-system ack-$SERVICE-controller --set aws.region="$AWS_REGION" ~/$SERVICE-chart

# 설치 확인
helm list --namespace ack-system
kubectl -n ack-system get pods -l "app.kubernetes.io/instance=ack-$SERVICE-controller"
kubectl get crd | grep $SERVICE

# IAM 서비스 계정 생성 및 권한 부여
eksctl create iamserviceaccount \
  --name ack-$SERVICE-controller \
  --region=ap-northeast-2 \
  --namespace ack-system \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
  --override-existing-serviceaccounts \
  --approve

eksctl delete iamserviceaccount \
  --name ack-$SERVICE-controller \
  --region=ap-northeast-2 \
  --namespace ack-system \
  --cluster $EKS_CLUSTER_NAME

# IAM 서비스 계정 확인
eksctl get iamserviceaccount --cluster $EKS_CLUSTER_NAME

# 서비스 계정 확인
kubectl get sa -n ack-system
kubectl describe sa ack-$SERVICE-controller -n ack-system

# ACK EC2 Controller 재시작
kubectl -n ack-system rollout restart deploy ack-$SERVICE-controller-$SERVICE-chart

# Pod 설명
kubectl describe pod -n ack-system -l k8s-app=$SERVICE-chart

# VPC 상태 확인
while true; do aws ec2 describe-vpcs --query 'Vpcs[*].{VPCId:VpcId, CidrBlock:CidrBlock}' --output text; echo "-----"; sleep 1; done

# VPC 생성
cat << EOF > vpc.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: VPC
metadata:
  name: vpc-tutorial-test
spec:
  cidrBlocks: 
  - 10.0.0.0/16
  enableDNSSupport: true
  enableDNSHostnames: true
EOF

kubectl apply -f vpc.yaml

# VPC 생성 확인
kubectl get vpcs
kubectl describe vpcs
aws ec2 describe-vpcs --query 'Vpcs[*].{VPCId:VpcId, CidrBlock:CidrBlock}' --output text

# VPC ID 변수 설정
VPCID=$(kubectl get vpcs vpc-tutorial-test -o jsonpath={.status.vpcID})

# 서브넷 상태 확인
while true; do aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[*].{SubnetId:SubnetId, CidrBlock:CidrBlock}' --output text; echo "-----"; sleep 1 ; done

# 서브넷 매니페스트 생성
cat << EOF > subnet.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Subnet
metadata:
  name: subnet-tutorial-test
spec:
  cidrBlock: 10.0.0.0/20
  vpcID: $VPCID
EOF

kubectl apply -f subnet.yaml

# 서브넷 생성 확인
kubectl get subnets
kubectl describe subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPCID" --query 'Subnets[*].{SubnetId:SubnetId, CidrBlock:CidrBlock}' --output text

# 리소스 삭제
kubectl delete -f subnet.yaml && kubectl delete -f vpc.yaml