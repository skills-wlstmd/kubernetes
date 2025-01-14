export EKS_CLUSTER_NAME=skills-eks-cluster
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install -n kube-system csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver

helm repo add aws-secrets-manager https://aws.github.io/secrets-store-csi-driver-provider-aws
helm install -n kube-system secrets-provider-aws aws-secrets-manager/secrets-store-csi-driver-provider-aws

aws --region ap-northeast-2 secretsmanager \
  create-secret --name secret_test \
  --secret-string '{"username":"foo", "password":"super-secret"}'

SECRET_ARN=$(aws --region ap-northeast-2 secretsmanager \
    describe-secret --secret-id  secret_test \
    --query 'ARN' | sed -e 's/"//g' )

echo $SECRET_ARN

aws --region ap-northeast-2 iam \
	create-policy --query Policy.Arn \
    --output text --policy-name secret_policy \
    --policy-document '{
    "Version": "2012-10-17",
    "Statement": [ {
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": ["'"$SECRET_ARN"'" ]
    } ]
}'

eksctl utils associate-iam-oidc-provider \
    --region=ap-northeast-2 \
    --cluster=$EKS_CLUSTER_NAME \
    --approve

eksctl create iamserviceaccount \
    --region=ap-northeast-2 \
    --name "secret-deployment-sa"  \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/secret_policy  \
    --override-existing-serviceaccounts \
    --approve

kubectl apply -f SecretProviderClass.yaml
kubectl apply -f deployment.yaml


export POD_NAME=$(kubectl get pods -l app=nginx -o jsonpath='{.items[].metadata.name}')
kubectl exec -it ${POD_NAME} -- cat /mnt/secrets/${SECRET_ARN}; echo