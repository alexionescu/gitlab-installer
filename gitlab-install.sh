#!/bin/bash

# GITLAB 5.1 Install Script
# Author: Alex Ionescu <ionescuac@gmail.com>
# This script performs an automatic install of Gitlab 5.1
# Tested on clean install of Ubuntu 12.04 LTS x64 & 13.04 x64


# Test if we have root
if [ "$(id -u)" -ne "0" ] ; then
	echo -e "\e[1;31mThis script must be run as root!\e[0m"
	exit
fi

# Config questions
echo -n "Enter the domain/IP GitLab will be accessible from (git.exmaple.com): "
read domain

if [ -z $domain ] ; then
	echo -e "\e[1;31mNo domain entered!\e[0m"
	exit
fi

echo -n "Enter a preferred password for the root and gitlab MySQL accounts. If blank the script will generate a random password for you: "
read -s userPassword

if [ $userPassword ] ; then
	echo -ne "\nVerify password: "
	read -s userPasswordVerify
	if [ "$userPassword" != "$userPasswordVerify" ] ; then
		echo -e "\n\e[1;31mPasswords did not match!\e[0m"
		exit
	fi
fi
 
# Packages/Dependencies
echo -e "\n\e[1;36mInstalling GitLab for domain: $domain\e[0m"
sleep 1
echo -e "\e[1;36mUpdating your system and downloading dependencies\e[0m"
sleep 2
apt-get update -y
apt-get upgrade -y
apt-get install -y sudo
apt-get install -y build-essential \
		zlib1g-dev \
		libyaml-dev \
		libssl-dev \
		libgdbm-dev \
		libreadline-dev \
		libncurses5-dev \
		libffi-dev \
		curl \
		git-core \
		openssh-server \
		redis-server \
		checkinstall \
		libxml2-dev \
		libxslt-dev \
		libcurl4-openssl-dev \
		libicu-dev \
		python \
		libpq-dev
debconf-set-selections <<< "postfix postfix/mailname string $domain"
debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
apt-get install -y postfix

# Download/combile ruby
echo -e "\e[1;36mDownloading and compiling ruby\e[0m"
mkdir /tmp/ruby && cd /tmp/ruby
curl --progress http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.3-p392.tar.gz | tar xz
cd ruby-1.9.3-p392
./configure
make
sudo make install
sudo gem install bundler

# Create GitLab user
echo -e "\e[1;36mCreating git user for GitLab\e[0m"
sudo adduser --disabled-login --gecos 'GitLab' git

# GitLab Shell
echo -e "\e[1;36mInstalling GitLab shell\e[0m"
sleep 2
sudo -u git -H sh -c "cd /home/git;
git clone https://github.com/gitlabhq/gitlab-shell.git;
cd gitlab-shell;
git checkout v1.3.0;
cp config.yml.example config.yml;
sed -i 's/localhost/$domain/g' config.yml;
./bin/install;"

# MySQL install
echo -e "\e[1;36mInstalling MySql\e[0m"
sleep 2
if [ -z $userPassword ] ; then
	apt-get install -y makepasswd # needed to create unique password non-interactively
# 
	userPassword=$(makepasswd --char=12) #generate random MySQL password
fi
# Next few lines creates cleartext copy of password only readable by root,
# will be deleted automatically by the package manager after install
debconf-set-selections <<< "mysql-server mysql-server/root_password password $userPassword"
debconf-set-selections <<< "mysql-server mysql-server/root_password_again password $userPassword" 
apt-get install -y mysql-server mysql-client libmysqlclient-dev
mysql -uroot -p$userPassword -Bse "FLUSH PRIVILEGES;CREATE USER 'gitlab'@'localhost' IDENTIFIED BY '$userPassword';CREATE DATABASE IF NOT EXISTS \`gitlabhq_production\` DEFAULT CHARACTER SET \`utf8\` COLLATE \`utf8_unicode_ci\`; GRANT SELECT, LOCK TABLES, INSERT, UPDATE, DELETE, CREATE, DROP, INDEX, ALTER ON \`gitlabhq_production\`.* TO 'gitlab'@'localhost';"

