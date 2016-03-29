#!/bin/bash -x
######
# This script load zabbix-metadata from ec2 and setup
# machine hostname
# if INFRA_HOSTNAME_CHANGED already exist,
# you can rereun using any args arg Ex. ./ch-hostname.sh force
#####

PATH="$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/aws/bin:/root/bin"
JAVA_HOME=`alternatives --display java | grep Current | awk '{print $5}'  | sed -e 's/bin\/java.//g'`
REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep -i region|awk -F\" '{print $4}'`
INSTANCEID=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep -i instanceId|awk -F\" '{print $4}'`
AWS_ACCESS_KEY=`curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/) | grep AccessKeyId | sed -e "s/.*\"AccessKeyId\" : \"//g" | sed -e "s/\",$//g"`
AWS_SECRET_KEY=`curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/) | grep SecretAccessKey | sed -e "s/.*\"SecretAccessKey\" : \"//g" | sed -e "s/\",$//g"`
AWS_DELEGATION_TOKEN="x-amz-security-token: $(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/$(curl --silent http://169.254.169.254/latest/meta-data/iam/security-credentials/) | grep Token | sed -e "s/.*\"Token\" : \"//g" | sed -e "s/\",$//g")"
VRENV=`ec2-describe-tags --region=$REGION --filter resource-id=$INSTANCEID | grep -i VReNv | awk '{print $5}' | tr '[:lower:]' '[:upper:]'`
INFRA_HOSTNAME_CHANGED=/opt/infra/hostname_changed
ZABBIX_METADATA=(`ec2-describe-tags --region $REGION --filter resource-id=$INSTANCEID | awk '{print $4, $5}' | grep -i 'zabbix-metadata' | awk '{print $2}'`)

# load from config if arg metadata is empty
if [ "$1" == "" ]; then
    if [ -f $INFRA_HOSTNAME_CHANGED ]
     then
      echo "Hostname already configured"
      exit 0
    fi
else
   if [ -z $ZABBIX_METADATA ]; then
     echo "empty zabbix metadata"
     exit 0
   fi
fi

# Only proceeds, if the instance belongs to PRODUCTION environment.
if [[ $VRENV != "PROD" ]]; then
  echo "This server does not belongs to PROD environment. Monitoring tools should not be installed."
  exit 0
fi

oldhostname=`hostname`
NEW_INSTANCE_ID=`echo $INSTANCEID| cut -d - -f2`
newhostname="$ZABBIX_METADATA-$NEW_INSTANCE_ID"
hostname $newhostname

sed -ie "s/^127.0.0.1.*/127.0.0.1 $newhostname/g" /etc/hosts
echo $newhostname > /etc/hostname
sed -ie "s/^HOSTNAME=.*/HOSTNAME=$newhostname/g" /etc/sysconfig/network
sed -ie "s/^HostMetadata=.*/HostMetadata=$ZABBIX_METADATA/g" /etc/zabbix/zabbix_agentd.conf

# always start
chkconfig zabbix-agent on
update-rc.d -f zabbix-agent defaults
service zabbix-agent restart
touch $INFRA_HOSTNAME_CHANGED