#!/bin/bash
public_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PublicSubnet01" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
public_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PublicSubnet02" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
public_c=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PublicSubnet03" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_a=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PrivateSubnet01" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_b=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PrivateSubnet02" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)
private_c=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=LatticeWorkshop-Client-PrivateSubnet03" --query "Subnets[].SubnetId[]" --region ap-northeast-2 --output text)

sed -i "s|public_a|$public_a|g" cluster.yaml
sed -i "s|public_b|$public_b|g" cluster.yaml
sed -i "s|public_c|$public_c|g" cluster.yaml
sed -i "s|private_a|$private_a|g" cluster.yaml
sed -i "s|private_b|$private_b|g" cluster.yaml
sed -i "s|private_c|$private_c|g" cluster.yaml

eksctl create cluster -f cluster.yaml

export EKS_CLUSTER_NAME=gw-eks-cluster
export AWS_REGION=ap-northeast-2

CLUSTER_SG=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --output json| jq -r '.cluster.resourcesVpcConfig.clusterSecurityGroupId')
PREFIX_LIST_ID=$(aws ec2 describe-managed-prefix-lists --query "PrefixLists[?PrefixListName=="\'com.amazonaws.$AWS_REGION.vpc-lattice\'"].PrefixListId" | jq -r '.[]')
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --ip-permissions "PrefixListIds=[{PrefixListId=${PREFIX_LIST_ID}}],IpProtocol=-1"
PREFIX_LIST_ID_IPV6=$(aws ec2 describe-managed-prefix-lists --query "PrefixLists[?PrefixListName=="\'com.amazonaws.$AWS_REGION.ipv6.vpc-lattice\'"].PrefixListId" | jq -r '.[]')
aws ec2 authorize-security-group-ingress --group-id $CLUSTER_SG --ip-permissions "PrefixListIds=[{PrefixListId=${PREFIX_LIST_ID_IPV6}}],IpProtocol=-1"

curl https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/recommended-inline-policy.json  -o recommended-inline-policy.json

aws iam create-policy \
    --policy-name VPCLatticeControllerIAMPolicy \
    --policy-document file://recommended-inline-policy.json

export VPCLatticeControllerIAMPolicyArn=$(aws iam list-policies --query 'Policies[?PolicyName==`VPCLatticeControllerIAMPolicy`].Arn' --output text)

kubectl create ns aws-application-networking-system

aws eks create-addon --cluster-name $EKS_CLUSTER_NAME --addon-name eks-pod-identity-agent --addon-version v1.0.0-eksbuild.1

kubectl get pods -n kube-system | grep 'eks-pod-identity-agent'

cat << EOF > gateway-api-controller-service-account.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
    name: gateway-api-controller
    namespace: aws-application-networking-system
EOF
kubectl apply -f gateway-api-controller-service-account.yaml

cat << EOF > trust-relationship.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowEksAuthToAssumeRoleForPodIdentity",
            "Effect": "Allow",
            "Principal": {
                "Service": "pods.eks.amazonaws.com"
            },
            "Action": [
                "sts:AssumeRole",
                "sts:TagSession"
            ]
        }
    ]
}
EOF

aws iam create-role --role-name VPCLatticeControllerIAMRole --assume-role-policy-document file://trust-relationship.json --description "IAM Role for AWS Gateway API Controller for VPC Lattice"

aws iam attach-role-policy --role-name VPCLatticeControllerIAMRole --policy-arn=$VPCLatticeControllerIAMPolicyArn

export VPCLatticeControllerIAMRoleArn=$(aws iam list-roles --query 'Roles[?RoleName==`VPCLatticeControllerIAMRole`].Arn' --output text)

aws eks create-pod-identity-association --cluster-name $EKS_CLUSTER_NAME --role-arn $VPCLatticeControllerIAMRoleArn --namespace aws-application-networking-system --service-account gateway-api-controller

kubectl apply -f https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/deploy-v1.0.5.yaml

kubectl get pods -n aws-application-networking-system 

kubectl apply -f https://raw.githubusercontent.com/aws/aws-application-networking-k8s/main/files/controller-installation/gatewayclass.yaml

aws vpc-lattice create-service-network --name my-hotel

aws vpc-lattice list-service-networks | jq -r '.items[]| select(.name=="my-hotel") | .id'

export my_hotel_sn_id=$(aws vpc-lattice list-service-networks | jq -r '.items[]| select(.name=="my-hotel") | .id')
export CLUSTER_VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)

# VPC는 1개의 Service Network에만 Associaation 이 가능합니다. 앞서 LAB에서 Superapp에 Client VPC를 Assocation 시켰다면, 삭제 후 Association 해야 합니다.
aws vpc-lattice create-service-network-vpc-association --service-network-identifier ${my_hotel_sn_id} --vpc-identifier ${CLUSTER_VPC_ID}

aws vpc-lattice list-service-network-vpc-associations --vpc-id ${CLUSTER_VPC_ID} | jq -r '.items[].status'

kubectl apply -f my-hotel-gateway.yaml

kubectl get gateway

kubectl apply -f parking.yaml
kubectl apply -f review.yaml
kubectl apply -f rate-route-path.yaml

kubectl get svc,pod,httproute

kubectl apply -f inventory-ver1.yaml
kubectl apply -f inventory-route.yaml

kubectl get svc,pod,httproute

export k8s_rates_svc_dns=$(kubectl get httproute rates -o json | jq -r '.metadata.annotations."application-networking.k8s.aws/lattice-assigned-domain-name"')
export k8s_inventory_svc_dns=$(kubectl get httproute inventory -o json | jq -r '.metadata.annotations."application-networking.k8s.aws/lattice-assigned-domain-name"')

kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/parking
kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/review 
kubectl exec deploy/parking -- curl $k8s_inventory_svc_dns

kubectl apply -f lattice-test-01.yaml

export k8s_lattice_test_01_svc_dns=$(kubectl get httproute lattice-test-01 -o json | jq -r '.metadata.annotations."application-networking.k8s.aws/lattice-assigned-domain-name"')

kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/parking
kubectl exec deploy/inventory-ver1 -- curl $k8s_rates_svc_dns/review 
kubectl exec deploy/parking -- curl $k8s_inventory_svc_dns
