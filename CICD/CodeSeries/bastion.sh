# ENV
export S3_BUCKET_NAME=skills-app-bueckt
export AWS_REGION=ap-northeast-2
export EKS_CLUSTER_NAME=skills-eks-cluster
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
export REPO_URL=https://github.com/wlstmd/eks-cicd

# Git
sudo yum install git -y

# Docker
sudo yum install docker -y
sudo systemctl enable docker
sudo usermod -aG docker ec2-user
sudo usermod -aG docker root
sudo systemctl start docker
sudo chmod 666 /var/run/docker.sock

docker --version

# Setting
mkdir ~/skills
mkdir ~/skills/manifest

# AWS Auth
cat << EOF > assume_role_policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "codebuild.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role --role-name codebuild-role --assume-role-policy-document file://assume_role_policy.json

cat << EOF > build_policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:*",
        "s3:*",
        "ecr:*",
        "codestar-connections:*",
        "eks:DescribeCluster"
      ],
      "Resource": "*"
    }
  ]
}
EOF

aws iam put-role-policy --role-name codebuild-role --policy-name build-policy --policy-document file://build_policy.json

kubectl get configmaps aws-auth -n kube-system -o yaml > aws-auth.yaml
CODEBUILD_ROLE_ARN=$(aws iam list-roles --query "Roles[?RoleName=='codebuild-role'].Arn" --output text)
awk -v arn="$CODEBUILD_ROLE_ARN" '/mapRoles: \|/ { print; print "    - groups:\n      - system:masters\n      rolearn: " arn "\n      username: codebuild-admin"; next }1' aws-auth.yaml > tmpfile && mv tmpfile aws-auth.yaml
kubectl apply -f aws-auth.yaml --force

# k8s
kubectl create ns skills

# curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json

# aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy

eksctl create iamserviceaccount \
  --cluster=$EKS_CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name AmazonEKSLoadBalancerControllerRole \
  --attach-policy-arn=arn:aws:iam::$AWS_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# eksctl delete iamserviceaccount \
#   --cluster=$EKS_CLUSTER_NAME \
#   --namespace=kube-system \
#   --name=aws-load-balancer-controller

helm repo add eks https://aws.github.io/eks-charts
helm repo update eks
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$EKS_CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

kubectl get deployment -n kube-system aws-load-balancer-controller

kubectl apply -f ./skills/manifest/service.yaml
kubectl apply -f ./skills/manifest/ingress.yaml

# Deploy
aws s3 cp s3://$S3_BUCKET_NAME/ ~/skills --recursive

git config --global credential.helper "!aws codecommit credential-helper $@"
git config --global credential.UseHttpPath true

git init
git add .
git commit -m "ininital commit"
git branch main
git checkout main
git remote add origin $REPO_URL
git push origin main

# Subnet Tag

#!/bin/bash
public_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-public-subnet-a" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
public_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-public-subnet-b" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-subnet-a" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=skills-private-subnet-b" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)

public_subnet_name=("$public_a" "$public_b")
private_subnet_name=("$private_a" "$private_b")

for name in "${public_subnet_name[@]}"
do
    aws ec2 create-tags --resources $name --tags Key=kubernetes.io/role/elb,Value=1
done

for name in "${private_subnet_name[@]}"
do
    aws ec2 create-tags --resources $name --tags Key=kubernetes.io/role/internal-elb,Value=1
done