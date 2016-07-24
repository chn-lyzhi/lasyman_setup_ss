#!/bin/bash
##########################################
# File Name: lasy_setup_ss.sh
# Author: Allan Xing
# Email: xingpeng2012@gmail.com
# Date: 20150301
# Version: v2.0
# History:
#	add centos support@0319
#----------------------------------------
#   fix bugs and code optimization@0319
#----------------------------------------
#	modify for new ss-panel version and add start-up for service@0609
##########################################

#----------------------------------------
#mysql data
HOST="localhost"
USER="ssuser"
PORT="3306"
ROOT_PASSWD="sspasswd"
DB_NAME="sspanel"
SQL_FILES="invite_code.sql ss_user_admin.sql ss_node.sql ss_reset_pwd.sql user.sql"
CREATED=0
RESET=1
#----------------------------------------

#check OS version
CHECK_OS_VERSION=`cat /etc/issue |sed -n 1"$1"p|awk '{printf $1}' |tr 'a-z' 'A-Z'`

#list the software need to be installed to the variable FILELIST
UBUNTU_TOOLS_LIBS="python-pip mysql-server libapache2-mod-php5 python-m2crypto php5-cli git \
				apache2 php5-gd php5-mysql php5-dev libmysqlclient15-dev php5-curl php-pear language-pack-zh*"

CENTOS_TOOLS_LIBS="php55w php55w-opcache mysql55w mysql55w-server php55w-mysql php55w-gd libjpeg* \
				php55w-imap php55w-ldap php55w-odbc php55w-pear php55w-xml php55w-xmlrpc php55w-mbstring \
				php55w-mcrypt php55w-bcmath php55w-mhash libmcrypt m2crypto python-setuptools httpd nginx git"

## check whether system is Ubuntu or not
function check_OS_distributor(){
	echo "checking distributor and release ID ..."
	if [[ "${CHECK_OS_VERSION}" == "UBUNTU" ]] ;then
		echo -e "\tCurrent OS: ${CHECK_OS_VERSION}"
		UBUNTU=1
	elif [[ "${CHECK_OS_VERSION}" == "CENTOS" ]] ;then
		echo -e "\tCurrent OS: ${CHECK_OS_VERSION}!!!"
		CENTOS=1
	else
		echo "not support ${CHECK_OS_VERSION} now"
		exit 1
	fi
}

## update system
function update_system()
{
	if [[ ${UNUNTU} -eq 1 ]];then
	{
		echo "apt-get update"
		apt-get update
	}
	elif [[ ${CENTOS} -eq 1 ]];then
	{
		##Webtatic EL6 for CentOS/RHEL 6.x
		rpm -Uvh https://mirror.webtatic.com/yum/el6/latest.rpm
		yum install mysql.`uname -i` yum-plugin-replace -y
		yum replace mysql --replace-with mysql55w -y
		yum replace php-common --replace-with=php55w-common -y
	}
	fi
}

## reset mysql root password 
function reset_mysql_root_pwd()
{
if [[ ${CENTOS} -eq 1 ]];then
echo "========================================================================="
echo "Reset MySQL root Password for CentOs"
echo "========================================================================="
echo ""
if [ -s /usr/bin/mysql ]; then
M_Name="mysqld"
else
M_Name="mariadb"
fi
echo "Stoping MySQL..."
/etc/init.d/$M_Name stop
echo "Starting MySQL with skip grant tables"
/usr/bin/mysqld_safe --skip-grant-tables >/dev/null 2>&1 &
if [[ $RESET -eq 1 ]];then
/usr/bin/mysql -u root mysql << EOF
EOF
/etc/init.d/$M_Name restart
sleep 5
fi
echo "using mysql to flush privileges and reset password"
echo "set password for root@localhost = pssword('$ROOT_PASSWD');"
/usr/bin/mysql -u root mysql << EOF
update user set password = Password('$ROOT_PASSWD') where User = 'root';
EOF
reset_status=`echo $?`
if [ $reset_status = "0" ]; then
echo "Password reset succesfully. Now killing mysqld softly"
killall mysqld
sleep 5
echo "Restarting the actual mysql service"
/etc/init.d/$M_Name start
echo "Password successfully reset to '$ROOT_PASSWD'"
RESET=1
else
echo "Reset MySQL root password failed!"
RESET=0
fi
elif [[ ${UBUNTU} -eq 1 ]];then
echo "========================================================================="
echo "Reset MySQL root Password for Ubuntu"
echo "========================================================================="
echo ""
echo "Stoping MySQL..."
service mysql stop
nohup mysqld --user=mysql --skip-grant-tables --skip-networking > /var/log/reset_mysql.log 2>&1 &
sleep 2
echo "update user set Password=PASSWORD('$ROOT_PASSWD') where user='root';"
mysql -u root mysql << EOF
update user set Password=PASSWORD('$ROOT_PASSWD') where user='root';
EOF
killall mysqld
echo "Restart MYSQL..."
service mysql start
rm -rf /var/log/reset_mysql.log
fi
}

