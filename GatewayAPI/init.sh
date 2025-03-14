aws cloudformation deploy \
  --stack-name "latticebaseinfrawithapiserver" \
  --template-file "./LatticeBaseInfraWithAPIServer.yaml" \
  --capabilities CAPABILITY_NAMED_IAM

export reservation_svc_dns=$(aws vpc-lattice list-services | jq -r '.items[].dnsEntry.domainName' | grep 'reservation')
export parking_svc_dns=$(aws vpc-lattice list-services | jq -r '.items[].dnsEntry.domainName' | grep 'parking')

InstanceClient1_IAM_ARN=$(aws iam get-role --role-name InstanceClient1_IAM --query Role.Arn --output text)
InstanceClient2_IAM_ARN=$(aws iam get-role --role-name InstanceClient2_IAM --query Role.Arn --output text)
parking_svc_arn=$(aws vpc-lattice list-services | jq -r '.items[] | select(.dnsEntry.domainName=="'$parking_svc_dns'") | .arn')