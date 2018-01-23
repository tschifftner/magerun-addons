#!/usr/bin/env bash
#
# Helper for $project ($environment)
#
# @author Tobias Schifftner, @tschifftner, ambimax® GmbH
# @copyright © 2017

PROJECT='${project}'
ENVIRONMENT='${environment}'
BUCKET='${bucket}'
PROJECTSTORAGE="${projectstorage}"
BUILD_FILE="${buildFile}"
ROOT="${root}"
HOSTS="${hosts}"
MAGENTO_ROOT="${magentoRoot}"

DATABASE_NAME="${databaseName}"
DATABASE_HOST="${databaseHost}"
DATABASE_USERNAME="${databaseUsername}"
DATABASE_PASSWORD="${databasePassword}"

# No configuration required
RELEASE_FOLDER="${ROOT}/releases"
#MAGENTO_ROOT="${RELEASE_FOLDER}/current/htdocs"
PRODUCTION_BACKUP="${PROJECTSTORAGE}/${PROJECT}/backup/production"
S3_PRODUCTION_BACKUP="${BUCKET}/${PROJECT}/backup/production"
MAGENTO_DEPLOYSCRIPTS="${PROJECTSTORAGE}/${PROJECT}/bin/deploy"
VHOST_TPL="${vhostTpl}"

# Colors
RED='\033[1;31m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

MAX_AGE=86400
NOW=`date +%s`
VERSION="2.0.0"

APACHE_CONFIG=/usr/local/etc/httpd

function error_exit {
    echo
	echo -e "${RED}\tERROR: ${1}${NC}" 1>&2
	echo
	exit 1
}

function echo_step {
    echo
    echo -e "${YELLOW}#### ${@}${ORANGE}"
}

function run {
    echo "${@}"
    ${@}
}

function run_mysql {
    echo "mysql -e \"${@}\""
    `which mysql` -e "${@}"
}
#
# Available commands
#

function info {
    _header
    echo "Project: $PROJECT"
    echo "Environemnt: $ENVIRONMENT"
    echo "Releases: $RELEASE_FOLDER"
    echo "Storage: $PROJECTSTORAGE"
    echo "Bucket: $BUCKET/$PROJECT/"
    echo "DB Date: " `date -r $(cat ${PRODUCTION_BACKUP}/database/created.txt) '+%d.%m.%Y %H:%M:%S'`
    echo "Files Date: " `date -r $(cat ${PRODUCTION_BACKUP}/files/created.txt) '+%d.%m.%Y %H:%M:%S'`
    echo
}

function install {
    echo_step "Start installation"
    if [ ! -d ${MAGENTO_DEPLOYSCRIPTS} ]; then error_exit "Magento Deployscripts not found"; fi
    run cd ${MAGENTO_DEPLOYSCRIPTS} && run git pull || error_exit "Unable to update magento-deployscripts"
    run ${MAGENTO_DEPLOYSCRIPTS}/deploy.sh -e $ENVIRONMENT -r $BUILD_FILE -t ${ROOT} -d || error_exit "Magento deployment failed"
}

function n98-magerun {
    run cd ${MAGENTO_ROOT} || error_exit "Cannot enter magento root directory"
    run ../tools/n98-magerun.phar ${@} || error_exit "n98-magerun failed"
}

function reindex {
    echo_step "Start reindex"
    run cd ${MAGENTO_ROOT} || error_exit "Cannot change directory"
    run ../tools/n98-magerun.phar index:reindex:all || error_exit "Reindexing all failed"
}

function root {
    run cd ${MAGENTO_ROOT} || error_exit "Cannot change directory"
    bash
}

