# VPC 및 관련 리소스 매니페스트 생성
cat << EOF > vpc-workflow.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: VPC
metadata:
  name: tutorial-vpc
spec:
  cidrBlocks: 
  - 10.0.0.0/16
  enableDNSSupport: true
  enableDNSHostnames: true
  tags:
    - key: name
      value: vpc-tutorial
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: InternetGateway
metadata:
  name: tutorial-igw
spec:
  vpcRef:
    from:
      name: tutorial-vpc
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: NATGateway
metadata:
  name: tutorial-natgateway1
spec:
  subnetRef:
    from:
      name: tutorial-public-subnet1
  allocationRef:
    from:
      name: tutorial-eip1
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: ElasticIPAddress
metadata:
  name: tutorial-eip1
spec:
  tags:
    - key: name
      value: eip-tutorial
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: RouteTable
metadata:
  name: tutorial-public-route-table
spec:
  vpcRef:
    from:
      name: tutorial-vpc
  routes:
  - destinationCIDRBlock: 0.0.0.0/0
    gatewayRef:
      from:
        name: tutorial-igw
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: RouteTable
metadata:
  name: tutorial-private-route-table-az1
spec:
  vpcRef:
    from:
      name: tutorial-vpc
  routes:
  - destinationCIDRBlock: 0.0.0.0/0
    natGatewayRef:
      from:
        name: tutorial-natgateway1
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Subnet
metadata:
  name: tutorial-public-subnet1
spec:
  availabilityZone: ap-northeast-2a
  cidrBlock: 10.0.0.0/20
  mapPublicIPOnLaunch: true
  vpcRef:
    from:
      name: tutorial-vpc
  routeTableRefs:
  - from:
      name: tutorial-public-route-table
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Subnet
metadata:
  name: tutorial-private-subnet1
spec:
  availabilityZone: ap-northeast-2a
  cidrBlock: 10.0.128.0/20
  vpcRef:
    from:
      name: tutorial-vpc
  routeTableRefs:
  - from:
      name: tutorial-private-route-table-az1
---
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: SecurityGroup
metadata:
  name: tutorial-security-group
spec:
  description: "ack security group"
  name: tutorial-sg
  vpcRef:
     from:
       name: tutorial-vpc
  ingressRules:
    - ipProtocol: tcp
      fromPort: 22
      toPort: 22
      ipRanges:
        - cidrIP: "0.0.0.0/0"
          description: "ingress"
EOF

# VPC 및 관련 리소스 생성
kubectl apply -f vpc-workflow.yaml

# 리소스 생성 상태 확인
kubectl get routetables,subnet

# VPC 환경 생성 확인
kubectl describe vpcs
kubectl describe internetgateways
kubectl describe routetables
kubectl describe natgateways
kubectl describe elasticipaddresses
kubectl describe securitygroups

# public 서브넷 ID 확인
PUBSUB1=$(kubectl get subnets tutorial-public-subnet1 -o jsonpath={.status.subnetID})
echo $PUBSUB1

# 보안 그룹 ID 확인
TSG=$(kubectl get securitygroups tutorial-security-group -o jsonpath={.status.id})
echo $TSG

# Amazon Linux 2023 AMI ID 확인
AL2023AMI=ami-049788618f07e189d
echo $AL2023AMI

# SSH 키페어 이름 설정
MYKEYPAIR=skills-practice

# echo $PUBSUB1 , $TSG , $AL2023AMI , $MYKEYPAIR

# 인스턴스 상태 확인
while true; do aws ec2 describe-instances --query "Reservations[*].Instances[*].{PublicIPAdd:PublicIpAddress,PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output table; date ; sleep 1 ; done

# public 서브넷에 인스턴스 생성
cat << EOF > tutorial-bastion-host.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Instance
metadata:
  name: tutorial-bastion-host
spec:
  imageID: $AL2023AMI # AL2023 AMI ID - ap-northeast-2
  instanceType: t3.medium
  subnetID: $PUBSUB1
  securityGroupIDs:
  - $TSG
  keyName: $MYKEYPAIR
  tags:
    - key: producer
      value: ack
EOF

kubectl apply -f tutorial-bastion-host.yaml

# 인스턴스 생성 확인
kubectl get instance
kubectl describe instance
aws ec2 describe-instances --query "Reservations[*].Instances[*].{PublicIPAdd:PublicIpAddress,PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output table

# 보안 그룹 수정 (아웃바운드 규칙 추가)
cat << EOF > modify-sg.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: SecurityGroup
metadata:
  name: tutorial-security-group
spec:
  description: "ack security group"
  name: tutorial-sg
  vpcRef:
     from:
       name: tutorial-vpc
  ingressRules:
    - ipProtocol: tcp
      fromPort: 22
      toPort: 22
      ipRanges:
        - cidrIP: "0.0.0.0/0"
          description: "ingress"
  egressRules:
    - ipProtocol: '-1'
      ipRanges:
        - cidrIP: "0.0.0.0/0"
          description: "egress"
EOF

# 보안 그룹 수정 적용
kubectl apply -f modify-sg.yaml

# 변경 확인 - 보안그룹에 아웃바운드 규칙 확인
kubectl logs -n $ACK_SYSTEM_NAMESPACE -l k8s-app=ec2-chart -f

# private 서브넷 ID 확인 - NATGW 생성 완료 후 RT/SubnetID가 확인되어 다소 시간 필요함
PRISUB1=$(kubectl get subnets tutorial-private-subnet1 -o jsonpath={.status.subnetID})
echo $PRISUB1

# echo $PRISUB1 , $TSG , $AL2023AMI , $MYKEYPAIR

# private 서브넷에 인스턴스 생성
cat << EOF > tutorial-instance-private.yaml
apiVersion: ec2.services.k8s.aws/v1alpha1
kind: Instance
metadata:
  name: tutorial-instance-private
spec:
  imageID: $AL2023AMI # AL2023 AMI ID - ap-northeast-2
  instanceType: t3.medium
  subnetID: $PRISUB1
  securityGroupIDs:
  - $TSG
  keyName: $MYKEYPAIR
  tags:
    - key: producer
      value: ack
EOF

# 인스턴스 생성
kubectl apply -f tutorial-instance-private.yaml

# 인스턴스 생성 확인
kubectl get instance
kubectl describe instance
aws ec2 describe-instances --query "Reservations[*].Instances[*].{PublicIPAdd:PublicIpAddress,PrivateIPAdd:PrivateIpAddress,InstanceName:Tags[?Key=='Name']|[0].Value,Status:State.Name}" --filters Name=instance-state-name,Values=running --output table

# SSH 접속

# 네트워크 상태 확인
ip -c addr
sudo ss -tnp
ping -c 2 8.8.8.8
curl ipinfo.io/ip ; echo # Public IP 확인 (EIP)
exit

# 리소스 삭제
kubectl delete -f tutorial-bastion-host.yaml && kubectl delete -f tutorial-instance-private.yaml
kubectl delete -f vpc-workflow.yaml