# GitLab Install
echo -e "\e[1;36mInstalling GitLab\e[0m"
sleep 2
sudo -u git -H sh -c "cd /home/git;
git clone https://github.com/gitlabhq/gitlabhq.git gitlab;
cd /home/git/gitlab;
git checkout 5-1-stable;
cp config/gitlab.yml.example config/gitlab.yml;
sed -i 's/localhost/$domain/g' config/gitlab.yml;"
sudo chown -R git /home/git/gitlab/log
sudo chown -R git /home/git/gitlab/tmp
sudo chmod -R u+rwX /home/git/gitlab/log
sudo chmod -R u+rwX /home/git/gitlab/tmp
sudo -u git -H sh -c "cd /home/git mkdir gitlab-satellites;
cd /home/git/gitlab/;
mkdir tmp/pids/;
mkdir tmp/sockets/;"
sudo chmod -R u+rwX /home/git/gitlab/tmp/pids
sudo chmod -R u+rwX /home/git/gitlab/tmp/sockets
sudo -u git -H sh -c "cd /home/git/gitlab;
cp config/puma.rb.example config/puma.rb;
cp config/database.yml.mysql config/database.yml
sed -i 's/root/gitlab/g' config/database.yml
sed -i 's/\"secure password\"/$userPassword/g' config/database.yml;"

# Install Gems
echo -e "\e[1;36mInstalling Gems\e[0m"
cd /home/git/gitlab
sudo gem install charlock_holmes --version '0.6.9'
sudo -u git -H bundle install --deployment --without development test postgress

# Initialize Database and Activate Advanced Features
echo -e "\e[1;36mInitialize database and activate advanced features\e[0m"
echo "yes" | sudo -u git -H bundle exec rake gitlab:setup RAILS_ENV=production

# Install init script
echo -e "\e[1;36mInstall init script\e[0m"
sleep 2
sudo curl --output /etc/init.d/gitlab https://raw.github.com/gitlabhq/gitlabhq/master/lib/support/init.d/gitlab
sudo chmod +x /etc/init.d/gitlab
sudo update-rc.d gitlab defaults 21

# Start GitLab
sudo service gitlab start

# Install nginx
echo -e "\e[1;36mInstalling nginx\e[0m"
sleep 2
sudo apt-get install -y nginx
sudo curl --output /etc/nginx/sites-available/gitlab https://raw.github.com/gitlabhq/gitlabhq/master/lib/support/nginx/gitlab
sudo ln -s /etc/nginx/sites-available/gitlab /etc/nginx/sites-enabled/gitlab
sed -i "s/YOUR_SERVER_FQDN/$domain/g" /etc/nginx/sites-available/gitlab
ip=`ifconfig | grep 'inet addr:' | grep -v '127.0.0.1' | cut -d: -f2 | awk '{ print $1 }'`
sed -i "s/YOUR_SERVER_IP/$ip/g" /etc/nginx/sites-available/gitlab 
sudo service nginx stop 
sudo service gitlab stop

rm /home/git/gitlab/tmp/sockets/*

sudo service gitlab start
sudo service nginx start

echo -e "\e[1;36m####################################################\e[0m"
echo -e "\e[1;36m#### Please wait 2-3 minutes while GitLab starts.\e[0m"
echo -e "\e[1;36m#### Domain: $domain\e[0m"
echo -e "\e[1;36m#### IP: $ip\e[0m"
if [ -z $userPasswordVerify ] ; then
	echo -e "\e[1;36m#### MySQL root and gitlab passwords: $userPassword\e[0m"
fi
echo -e "\e[1;36m#### http://$ip\e[0m"
echo -e "\e[1;36m#### Username: admin@local.host\e[0m"
echo -e "\e[1;36m#### Password: 5iveL!fe\e[0m"
echo -e "\e[1;36m####################################################\e[0m"