function self-update
{
    echo_step "Run self-update"
    for D in ~/.n98-magerun/modules/*; do
        if [ -d "${D}" ]; then
            run cd "${D}" || "Cannot access module direcotry"
            run git pull || error_exit "Unable to update git repo ${D}"
        fi
    done

    run n98-magerun project:helper:create ${PROJECT} ${ENVIRONMENT} || error_exit "Failed to create project-helper"
}

function version {
    echo "${VERSION}"
}


#
# brew
#

function brew:install:apache {
#    brew install apache2
#    brew services start apache2

    run sudo apachectl stop || echo ""
    run sudo launchctl unload -w /System/Library/LaunchDaemons/org.apache.httpd.plist 2>/dev/null || echo "Cannot unload autostart of httpd"

    if [ -d /usr/local/Cellar/httpd ]; then
        run brew reinstall httpd24 --with-privileged-ports --with-http2 || error_exit "Reinstallation of httpd24 failed"
    else
        run brew install httpd24 --with-privileged-ports --with-http2 || error_exit "Installation of httpd24 failed"
    fi

    VERSION=`cd /usr/local/Cellar/httpd && ls -dt * | head -n 1`
    run sudo cp -v /usr/local/Cellar/httpd/${VERSION}/homebrew.mxcl.httpd.plist /Library/LaunchDaemons || error_exit "Cannod copy lunch daemon"
    run sudo chown -v root:wheel /Library/LaunchDaemons/homebrew.mxcl.httpd.plist || error_exit "Cannot set permissions on lunch daemon"
    run sudo chmod -v 644 /Library/LaunchDaemons/homebrew.mxcl.httpd.plist || error_exit "Cannot set permissions on lunch daemon"

    setup:apache

    run sudo launchctl load /Library/LaunchDaemons/homebrew.mxcl.httpd.plist || error_exit "Cannot load lunch daemon"
}

function brew:install:dnsmasq {
    brew install dnsmasq
    addToFileIfMissing "^address=\/\.dev" "address=/.dev/127.0.0.1" /usr/local/etc/dnsmasq.conf
    addToFileIfMissing "^address=\/\.local" "address=/.local/127.0.0.1" /usr/local/etc/dnsmasq.conf

    sudo mkdir -v /etc/resolver
    sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolver/dev'
    sudo brew services start dnsmasq
}

function brew:install:bash-completion {
    brew install bash-completion
    brew tap homebrew/completions
    addToFileIfMissing "[ -f /usr/local/etc/bash_completion ] && . /usr/local/etc/bash_completion" ~/.bash_profile
}

function brew:install:mariadb {
    brew install mariadb
    brew services start mariadb

    addToFileIfMissing "^\[client\]" "[client]" ~/.my.cnf
    addToFileIfMissing "^user" "user=root" ~/.my.cnf
    addToFileIfMissing "^password" "password=" ~/.my.cnf
}

function _installPhp {
    version=$1
    run brew unlink php56 || echo ""
    run brew unlink php70 || echo ""
    run brew unlink php71 || echo ""

    if [ -f /usr/local/opt/php${version}/bin/php ]; then
        run brew reinstall php${version} --with-apache
        run brew reinstall --build-from-source php${version}-opcache php${version}-apcu php${version}-mcrypt php${version}-imagick php${version}-pdo-dblib php${version}-yaml php${version}-xdebug php${version}-intl
    else
        run brew install php${version} --with-apache
        run brew install --build-from-source php${version}-opcache php${version}-apcu php${version}-mcrypt php${version}-imagick php${version}-pdo-dblib php${version}-yaml php${version}-xdebug php${version}-intl
    fi

    setup:php-ini
    run brew link php${version} || error_exit "Unable to link php${version}"
}

function brew:install:php56 {
    _installPhp 5.6
}

function brew:install:php70 {
    _installPhp 70
}

function brew:install:php71 {
    _installPhp 71
}


#
# create
#


function create:admin {
    echo_step "Create admin"
    cd ${MAGENTO_ROOT} || error_exit "Magento root not found"
    run ../tools/n98-magerun.phar admin:user:create dev dev@ambimax.de test Test User || error_exit "Cannot create admin"
}

#
# reset
#

function reset:all {
    echo_step "Start reset"
    run ${MAGENTO_DEPLOYSCRIPTS}/project_reset.sh -e $ENVIRONMENT -p ${MAGENTO_ROOT} -s ${PRODUCTION_BACKUP} || error_exit "Reset failed"
}

function reset:config {
    echo_step "Reset project config"
    run cd ${MAGENTO_ROOT} || error_exit "Cannot enter magento root directory"
    run ../vendor/aoepeople/zettr/zettr.phar apply ${ENVIRONMENT} ../config/settings.csv || error_exit "Applying config failed"
}

function reset:db {
    echo_step "Start database reset"
    if [ -z $DATABASE_NAME ]; then error_exit "No database name set"; fi
    echo "gzip -dc ${PRODUCTION_BACKUP}/database/combined_dump.sql.gz | mysql $DATABASE_NAME"
    run $(`which gzip` -dc ${PRODUCTION_BACKUP}/database/combined_dump.sql.gz | `which mysql` $DATABASE_NAME) || error_exit "Unable to import original database"

    # Reset config only when magento root folder exists
    if [ -d ${MAGENTO_ROOT} ]; then
        reset:config
    fi
}


#
# setup
#

function setup:apache
{
    FILE=/usr/local/etc/httpd/httpd.conf

    if [ ! -f $FILE ]; then
        brew:install:apache
    fi

    run sudo mkdir -p ${APACHE_CONFIG}/users || error_exit "Cannot create users dir"
    run sudo mkdir -p ${APACHE_CONFIG}/vhosts || error_exit "Cannot create vhost dir"
    run sudo mkdir -p /private/var/log/apache2 || error_exit "Cannot create log dir"

    GROUP=$(id -g -n $USER)
    run sudo chown -R $USER:$GROUP ${APACHE_CONFIG} || error_exit "Cannot set permissions on ${APACHE_CONFIG}"
    run sudo chown -R $USER:$GROUP /var/log/apache2 || error_exit "Cannot set permissions on /var/log/apache2"
    run sudo chown -R $USER:$GROUP /Library/WebServer || error_exit "Cannot set permissions on /Library/WebServer"

    LIBPHP=/usr/local/opt/php70/libexec/apache2/libphp7.so
    if [ ! -f ${LIBPHP} ]; then
        brew:install:php
    fi

    echo "<Directory "/Users/$USER/">
AllowOverride All
Options Indexes MultiViews FollowSymLinks
Require all granted
</Directory>" > ${APACHE_CONFIG}/users/$USER.conf


#    if [ ! -f "$FILE.original" ]; then
#        cp $FILE ${FILE}.original
#    fi
    cp -f ${FILE}.default $FILE

    VERSION=`cd /usr/local/Cellar/httpd && ls -dt * | head -n 1`
    MODULES_DIR=/usr/local/Cellar/httpd/${VERSION}/lib/httpd/modules

    addToFileIfMissing "# Custom Settings" $FILE
    addToFileIfMissing "ServerName localhost" $FILE
    addToFileIfMissing "Listen 0.0.0.0:80" $FILE
    addToFileIfMissing "User $USER" $FILE
    addToFileIfMissing "Group $GROUP" $FILE
    addToFileIfMissing "^LoadModule authz_core_module" "LoadModule authz_core_module ${MODULES_DIR}/mod_authz_core.so" $FILE
    addToFileIfMissing "^LoadModule authz_host_module" "LoadModule authz_host_module ${MODULES_DIR}/mod_authz_host.so" $FILE
    addToFileIfMissing "LoadModule userdir_module ${MODULES_DIR}/mod_userdir.so" $FILE
    addToFileIfMissing "LoadModule include_module ${MODULES_DIR}/mod_include.so" $FILE
    addToFileIfMissing "LoadModule rewrite_module ${MODULES_DIR}/mod_rewrite.so" $FILE
    addToFileIfMissing "LoadModule deflate_module ${MODULES_DIR}/mod_deflate.so" $FILE
    addToFileIfMissing "LoadModule http2_module ${MODULES_DIR}/mod_http2.so" $FILE
    addToFileIfMissing "LoadModule expires_module ${MODULES_DIR}/mod_expires.so" $FILE
    addToFileIfMissing "LoadModule vhost_alias_module ${MODULES_DIR}/mod_vhost_alias.so" $FILE
    addToFileIfMissing "^LoadModule php7_module" "LoadModule php7_module ${LIBPHP}" $FILE

    addToFileIfMissing "^IncludeOptional ${APACHE_CONFIG}/users/\*.conf" "IncludeOptional ${APACHE_CONFIG}/users/*.conf" $FILE
    addToFileIfMissing "^IncludeOptional ${APACHE_CONFIG}/vhosts/\*.conf" "IncludeOptional ${APACHE_CONFIG}/vhosts/*.conf" $FILE
    addToFileIfMissing "^<FilesMatch \.php\$>" "<FilesMatch \.php$>
    SetHandler application/x-httpd-php
</FilesMatch>" $FILE

    run apachectl -t || error_exit "Wrong apache2 configuration"
    run sudo apachectl stop || echo ""
    run sudo apachectl start || error_exit "Unable to start apache2"
}


function setup:apache:vhost
{
    echo_step "Setup Apache Vhost"
    run mkdir -p ${APACHE_CONFIG}/vhosts || error_exit "Cannot create vhost dir"
    echo "${VHOST_TPL}" > ${APACHE_CONFIG}/vhosts/${PROJECT}-${ENVIRONMENT}.conf || error_exit "Cannot write vhost template"
    run apachectl -t || error_exit "Wrong apache2 configuration"
    run sudo apachectl restart || error_exit "Unable to restart apache2"
}

function setup:cleanup {
    echo_step "Start cleanup"
    run ${MAGENTO_DEPLOYSCRIPTS}/cleanup.sh -r $RELEASE_FOLDER || error_exit "Cleanup failed"
}

function setup:database
{
    echo_step "Setup database"
    run_mysql "create database if not exists ${DATABASE_NAME};" || error_exit "Creation of database failed $?"

    if [[ -z $DATABASE_PASSWORD ]]; then
        run_mysql "GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO ${DATABASE_USERNAME}@'${DATABASE_HOST}';" || error_exit "Unable to grant mysql permissions"
    else
        run_mysql "GRANT ALL PRIVILEGES ON ${DATABASE_NAME}.* TO ${DATABASE_USERNAME}@'${DATABASE_HOST}' IDENTIFIED BY '${DATABASE_PASSWORD}';" || error_exit "Unable to grant mysql permissions"
    fi
    run_mysql "FLUSH PRIVILEGES;" || error_exit "Unable to flush mysql privileges"
}

function setup:deployscripts {
    echo_step "Install/Update deploy scripts"
    run mkdir -p $PROJECTSTORAGE/$PROJECT/bin
    if [ ! -d ${MAGENTO_DEPLOYSCRIPTS} ]; then
        run git clone https://github.com/ambimax/magento-deployscripts.git ${MAGENTO_DEPLOYSCRIPTS} || error_exit "Failed to clone magento-deployscripts"
    else
        cd ${MAGENTO_DEPLOYSCRIPTS} || "Cannot change to magento deployscripts dir"
        run git pull || error_exit "Unable to update magento-deployscripts"
    fi
}

function setup:folders {
    run mkdir -p $RELEASE_FOLDER
    run mkdir -p "${ROOT}/logs"
    run mkdir -p "${ROOT}/shared/media"
    run mkdir -p "${ROOT}/shared/var"
    echo "Folders successfully created"
}

function setup:host
{
    HOSTNAME=$1
    if [ -z $1 ]; then
        HOSTNAME="${PROJECT}.local";
    fi

    addToFileIfMissing "127.0.0.1 ${HOSTNAME}" /etc/hosts
}

function setup:hosts
{
    for host in ${HOSTS}
    do
        setup:host $host
    done
}

function setup:php-ini {
    PHP_INI=`php --ini | grep "Loaded " | sed -e 's/Loaded Configuration File://' | tr -d " "`

    sed -i.bak "s/memory_limit = .*/memory_limit = 1G/" $PHP_INI
    sed -i.bak "s/max_execution_time = .*/max_execution_time = 300/" $PHP_INI
    sed -i.bak "s/max_input_time = .*/max_input_time = 300/" $PHP_INI
    sed -i.bak "s/error_reporting = .*/error_reporting = E_ALL/" $PHP_INI
    sed -i.bak "s/display_errors = .*/display_errors = On/" $PHP_INI
    sed -i.bak "s/display_startup_errors = .*/display_startup_errors = On/" $PHP_INI
    sed -i.bak "s/log_errors = .*/log_errors = On/" $PHP_INI
    sed -i.bak "s/error_log = .*/error_log = php_errors.log/" $PHP_INI
    echo "Settings applied to ${PHP_INI}"
}

