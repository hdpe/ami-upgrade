#!/bin/bash
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
: ${DRY_RUN:="false"}

# set up fd 3 for logging
if [[ "$QUIET" = "false" ]]; then
    exec 3>&1
else
    exec 3>/dev/null
fi

main() {
    local instance_id=$(determine_instance_id)

    start_instance ${instance_id:?}
    trap "stop_instance $instance_id" INT TERM

    local host=$(determine_instance_addr $instance_id)

    execute_user_script ${host:?}
    
    trap - INT TERM
    stop_instance $instance_id

    local current_image_id=$(determine_current_image_id)

    if [[ -n "$current_image_id" ]]; then
        delete_image $current_image_id
    fi

    create_new_image $instance_id
}

# helper functions

# return: the instance id
determine_instance_id() {
    log "determining instance ID for $INSTANCE_NAME_TAG"

    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=$INSTANCE_NAME_TAG" \
            | jq -r '.Reservations[0].Instances[0].InstanceId' 
}

# args: instance_id
start_instance() {
    local instance_id=$1

    if [[ "$DRY_RUN" != "false" ]]; then
        log "would start $instance_id"
        return
    fi

    log "starting $instance_id"

    aws ec2 start-instances --instance-ids $instance_id > /dev/null

    log "waiting for $instance_id to start"

    aws ec2 wait instance-running --instance-ids $instance_id
}

# args: instance_id
stop_instance() {
    local instance_id=$1

    if [[ "$DRY_RUN" != "false" ]]; then
        log "would stop $instance_id"
        return
    fi

    log "stopping $instance_id"

    aws ec2 stop-instances --instance-ids $instance_id > /dev/null

    log "waiting for $instance_id to stop"

    aws ec2 wait instance-stopped --instance-ids $instance_id
}

# args: instance_id
# return: ip address of instance
determine_instance_addr() {
    local instance_id=$1

    log "determining IP ($IP_TYPE) for $instance_id"

    aws ec2 describe-instances --instance-ids $instance_id \
            | jq -r ".Reservations[0].Instances[0].${IP_TYPE}IpAddress" 
}

# args: host
execute_user_script() {
    local host=$1

    local ssh_timeout=60
    local ssh_time=0
    local ssh_args=(-q $SSH_ARGS $REMOTE_USER@$host "$USER_SCRIPT")

    if [[ "$DRY_RUN" != "false" ]]; then
        log "would execute \`ssh ${ssh_args[@]}\`"
        return
    fi

    log 'waiting for SSH...'

    until nc -z $host 22 &> /dev/null; do 
        if [[ ssh_time -ge ssh_timeout ]]; then
            echo "timeout waiting for SSH" >&2
            exit 1
        fi

        sleep 1
        ssh_time=$((ssh_time+1))
    done

    log "executing user script"

    ssh -q "${ssh_args[@]}" >&3
}

# return: image id
determine_current_image_id() {
    log "determining previous image ID for $AMI_NAME"

    aws ec2 describe-images --filters "Name=name,Values=$AMI_NAME" \
        | jq -r '.Images[0].ImageId // empty'
}

# args: image_id
delete_image() {
    local image_id=$1

    log "getting snapshot IDs for $image_id"
	
    local snapshot_ids=$(aws ec2 describe-images --image-ids $image_id \
	| jq -r '.Images[].BlockDeviceMappings[].Ebs.SnapshotId')

    if [[ "$DRY_RUN" != "false" ]]; then
        log "would deregister image $image_id"
    else
        log "deregistering image $image_id"

        aws ec2 deregister-image --image-id $image_id
    fi

    for snapshot_id in ${snapshot_ids}; do
        if [[ "$DRY_RUN" != "false" ]]; then
            log "would delete snapshot $snapshot_id"
        else
            log "deleting snapshot $snapshot_id"

            aws ec2 delete-snapshot --snapshot-id $snapshot_id
        fi
    done
}

# args: instance_id
# return: new image id
create_new_image() {
    local image_id=$1

    if [[ "$DRY_RUN" != "false" ]]; then
        log "would create new image from $instance_id"
        return
    fi

    log "creating new image from $instance_id"

    local new_image_id=$(aws ec2 create-image --instance-id $instance_id --name "$AMI_NAME" \
        | jq -r '.ImageId')

    log "waiting for image ${new_image_id:?} to become available"

    aws ec2 wait image-available --image-ids $new_image_id

    echo $new_image_id
}

log() {
    echo $@ >&3
}

main
