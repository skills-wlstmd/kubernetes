EKS_CLUSTER_NAME=skills-eks-cluster

sudo yum install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm

aws ec2 describe-instances --filters "Name=tag:eks:nodegroup-name,Values=skills-app-nodegroup" --query "Reservations[*].Instances[*].InstanceId" --output text

aws ssm start-session --target <instance-id>

# Worker Node
sudo ipvsadm -L

sudo lsmod | egrep -i "ip_vs|ip_vs_rr|ip_vs_wrr|ip_vs_sh|nf_conntrack"

aws eks list-addons --cluster-name $EKS_CLUSTER_NAME | grep proxy

aws eks update-addon --cluster-name $EKS_CLUSTER_NAME --addon-name kube-proxy \
    --addon-version v1.31.2-eksbuild.3\
    --configuration-values '{"ipvs": {"scheduler": "rr"}, "mode": "ipvs"}' \
    --resolve-conflicts OVERWRITE

kubectl get cm kube-proxy-config -n kube-system -o yaml > kube-proxy-config-old.yml

kubectl edit cm kube-proxy-config -n kube-system

eksctl get nodegroup --cluster=$EKS_CLUSTER_NAME

# scale-in
eksctl scale nodegroup --cluster=$EKS_CLUSTER_NAME --nodes=0 --name=skills-app-nodegroup --nodes-min=0 --nodes-max=4 --wait

# scale-out
eksctl scale nodegroup --cluster=$EKS_CLUSTER_NAME --nodes=2 --name=skills-app-nodegroup --nodes-min=2 --nodes-max=4 --wait

sudo ipvsadm -L