function setup:project
{
    if [ -z $DATABASE_NAME ] || [ -z $DATABASE_USERNAME ] || [ -z $DATABASE_PASSWORD ]; then
        echo_step
        echo_step "  Please check if"
        echo_step "    1) database is created"
        echo_step "    2) database user is setup"
        echo_step
        echo_step "  Otherwise install will fail!"
        echo_step
        echo_step "  -> Information can be found in config/settings.csv on github.com"
        echo_step
        read -n1 -r -p "Press key to continue..." key
    else
        setup:database
    fi

    setup:folders
    setup:deployscripts
    sync:fast
    reset:db
    install

    if [[ "${ENVIRONMENT}" = "devbox" ]]; then
        setup:hosts
        setup:apache:vhost
    fi

    echo_step
    echo_step "Setup completed"
    echo_step
}

function setup:n98-magerun:autocompletion
{
    DIR=/etc/bash_completion.d/
    if [ ! -d $DIR ]; then
        DIR=$(brew --prefix)/etc/bash_completion.d
    fi

    if [ -d $DIR ]; then
        wget https://raw.githubusercontent.com/netz98/n98-magerun/master/res/autocompletion/bash/n98-magerun.phar.bash -O $DIR/n98-magerun.phar.bash
    else
        echo "Please install brew:install:bash-completion first"
    fi
}

