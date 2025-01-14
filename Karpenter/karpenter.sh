# KarpenterNodeRole이라는 IAM Role을 생성 (해당 Role은 Scale-out 된 노드가 사용할 IAM Role)
cat << EOF > node-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam create-role --role-name "KarpenterNodeRole-skills-eks" \
    --assume-role-policy-document file://node-trust-policy.json
    
aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy

aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

aws iam attach-role-policy --role-name "KarpenterNodeRole-skills-eks" \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
    --instance-profile-name "KarpenterNodeInstanceProfile-skills-eks"

aws iam add-role-to-instance-profile \
    --instance-profile-name "KarpenterNodeInstanceProfile-skills-eks" \
    --role-name "KarpenterNodeRole-skills-eks"


# KarpenterControllerRole이라는 IAM Role을 생성 (해당 Role은 Karpenter Pod가 사용할 IAM Role)
aws eks describe-cluster --name skills-eks-cluster --query "cluster.identity.oidc.issuer" --output text

cat << EOF > controller-trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::362708816803:oidc-provider/OIDC_ENDPOINT#*//}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "OIDC_ENDPOINT#*//}:aud": "sts.amazonaws.com",
                    "OIDC_ENDPOINT#*//}:sub": "system:serviceaccount:karpenter:karpenter"
                }
            }
        }
    ]
}
EOF

aws iam create-role --role-name KarpenterControllerRole-skills-eks \
    --assume-role-policy-document file://controller-trust-policy.json
    
cat << EOF > controller-policy.json
{
    "Statement": [
        {
            "Action": [
                "ssm:GetParameter",
                "ec2:DescribeImages",
                "ec2:RunInstances",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeLaunchTemplates",
                "ec2:DescribeInstances",
                "ec2:DescribeInstanceTypes",
                "ec2:DescribeInstanceTypeOfferings",
                "ec2:DescribeAvailabilityZones",
                "ec2:DeleteLaunchTemplate",
                "ec2:CreateTags",
                "ec2:CreateLaunchTemplate",
                "ec2:CreateFleet",
                "ec2:DescribeSpotPriceHistory",
                "pricing:GetProducts"
            ],
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "Karpenter"
        },
        {
            "Action": "ec2:TerminateInstances",
            "Condition": {
                "StringLike": {
                    "ec2:ResourceTag/karpenter.sh/provisioner-name": "*"
                }
            },
            "Effect": "Allow",
            "Resource": "*",
            "Sid": "ConditionalEC2Termination"
        },
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "arn:aws:iam::362708816803:role/KarpenterNodeRole-skills-eks",
            "Sid": "PassNodeIAMRole"
        },
        {
            "Effect": "Allow",
            "Action": "eks:DescribeCluster",
            "Resource": "arn:aws:eks:ap-northeast-2:362708816803:cluster/skills-eks-cluster",
            "Sid": "EKSClusterEndpointLookup"
        }
    ],
    "Version": "2012-10-17"
}
EOF

aws iam put-role-policy --role-name KarpenterControllerRole-skills-eks \
    --policy-name KarpenterControllerPolicy-skills-eks \
    --policy-document file://controller-policy.json

kubectl edit configmap aws-auth -n kube-system

helm template karpenter oci://public.ecr.aws/karpenter/karpenter --version v0.31.0 --namespace karpenter \
    --set settings.aws.defaultInstanceProfile=KarpenterNodeInstanceProfile-skills-eks \
    --set settings.aws.clusterName=skills-eks-cluster \
    --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::362708816803:role/KarpenterControllerRole-skills-eks" \
    --set controller.resources.requests.cpu=1 \
    --set controller.resources.requests.memory=1Gi \
    --set controller.resources.limits.cpu=1 \
    --set controller.resources.limits.memory=1Gi > karpenter.yaml

kubectl create ns karpenter

kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter/v0.31.0/pkg/apis/crds/karpenter.sh_provisioners.yaml
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter/v0.31.0/pkg/apis/crds/karpenter.k8s.aws_awsnodetemplates.yaml
kubectl create -f \
    https://raw.githubusercontent.com/aws/karpenter/v0.31.0/pkg/apis/crds/karpenter.sh_machines.yaml
kubectl apply -f karpenter.yaml

kubectl get po -n karpenter

kubectl apply -f provisioner.yaml

kubectl apply -f deployment.yaml

kubectl describe pod nginx-xxxx

kubectl logs -n karpenter  deploy/karpenter -f