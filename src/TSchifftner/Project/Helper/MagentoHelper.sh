#!/usr/bin/env bash
#
# Helper for $project ($environment)
# @author Tobias Schifftner, @tschifftner, ambimax® GmbH
# @copyright © 2017

PROJECT='${project}'
ENVIRONMENT='${environment}'
S3BUCKET='${s3bucket}'
PROJECTSTORAGE="${projectstorage}"
RELEASE_FOLDER="${releaseFolder}"
BUILD_FILE="${buildFile}"

# Magento deployment default functions
function fullsync {
    aws s3 cp $S3BUCKET/$PROJECT/backup/production/database/created.txt $PROJECTSTORAGE/$PROJECT/backup/production/database/created.txt
    aws s3 cp $S3BUCKET/$PROJECT/backup/production/files/created.txt $PROJECTSTORAGE/$PROJECT/backup/production/files/created.txt
    aws s3 sync --delete $S3BUCKET/$PROJECT/backup/production $PROJECTSTORAGE/$PROJECT/backup/production
}

function fastsync {
    aws s3 cp $S3BUCKET/$PROJECT/backup/production/database/created.txt $PROJECTSTORAGE/$PROJECT/backup/production/database/created.txt
    aws s3 cp $S3BUCKET/$PROJECT/backup/production/files/created.txt $PROJECTSTORAGE/$PROJECT/backup/production/files/created.txt
    aws s3 sync --delete $S3BUCKET/$PROJECT/backup/production/database $PROJECTSTORAGE/$PROJECT/backup/production/database
    aws s3 sync --delete --exclude "import/*" --exclude "catalog/*" $S3BUCKET/$PROJECT/backup/production/files $PROJECTSTORAGE/$PROJECT/backup/production/files
}

function reindex {
    cd $RELEASE_FOLDER/current/htdocs && ../tools/n98-magerun.phar index:reindex:all
}

function install {
    $PROJECTSTORAGE/$PROJECT/bin/deploy/deploy.sh -e $ENVIRONMENT -r $BUILD_FILE -t ~/www/$PROJECT/$ENVIRONMENT -d
}

function reset {
    $PROJECTSTORAGE/$PROJECT/bin/deploy/project_reset.sh -e $ENVIRONMENT -p $RELEASE_FOLDER/current/htdocs/ -s $PROJECTSTORAGE/$PROJECT/backup/production
}

function cleanup {
    $PROJECTSTORAGE/$PROJECT/bin/deploy/cleanup.sh -r $RELEASE_FOLDER
}

function create-admin {
    cd $RELEASE_FOLDER/current/htdocs && ../tools/n98-magerun.phar admin:user:create dev dev@ambimax.de test Test User
}

function info {
    echo "Project: $PROJECT"
    echo "Environemnt: $ENVIRONMENT"
    echo "Releases: $RELEASE_FOLDER"
    echo "Storage: $PROJECTSTORAGE"
    echo "s3: $S3BUCKET/$PROJECT/"
    echo "DB Date: " `date -r $(cat $PROJECTSTORAGE/$PROJECT/backup/production/database/created.txt) '+%d.%m.%Y %H:%M:%S'`
    echo "Files Date: " `date -r $(cat $PROJECTSTORAGE/$PROJECT/backup/production/files/created.txt) '+%d.%m.%Y %H:%M:%S'`
}

function setup {
    mkdir -p $RELEASE_FOLDER
    mkdir -p "$RELEASE_FOLDER/../shared/media"
    mkdir -p "$RELEASE_FOLDER/../shared/var"
    mkdir -p $PROJECTSTORAGE/$PROJECT/bin
    if [ ! -d $PROJECTSTORAGE/$PROJECT/bin/deploy ]; then
        git clone https://github.com/ambimax/magento-deployscripts.git $PROJECTSTORAGE/$PROJECT/bin/deploy
    else
        (cd $PROJECTSTORAGE/$PROJECT/bin/deploy && git pull)
    fi
    fastsync
    gzip -dc $PROJECTSTORAGE/$PROJECT/backup/production/database/combined_dump.sql.gz | mysql $PROJECT
    install
}


# run script
if [ `type -t $1`"" == 'function' ]; then
    current=$(pwd)
    echo -e "\e[93m" && $@ && echo -e "\e[0m"
    cd $current
else
echo -e "
    \e[91mdelphin (devbox)\e[0m - helper script

    USAGE:

    \e[0;32mfullsync \e[0m
    Synchronizes full media in projectstorage folder with aws s3

    \e[0;32mfastsync \e[0m
    Synchronises database but only files timestamp file

    \e[0;32minstall \e[0m
    deploys full project including database import and media synchronisation

    \e[0;32mreset \e[0m
    Imports latest database and synchronises media files with projectstorage

    \e[0;32mreindex \e[0m
    Reindex products, categories, search, etc

    \e[0;32mcleanup \e[0m
    Removes old installed builds from releases folder




    \e[0;32mcreate-admin \e[0m
    Creates admin user 'dev' with password 'test'

    \e[0;32msetup \e[0m
    Initial setup full project

"
fi