# AMI Upgrade

Start a pre-existing EC2 "template" instance, run a user script on it, stop, kill any existing AMIs and snapshots from the old template, and register a new AMI from the updated instance.

Handy for transient instances like Jenkins slaves where you don't want to be manually regenerating the AMI all the time, and you don't want to delay the instance's startup by sticking lots of yum updating in instance user data.

## Example of use

### Environment

`.env`

```
# AWS credentials
AWS_ACCESS_KEY_ID=blahblahblahkey
AWS_SECRET_ACCESS_KEY=blahblahblahblahblahblahblahblahblahblahkey
AWS_DEFAULT_REGION=eu-west-2

# Value of the "Name" tag for the template instance
INSTANCE_NAME_TAG=My Jenkins Slave Template Instance

# Name of the image to be destroyed and created
AMI_NAME=AmazonLinuxNodeDockerJenkinsSlave

# IP to use: Private (default) or Public
IP_TYPE=Private

# User to use for SSH
REMOTE_USER=ec2-user

# Any extra SSH args (you get -q for free)
SSH_ARGS=-i /.id_rsa -tt -o StrictHostKeyChecking=no

# The command to run on the remote!
USER_SCRIPT=sudo yum update -y

# Output everything (false - default), or just the new image ID (true)
QUIET=false
```

### Run script

```
$ docker run --rm --env-file .env -v ~/.ssh/id_rsa:/.id_rsa ami-upgrade
```

## TODO

* What you using `jq` for? Use aws-cli's native JMESPath JSON wrangling
* How can CloudFormation help with all this?
