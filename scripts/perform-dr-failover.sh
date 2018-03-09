#!/bin/bash

usage() { 
	echo "Usage:$0 project_name project_database_dc prod_url prod_token test_url test_token" 
	exit 1
} 

if ([ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ] || [ -z "$5" ] || [ -z "$6" ]); then
  usage
fi

# Parameters
#OPENSHIFT_APP_NAME=hackathon
#OPENSHIFT_APP_DC=mariadb
#OPENSHIFT_PROD_URL=https://openshift.144.76.134.230.xip.io:8443
#OPENSHIFT_PROD_TOKEN=lKffkOuOQCXsQrPGTaX5Z_jJhIdV15ip5laM4IJ6qGM
#OPENSHIFT_TEST_URL=https://openshift.144.76.134.229.xip.io:8443
#OPENSHIFT_TEST_TOKEN=7Pfd17d4NIBghixsPTdQ3S-FPQaemnQ1W2OMl3szfFs

OPENSHIFT_APP_NAME=$1
OPENSHIFT_APP_DC=$2
OPENSHIFT_PROD_URL=$3
OPENSHIFT_PROD_TOKEN=$4
OPENSHIFT_TEST_URL=$5
OPENSHIFT_TEST_TOKEN=$6

echo "INFO: Gathering Objects from Production"
oc login $OPENSHIFT_PROD_URL --token=$OPENSHIFT_PROD_TOKEN --insecure-skip-tls-verify --insecure-skip-tls-verify

oc get secret $OPENSHIFT_APP_DC -n $OPENSHIFT_APP_NAME-prod -o yaml --export=true |sed '/creationTimestamp/d' |sed '/selfLink/d' |sed -e '17,22d' >/tmp/secret.yaml

PV=`oc get pv |grep $OPENSHIFT_APP_NAME-prod/$OPENSHIFT_APP_DC |awk {'print $1'}`;oc get pv $PV -o yaml |sed '/creationTimestamp/d' |sed '/resourceVersion/d' |sed '/selfLink/d' |sed '/uid:/d' |sed -e '19,23d' >/tmp/pv

oc get pvc $OPENSHIFT_APP_DC -n $OPENSHIFT_APP_NAME-prod -o yaml|sed '/creationTimestamp/d' |sed -e '12,20d' >/tmp/pvc

oc get project $OPENSHIFT_APP_NAME-prod -o yaml >/tmp/project.yaml

oc scale dc/$OPENSHIFT_APP_DC --replicas=0 -n $OPENSHIFT_APP_NAME-prod

sleep 3

source /home/cloud-user/keystonerc_prod

sleep 15

echo "INFO: Getting PV relationships"
PVC=`oc get pv |grep $OPENSHIFT_APP_NAME-prod/$OPENSHIFT_APP_DC |awk {'print $1'}`;openstack volume list |grep $PVC |awk {'print $2'} >/tmp/volumeid

sleep 15

echo "INFO: Creating volume transfer request"
VOLUMEID=`cat /tmp/volumeid`;openstack volume transfer request create $VOLUMEID >/tmp/volume-transfer-request

sleep 3

source /home/cloud-user/keystonerc_dr

sleep 3

echo "INFO: Accepting transfer move request"
AUTH_KEY=`cat /tmp/volume-transfer-request |grep auth_key |awk {'print $4'}`;ID=`cat /tmp/volume-transfer-request |grep ' id' |awk {'print $4'}`;openstack volume transfer request accept $ID $AUTH_KEY

sleep 15

oc login $OPENSHIFT_TEST_URL --token=$OPENSHIFT_TEST_TOKEN --insecure-skip-tls-verify --insecure-skip-tls-verify

sleep 1

echo "INFO: Creating DR Project"
oc new-project $OPENSHIFT_APP_NAME-prod

sleep 3

echo "INFO: Setting SELinux Labels on DR Project"
SCC_MCS=`cat /tmp/project.yaml |grep openshift.io/sa.scc.mcs: |awk {'print $2'}`;oc patch namespace $OPENSHIFT_APP_NAME-prod -p "{\"metadata\":{\"annotations\":{\"openshift.io/sa.scc.mcs\":\"$SCC_MCS\"}}}"

sleep 3

SCC_SUPP_GROUPS=`cat /tmp/project.yaml |grep openshift.io/sa.scc.supplemental-groups: |awk {'print $2'}`;oc patch namespace $OPENSHIFT_APP_NAME-prod -p "{\"metadata\":{\"annotations\":{\"openshift.io/sa.scc.supplemental-groups\":\"$SCC_SUPP_GROUPS\"}}}"

sleep 3

SCC_UID_RANGES=`cat /tmp/project.yaml |grep openshift.io/sa.scc.uid-range: |awk {'print $2'}`;oc patch namespace $OPENSHIFT_APP_NAME-prod -p "{\"metadata\":{\"annotations\":{\"openshift.io/sa.scc.uid-range\":\"$SCC_UID_RANGES\"}}}"

sleep 3

echo "INFO: Creating secrets and storage mappings on DR"
oc create -f /tmp/secret.yaml -n $OPENSHIFT_APP_NAME-prod

oc create -f /tmp/pv

oc create -f /tmp/pvc
