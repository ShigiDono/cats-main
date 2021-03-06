#!/usr/bin/env bash
# user, that executes this script must be in sudo group

#parse command line
step="*"

while [[ $# -gt 1 ]]; do
	key=$1
	case $key in 
	-s|--step)
		step="$2"
		shift
	;;
	*)
		echo 'Unknown option: '
		tail -1 $key
		exit
	;;
	esac
	shift
done
if [[ -n $1 ]]; then
	echo "Last option not have argument: "
	tail -1 $1
	exit
fi

CATS_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )" # assume, that script is in a root dir of repo

# PROXY USERS, PLEASE READ THIS
# If your network is behind proxy please uncomment and set following variables
#export http_proxy=host:port
#export https_proxy=$http_proxy
#export ftp_proxy=$http_proxy
#
# You also NEED to replace following line in /etc/sudoers:
# Defaults        env_reset
# With:
# Defaults env_keep="http_proxy https_proxy ftp_proxy"

# Group, apache running under
http_group=www-data

echo "1. Install apt packages... "
if [[ $step =~ (^|,)1(,|$)  || $step == "*" ]]; then
	packages=(git firebird2.5-dev firebird2.5-classic build-essential libaspell-dev
		aspell-en aspell-ru apache2 libapache2-mod-perl2 libapreq2-3 libapreq2-dev
		libapache2-mod-perl2-dev libexpat1 libexpat1-dev libapache2-request-perl cpanminus)
	sudo apt-get -y install ${packages[@]}
	echo "ok"
else
	echo "skip"
fi

echo "2. Install cpan packages... "
if [[ $step =~ (^|,)2(,|$) || $step == "*" ]]; then
	cpan_packages=(DBI DBD::Firebird Algorithm::Diff Text::Aspell SQL::Abstract Archive::Zip
	    JSON::XS YAML::Syck Apache2::Request XML::Parser::Expat Template Authen::Passphrase)
	sudo cpanm -S ${cpan_packages[@]}
	echo "ok"
else
	echo "skip"
fi

echo "3. Init and update submodules... "
if [[ $step =~ (^|,)3(,|$) || $step == "*" ]]; then
	git submodule init
	git submodule update
	echo "ok"
else
	echo "skip"
fi


echo "4. Install formal input... "
if [[ $step =~ (^|,)4(,|$) || $step == "*" ]]; then
	formal_input='https://github.com/downloads/klenin/cats-main/FormalInput.tgz'
	wget $formal_input -O fi.tgz
	tar -xzvf fi.tgz
	pushd FormalInput/
	perl Makefile.PL
	make
	sudo make install
	popd
	rm fi.tgz
	rm -rf FormalInput
	echo "ok"
else
	echo "skip"
fi

echo "5. Generating docs... "
if [[ $step =~ (^|,)5(,|$) || $step == "*" ]]; then
	cd docs/tt
	ttree -f ttreerc
	cd $CATS_ROOT
	echo "ok"
else
	echo "skip"
fi