#install one software every cycle
function install_soft_for_each(){
	echo "check OS version..."
	check_OS_distributor
	if [[ ${UBUNTU} -eq 1 ]];then
		echo "Will install below software on your Ubuntu system:"
		update_system
		for file in ${UBUNTU_TOOLS_LIBS}
		do
			trap 'echo -e "\ninterrupted by user, exit";exit' INT
			echo "========================="
			echo "installing $file ..."
			echo "-------------------------"
			apt-get install $file -y
			sleep 1
			echo "$file installed ."
		done
		pip install cymysql shadowsocks
		echo "=======ready to reset mysql root password========"
		reset_mysql_root_pwd
	elif [[ ${CENTOS} -eq 1 ]];then
		echo "Will install softwears on your CentOs system:"
		update_system
		for file in ${CENTOS_TOOLS_LIBS}
		do
			trap 'echo -e "\ninterrupted by user, exit";exit' INT
			echo "========================="
			echo "installing $file ..."
			echo "-------------------------"
			yum install $file -y
			sleep 3
			echo "$file installed ."
		done
		easy_install pip
		pip install cymysql
#		echo "=======ready to reset mysql root password========"
#		reset_mysql_root_pwd
#		if [ $RESET -eq 0 ];then
#			reset_mysql_root_pwd
#		fi
	else
		echo "Other OS not support yet, please try Ubuntu or CentOs"
		exit 1
	fi
}


#mysql operation
function mysql_op()
{
	if [[ ${CREATED} -eq 0 ]];then
		mysql -h${HOST} -P${PORT} -u${USER} -p${ROOT_PASSWD} -e "$1"
	else
		mysql -h${HOST} -P${PORT} -u${USER} -p${ROOT_PASSWD} ${DB_NAME} -e "$1"
	fi
}

## configure firewall
function setup_firewall()
{
	for port in 443 80 `seq 10000 20000`
	do
		iptables -I INPUT -p tcp --dport $port -j ACCEPT
	done
	/etc/init.d/iptables save
	/etc/init.d/iptables restart
}

function install_manyuser_ss() {
    cd /root
    git clone -b manyuser https://github.com/mengskysama/shadowsocks.git
    cd ./shadowsocks/shadowsocks
    mysql -u ssuser -psspasswd sspanel < ./shadowsocks.sql
    sed -i "/^MYSQL_HOST/ s#'.*'#'localhost'#" ${SS_ROOT}/Config.py
    sed -i "/^MYSQL_PORT/ s#'.*'#'${PORT}'#" ${SS_ROOT}/Config.py
    sed -i "/^MYSQL_USER/ s#'.*'#'${USER}'#" ${SS_ROOT}/Config.py
    sed -i "/^MYSQL_PASS/ s#'.*'#'${ROOT_PASSWD}'#" ${SS_ROOT}/Config.py
    sed -i "/^MYSQL_DB/ s#'.*'#'${DB_NAME}'#" ${SS_ROOT}/Config.py

}

