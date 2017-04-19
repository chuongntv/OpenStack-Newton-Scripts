#!/bin/bash
## Install Barbican


##########################################
dir_path=$(dirname $0)
path_barbican=/etc/barbican/barbican.conf
log_barbican=/var/log/barbican/

source $dir_path/config.cfg
source $dir_path/lib/functions.sh
source $dir_path/admin-openrc

echocolor "Start to install Barbican"
sleep 3


# Config service
openstack user create barbican --domain default --password  $DEFAULT_PASS
openstack role add --project service --user barbican admin
openstack role create creator
openstack role add --project service --user barbican creator
openstack service create --name barbican --description "Key Manager" key-manager
openstack endpoint create --region RegionOne key-manager public http://$CTL_MGNT_IP:9311
openstack endpoint create --region RegionOne key-manager internal http://$CTL_MGNT_IP:9311
openstack endpoint create --region RegionOne key-manager admin http://$CTL_MGNT_IP:9311


# Create a database:
cat << EOF | mysql -uroot -p$DEFAULT_PASS
CREATE DATABASE barbican;
GRANT ALL PRIVILEGES ON barbican.* TO 'barbican'@'localhost' IDENTIFIED BY '$DEFAULT_PASS';
GRANT ALL PRIVILEGES ON barbican.* TO 'barbican'@'%' IDENTIFIED BY '$DEFAULT_PASS';
FLUSH PRIVILEGES;
EOF


# Install package barbican-service
apt-get -y install barbican-api barbican-keystone-listener barbican-worker

# Edit file barbican.conf
test -f $path_barbican.orig || cp $path_barbican $path_barbican.orig
ops_edit $path_barbican DEFAULT sql_connection mysql+pymysql://barbican:$DEFAULT_PASS@127.0.0.1/barbican?charset=utf8
ops_edit $path_barbican oslo_messaging_rabbit rabbit_userid openstack
ops_edit $path_barbican oslo_messaging_rabbit rabbit_password $DEFAULT_PASS/
ops_edit $path_barbican queue enable True
sed -i 's/\/v1: barbican_api/\/v1: barbican-api-keystone/g' /etc/barbican/barbican-api-paste.ini

cat << EOF >> $path_barbican
[keystone_authtoken]

auth_uri = http://$CTL_MGNT_IP:5000
auth_url = http://$CTL_MGNT_IP:35357
memcached_servers = $CTL_MGNT_IP:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = barbican
password = $DEFAULT_PASS
EOF
# Upgrade Database
barbican-manage db upgrade

# Restart service
/etc/init.d/apache2 restart
/etc/init.d/barbican-keystone-listener restart
/etc/init.d/barbican-worker restart

echocolor "Finish installing"