#
# sync
#

function sync:full {
    echo_step "Start fullsync"
    run aws s3 sync --exact-timestamps --delete ${S3_PRODUCTION_BACKUP} ${PRODUCTION_BACKUP} || error_exit "Fullsync failed"
}

function sync:fast {
    echo_step "Start fastsync"

    DB_CREATED=`cat ${PRODUCTION_BACKUP}/database/created.txt`
    AGE_DB=$((NOW-DB_CREATED))
    if [ -z $1 ] && [ "$AGE_DB" -lt "$MAX_AGE" ] ; then
        echo "DB age ok (${AGE_DB} sec) - skipping...";
    else
        run aws s3 sync --exact-timestamps --delete ${S3_PRODUCTION_BACKUP}/database ${PRODUCTION_BACKUP}/database || error_exit "Database sync failed"
    fi;

    FILES_CREATED=`cat ${PRODUCTION_BACKUP}/files/created.txt`
    AGE_FILES=$((NOW-FILES_CREATED))
    if [ -z $1 ] && [ "$AGE_FILES" -lt "$MAX_AGE" ] ; then
        echo "Files age ok (${AGE_FILES} sec) - skipping...";
    else
        run aws s3 sync --exact-timestamps --delete --exclude "import/*" --exclude "catalog/*" ${S3_PRODUCTION_BACKUP}/files ${PRODUCTION_BACKUP}/files || error_exit "Files sync failed"
    fi;
}


