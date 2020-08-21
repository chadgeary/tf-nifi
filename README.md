# Reference
Terraform with Ansible to create/manage a full AWS-based secure Apache NiFi cluster/stack.

# Requirements
- Terraform installed.
- AWS credentials (e.g. `aws configure` if awscli is installed)
- Customized variables (see Variables section).

# Variables
Edit the vars file (.tfvars) to customize the deployment, especially:

**bucket_name**

- a unique bucket name, terraform will create the bucket to store various resources.

**mgmt_cidr**

- an IP range granted NiFi webUI and EC2 SSH access via the ELB hostname.
- deploying from home? `dig +short myip.opendns.com @resolver1.opendns.com | awk '{ print $1"/32" }'`

**kms_manager**

- an AWS user account (not root) that will be granted access to the KMS key (to read S3 objects).

- Don't have an IAM user? Replace all occurrences of `${data.aws_iam_user.tf-nifi-kmsmanager.arn}` with a role ARN (e.g. an Instance Profile ARN), and remove the `aws_iam_user` block in tf-nifi-generic.tf.

**instance_key**

- a public SSH key for SSH access to instances.

**instance_vol_size**

- the volume/filesystem size of the zookeeper and node instances, in GiB.

# Deploy
```
# Initialize terraform
terraform init

# Apply terraform - the first apply takes a while creating an encrypted AMI.
terraform apply -var-file="tf-nifi.tfvars"

# Wait for SSM Ansible Playbook, watch:
https://console.aws.amazon.com/systems-manager/state-manager
```

# WebUI Access
WebUI access is permitted to the mgmt_cidr defined in tf-nifi.tfvars. Authentication requires the admin password-protected certificate generated by the Ansible playbook:
- Gather keystore.pkcs12 from either:
  - The S3 bucket (defined in tf-nifi.tfvars)/certificates/admin/, or
  - An EC2 instance (via ssh to ELB hostname) under /opt/nifi-certificates/admin/
- Import keystore.pkcs12 as certificate into Web Browser
  - Use generated_password (also in S3/EC2) when prompted for password
- Browse to the zookeeper elb dns name, e.g.: `https://tf-nifi-zk-elb-123456.us-east-2.elb.amazonaws.com/nifi`

# Ansible / SSM Notes
There are two Ansible playbooks deployed via terraform to AWS SSM, zookeepers/zookeepers.yml and nodes/nodes.yml.
- Both playbooks install Apache NiFi.
- Zookeepers includes Apache Zookeeper and custom services (mini playbooks) for cluster management.
- Playbooks are deployed to instances via SSM at instance launch time, though an administrator may reapply the SSM association at any time.

# Scaling Notes
Special actions take place during scaling to handle NiFi cluster management.

**Scale Up**

Every node spawned via Autoscale applies the nodes.yml playbook via SSM, overview:
- node installs pre-requisting packages/libraries, the Apache NiFi software, and nifi conf.
- node generates signed certificate and creates user in cluster.
- node touches S3://`bucket`/nifi/cluster/join/`node name`
- a Zookeeper monitoring S3 copies latest NiFi conf to S3://`bucket`/nifi/conf/
- a Zookeeper touches S3://`bucket`/nifi/cluster/invite/`node name`
- node copies the up-to-date NiFi conf from S3 to /opt/nifi/conf/
- node starts the NiFi service, joined to cluster.

**Scale Down**

Every node terminated via Autoscale uses special actions to gracefully exit the cluster, overview:
- Autoscale uses a Lifecycle Hook to notify an SNS topic of scale down.
- SNS topic has a subscription: a Lambda function.
- Lambda function spawns an SSM RunCommand.
- SSM RunCommand executes a shell script: `nodes/scale-down` on the terminating instance(s).
- `scale-down` overview:
  - node retrieves NodeId (node's ID within the NiFi cluster).
  - node disconnects from the NiFi cluster.
  - node offloads in-flight work from the cluster.
  - node touches S3://`bucket`/nifi/cluster/leave/<node id>
  - a Zookeeper monitoring S3 deletes the NodeId.
  - node completes the Autoscale Lifecycle Hook
  - AWS terminates the instance.

# AMI Notes
- AMI is [Ubuntu 1804](https://cloud-images.ubuntu.com/locator/ec2/), change the vendor_ami_name_string var as needed (especially the date).
