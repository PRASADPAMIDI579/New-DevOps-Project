#!/bin/bash
#!/bin/bash

LOG=/tmp/instance-create.log
rm -f $LOG

INSTANCE_NAME=$1
if [ -z "${INSTANCE_NAME}" ]; then
  echo -e "\e[1;34m Instance Name Argument is needed\e[0m"
  exit
  fi



AMI_ID=$(aws ec2 describe-images --filters "Name=name,Values=Amazon Linux 2023 AMI" --query 'Images[*].[ImageId]' --output text)
if [ -z "${AMI_ID}" ]; then
  echo -e "\e[1;32mUnable to find AMI_ID\e[0m"
  else
    echo -e "\e[1;33m AMI ID = ${AMI_ID}\e[0m"
  fi

PRIVATE_IP=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
if [ -z "${PRIVATE_IP}" ]; then
  SG_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=Aws-Practice --query "SecurityGroups[*].GroupId" --output text)
  if [ -z "${SG_ID}" ]; then
    echo -e "\e[1;32m Security Group Aws-Practice does not exist"
    exit
    fi


  aws ec2 run-instances --image-id ${AMI_ID} --instance-type t2.small --output text --tag-specifications "ResourceType=instance,
  Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" "ResourceType=spot-instances-request,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" --instance-market-options "MarketType=spot,SpotOptions={InstanceInterruptionBehavior=stop,SpotInstanceType=Persistent}" --security-group-ids "${SG_ID}" &>>$LOG

  echo -e "\e[1m Instance Created\e[0m"
else
  echo "Instance ${INSTANCE_NAME} is already exists, Hence not creating"
fi

IPADDRESS=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=${INSTANCE_NAME}" --query 'Reservations[*].Instances[*].PrivateIpAddress' --output text)
echo '{
            "Comment": "CREATE/DELETE/UPSERT a record ",
            "Changes": [{
            "Action": "UPSERT",
                        "ResourceRecordSet": {
                                    "Name": "DNSNAME",
                                    "Type": "A",
                                    "TTL": 300,
                                 "ResourceRecords": [{ "Value": "IPADDRESS"}]
}}]
}' | sed -e"s/DNSNAME/${INSTANCE_NAME}/" -e"s/IPADDRESS/${IPADDRESS}/" >/tmp/record.json

ZONE_ID=$( aws route53 list-hosted-zones --query "HostedZones[*].{name:Name,ID:Id}" --output text | grep roboshop.internal | awk '{print $1}' | awk -F '{print $3}')
aws route53 change-resource-record-sets --hosted-zone-id $ZONE_ID --change-batch file:///tmp/record.json --output text &>>$LOG

echo -e "\e[1m DNS Record Created\e[0m"