#!/usr/bin/env bash
# Provision one EC2 host for isolated Buzz agent containers (hosted community relay).
# Creates: IAM role/instance profile (SSM + read /buzz/* parameters), security group
# (no inbound; set OPEN_HTTP=true to open 80/443, only needed for a self-hosted relay),
# t3.large Ubuntu 24.04 with Docker, 60 GB gp3, IMDSv2, Elastic IP.
# Safe to re-run: existing resources tagged/named "buzz" are reused.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
NAME="${NAME:-buzz}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.large}"
DISK_GB="${DISK_GB:-60}"
OPEN_HTTP="${OPEN_HTTP:-false}"
HERE="$(cd "$(dirname "$0")" && pwd)"
aws() { command aws --region "$REGION" --output text "$@"; }

echo "==> Account: $(aws sts get-caller-identity --query Account)  Region: $REGION"

# --- Network: default VPC -----------------------------------------------------
VPC_ID=$(aws ec2 describe-vpcs --filters Name=is-default,Values=true --query 'Vpcs[0].VpcId')
[[ "$VPC_ID" == "None" || -z "$VPC_ID" ]] && { echo "No default VPC in $REGION"; exit 1; }
SUBNET_ID=$(aws ec2 describe-subnets --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true \
  --query 'sort_by(Subnets,&AvailabilityZone)[0].SubnetId')
echo "==> VPC $VPC_ID  subnet $SUBNET_ID"

# --- Security group: no inbound by default (admin via SSM, agents only connect out) ---
SG_ID=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values="$VPC_ID" Name=group-name,Values="$NAME-sg" \
  --query 'SecurityGroups[0].GroupId' 2>/dev/null || true)
if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  SG_ID=$(aws ec2 create-security-group --group-name "$NAME-sg" --description "Buzz agents host" \
    --vpc-id "$VPC_ID" --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=$NAME}]" --query GroupId)
  [ "$OPEN_HTTP" = true ] && for p in 80 443; do
    aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --ip-permissions \
      "IpProtocol=tcp,FromPort=$p,ToPort=$p,IpRanges=[{CidrIp=0.0.0.0/0}],Ipv6Ranges=[{CidrIpv6=::/0}]" >/dev/null
  done
fi
echo "==> Security group $SG_ID"

# --- IAM role for SSM Session Manager -----------------------------------------
if ! aws iam get-role --role-name "$NAME-ec2" >/dev/null 2>&1; then
  aws iam create-role --role-name "$NAME-ec2" --assume-role-policy-document \
    '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' >/dev/null
  aws iam attach-role-policy --role-name "$NAME-ec2" --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
fi
# Agents' model credentials live in SSM Parameter Store under /buzz/* (read by refresh-secrets.sh).
ACCOUNT=$(aws sts get-caller-identity --query Account)
aws iam put-role-policy --role-name "$NAME-ec2" --policy-name buzz-read-agent-secrets --policy-document \
  "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ssm:GetParameter\",\"ssm:GetParameters\"],\"Resource\":\"arn:aws:ssm:$REGION:$ACCOUNT:parameter/buzz/*\"}]}"
if ! aws iam get-instance-profile --instance-profile-name "$NAME-ec2" >/dev/null 2>&1; then
  aws iam create-instance-profile --instance-profile-name "$NAME-ec2" >/dev/null
  aws iam add-role-to-instance-profile --instance-profile-name "$NAME-ec2" --role-name "$NAME-ec2"
  echo "==> Waiting for instance profile to propagate"; sleep 15
fi

# --- Instance ------------------------------------------------------------------
INSTANCE_ID=$(aws ec2 describe-instances --filters Name=tag:Name,Values="$NAME" \
  Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[0].Instances[0].InstanceId')
if [[ -z "$INSTANCE_ID" || "$INSTANCE_ID" == "None" ]]; then
  AMI_ID=$(aws ssm get-parameter --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query Parameter.Value)
  echo "==> Launching $INSTANCE_TYPE from $AMI_ID"
  INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --subnet-id "$SUBNET_ID" --security-group-ids "$SG_ID" \
    --iam-instance-profile Name="$NAME-ec2" \
    --metadata-options HttpTokens=required,HttpEndpoint=enabled,HttpPutResponseHopLimit=1 \
    --block-device-mappings "DeviceName=/dev/sda1,Ebs={VolumeSize=$DISK_GB,VolumeType=gp3,Encrypted=true,DeleteOnTermination=false}" \
    --user-data "file://$HERE/user-data.sh" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NAME}]" "ResourceType=volume,Tags=[{Key=Name,Value=$NAME}]" \
    --query 'Instances[0].InstanceId')
fi
echo "==> Instance $INSTANCE_ID"
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# --- Elastic IP ----------------------------------------------------------------
ALLOC_ID=$(aws ec2 describe-addresses --filters Name=tag:Name,Values="$NAME" --query 'Addresses[0].AllocationId')
if [[ -z "$ALLOC_ID" || "$ALLOC_ID" == "None" ]]; then
  ALLOC_ID=$(aws ec2 allocate-address --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=$NAME}]" --query AllocationId)
fi
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOC_ID" >/dev/null
EIP=$(aws ec2 describe-addresses --allocation-ids "$ALLOC_ID" --query 'Addresses[0].PublicIp')

cat <<MSG

Done.
  Instance:   $INSTANCE_ID ($INSTANCE_TYPE, $REGION)
  Elastic IP: $EIP

Next (see SETUP.md):
  1. Wait ~3 min for the Docker install (check: aws ssm describe-instance-information)
  2. cp config.example.env config.env; set INSTANCE_ID=$INSTANCE_ID and the rest, then:
     ./ssm-run.sh setup-agents.sh
Shell access:  aws ssm start-session --region $REGION --target $INSTANCE_ID
MSG
