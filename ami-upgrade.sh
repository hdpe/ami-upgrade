#!/bin/sh
set -e

# mandatory env vars for AWS client
: ${AWS_ACCESS_KEY:?}
: ${AWS_SECRET_ACCESS_KEY:?}
: ${AWS_DEFAULT_REGION:?}

# mandatory env vars for script
: ${AMI_NAME:?}
: ${INSTANCE_NAME_TAG:?}
: ${IDENTITY_FILE:?}
: ${REMOTE_USER:?}

INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME_TAG" \
        | jq -r '.Reservations[0].Instances[0].InstanceId') 

aws ec2 start-instances --instance-ids $INSTANCE_ID

aws ec2 wait instance-running --instance-ids $INSTANCE_ID

HOST=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
        | jq -r '.Reservations[0].Instances[0].PrivateIpAddress') 

until nc -z $HOST 22; do 
    echo 'waiting for SSH...'
    sleep 1
done

mkdir -p ~/.ssh && ssh-keyscan -H -t rsa $HOST > ~/.ssh/known_hosts

ssh -i "$IDENTITY_FILE" -tt $REMOTE_USER@$HOST 'sudo yum update -y'

aws ec2 stop-instances --instance-ids $INSTANCE_ID

aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID

CURRENT_IMAGE_ID=$(aws ec2 describe-images --filters "Name=name,Values=$AMI_NAME" \
    | jq -r '.Images[0].ImageId // empty')

if [ -n "$CURRENT_IMAGE_ID" ]; then
    SNAPSHOT_IDS=$(aws ec2 describe-images --image-ids $CURRENT_IMAGE_ID \
	| jq -r '.Images[].BlockDeviceMappings[].Ebs.SnapshotId')

    aws ec2 deregister-image --image-id $CURRENT_IMAGE_ID

    for SNAPSHOT_ID in ${SNAPSHOT_IDS}; do
	aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID
    done
fi

NEW_IMAGE_ID=$(aws ec2 create-image --instance-id $INSTANCE_ID --name "$AMI_NAME" \
    | jq -r '.ImageId')

aws ec2 wait image-available --image-ids $NEW_IMAGE_ID

echo $NEW_IMAGE_ID