#setup manyuser ss
function setup_manyuser_ss()
{
	SS_ROOT=/root/shadowsocks/shadowsocks
	echo -e "download manyuser shadowsocks\n"
	cd /root
	git clone -b manyuser https://github.com/mengskysama/shadowsocks.git
	cd ${SS_ROOT}
	#modify Config.py
	echo -e "modify Config.py...\n"
	sed -i "/^MYSQL_HOST/ s#'.*'#'localhost'#" ${SS_ROOT}/Config.py
	sed -i "/^MYSQL_USER/ s#'.*'#'${USER}'#" ${SS_ROOT}/Config.py
	sed -i "/^MYSQL_PASS/ s#'.*'#'${ROOT_PASSWD}'#" ${SS_ROOT}/Config.py
#sed -i "/rc4-md5/ s#"rc4-md5"#aes-256-cfb#" ${SS_ROOT}/config.json
	#create database shadowsocks
	echo -e "create database shadowsocks...\n"
	create_db_sql="create database IF NOT EXISTS ${DB_NAME}"
	mysql_op "${create_db_sql}"
	if [ $? -eq 0 ];then
		 CREATED=1
	fi
	#import shadowsocks sql
	echo -e "import shadowsocks sql..."
	import_db_sql="source ${SS_ROOT}/shadowsocks.sql"
	mysql_op "${import_db_sql}"
}

function installNginx() {
    echo "installing Nginx..."
    yum -y install nginx
    service nginx start
    chkconfig nginx on
}

function install_redis() {
    wget http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm
    rpm -ivh epel-release-6-8.noarch.rpm
    yum -y install redis
}

function install_sspanel() {
    cd ~
    git clone https://github.com/maxidea-com/ss-panel.git
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/bin --filename=composer
    cd /root/ss-panel/
    composer install
    chmod -R 777 storage
    cp .env.example .env
    cat > /root/ss-panel/.env << EOF
//  ss-panel v3 配置
//
// !!! 修改此key为随机字符串确保网站安全 !!!
key = 'hehehehehe+1s+2s+3s'
debug =  'false'  //  正式环境请确保为false #如果启动站点出现“Slim Application Error”，则把debug设置为‘true’，即可在页面上查看错误日志。
appName = 'ss控制平台v3.0'             //站点名称
baseUrl = 'http://ss.glrou.xyz'            // 站点地址
timeZone = 'PRC'        // RPC 中国时间  UTC 格林时间
pwdMethod = 'sha256'       // 密码加密   可选 md5,sha256
salt = ''               // 密码加密用，从旧版升级请留空
theme    = 'default'   // 主题
authDriver = 'redis'   // 登录验证存储方式,推荐使用Redis   可选: cookie,redis
sessionDriver = 'redis'
cacheDriver   = 'redis'

// 邮件
mailDriver = 'mailgun'   // mailgun or smtp #如需使用邮件提醒，例如邮件找回密码，请注册mailgun账号并设置 （https://mailgun.com/）

// 用户签到设置
checkinTime = '22'      // 签到间隔时间 单位小时
checkinMin = '99'       // 签到最少流量 单位MB
checkinMax = '199'       // 签到最多流量

//
defaultTraffic = '50'      // 用户初始流量 单位GB

// 注册后获得的邀请码数量 #建议禁用，设置为0，以后邀请码从admin后台手工生成
inviteNum = '0'

# database 数据库配置
db_driver = 'mysql'
db_host = 'localhost'
db_database = '${DB_NAME}'
db_username = '${USER}'
db_password = '${ROOT_PASSWD}'
db_charset = 'utf8'
db_collation = 'utf8_general_ci'
db_prefix = ''

# redis
redis_scheme = 'tcp'
redis_host = '127.0.0.1'
redis_port = '6379'
redis_database = '0'
EOF
    mysql -u ssuser -psspasswd sspanel < db-160212.sql

    touch /etc/nginx/conf.d/sspanel.conf
    cat << EOF > /etc/nginx/conf.d/sspanel.conf
server {
    listen 80;
    server_name ss.glrou.xyz;
    root /root/ss-panel/public;
    index index.php index.html index.htm;

    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }

    # pass the PHP scripts to FastCGI server listening on 127.0.0.1:9000
    #
    location ~ \.php$ {
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    #       # NOTE: You should have "cgi.fix_pathinfo = 0;" in php.ini
    #
    #       # With php5-cgi alone:
    #       fastcgi_pass 127.0.0.1:9000;
    #       # With php5-fpm:
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_index index.php;
    include fastcgi_params;
    }
}
EOF
}

