#!/bin/sh

# Enable the service
sysrc -f /etc/rc.conf mysql_enable="YES"
sysrc -f /etc/rc.conf dnsmasq_enable="YES"
sysrc -f /etc/rc.conf cloudstack_enable="YES"

# Start the service
service mysql-server start 2>/dev/null
service dnsmasq start 2>/dev/null

#Fetch sources
INP="/usr/local/www/cloudstack"
mkdir $INP/files

echo "Fetch External Dependencys"
fetch -o $INP/files http://download.cloud.com.s3.amazonaws.com/tools/vhd-util
#fetch -o $INP/files http://cloudstack.apt-get.eu/systemvm/4.11/systemvmtemplate-4.11.0-xen.vhd.bz2
#fetch -o $INP/files http://cloudstack.apt-get.eu/systemvm/4.11/systemvmtemplate-4.11.1-hyperv.vhd.zip
#fetch -o $INP/files http://cloudstack.apt-get.eu/systemvm/4.11/systemvmtemplate-4.11.1-kvm.qcow2.bz2
#fetch -o $INP/files http://cloudstack.apt-get.eu/systemvm/4.11/systemvmtemplate-4.11.1-ovm.raw.bz2
#fetch -o $INP/files http://cloudstack.apt-get.eu/systemvm/4.11/systemvmtemplate-4.11.1-vmware.ova
#fetch -o $INP/files http://cloudstack.apt-get.eu/systemvm/4.11/systemvmtemplate-4.11.1-xen.vhd.bz2
#wget  --no-check-certificate https://people.freebsd.org/~miwi/cl/repo.tgz -P $INP/files

cd $INP
for i in \
        build/replace.properties
do
sed -i .bak 's,MSLOG=vmops.log,MSLOG=/var/log/cloudstack/vmops.log,' $i
sed -i .bak 's,APISERVERLOG=api.log,APISERVERLOG=/var/log/cloudstack/api.log,' $i
sed -i .bak 's,AGENTLOG=logs/agent.log,AGENTLOG=/var/log/cloudstack/agent.log,' $i
done

USER="dbadmin"
DB="cloud"

# Save the config values
echo "$DB" > /root/dbname
echo "$USER" > /root/dbuser
export LC_ALL=C
cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1 > /root/dbpassword
PASS=`cat /root/dbpassword`
hostname >/root/hname
HOST=`cat /root/hname`

echo ${IOCAGE_PLUGIN_IP} $HOST > /etc/hosts 

#DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
mysql -u root <<-EOF
UPDATE mysql.user SET Password=PASSWORD('${PASS}') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.db WHERE Db='test' OR Db='test_%';

CREATE USER '${USER}'@'localhost' IDENTIFIED BY '${PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON ${DB}.* TO '${USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

for i in cloud usage simulator 
do
	sed -i '' "s|db.$i.username=cloud|db.$i.username=${USER}|g" /usr/local/www/cloudstack/utils/conf/db.properties
done

for i in cloud usage simulator
do
        sed -i '' "s|db.$i.password=cloud|db.$i.password=${PASS}|g" /usr/local/www/cloudstack/utils/conf/db.properties
done

sed -i '' "s|db.root.password=|db.root.password=${PASS}|g" /usr/local/www/cloudstack/utils/conf/db.properties
sed -i '' "s|DBUSER=cloud|DBUSER=${USER}|g" /usr/local/www/cloudstack/build/replace.properties
sed -i '' "s|DBPW=cloud|DBPW=${PASS}|g" /usr/local/www/cloudstack/build/replace.properties
sed -i '' "s|DBROOTPW=|DBROOTPW=${PASS}|g" /usr/local/www/cloudstack/build/replace.properties

#set cluster ip
if [ -n "$IOCAGE_PLUGIN_IP" ] ; then
  sed -i '' "s|cluster.node.IP=127.0.0.1|cluster.node.IP=${IOCAGE_PLUGIN_IP}|g" /usr/local/www/cloudstack/client/conf/db.properties.in
fi

#Sometime the network stucks, we want to make sure we have all dependency already download,
#that gives time for another try during the build
mvn dependency:go-offline

mvn -DskipTests -T 4 clean install -P systemvm
mvn -DskipTests -P developer -pl developer -Ddeploydb

# auto generate ssh key
echo -e "\n"|ssh-keygen -t rsa -N ""
#we need it for the first start 
cp /root/.ssh/id_rsa /root/.ssh/id_rsa.cloud
cp /root/.ssh/id_rsa.pub /root/.ssh/id_rsa.cloud.pub

/usr/local/etc/rc.d/cloudstack start

mv $INP/files/vhd-util $INP/client/target/common/scripts/vm/hypervisor/xenserver/

echo "Database User: $USER"
echo "Database Password: $PASS"

echo "The installation was successful"
echo "Username: admin"
echo "Password: password"
echo "Please change the Password immediately"
echo ""
echo "The first start can take up to 3 min during the first initalisation."
