#!/bin/bash
# install ssm
yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm

# stop ssm
systemctl stop amazon-ssm-agent

# update
yum -y update

# reboot
systemctl reboot