#
# Add string to file when missing
#
# @param $NEEDLE string
# @param $STRING string
# @param $FILE string
#
function addToFileIfMissing
{
    if [ "$#" -eq 2 ]; then
        NEEDLE="^${1}"
        STRING=$1
        FILE=$2
    fi
    if [ "$#" -eq 3 ]; then
        NEEDLE=$1
        STRING=$2
        FILE=$3
    fi

    FOUND=`grep "${NEEDLE}" ${FILE}`
    if [ -n "${FOUND}" ]; then
        echo "Entry '${STRING}' already exists."
    else
        echo "Add '${STRING}'"
        echo "${STRING}" >> ${FILE} || error_exit "Adding ${STRING} to ${FILE} failed"
    fi
}

function _format {
    if [ "$#" -eq 1 ]; then
        echo
        printf "${YELLOW}%-35s\n" "$1"
    fi
    if [ "$#" -eq 2 ]; then
        printf " ${GREEN}%-35s ${NC}%-30s\n" "$1" "$2"
    fi
}

function _header {
echo -e "
${GREEN}${PROJECT}-${ENVIRONMENT} ${NC}version ${YELLOW}$(version)${NC} by ${GREEN}ambimax® GmbH

${YELLOW}Usage:
${NC}  command [options] [arguments]"
}



# run script
if [ `type -t $1`"" == 'function' ]; then
    echo -e "${ORANGE}"
    ${@}
else

    _header

    _format "Available Commands"

    _format "info" "Show settings"
    _format "install" "deploys full project including database import and media synchronisation"
    _format "n98-magerun" "Run n98-magerun commands in project"
    _format "reindex" "Reindex products, categories, search, etc"
    _format "root" "Go to magento root"
    _format "self-update" "Updates n98-magerun modules and this helper ${YELLOW}(beta)"
    _format "version" "Returns version of this helper"

    _format "bew"
    _format "brew:install:apache" "Installs apache2 on mac"
    _format "brew:install:bash-completion" "Installs bash-completion on mac"
    _format "brew:install:dnsmasq" "Installs dnsmasq on mac"
    _format "brew:install:mariadb" "Installs mariadb on mac"
    _format "brew:install:php56" "Installs php 5.6 on mac"
    _format "brew:install:php70" "Installs php 7.0 on mac"
    _format "brew:install:php71" "Installs php 7.1 on mac"

    _format "create"
    _format "create:admin" "Creates admin user 'dev' with password 'test'"

    _format "reset"
    _format "reset:all" "Imports latest database and synchronises media files with projectstorage"
    _format "reset:config" "Reset project config"
    _format "reset:db" "Imports latest synced database and applies project config"

    _format "setup"
    _format "setup:apache" "Setup Apache"
    _format "setup:apache:vhost" "Setup Apache Vhost to ${APACHE_CONFIG}/vhosts/"
    _format "setup:cleanup" "Removes old installed builds from releases folder"
    _format "setup:database" "Setup database"
    _format "setup:deployscripts" "Installs/Updates magento-deployscripts"
    _format "setup:folders" "Create required project folders"
    _format "setup:hosts" "Add all hosts to /etc/hosts"
    _format "setup:n98-magerun:autocompletion" "Add autocompletion for n98-magerun"
    _format "setup:php-ini" "Applies some php.ini settings for development"
    _format "setup:project" "Initial setup full project"

    _format "sync"
    _format "sync:fast" "Synchronises database but only files timestamp file"
    _format "sync:full" "Synchronizes full media in projectstorage folder with aws s3"

    echo
fi