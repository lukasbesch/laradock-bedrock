#!/bin/bash

# This shell script is an optional tool to simplify
# the installation and usage of laradock in general.

# To run, make sure to add permissions to this file:
# chmod +x laradock.sh

# USAGE EXAMPLE:
# Open bash in workspace: ./laradock.sh bash
# Open bash in workspace as root: ./laradock.sh bash --root
# Composer install: ./laradock.sh -- composer install
# Composer update: ./laradock.sh -- composer update

DOTENVSH_DEBUG=true

load_env () {
    export $(egrep -v '^#' .env | xargs) 2> /dev/null
}

load_env

if [[ -z $USE_DOCKER_SYNC ]]; then
    USE_DOCKER_SYNC=false
    if [[ $DOCKER_SYNC_STRATEGY == "native_osx" ]]; then
        USE_DOCKER_SYNC=true
    fi
fi

# prints colored text
print_style () {

    if [[ "$2" == "info" ]]; then
        COLOR="96m"
    elif [[ "$2" == "success" ]]; then
        COLOR="92m"
    elif [[ "$2" == "warning" ]]; then
        COLOR="93m"
    elif [[ "$2" == "danger" ]]; then
        COLOR="91m"
    else #default color
        COLOR="0m"
    fi

    STARTCOLOR="\e[$COLOR"
    ENDCOLOR="\e[0m"

    printf "$STARTCOLOR%b$ENDCOLOR" "$1"
}

display_options () {
    print_style "laradock.sh\n" "info";
    print_style "Available options:\n" "info";
    print_style "   create" "success"; printf "\t\t\t Creates docker environment.\n"
    print_style "   up" "success"; printf "\t\t\t\t Runs docker compose.\n"
    print_style "   down" "success"; printf "\t\t\t\t Stops containers.\n"
    print_style "   rebuild" "success"; printf "\t\t\t Rebuilds containers.\n"
    print_style "   sync" "success"; printf "\t\t\t\t Manually triggers the synchronization of files.\n"
    print_style "   sync clean" "danger"; printf "\t\t\t Removes all files from docker-sync.\n"
    print_style "   bash [--root]" "success"; printf "\t\t Opens bash on the workspace, optionally as root user.\n"
    print_style "   wp [command]" "success"; printf "\t\t\t Runs WP-CLI\n"
    print_style "   composer [command]" "success"; printf "\t\t Runs Composer in container\n"
    print_style "   theme composer [command]" "success"; printf "\t Runs Composer in theme directory\n"
    print_style "   -- [command]" "success"; printf "\t\t\t Executes any command in workspace.\n"
    print_style "   help" "info"; printf "\t\t\t Help\n"
    print_style "\nExample:" "info"; printf "\t\t ./laradock.sh -- composer install --no-dev --optimize-autoloader\n"
}

function invalid_arguments() {
    print_style $1 $2
    display_options
    exit 1
}

up () {
    if [[ ! -z "$USE_DOCKER_SYNC" ]]; then
        print_style "Initializing docker-sync\n" "info"
        print_style "May take a long time (15min+) on the first run\n" "info"
        docker-sync start;
    fi;
    print_style "Initializing docker-compose\n" "info"
    docker-compose up -d $DEFAULT_WEBSERVER $DEFAULT_DB_SYSTEM;
}

down () {
    print_style "Stopping Docker Compose\n" "info"
    docker-compose stop

    if [[ ! -z "$USE_DOCKER_SYNC" ]]; then
        print_style "Stopping Docker Sync\n" "info"
        docker-sync stop
    fi;

}

rebuild () {
    print_style "Rebuilding docker images \n" "info"
    docker-compose build workspace php-fpm $DEFAULT_WEBSERVER $DEFAULT_DB_SYSTEM;
}

env_copy () {
    while true; do
        print_style "Use the default .env file? (y/n)\n" "warning"
        read -p "" yn
        case $yn in
            [Yy]* ) cp env-example .env; load_env; break;;
            [Nn]* ) exit;;
            * ) echo "Please answer yes or no.";;
        esac
    done
}

database_create () {
    pushd $APP_CODE_PATH_HOST > /dev/null
    FOLDER=${PWD##*/}
    popd > /dev/null
    read -p "Enter DB name (default: $FOLDER): " dbName
    if [[ -z "$dbName" ]]; then
       dbName=$FOLDER
    fi
    dbChar="utf8";
    dbCollate="utf8_unicode_ci";
    docker-compose exec $DEFAULT_DB_SYSTEM bash -c 'mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS \`'$dbName'\` CHARACTER SET '$dbChar' COLLATE '$dbCollate';"'
}

run_bash_command () {
    CDTODIR=$1
    shift
    docker-compose exec --user=laradock workspace bash -c "cd $CDTODIR && $*"
}

docker_sync () {
    if [[ $( gem list '^docker-sync$' -i ) -ne true ]]; then
        print_style "Installing docker-sync\n" "info"
        gem install docker-sync
    fi;

    print_style "Manually triggering sync between host and docker-sync container.\n" "info"
    docker-sync sync;
}
docker_sync_clean () {
    print_style "Removing and cleaning up files from the docker-sync container.\n" "warning"
    docker-sync clean
}

if [[ $# -eq 0 ]] ; then
    invalid_arguments "Missing arguments.\n" "danger"
fi

if [[ "$1" == "create" ]]; then
    print_style "Initializing Docker Compose\n" "info"
    if [[ ! -e .env ]]; then
        print_style "No .env file found!\n" "danger"
        env_copy && up
    else
        up
    fi
    database_create;

elif [[ "$1" == "rebuild" ]]; then
    if [[ ! -f .env ]]; then
        ls; exit;
        print_style "No .env file found!\n" "danger"
        env_copy;
    else
        down
        rebuild && up
    fi

elif [[ "$1" == "up" ]]; then
    if [[ ! -f .env ]]; then
        print_style "No .env file found!\n" "danger"
        env_copy;
    else
        up
    fi

elif [[ "$1" == "down" ]]; then
    down

elif [[ "$1" == "sync" ]]; then
    if [[ "$2" == "clean" ]]; then
        docker_sync_clean
    elif [[ -z $2 ]]; then
        docker_sync
    else
        invalid_arguments "Invalid arguments.\n" "danger"
    fi;

elif [[ "$1" == "bash" ]]; then
    SSHUSER=laradock
    if [[ "$2" == "--root" ]]; then
        SSHUSER=root
    fi
    #print_style "Opens bash on the workspace as $SSHUSER\n" "info"
    docker-compose exec --user=$SSHUSER workspace bash;

elif [[ "$1" == "wp" ]]; then
    run_bash_command . $*

elif [[ "$1" == "composer" ]]; then
    run_bash_command . $*

elif [[ "$1" == "theme" ]]; then
    shift

    if [[ ! -d $APP_CODE_PATH_HOST$THEME_CODE_PATH ]]; then
        print_style "Could not resolve $APP_CODE_PATH_HOST$THEME_CODE_PATH\n Check THEME_CODE_PATH in your .env file.\n" "danger"
    elif [[ "$1" == "composer" ]]; then
        run_bash_command $THEME_CODE_PATH $*
    else
        invalid_arguments "Invalid arguments.\n\nRun ./laradock.sh theme composer [commands]" "danger"
    fi

elif [[ "$1" == "--" ]]; then
    shift # removing first argument
    docker-compose exec --user=laradock workspace bash -c "$*"

elif [[ "$1" == "help" ]]; then
    display_options

else
    invalid_arguments "Invalid arguments.\n" "danger"
fi
