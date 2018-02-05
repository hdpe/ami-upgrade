#!/bin/sh
set -e

# mandatory env vars for AWS client
: ${AWS_ACCESS_KEY_ID:?}
: ${AWS_SECRET_ACCESS_KEY:?}
: ${AWS_DEFAULT_REGION:?}

# mandatory env vars for script
: ${AMI_NAME:?}
: ${INSTANCE_NAME_TAG:?}
: ${REMOTE_USER:?}
: ${USER_SCRIPT:?}

# optional env vars for script
: ${IP_TYPE:="Private"}
: ${SSH_ARGS:=""}
: ${QUIET:="false"}

log() {
    if [ "$QUIET" = "false" ]; then
	echo $@
    fi
}

log "determining instance ID for $INSTANCE_NAME_TAG"

INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$INSTANCE_NAME_TAG" \
        | jq -r '.Reservations[0].Instances[0].InstanceId') 

log "starting ${INSTANCE_ID:?}"

aws ec2 start-instances --instance-ids $INSTANCE_ID > /dev/null

log "waiting for $INSTANCE_ID to start"

aws ec2 wait instance-running --instance-ids $INSTANCE_ID

log "determining IP ($IP_TYPE) for $INSTANCE_ID"

HOST=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID \
        | jq -r ".Reservations[0].Instances[0].${IP_TYPE}IpAddress") 

until nc -z ${HOST:?} 22; do 
    log 'waiting for SSH...'
    sleep 1
done

log "executing user script"

ssh -q $SSH_ARGS $REMOTE_USER@$HOST "$USER_SCRIPT" > /dev/null

log "stopping $INSTANCE_ID"

aws ec2 stop-instances --instance-ids $INSTANCE_ID > /dev/null

log "waiting for $INSTANCE_ID to stop"

aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID

log "determining previous image ID for $AMI_NAME"

CURRENT_IMAGE_ID=$(aws ec2 describe-images --filters "Name=name,Values=$AMI_NAME" \
    | jq -r '.Images[0].ImageId // empty')

if [ -n "$CURRENT_IMAGE_ID" ]; then

    log "getting snapshot IDs for $CURRENT_IMAGE_ID"
	
    SNAPSHOT_IDS=$(aws ec2 describe-images --image-ids $CURRENT_IMAGE_ID \
	| jq -r '.Images[].BlockDeviceMappings[].Ebs.SnapshotId')

    log "deregistering image $CURRENT_IMAGE_ID"

    aws ec2 deregister-image --image-id $CURRENT_IMAGE_ID

    for SNAPSHOT_ID in ${SNAPSHOT_IDS}; do

	log "deleting snapshot $SNAPSHOT_ID"

	aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID
    done
fi

log "creating new image from $INSTANCE_ID"

NEW_IMAGE_ID=$(aws ec2 create-image --instance-id $INSTANCE_ID --name "$AMI_NAME" \
    | jq -r '.ImageId')

log "waiting for image ${NEW_IMAGE_ID:?} to become available"

aws ec2 wait image-available --image-ids $NEW_IMAGE_ID

echo $NEW_IMAGE_ID
