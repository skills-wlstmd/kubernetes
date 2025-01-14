# 변수 지정
export SERVICE=s3
export EKS_CLUSTER_NAME=skills-eks-cluster
export ACK_SYSTEM_NAMESPACE=ack-system
export AWS_REGION=ap-northeast-2
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export BUCKET_NAME=my-ack-s3-bucket-$AWS_ACCOUNT_ID

# helm 차트 다운로드
export RELEASE_VERSION=$(curl -sL https://api.github.com/repos/aws-controllers-k8s/$SERVICE-controller/releases/latest | grep '"tag_name":' | cut -d'"' -f4 | cut -c 2-)
helm pull oci://public.ecr.aws/aws-controllers-k8s/$SERVICE-chart --version=$RELEASE_VERSION
tar xzvf $SERVICE-chart-$RELEASE_VERSION.tgz

# ACK S3 Controller 설치
helm install --create-namespace -n $ACK_SYSTEM_NAMESPACE ack-$SERVICE-controller --set aws.region="$AWS_REGION" ~/$SERVICE-chart

# 설치 확인
helm list --namespace $ACK_SYSTEM_NAMESPACE
kubectl -n ack-system get pods
kubectl get crd | grep $SERVICE

kubectl get all -n ack-system
kubectl describe sa -n ack-system ack-s3-controller

# IAM 서비스 계정 생성 및 권한 부여
eksctl create iamserviceaccount \
  --name ack-$SERVICE-controller \
  --region=ap-northeast-2 \
  --namespace ack-system \
  --cluster $EKS_CLUSTER_NAME \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess \
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

# ACK S3 Controller 재시작
kubectl -n ack-system rollout restart deploy ack-$SERVICE-controller-$SERVICE-chart

# Pod 설명
kubectl describe pod -n ack-system -l k8s-app=$SERVICE-chart

# S3 생성
aws s3 ls

# S3 버킷 매니페스트 생성
cat << EOF > bucket.yaml
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: BUCKET_NAME
spec:
  name: BUCKET_NAME
EOF

sed -i "s|BUCKET_NAME|$BUCKET_NAME|g" bucket.yaml

kubectl create -f bucket.yaml

# S3 버킷 확인
aws s3 ls
kubectl get buckets
kubectl describe bucket/$BUCKET_NAME | head -6

aws s3 ls | grep $BUCKET_NAME

# S3 버킷 태그 추가
cat << EOF > bucket.yaml
apiVersion: s3.services.k8s.aws/v1alpha1
kind: Bucket
metadata:
  name: BUCKET_NAME
spec:
  name: BUCKET_NAME
  tagging:
    tagSet:
    - key: myTagKey
      value: myTagValue
EOF

sed -i "s|BUCKET_NAME|$BUCKET_NAME|g" bucket.yaml

# S3 버킷 태그 적용
kubectl apply -f bucket.yaml

# S3 버킷 설명
kubectl describe bucket/$BUCKET_NAME | grep Spec: -A5

# S3 버킷 삭제
kubectl delete -f bucket.yaml
kubectl get bucket/$BUCKET_NAME
aws s3 ls | grep $BUCKET_NAME