# AMI Upgrade

Start a pre-existing EC2 "template" instance, `yum` update everything, stop, kill any existing AMIs and snapshots from the old template, and register a new AMI from the updated instance.

Handy for transient instances like Jenkins slaves where you don't want to be manually regenerating the AMI all the time, and you don't want to delay the instance's startup by sticking lots of yum updating in instance user data.

## Example of use

### Environment

`.env`:

```
AWS_ACCESS_KEY=blahblahblahkey
AWS_SECRET_ACCESS_KEY=blahblahblahblahblahblahblahblahblahblahkey
AWS_DEFAULT_REGION=eu-west-2
IDENTITY_FILE=/.key
INSTANCE_NAME_TAG=My Jenkins Slave Template Instance
AMI_NAME=AmazonLinuxNodeDockerJenkinsSlave
REMOTE_USER=ec2-user
```

### Run script

```
$ docker run --rm --env-file .env -v ~/.ssh/id_rsa:/.key ami-upgrade
```

## TODO

What you using `jq` for? Use aws-cli's native JSON wrangling.