#setup ss-panel
function setup_sspanel()
{
	PANEL_ROOT=/root/ss-panel
	echo -e "download ss-panel ...\n"
	cd /root
	git clone -b v2 https://github.com/orvice/ss-panel.git
	#import pannel sql
	for mysql in ${SQL_FILES}
	do
		import_panel_sql="source ${PANEL_ROOT}/sql/${mysql}"
		mysql_op "${import_panel_sql}"
	done
	#modify config
	echo -e "modify lib/config-simple.php...\n"
	if [ -f "${PANEL_ROOT}/lib/config-simple.php" ];then
		mv ${PANEL_ROOT}/lib/config-simple.php ${PANEL_ROOT}/lib/config.php
	fi
	sed -i "/DB_PWD/ s#'password'#'${ROOT_PASSWD}'#" ${PANEL_ROOT}/lib/config.php
	sed -i "/DB_DBNAME/ s#'db'#'${DB_NAME}'#" ${PANEL_ROOT}/lib/config.php


#cp -rd ${PANEL_ROOT}/* /var/www/html/
#	rm -rf /var/www/html/index.html
}

function start_SS() {
    yum -y install supervisor
    touch /etc/supervisor/conf.d/shadowsocks.conf
    cat << EOF > /etc/supervisor/conf.d/shadowsocks.conf
[program:shadowsocks]
command=python /root/shadowsocks/shadowsocks/server.py -c /root/shadowsocks/shadowsocks/config.json
autorestart=true
user=root
EOF
    service supervisor start
    supervisorctl reload
    sed -i '$a ulimit -n 51200' /etc/profile
    sed -i '$a ulimit -Sn 4096' /etc/profile
    sed -i '$a ulimit -Hn 8192' /etc/profile
    sed -i '$a ulimit -n 51200' /etc/supervisor
    sed -i '$a ulimit -Sn 4096' /etc/default/supervisor
    sed -i '$a ulimit -Hn 8192' /etc/default/supervisor

}

#start shadowsocks server
function start_ss()
{
	if [[ $UBUNTU -eq 1 ]];then
		service apache2 restart
	elif [[ $CENTOS -eq 1 ]];then
        service nginx restart
        sleep 5
#		/etc/init.d/httpd start
	fi
	if [[ $? != 0 ]];then
		echo "Web server restart failed, please check!"
		echo "ERROR!!!"
		exit 1
	fi
	cd /root/shadowsocks/shadowsocks
	nohup python server.py > /dev/null 2>&1 &
	echo "setup firewall..."
	setup_firewall
	#add start-up
	echo "cd /root/shadowsocks/shadowsocks;python server.py > /dev/null 2>&1 &" >> /etc/rc.d/rc.local
#取消httpd
#echo "/etc/init.d/httpd start" >> /etc/rc.d/rc.local
	echo "/etc/init.d/mysqld start" >> /etc/rc.d/rc.local
	####
	echo ""
	echo "========================================================================e"
	echo "congratulations, shadowsocks server starting..."
	echo "========================================================================"
	echo "The log file is in /var/log/shadowsocks.log..."
	echo "type your ip into your web browser, you can see the web, also you can configure that at '/var/www/html'"
	echo "========================================================================"
}

#====================
# main
#
#judge whether root or not
if [ "$UID" -eq 0 ];then
read -p "(Please input New MySQL root password):" ROOT_PASSWD
if [ "$ROOT_PASSWD" = "" ]; then
echo "Error: Password can't be NULL!!"
exit 1
fi
	install_soft_for_each
    install_redis
	setup_manyuser_ss
    installNginx
    install_redis
    install_sspanel
    start_SS
#	setup_sspanel
#start_ss
    service mysql restart
    service php5-fpm restart
    service nginx restart
    service redis restart
    supervisorctl restart shadowsocks

else
	echo -e "please run it as root user again !!!\n"
	exit 1
fi