echo "6. Configure Apache... "
if [[ $step =~ (^|,)6(,|$) || $step == "*" ]]; then
APACHE_CONFIG=$(cat <<EOF
PerlSetEnv CATS_DIR ${CATS_ROOT}/cgi-bin/
<VirtualHost *:80>
	PerlRequire ${CATS_ROOT}/cgi-bin/CATS/Web/startup.pl
	<Directory "${CATS_ROOT}/cgi-bin/">
		Options -Indexes
		LimitRequestBody 1048576
		Require all granted
		PerlSendHeader On
		SetHandler perl-script
		PerlResponseHandler main
	</Directory>
	ExpiresActive On
	ExpiresDefault "access plus 5 seconds"
	ExpiresByType text/css "access plus 1 week"
	ExpiresByType application/javascript "access plus 1 week"
	ExpiresByType image/gif "access plus 1 week"
	ExpiresByType image/png "access plus 1 week"
	ExpiresByType image/x-icon "access plus 1 week"

	Alias /cats/static/ "${CATS_ROOT}/static/"
	<Directory "${CATS_ROOT}/static">
		# Apache allows only absolute URL-path
		ErrorDocument 404 /cats/main.pl?f=static
		#Options FollowSymLinks
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/download/ "${CATS_ROOT}/download/"
	<Directory "${CATS_ROOT}/download">
		Options -Indexes
		Require all granted
	</Directory>

	Alias /cats/docs/ "${CATS_ROOT}/docs/"
	<Directory "${CATS_ROOT}/docs">
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	Alias /cats/ev/ "${CATS_ROOT}/ev/"
	<Directory "${CATS_ROOT}/ev">
		AddDefaultCharset utf-8
		Require all granted
	</Directory>

	<Directory "${CATS_ROOT}/docs/std/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>

	<Directory "${CATS_ROOT}/images/std/">
		AllowOverride Options=Indexes,MultiViews,ExecCGI FileInfo
		Require all granted
	</Directory>

	Alias /cats/synh/ "${CATS_ROOT}/synhighlight/"
	Alias /cats/images/ "${CATS_ROOT}/images/"
	Alias /cats/js/ "${CATS_ROOT}/js/"
	Alias /cats/ "${CATS_ROOT}/cgi-bin/"
</VirtualHost>
EOF
)
	
	sudo sh -c "echo '$APACHE_CONFIG' > /etc/apache2/sites-available/000-cats.conf"
	sudo a2ensite 000-cats
	sudo a2dissite 000-default
	sudo a2enmod expires
	sudo a2enmod apreq2
	# now adjust permissions
	sudo chgrp -R ${http_group} cgi-bin download static templates tt
	chmod -R g+r cgi-bin
	chmod g+rw static tt download/{,att,img,pr,vis} cgi-bin/rank_cache{,/r}
	sudo service apache2 reload
	echo "ok"
else
	echo "skip"
fi

echo "7. Configure and init cats database... "
if [[ $step =~ (^|,)7(,|$) || $step == "*" ]]; then
	CONFIG_NAME="Config.pm"
	CONFIG_ROOT="${CATS_ROOT}/cgi-bin/cats-problem/CATS"
	CREATE_DB_NAME="create_db.sql"
	CREATE_DB_ROOT="${CATS_ROOT}/sql/interbase"
	FB_ALIASES="/etc/firebird/2.5/aliases.conf"

	CONFIG="$CONFIG_ROOT/$CONFIG_NAME"
	cp "$CONFIG_ROOT/${CONFIG_NAME}.template" $CONFIG

	CREATE_DB="$CREATE_DB_ROOT/$CREATE_DB_NAME"
	cp "$CREATE_DB_ROOT/${CREATE_DB_NAME}.template" $CREATE_DB

	echo -e "...\n...\n..."

	answer=""
	while [ "$answer" != "y" -a "$answer" != "n" ]; do
	   echo -n "Do you want to do the automatic setup? "
	   read answer
	done

	if [ "$answer" = "n" ]; then
	   echo -e "Setup is done, you need to do following manualy:\n"
	   echo -e " 1. Navigate to ${CONFIG_ROOT}/"
	   echo -e " 2. Adjust your database connection settings in ${CONFIG_NAME}"
	   echo -e " 3. Navigate to ${CREATE_DB_ROOT}/"
	   echo -e " 4. Adjust your database connection settings in ${CREATE_DB_NAME} and create database\n"
	   exit 0
	fi

	def_path_to_db="$HOME/.cats/cats.fdb"
	def_db_host="localhost"

	read -e -p "Path to database: " -i $def_path_to_db path_to_db
	read -e -p "Host: " -i $def_db_host db_host
	read -e -p "Username: " db_user
	read -e -p "Password: " db_pass

	sudo sh -c "echo 'cats=$path_to_db' > $FB_ALIASES"

	if [[ "$path_to_db" = "$def_path_to_db" ]]; then
		mkdir "$HOME/.cats"
	fi

	sed -i -e "s/<path-to-your-database>/cats/g" $CONFIG
	sed -i -e "s/<your-host>/$db_host/g" $CONFIG
	sed -i -e "s/<your-username>/$db_user/g" $CONFIG
	sed -i -e "s/<your-password>/$db_pass/g" $CONFIG

	sed -i -e "s/<path-to-your-database>/cats/g" $CREATE_DB
	sed -i -e "s/<your-username>/$db_user/g" $CREATE_DB
	sed -i -e "s/<your-password>/$db_pass/g" $CREATE_DB

	sudo chown firebird.firebird $(dirname "$path_to_db")
	cd "$CREATE_DB_ROOT"
	sudo isql-fb -i "$CREATE_DB_NAME"
	cd "$CATS_ROOT"
	echo "ok"
else
	echo "skip"
fi
