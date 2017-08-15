# Deployment

## AWS Elastic Beanstalk

### Set up a VPC

See [Setup AWS VPC with public and private subnets](https://github.com/dwilkie/twilreapi/blob/master/docs/AWS_VPC_SETUP.md)

### Create a Bastion Host (optional)

Since the EC2 Instances are launched in the private subnets, you cannot access them from the Internet. Follow [this guide](https://github.com/dwilkie/twilreapi/blob/master/docs/AWS_BASTION_HOST.md) to setup a Bastion Host in order to connect to your instances on the private subnet.

Note although not officially recommended, if you're also [setting up FreeSWITCH](https://github.com/dwilkie/freeswitch-config) on a public subnet you could also use this instance as the Bastion Host.

### Create a new web application environment

Launch a new web application environment using the ruby (Puma) platform. When prompted for the VPC, enter the VPC you created above. When prompted if you want to associate a public IP Address select No. When prompted for EC2 subnets, enter your *private* subnets. When prompted for your ELB subnets enter your *public* subnets. This will set up your environment similar to what is shown in [this diagram](http://docs.aws.amazon.com/AmazonVPC/latest/UserGuide/VPC_Scenario2.html).

```
$ eb platform select --profile <profile-name>
$ eb create --vpc -r <region> --profile <profile-name>
```

Set the following ENV Variables:

```
SECRET_KEY_BASE=`bundle exec rails secret`
```

#### Connecting to RDS

Follow [this guide](https://docs.aws.amazon.com/elasticbeanstalk/latest/dg/AWSHowTo.RDS.html?icmpid=docs_elasticbeanstalk_console)

This needs to be done on both the web and worker environments.

#### Setting up the Database

##### Set the DATABASE_URL

```
$ eb setenv -e <environment-name> --profile <profile-name> DATABASE_URL=postgres://database-endpoint
```

##### SSH into instance through Bastion Host

```
$ eb ssh <environment-name> --profile <profile-name> -e "ssh -A"
```

##### SSH into Twilreapi instance

```
$ ssh <ip-of-twilreapi-instance>
```

CREATE_ADMIN_ACCOUNT=1 ADMIN_ACCOUNT_PERMISSIONS=comma_separated_list_of_permissions bin/rails db:seed

##### Move into source code directory and su to root

```
$ cd /var/app/current
$ sudo su
```

##### Load the database schema

```
$ bundle exec rake db:schema:load
```

##### Setup an admin account for managing inbound phone calls

```
$ CREATE_ADMIN_ACCOUNT=1 ADMIN_ACCOUNT_PERMISSIONS=manage_inbound_phone_calls bundle exec rake db:seed
```

##### Setup an admin account for managing Call Data Records

```
$ CREATE_ADMIN_ACCOUNT=1 ADMIN_ACCOUNT_PERMISSIONS=manage_call_data_records bundle exec rake db:seed
```

##### Setup a user account

```
$ bundle exec rake db:seed
```

#### Setup Background Processing

In order to queue jobs to SQS, support for [active_elastic_job](https://github.com/tawan/active-elastic-job) is built in. Follow the [README](https://github.com/tawan/active-elastic-job).

To use [Active Elastic Job](https://github.com/tawan/active-elastic-job) set the following ENV Variables in your web environment: `ACTIVE_JOB_USE_ACTIVE_JOB=1 ACTIVE_JOB_QUEUE_ADAPTER=active_elastic_job AWS_REGION=<your-aws-region>`

##### Processing Outbound Calls

Set the SQS queue name in the ENV variable `ACTIVE_JOB_ACTIVE_ELASTIC_JOB_OUTBOUND_CALL_WORKER_QUEUE` in your web environment. The queue name will be generated when you create the worker environment (see below).

##### Processing CDRs

Set the SQS queue name in the ENV variable `ACTIVE_JOB_ACTIVE_ELASTIC_JOB_CALL_DATA_RECORD_WORKER_QUEUE` in your web environment. The queue name will be generated when you create the worker environment (see below).

Create an IAM user which has access to S3 and a bucket in which to store the CDRs. Then set the following ENV variables in your web environment:

```
CDR_STORAGE=s3
AWS_S3_REFILE_BUCKET=bucket-to-store-cdrs
AWS_REGION=region
AWS_S3_REFILE_STORE_PREFIX=store
AWS_ACCESS_KEY_ID=access-key-id-of-user-who-as-access-to-bucket
AWS_SECRET_ACCESS_KEY=secret-access-key-id-of-user-who-as-access-to-bucket
```

### Create worker environments

Create a worker environment for Processing Outbound Calls (twilreapi-outbound-call-processor) and another for Processing CDRs (twilreapi-cdr-processor).

Launch a new worker environment using the ruby (Puma) platform. When prompted for the VPC, enter the VPC you created above. When prompted for EC2 subnets, enter the *private* subnets (separated by a comma for both availability zones). Enter the same for your ELB subnets (note there is no ELB for Worker environments so this setting will be ignored)

```
$ eb create --vpc --tier worker -i t2.nano --profile <profile-name>
```

#### Setup worker environments

Ensure you set `DATABASE_URL` and `SECRET_KEY_BASE` to the same values as you specified for the web environment. In addition specify the following variables:

```
RAILS_SKIP_ASSET_COMPILATION=true
RAILS_SKIP_MIGRATIONS=true
PROCESS_ACTIVE_ELASTIC_JOBS=true
```

For the worker environment that processes outbound calls set the following variables:

```
TWILREAPI_WORKER_JOB_OUTBOUND_CALL_JOB_DRB_URL=druby://somleng-host-url:9050
```

For the worker environment that processes CDRs set the S3 storage configuration variables to the [same values](#processing-cdrs) as you set in the web environment

#### Configure the SQS queue

If you use the autogenerated queue for your worker environment then a dead-letter queue is automatically configured. This setting can be configured in the Elastic Beanstalk web console.

#### Setup Autoscaling based on SQS queue size

I followed [this article](http://blog.cbeer.info/2016/autoscaling-elasticbeanstalk-workers-sqs-length/) but not the section on CloudFormation. The important steps are:

1. Create two CloudWatch alarms for each SQS queue using the AWS CloudWatch console using the metric `ApproximateNumberOfMessagesVisible`. One alarm should be for scaling up, and the other for scaling down.
2. Attach the alarm to the AutoScaling group which was created by Elastic Beanstalk for the worker environment.

### CI Deployment

See [CI DEPLOYMENT](https://github.com/dwilkie/twilreapi/blob/master/docs/CI_DEPLOYMENT.md)

### SSH to the worker environment

Since the worker environment is on a private subnet, you can't reach it from the Internet. Instead ssh into your web environment and use ssh forwarding get to your worker instance.

```
$ eb ssh -e "ssh -A"
$ [ec2-user@private_ip_of_web_env ~]$ ssh <private_ip_of_worker_env>
```

### Running rake tasks on the server

```
$ cd /var/app/current
$ sudo su
$ bundle exec rake <task>
```