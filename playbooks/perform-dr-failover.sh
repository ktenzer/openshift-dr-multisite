#!/bin/bash
OPENSHIFT_APP_NAME=keithtest1
OPENSHIFT_APP_DC=mariadb

PV=`oc get pv |grep $OPENSHIFT_APP_NAME-prod/$OPENSHIFT_APP_DC |awk {'print $1'}`;oc get pv $PV -o yaml |sed '/creationTimestamp/d' |sed '/resourceVersion/d' |sed '/selfLink/d' |sed '/uid:/d' |sed -e '19,23d' >/tmp/pv
