#!/bin/bash
#
# Name: sinatra_app_prov.sh
#
# Description: Provisioning script for the REA pre-interview task.
# This script will do the following:
#
# * Install ruby, gems via yum
# * Installation of nginx via RPM (packaged) - This version comes with mod_security
# * Install unicorn via gems
# * Copying of working configurations for nginx & sinatra app
# * Configuration of relevant firewall rules to allow inbound connections to port 80
# * Disable all non-necessary services
# * Implementation of a mod_security configuration for nginx
# 
# Requires:  
# * RHEL/CentOS 6 64bit
# * Needs to be run via sudo with root level permissions
#
# Author: Rhys McMurdo
#
# Date: 11/01/2014
#
# 
# Declare Variables

# Installation location for sinatra_app
MYAPP_DEST="/var/www/sinatra"

# unicorn user account. Should have rights to the app folder
UNICORN_USER="unicorn"

# base directory for where all the relevant installation files exist (For nginx rpm to rules, app and configuration)
BASEDIR=`pwd`

# nginx filename
NGINX="nginx-1.4.4-modsec.el6.x86_64.rpm"

# .rb file
SINAT_APP_FILE="helloworld.rb"

# config file
SINAT_APP_CFG="config.ru"

# Init script used to start the sinatra app on startup.
SINAT_APP_STARTUP="sinatra_app"

# default.conf file for nginx. Used to replace the default one with the RPM
NGINX_DEF_CFG="default.conf"

# Listing of all essential processes. This is used during the hardening phase. Split into multiple lines for 
# readability
MYNECESS_PROC=" abrt-ccpp abrtd acpid atd auditd autofs blk-availability certmonger cpuspeed crond"
MYNECESS_PROC="${MYNECESS_PROC} haldaemon ip6tables iptables irqbalance kdump lvm2-monitor mcelogd mdmonitor"
MYNECESS_PROC="${MYNECESS_PROC} messagebus netfs nginx ${SINAT_APP_STARTUP} network portreserve postfix rsyslog sshd sysstat udev-post "

# Uncomment to allow for some debugging of script
# set -x

# Install gcc and rsync
/usr/bin/yum -y install gcc rsync

# Firstly, lets check to see if necessary applications exist
if [ ! -f /usr/bin/gem ]
then
	/usr/bin/yum -y install ruby ruby-devel rubygems 
	if [ $? -ne 0 ]
	then
		echo "Error installing ruby packages"
		exit 2
	fi

fi


# install the nginx package

/usr/bin/yum -y install ${BASEDIR}/${NGINX}
if [ $? -ne 0 ]
	then
		echo "Error installing nginx"
		exit 2
fi

# Next lets install unicorn via gem


/usr/bin/gem install unicorn
if [ $? -ne 0 ]
	then
		echo "Error installing unicorn"
		exit 2
fi

# Need to install sinatra too
/usr/bin/gem install sinatra



# Force create the folder

/bin/mkdir -p ${MYAPP_DEST}

# Add the unicorn user
/usr/sbin/useradd -d ${MYAPP_DEST} -s /sbin/nologin ${UNICORN_USER}

# Copy the application files 
/bin/cp ${BASEDIR}/${SINAT_APP_CFG} ${MYAPP_DEST}
/bin/cp ${BASEDIR}/${SINAT_APP_FILE} ${MYAPP_DEST}

# Copy the init file across
/bin/cp ${BASEDIR}/${SINAT_APP_STARTUP} /etc/init.d/

# Configure the app for startup 
/sbin/chkconfig ${SINAT_APP_STARTUP} on

# Start the service
/sbin/service ${SINAT_APP_STARTUP} start

if [ $? -ne 0 ]
	then
		echo "Error running the sinatra app"
		exit 2
fi

# Copy over the nginx configuration file 
/bin/cp -f ${BASEDIR}/${NGINX_DEF_CFG} /etc/nginx/conf.d/

# Copy over the nginx mod security rulesets

/bin/mkdir -p /etc/nginx/conf.d/crs 
/usr/bin/rsync -av ${BASEDIR}/crs/ /etc/nginx/conf.d/crs/
/bin/cp -f ${BASEDIR}/modsecurity.conf /etc/nginx/

# Configure nginx for startup 
/sbin/chkconfig nginx on

# Start the service
/sbin/service nginx start

# Now the application has been configured to start, perform hardening steps 

# check all configured services and disable any which are un-necessary

for serv in `/sbin/chkconfig --list | grep "3:on" | awk '{print $1}'`
do

	if [ `echo ${MYNECESS_PROC} | grep " ${serv} " | wc -l` -eq 0 ]
		then
			# If we reach here then it is an unnecessary service which needs to be disabled
			/sbin/service ${serv} stop
			/sbin/chkconfig ${serv} off
	fi

done

# Update iptables firewall rulessets to allow port 80
/sbin/iptables -I INPUT 2 -m state --state NEW -p tcp -m tcp --dport 80 -j ACCEPT
/sbin/service iptables save

# Should now be complete
exit 0

