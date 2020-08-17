#!/bin/bash

# Common functions definitions

function get_setup_params_from_configs_json
{
    local configs_json_path=${1}    # E.g., /var/lib/cloud/instance/wordpress_on_azure_configs.json

    (dpkg -l jq &> /dev/null) || (apt -y update; apt -y install jq)

    # Wait for the cloud-init write-files user data file to be generated (just in case)
    local wait_time_sec=0
    while [ ! -f "$configs_json_path" ]; do
        sleep 15
        let "wait_time_sec += 15"
        if [ "$wait_time_sec" -ge "1800" ]; then
            echo "Error: Cloud-init write-files didn't complete in 30 minutes!"
            return 1
        fi
    done

    local json=$(cat $configs_json_path)
    export glusterNode=$(echo $json | jq -r .fileServerProfile.glusterVmName)
    export glusterVolume=$(echo $json | jq -r .fileServerProfile.glusterVolName)
    export siteFQDN=$(echo $json | jq -r .siteProfile.siteURL)
    export httpsTermination=$(echo $json | jq -r .siteProfile.httpsTermination)
    export dbIP=$(echo $json | jq -r .dbServerProfile.fqdn)
    export dbadminlogin=$(echo $json | jq -r .dbServerProfile.adminLogin)
    export dbadminloginazure=$(echo $json | jq -r .dbServerProfile.adminLoginAzure)
    export dbadminpass=$(echo $json | jq -r .dbServerProfile.adminPassword)
    export storageAccountName=$(echo $json | jq -r .wordpressProfile.storageAccountName)
    export storageAccountKey=$(echo $json | jq -r .wordpressProfile.storageAccountKey)
    export redisDeploySwitch=$(echo $json | jq -r .wordpressProfile.redisDeploySwitch)
    export redisDns=$(echo $json | jq -r .wordpressProfile.redisDns)
    export redisAuth=$(echo $json | jq -r .wordpressProfile.redisKey)
    export dbServerType=$(echo $json | jq -r .dbServerProfile.type)
    export fileServerType=$(echo $json | jq -r .fileServerProfile.type)
    export mssqlDbServiceObjectiveName=$(echo $json | jq -r .dbServerProfile.mssqlDbServiceObjectiveName)
    export mssqlDbEdition=$(echo $json | jq -r .dbServerProfile.mssqlDbEdition)
    export mssqlDbSize=$(echo $json | jq -r .dbServerProfile.mssqlDbSize)
    export thumbprintSslCert=$(echo $json | jq -r .siteProfile.thumbprintSslCert)
    export thumbprintCaCert=$(echo $json | jq -r .siteProfile.thumbprintCaCert)
    export syslogServer=$(echo $json | jq -r .wordpressProfile.syslogServer)
    export htmlLocalCopySwitch=$(echo $json | jq -r .wordpressProfile.htmlLocalCopySwitch)
    export nfsVmName=$(echo $json | jq -r .fileServerProfile.nfsVmName)
    export nfsHaLbIP=$(echo $json | jq -r .fileServerProfile.nfsHaLbIP)
    export nfsHaExportPath=$(echo $json | jq -r .fileServerProfile.nfsHaExportPath)
    export nfsByoIpExportPath=$(echo $json | jq -r .fileServerProfile.nfsByoIpExportPath)
    export phpVersion=$(echo $json | jq -r .phpProfile.phpVersion)
    export cmsApplication=$(echo $json | jq -r .wordpressProfile.cmsApplication)
    export lbDns=$(echo $json | jq -r .wordpressProfile.lbDns)
    export applicationDbName=$(echo $json | jq -r .wordpressProfile.applicationDbName)
    export wpAdminPass=$(echo $json | jq -r .wordpressProfile.wpAdminPass)
    export wpDbUserPass=$(echo $json | jq -r .wordpressProfile.wpDbUserPass)
    export wpVersion=$(echo $json | jq -r .wordpressProfile.wpVersion)
    export sshUsername=$(echo $json | jq -r .wordpressProfile.sshUsername)
    export fileServerDiskSize=$(echo $json | jq -r .fileServerProfile.fileServerDiskSize)
}

function get_php_version {
# Returns current PHP version, in the form of x.x, eg 7.2 or 7.4
    if [ -z "$_PHPVER" ]; then
        _PHPVER=`/usr/bin/php -r "echo PHP_VERSION;" | /usr/bin/cut -c 1,2,3`
    fi
    echo $_PHPVER
}

function create_database {
    local dbIP=$1
    local dbadminloginazure=$2
    local dbadminpass=$3
    local applicationDbName=$4
    local wpDbUserId=$5
    local wpDbUserPass=$6

    # create database for application
    mysql -h $dbIP -u $dbadminloginazure -p$dbadminpass -e "CREATE DATABASE $applicationDbName CHARACTER SET utf8;"
    # grant user permission for database
    mysql -h $dbIP -u $dbadminloginazure -p$dbadminpass -e "GRANT ALL ON $applicationDbName.* TO $wpDbUserId IDENTIFIED BY '$wpDbUserPass';"
}

function download_wordpress {
    local wordpressPath=/wordpress/html
    #local path=/var/lib/waagent/custom-script/download/0
    local siteFQDN=$1
    local version=$2

    cd $wordpressPath
    wget https://wordpress.org/wordpress-$version.tar.gz
    tar -xvf $wordpressPath/wordpress-$version.tar.gz
    rm $wordpressPath/wordpress-$version.tar.gz
    mv $wordpressPath/wordpress $wordpressPath/$siteFQDN
}

function create_wpconfig {
    local dbIP=$1
    local applicationDbName=$2
    local dbadminloginazure=$3
    local dbadminpass=$4
    local siteFQDN=$5

    cat <<EOF >/wordpress/html/$siteFQDN/wp-config.php
  <?php
  /**
  * Following configration file will be updated in the wordpress folder in runtime 
  *
  * Following configurations: Azure Database for MySQL server settings, Table Prefix,
  * Secret Keys, WordPress Language, and ABSPATH. 
  * 
  * wp-config.php  file is used during the installation.
  * Copy the wp-config file to wordpress folder.
  *
  */
  // ** Azure Database for MySQL server settings - You can get the following details from Azure Portal** //
  /** Database name for WordPress */
  define('DB_NAME', '$applicationDbName');
  /** username for MySQL database */
  define('DB_USER', '$dbadminloginazure');
  /** password for MySQL database */
  define('DB_PASSWORD', '$dbadminpass');
  /** Azure Database for MySQL server hostname */
  define('DB_HOST', '$dbIP');
  /** Database Charset to use in creating database tables. */
  define('DB_CHARSET', 'utf8');
  /** The Database Collate type. Don't change this if in doubt. */
  define('DB_COLLATE', '');
  /**
  * Authentication Unique Keys and Salts.
  * You can generate unique keys and salts at https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service
  * You can change these at any point in time to invalidate all existing cookies.
  */
  define('AUTH_KEY',         'h|Eu6ge.=Ej?fyV]/sHw:Ur~>(tkhZH(S^I[DHjE+OD}^MsG\`j0a/y8.n]@L8P{o');
  define('SECURE_AUTH_KEY',  '\`D2d-b,i1YmFQqOy/^]#p_G^fSXWyPm]e:)}H~BVIG\`>vG\$AnnYqUj^#*pPB;*,j');
  define('LOGGED_IN_KEY',    'Wqfh/&|XT| \$o0xeb+%Xf|_N;9Dpp19nzlB& b4w0I.D1;q<|-{4ajT\$JT(QF<@6');
  define('NONCE_KEY',        '89mwVzZXf2-[qjN+k-]#lbg8+>gxO%Fso9;-ptiUwqFS_4x-u\$6I<d,~v=mF2__|');
  define('AUTH_SALT',        't#ry@FfhD3,Y(lZf7+*V,&5rs(&\$xP,tz6[*<_&&CJW/]?2![NEQhsIi2vm-NYlZ');
  define('SECURE_AUTH_SALT', '9zIjp#dKMLLi{&Ag[Ig0Q]oP[[jN qNz<_Z= Gx#Ig/mi>k-J(oE6Prr&L[zR5Vp');
  define('LOGGED_IN_SALT',   '+(B*,@@5eH<?Mq7t-04>b>F%~C!6,+g?vf:w8N(Ne+nwA85N^U54#LHhssf1=>ap');
  define('NONCE_SALT',       'drEw_Z[MD z7Jv,t;WuR8&Q #z? D0c8RR!v*~mkSW1-PlXa9Bl>5&b|=Xe{z9a^');
  /**
  * WordPress Database Table prefix.
  *
  * You can have multiple installations in one database if you give each a unique prefix.
  * Only numbers, letters, and underscores are allowed.
  */
  \$table_prefix  = 'wp_';
  /**
  * WordPress Localized Language, defaults language is English.
  *
  * A corresponding MO file for the chosen language must be installed to wp-content/languages. 
  */
  define('WPLANG', '');
  /**
  * For developers: Debugging mode for WordPress.
  * Change WP_DEBUG to true to enable the display of notices during development.
  * It is strongly recommended that plugin and theme developers use WP_DEBUG in their development environments.
  */
  define('WP_DEBUG', false);
  /** Disable Automatic Updates Completely */
  define( 'AUTOMATIC_UPDATER_DISABLED', True );
  /** Define AUTOMATIC Updates for Components. */
  define( 'WP_AUTO_UPDATE_CORE', True );
  /** Absolute path to the WordPress directory. */
  if ( !defined('ABSPATH') )
    define('ABSPATH', dirname(__FILE__) . '/');
  /** Sets up WordPress vars and included files. */
  require_once(ABSPATH . 'wp-settings.php');
  /** Avoid FTP credentails. */
  define('FS_METHOD','direct');
EOF
}

function install_wp_cli {
    cd /tmp
    wget https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
    chmod +x /tmp/wp-cli.phar
    mv /tmp/wp-cli.phar /usr/local/bin/wp
}

function install_wordpress {
    local lbDns=$1
    local wpTitle=$2
    local wpAdminUser=$3
    local wpAdminPassword=$4
    local wpAdminEmail=$5
    local wpPath=$6

    wp core install --url=https://$lbDns --title=$wpTitle --admin_user=$wpAdminUser --admin_password=$wpAdminPassword --admin_email=$wpAdminEmail --path=$wpPath --allow-root
}

function install_plugins {
    local path=$1
    wp plugin install woocommerce --path=$path --allow-root
    wp plugin activate woocommerce --path=$path --allow-root
    wp plugin activate akismet --path=$path --allow-root
    chown -R www-data:www-data $path
}

function linking_data_location {
    local dataPath=/wordpress/data
    mkdir -p $dataPath/$1
    mkdir -p $dataPath/$1/wp-content
    mv /wordpress/html/$1/wp-content /tmp/wp-content
    ln -s $dataPath/$1/wp-content /wordpress/html/$1/
    mv /tmp/wp-content/* $dataPath/$1/wp-content/
    chmod 0755 $dataPath/$1/wp-content
    chown -R www-data:www-data $dataPath/$1
}

function generate_sslcerts {
    local path=/wordpress/certs/$1
    mkdir -p $path
    echo -e "Generating SSL self-signed certificate"
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $path/nginx.key -out $path/nginx.crt -subj "/C=US/ST=WA/L=Redmond/O=IT/CN=$1"
    chmod 400 $path/nginx.*
    chown www-data:www-data $path/nginx.*
    chown -R www-data:www-data /wordpress/data/$1
}

function generate_text_file {
    local dnsSite=$1
    local username=$2
    local passw=$3
    local dbIP=$4
    local wpDbUserId=$5
    local wpDbUserPass=$6
    local sshUsername=$7

    cat <<EOF >/home/$sshUsername/wordpress.txt
WordPress Details
WordPress site name: $dnsSite
username: $username
password: $passw

Database details
db server name: $dbIP
wpDbUserId: $wpDbUserId
wpDbUserPass: $wpDbUserPass

EOF
}

function install_php_mssql_driver
{
    # Download and build php/mssql driver
    /usr/bin/curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add -
    /usr/bin/curl https://packages.microsoft.com/config/ubuntu/16.04/prod.list > /etc/apt/sources.list.d/mssql-release.list
    sudo apt-get update
    sudo ACCEPT_EULA=Y apt-get install msodbcsql mssql-tools unixodbc-dev -y
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bash_profile
    echo 'export PATH="$PATH:/opt/mssql-tools/bin"' >> ~/.bashrc
    source ~/.bashrc

    #Build mssql driver
    /usr/bin/pear config-set php_ini `php --ini | grep "Loaded Configuration" | sed -e "s|.*:\s*||"` system
    /usr/bin/pecl install sqlsrv
    /usr/bin/pecl install pdo_sqlsrv
    PHPVER=$(get_php_version)
    echo "extension=sqlsrv.so" >> /etc/php/$PHPVER/fpm/php.ini
    echo "extension=pdo_sqlsrv.so" >> /etc/php/$PHPVER/fpm/php.ini
    echo "extension=sqlsrv.so" >> /etc/php/$PHPVER/cli/php.ini
    echo "extension=pdo_sqlsrv.so" >> /etc/php/$PHPVER/cli/php.ini
}

function check_fileServerType_param
{
    local fileServerType=$1
    if [ "$fileServerType" != "gluster" -a "$fileServerType" != "azurefiles" -a "$fileServerType" != "nfs" -a "$fileServerType" != "nfs-ha" -a "$fileServerType" != "nfs-byo" ]; then
        echo "Invalid fileServerType ($fileServerType) given. Only 'gluster', 'azurefiles', 'nfs', 'nfs-ha' or 'nfs-byo' are allowed. Exiting"
        exit 1
    fi
}

function create_azure_files_share
{
    local shareName=$1
    local storageAccountName=$2
    local storageAccountKey=$3
    local logFilePath=$4
    local fileServerDiskSize=$5

    az storage share create \
        --name $shareName \
        --account-name $storageAccountName \
        --account-key $storageAccountKey \
        --fail-on-exist >> $logFilePath \
        --quota $fileServerDiskSize
}

function setup_and_mount_gluster_share
{
    local glusterNode=$1
    local glusterVolume=$2
    local mountPoint=$3     # E.g., /wordpress

    grep -q "${mountPoint}.*glusterfs" /etc/fstab || echo -e $glusterNode':/'$glusterVolume'   '$mountPoint'         glusterfs       defaults,_netdev,log-level=WARNING,log-file=/var/log/gluster.log 0 0' >> /etc/fstab
    mount $mountPoint
}

function setup_and_mount_azure_files_share
{
    local shareName=$1
    local storageAccountName=$2
    local storageAccountKey=$3

    cat <<EOF > /etc/wordpress_azure_files.credential
username=$storageAccountName
password=$storageAccountKey
EOF
    chmod 600 /etc/wordpress_azure_files.credential
    
    grep -q -s "^//$storageAccountName.file.core.windows.net/wordpress\s\s*/wordpress\s\s*cifs" /etc/fstab && _RET=$? || _RET=$?
    if [ $_RET != "0" ]; then
        echo -e "\n//$storageAccountName.file.core.windows.net/wordpress   /wordpress cifs    credentials=/etc/wordpress_azure_files.credential,uid=www-data,gid=www-data,nofail,vers=3.0,dir_mode=0770,file_mode=0660,serverino,mfsymlinks" >> /etc/fstab
    fi
    mkdir -p /wordpress
    mount /wordpress
}

function setup_wordpress_mount_dependency_for_systemd_service
{
  local serviceName=$1 # E.g., nginx
  if [ -z "$serviceName" ]; then
    return 1
  fi

  local systemdSvcOverrideFileDir="/etc/systemd/system/${serviceName}.service.d"
  local systemdSvcOverrideFilePath="${systemdSvcOverrideFileDir}/wordpress_override.conf"

  grep -q -s "After=wordpress.mount" $systemdSvcOverrideFilePath && _RET=$? || _RET=$?
  if [ $_RET != "0" ]; then
    mkdir -p $systemdSvcOverrideFileDir
    cat <<EOF > $systemdSvcOverrideFilePath
[Unit]
After=wordpress.mount
EOF
    systemctl daemon-reload
  fi
}

# Functions for making NFS share available
# TODO refactor these functions with the same ones in install_gluster.sh
function scan_for_new_disks
{
    local BLACKLIST=${1}    # E.g., /dev/sda|/dev/sdb
    declare -a RET
    local DEVS=$(ls -1 /dev/sd*|egrep -v "${BLACKLIST}"|egrep -v "[0-9]$")
    for DEV in ${DEVS};
    do
        # Check each device if there is a "1" partition.  If not,
        # "assume" it is not partitioned.
        if [ ! -b ${DEV}1 ];
        then
            RET+="${DEV} "
        fi
    done
    echo "${RET}"
}

function create_raid0_ubuntu {
    local RAIDDISK=${1}       # E.g., /dev/md1
    local RAIDCHUNKSIZE=${2}  # E.g., 128
    local DISKCOUNT=${3}      # E.g., 4
    shift
    shift
    shift
    local DISKS="$@"

    dpkg -s mdadm && _RET=$? || _RET=$?
    if [ $_RET -eq 1 ];
    then 
        echo "installing mdadm"
        sudo apt-get -y -q install mdadm
    fi
    echo "Creating raid0"
    udevadm control --stop-exec-queue
    echo "yes" | mdadm --create $RAIDDISK --name=data --level=0 --chunk=$RAIDCHUNKSIZE --raid-devices=$DISKCOUNT $DISKS
    udevadm control --start-exec-queue
    mdadm --detail --verbose --scan > /etc/mdadm/mdadm.conf
}

function do_partition {
    # This function creates one (1) primary partition on the
    # disk device, using all available space
    local DISK=${1}   # E.g., /dev/sdc

    echo "Partitioning disk $DISK"
    echo -ne "n\np\n1\n\n\nw\n" | fdisk "${DISK}" 
    #> /dev/null 2>&1

    #
    # Use the bash-specific $PIPESTATUS to ensure we get the correct exit code
    # from fdisk and not from echo
    if [ ${PIPESTATUS[1]} -ne 0 ];
    then
        echo "An error occurred partitioning ${DISK}" >&2
        echo "I cannot continue" >&2
        exit 2
    fi
}

function add_local_filesystem_to_fstab {
    local UUID=${1}
    local MOUNTPOINT=${2}   # E.g., /wordpress

    grep -q -s "${UUID}" /etc/fstab && _RET=$? || _RET=$?
    if [ $_RET -eq 0 ];
    then
        echo "Not adding ${UUID} to fstab again (it's already there!)"
    else
        LINE="\nUUID=${UUID} ${MOUNTPOINT} ext4 defaults,noatime 0 0"
        echo -e "${LINE}" >> /etc/fstab
    fi
}

function setup_raid_disk_and_filesystem {
    local MOUNTPOINT=${1}     # E.g., /wordpress
    local RAIDDISK=${2}       # E.g., /dev/md1
    local RAIDPARTITION=${3}  # E.g., /dev/md1p1
    local CREATE_FILESYSTEM=${4}  # E.g., "" (true) or any non-empty string (false)

    local DISKS=$(scan_for_new_disks "/dev/sda|/dev/sdb")
    echo "Disks are ${DISKS}"
    declare -i DISKCOUNT
    local DISKCOUNT=$(echo "$DISKS" | wc -w) 
    echo "Disk count is $DISKCOUNT"
    if [ $DISKCOUNT = "0" ]; then
        echo "No new (unpartitioned) disks available... Returning non-zero..."
        return 1
    fi

    if [ $DISKCOUNT -gt 1 ]; then
        create_raid0_ubuntu ${RAIDDISK} 128 $DISKCOUNT $DISKS
        AZMDL_DISK=$RAIDDISK
        if [ -z "$CREATE_FILESYSTEM" ]; then
          do_partition ${RAIDDISK}
          local PARTITION="${RAIDPARTITION}"
        fi
    else # Just one unpartitioned disk
        AZMDL_DISK=$DISKS
        if [ -z "$CREATE_FILESYSTEM" ]; then
          do_partition ${DISKS}
          local PARTITION=$(fdisk -l ${DISKS}|grep -A 1 Device|tail -n 1|awk '{print $1}')
        fi
    fi

    echo "Disk (RAID if multiple unpartitioned disks, or as is if only one unpartitioned disk) is set up, and env var AZMDL_DISK is set to '$AZMDL_DISK' for later reference"

    if [ -z "$CREATE_FILESYSTEM" ]; then
      echo "Creating filesystem on ${PARTITION}."
      mkfs -t ext4 ${PARTITION}
      mkdir -p "${MOUNTPOINT}"
      local UUID=$(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3}'|tr -d "\"")
      add_local_filesystem_to_fstab "${UUID}" "${MOUNTPOINT}"
      echo "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
      mount "${MOUNTPOINT}"
    fi
}

function configure_nfs_server_and_export {
    local MOUNTPOINT=${1}     # E.g., /wordpress

    echo "Installing nfs server..."
    apt install -y nfs-kernel-server

    echo "Exporting ${MOUNTPOINT}..."
    grep -q -s "^${MOUNTPOINT}" /etc/exports && _RET=$? || _RET=$?
    if [ $_RET = "0" ]; then
        echo "${MOUNTPOINT} is already exported. Returning..."
    else
        echo -e "\n${MOUNTPOINT}   *(rw,sync,no_root_squash)" >> /etc/exports
        systemctl restart nfs-kernel-server.service
    fi
}

function configure_nfs_client_and_mount0 {
    local NFS_HOST_EXPORT_PATH=${1}   # E.g., controller-vm-ab12cd:/wordpress or 172.16.3.100:/drbd/data
    local MOUNTPOINT=${2}             # E.g., /wordpress

    apt install -y nfs-common
    mkdir -p ${MOUNTPOINT}

    grep -q -s "^${NFS_HOST_EXPORT_PATH}" /etc/fstab && _RET=$? || _RET=$?
    if [ $_RET = "0" ]; then
        echo "${NFS_HOST_EXPORT_PATH} already in /etc/fstab... skipping to add"
    else
        echo -e "\n${NFS_HOST_EXPORT_PATH}    ${MOUNTPOINT}    nfs    auto    0    0" >> /etc/fstab
    fi
    mount ${MOUNTPOINT}
}

function configure_nfs_client_and_mount {
    local NFS_SERVER=${1}     # E.g., controller-vm-ab12cd or IP (NFS-HA LB)
    local NFS_DIR=${2}        # E.g., /wordpress or /drbd/data
    local MOUNTPOINT=${3}     # E.g., /wordpress

    configure_nfs_client_and_mount0 "${NFS_SERVER}:${NFS_DIR}" ${MOUNTPOINT}
}

SERVER_TIMESTAMP_FULLPATH="/wordpress/html/.last_modified_time.wordpress"
LOCAL_TIMESTAMP_FULLPATH="/var/www/html/.last_modified_time.wordpress"

# Create a script to sync /wordpress/html (gluster/NFS) and /var/www/html (local) and set up a minutely cron job
# Should be called by root and only on a VMSS web frontend VM
function setup_html_local_copy_cron_job {
  if [ "$(whoami)" != "root" ]; then
    echo "${0}: Must be run as root!"
    return 1
  fi

  local SYNC_SCRIPT_FULLPATH="/usr/local/bin/sync_wordpress_html_local_copy_if_modified.sh"
  mkdir -p $(dirname ${SYNC_SCRIPT_FULLPATH})

  local SYNC_LOG_FULLPATH="/var/log/wordpress-html-sync.log"

  cat <<EOF > ${SYNC_SCRIPT_FULLPATH}
#!/bin/bash

sleep \$((\$RANDOM%30))

if [ -f "$SERVER_TIMESTAMP_FULLPATH" ]; then
  SERVER_TIMESTAMP=\$(cat $SERVER_TIMESTAMP_FULLPATH)
  if [ -f "$LOCAL_TIMESTAMP_FULLPATH" ]; then
    LOCAL_TIMESTAMP=\$(cat $LOCAL_TIMESTAMP_FULLPATH)
  else
    logger -p local2.notice -t wordpress "Local timestamp file ($LOCAL_TIMESTAMP_FULLPATH) does not exist. Probably first time syncing? Continuing to sync."
    mkdir -p /var/www/html
  fi
  if [ "\$SERVER_TIMESTAMP" != "\$LOCAL_TIMESTAMP" ]; then
    logger -p local2.notice -t wordpress "Server time stamp (\$SERVER_TIMESTAMP) is different from local time stamp (\$LOCAL_TIMESTAMP). Start syncing..."
    if [[ \$(find $SYNC_LOG_FULLPATH -type f -size +20M 2> /dev/null) ]]; then
      truncate -s 0 $SYNC_LOG_FULLPATH
    fi
    echo \$(date +%Y%m%d%H%M%S) >> $SYNC_LOG_FULLPATH
    rsync -av --delete /wordpress/html/. /var/www/html >> $SYNC_LOG_FULLPATH
  fi
else
  logger -p local2.notice -t wordpress "Remote timestamp file ($SERVER_TIMESTAMP_FULLPATH) does not exist. Is /wordpress mounted? Exiting with error."
  exit 1
fi
EOF
  chmod 500 ${SYNC_SCRIPT_FULLPATH}

  local CRON_DESC_FULLPATH="/etc/cron.d/sync-wordpress-html-local-copy"
  cat <<EOF > ${CRON_DESC_FULLPATH}
* * * * * root ${SYNC_SCRIPT_FULLPATH}
EOF
  chmod 644 ${CRON_DESC_FULLPATH}

  # Addition of a hook for custom script run on VMSS from shared mount to allow customised configuration of the VMSS as required
  local CRON_DESC_FULLPATH2="/etc/cron.d/update-vmss-config"
  cat <<EOF > ${CRON_DESC_FULLPATH2}
* * * * * root [ -f /wordpress/bin/update-vmss-config ] && /bin/bash /wordpress/bin/update-vmss-config
EOF
  chmod 644 ${CRON_DESC_FULLPATH2}
}

LAST_MODIFIED_TIME_UPDATE_SCRIPT_FULLPATH="/usr/local/bin/update_last_modified_time.wordpress.sh"

# Create a script to modify the last modified timestamp file (/wordpress/html/.last_modified_time.wordpress)
# Should be called by root and only on the controller VM.
# The sysadmin should run the generated script everytime the /wordpress/html directory content is updated (e.g., app upgrade, config change or plugin install/upgrade)
function create_last_modified_time_update_script {
  if [ "$(whoami)" != "root" ]; then
    echo "${0}: Must be run as root!"
    return 1
  fi

  mkdir -p $(dirname $LAST_MODIFIED_TIME_UPDATE_SCRIPT_FULLPATH)
  cat <<EOF > $LAST_MODIFIED_TIME_UPDATE_SCRIPT_FULLPATH
#!/bin/bash
echo \$(date +%Y%m%d%H%M%S) > $SERVER_TIMESTAMP_FULLPATH
EOF

  chmod +x $LAST_MODIFIED_TIME_UPDATE_SCRIPT_FULLPATH
}

function run_once_last_modified_time_update_script {
  $LAST_MODIFIED_TIME_UPDATE_SCRIPT_FULLPATH
}

function config_one_site_on_vmss
{
  local siteFQDN=${1}             # E.g., "www.contoso.com". Will be used as the site's HTML subdirectory name in /wordpress/html (as /wordpress/html/$siteFQDN)
  local htmlLocalCopySwitch=${2}  # "true" or anything else (don't care)
  local httpsTermination=${3}     # "VMSS" or "None"

  # Find the correct htmlRootDir depending on the htmlLocalCopySwitch
  if [ "$htmlLocalCopySwitch" = "true" ]; then
    local htmlRootDir="/var/www/html/$siteFQDN"
  else
    local htmlRootDir="/wordpress/html/$siteFQDN"
  fi

  local certsDir="/wordpress/certs/$siteFQDN"
  local PhpVer=$(get_php_version)

  if [ "$httpsTermination" = "VMSS" ]; then
    # Configure nginx/https
    cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 443 ssl http2;
        index index.php index.html index.htm;
        server_name ${siteFQDN};

        # Use a higher keepalive timeout to reduce the need for repeated handshakes
        keepalive_timeout 300s; # up from 75 secs default
        ssl on;
        ssl_certificate ${certsDir}/nginx.crt;
        ssl_certificate_key ${certsDir}/nginx.key;

        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;

        # Log to syslog
        # error_log syslog:server=localhost,facility=local1,severity=error,tag=wordpress;
        # access_log syslog:server=localhost,facility=local1,severity=notice,tag=wordpress combined;
        
        # Server Logs
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        root ${htmlRootDir};
        location ~* \.php$ {
          include fastcgi_params;
          # Remove X-Powered-By, which is an information leak
          fastcgi_hide_header X-Powered-By;
          fastcgi_buffers 16 16k;
          fastcgi_buffer_size 32k;
          fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
          fastcgi_pass unix:/run/php/php${PhpVer}-fpm.sock;
          fastcgi_read_timeout 3600;
          fastcgi_index index.php;
          include fastcgi_params;
        }
}
EOF
  fi

  cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 80;
	      index index.php index.html index.htm;
        server_name ${siteFQDN};

        # Log to syslog
        # error_log syslog:server=localhost,facility=local1,severity=error,tag=wordpress;
        # access_log syslog:server=localhost,facility=local1,severity=notice,tag=wordpress combined;

        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;

        # Server Logs
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        root ${htmlRootDir};
        location ~* \.php$ {
          include fastcgi_params;
          # Remove X-Powered-By, which is an information leak
          fastcgi_hide_header X-Powered-By;
          fastcgi_buffers 16 16k;
          fastcgi_buffer_size 32k;
          fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
          fastcgi_pass unix:/run/php/php${PhpVer}-fpm.sock;
          fastcgi_read_timeout 3600;
          fastcgi_index index.php;
          include fastcgi_params;
        }
}

EOF
} # function config_one_site_on_vmss

function config_all_sites_on_vmss
{
  local htmlLocalCopySwitch=${1}  # "true" or anything else (don't care)
  local httpsTermination=${2}     # "VMSS" or "None"

  local allSites=$(ls /wordpress/html)
  for site in $allSites; do
    config_one_site_on_vmss $site $htmlLocalCopySwitch $httpsTermination
  done
}

# To be used after the initial deployment on any site addition/deletion
function reset_all_sites_on_vmss
{
  local htmlLocalCopySwitch=${1}  # "true" or anything else (don't care)
  local httpsTermination=${2}     # "VMSS" or "None"

  rm /etc/nginx/sites-enabled/*

  config_all_sites_on_vmss $htmlLocalCopySwitch $httpsTermination

  sudo systemctl restart nginx
}

function create_main_nginx_conf_on_controller
{
    local httpsTermination=${1} # "None" or anything else

    cat <<EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes 2;
pid /run/nginx.pid;

events {
	worker_connections 2048;
}

http {
  sendfile on;
  server_tokens off;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  types_hash_max_size 2048;
  client_max_body_size 0;
  proxy_max_temp_file_size 0;
  server_names_hash_bucket_size  128;
  fastcgi_buffers 16 16k; 
  fastcgi_buffer_size 32k;
  proxy_buffering off;
  include /etc/nginx/mime.types;
  default_type application/octet-stream;

  access_log /var/log/nginx/access.log;
  error_log /var/log/nginx/error.log;

  set_real_ip_from   127.0.0.1;
  real_ip_header      X-Forwarded-For;
  #ssl_protocols TLSv1 TLSv1.1 TLSv1.2; # Dropping SSLv3, ref: POODLE
  #upgrading to TLSv1.2 and droping 1 & 1.1
  ssl_protocols TLSv1.2;
  #ssl_prefer_server_ciphers on;
  #adding ssl ciphers
  ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-SHA384;
  
  gzip on;
  gzip_disable "msie6";
  gzip_vary on;
  gzip_proxied any;
  gzip_comp_level 6;
  gzip_buffers 16 8k;
  gzip_http_version 1.1;
  gzip_types application/atom+xml application/javascript application/json application/ld+json application/manifest+json application/rss+xml application/vnd.geo+json application/vnd.ms-fontobject application/x-font-ttf application/x-web-app-manifest+json application/xhtml+xml application/xml font/opentype image/bmp image/svg+xml image/x-icon text/cache-manifest text/css text/plain text/vcard text/vnd.rim.location.xloc text/vtt text/x-component text/x-cross-domain-policy

  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
EOF
}

function create_per_site_nginx_conf_on_controller
{
    local siteFQDN=${1}
    local httpsTermination=${2} # "None", "VMSS", etc
    local htmlDir=${3}          # E.g., /wordpress/html/site1.org
    local certsDir=${4}         # E.g., /wordpress/certs/site1.org

    if [ "$httpsTermination" = "VMSS" ]; then
    # Configure nginx/https
    cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 443 ssl http2;
        index index.php index.html index.htm;
        server_name ${siteFQDN};

        # Use a higher keepalive timeout to reduce the need for repeated handshakes
        keepalive_timeout 300s; # up from 75 secs default
        ssl on;
        ssl_certificate ${certsDir}/nginx.crt;
        ssl_certificate_key ${certsDir}/nginx.key;

        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;

        # Log to syslog
        # error_log syslog:server=localhost,facility=local1,severity=error,tag=wordpress;
        # access_log syslog:server=localhost,facility=local1,severity=notice,tag=wordpress combined;
        
        # Server Logs
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        root ${htmlRootDir};
        location ~* \.php$ {
          include fastcgi_params;
          # Remove X-Powered-By, which is an information leak
          fastcgi_hide_header X-Powered-By;
          fastcgi_buffers 16 16k;
          fastcgi_buffer_size 32k;
          fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
          fastcgi_pass unix:/run/php/php${PhpVer}-fpm.sock;
          fastcgi_read_timeout 3600;
          fastcgi_index index.php;
          include fastcgi_params;
        }
}
EOF
  fi

  cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 80;
	      index index.php index.html index.htm;
        server_name ${siteFQDN};

        # Log to syslog
        # error_log syslog:server=localhost,facility=local1,severity=error,tag=wordpress;
        # access_log syslog:server=localhost,facility=local1,severity=notice,tag=wordpress combined;
        
        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;

        # Server Logs
        access_log /var/log/nginx/access.log;
        error_log /var/log/nginx/error.log;

        root ${htmlRootDir};
        location ~* \.php$ {
          include fastcgi_params;
          # Remove X-Powered-By, which is an information leak
          fastcgi_hide_header X-Powered-By;
          fastcgi_buffers 16 16k;
          fastcgi_buffer_size 32k;
          fastcgi_param   SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
          fastcgi_pass unix:/run/php/php${PhpVer}-fpm.sock;
          fastcgi_read_timeout 3600;
          fastcgi_index index.php;
          include fastcgi_params;
        }
}

EOF
}

function create_per_site_nginx_ssl_certs_on_controller
{
    local siteFQDN=${1}
    local certsDir=${2}
    local httpsTermination=${3}
    local thumbprintSslCert=${4}
    local thumbprintCaCert=${5}

    if [ "$httpsTermination" = "VMSS" ]; then
        ### SSL cert ###
        if [ "$thumbprintSslCert" != "None" ]; then
            echo "Using VM's cert (/var/lib/waagent/$thumbprintSslCert.*) for SSL..."
            cat /var/lib/waagent/$thumbprintSslCert.prv > $certsDir/nginx.key
            cat /var/lib/waagent/$thumbprintSslCert.crt > $certsDir/nginx.crt
            if [ "$thumbprintCaCert" != "None" ]; then
                echo "CA cert was specified (/var/lib/waagent/$thumbprintCaCert.crt), so append it to nginx.crt..."
                cat /var/lib/waagent/$thumbprintCaCert.crt >> $certsDir/nginx.crt
            fi
        else
            echo -e "Generating SSL self-signed certificate"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $certsDir/nginx.key -out $certsDir/nginx.crt -subj "/C=US/ST=WA/L=Redmond/O=IT/CN=$siteFQDN"
        fi
        chown -R www-data:www-data $certsDir
        chmod 0400 $certsDir/*
    fi
}

function update_php_config_on_controller
{
    # php config
    PhpVer=$(get_php_version)
    PhpIni=/etc/php/${PhpVer}/fpm/php.ini
    sed -i "s/memory_limit.*/memory_limit = 512M/" $PhpIni
    sed -i "s/max_execution_time.*/max_execution_time = 18000/" $PhpIni
    sed -i "s/max_input_vars.*/max_input_vars = 100000/" $PhpIni
    sed -i "s/max_input_time.*/max_input_time = 600/" $PhpIni
    sed -i "s/upload_max_filesize.*/upload_max_filesize = 1024M/" $PhpIni
    sed -i "s/post_max_size.*/post_max_size = 1056M/" $PhpIni
    sed -i "s/;opcache.use_cwd.*/opcache.use_cwd = 1/" $PhpIni
    sed -i "s/;opcache.validate_timestamps.*/opcache.validate_timestamps = 1/" $PhpIni
    sed -i "s/;opcache.save_comments.*/opcache.save_comments = 1/" $PhpIni
    sed -i "s/;opcache.enable_file_override.*/opcache.enable_file_override = 0/" $PhpIni
    sed -i "s/;opcache.enable.*/opcache.enable = 1/" $PhpIni
    sed -i "s/;opcache.memory_consumption.*/opcache.memory_consumption = 256/" $PhpIni
    sed -i "s/;opcache.max_accelerated_files.*/opcache.max_accelerated_files = 8000/" $PhpIni

    # fpm config - overload this
    cat <<EOF > /etc/php/${PhpVer}/fpm/pool.d/www.conf
[www]
user = www-data
group = www-data
listen = /run/php/php${PhpVer}-fpm.sock
listen.owner = www-data
listen.group = www-data
pm = dynamic
pm.max_children = 3000
pm.start_servers = 20
pm.min_spare_servers = 22
pm.max_spare_servers = 30
EOF
}

function create_per_site_sql_db_from_controller
{
    local dbServerType=${1}
    local dbIP=${2}
    local dbadminloginazure=${3}
    local dbadminpass=${4}
    local wordpressdbname=${5}
    local wordpressdbuser=${6}
    local wordpressdbpass=${7}
    local mssqlDbSize=${8}
    local mssqlDbEdition=${9}
    local mssqlDbServiceObjectiveName=${10}

    if [ $dbServerType = "mysql" ]; then
        mysql -h $dbIP -u $dbadminloginazure -p${dbadminpass} -e "CREATE DATABASE ${wordpressdbname} CHARACTER SET utf8;"
        mysql -h $dbIP -u $dbadminloginazure -p${dbadminpass} -e "GRANT ALL ON ${wordpressdbname}.* TO ${wordpressdbuser} IDENTIFIED BY '${wordpressdbpass}';"

        echo "mysql -h $dbIP -u $dbadminloginazure -p${dbadminpass} -e \"CREATE DATABASE ${wordpressdbname};\"" >> /tmp/debug
        echo "mysql -h $dbIP -u $dbadminloginazure -p${dbadminpass} -e \"GRANT ALL ON ${wordpressdbname}.* TO ${wordpressdbuser} IDENTIFIED BY '${wordpressdbpass}';\"" >> /tmp/debug
    elif [ $dbServerType = "mssql" ]; then
        /opt/mssql-tools/bin/sqlcmd -S $dbIP -U $dbadminloginazure -P ${dbadminpass} -Q "CREATE DATABASE ${wordpressdbname} ( MAXSIZE = $mssqlDbSize, EDITION = '$mssqlDbEdition', SERVICE_OBJECTIVE = '$mssqlDbServiceObjectiveName' )"
        /opt/mssql-tools/bin/sqlcmd -S $dbIP -U $dbadminloginazure -P ${dbadminpass} -Q "CREATE LOGIN ${wordpressdbuser} with password = '${wordpressdbpass}'"
        /opt/mssql-tools/bin/sqlcmd -S $dbIP -U $dbadminloginazure -P ${dbadminpass} -d ${wordpressdbname} -Q "CREATE USER ${wordpressdbuser} FROM LOGIN ${wordpressdbuser}"
        /opt/mssql-tools/bin/sqlcmd -S $dbIP -U $dbadminloginazure -P ${dbadminpass} -d ${wordpressdbname} -Q "exec sp_addrolemember 'db_owner','${wordpressdbuser}'"
    else
        # Create postgres db
        echo "${dbIP}:5432:postgres:${dbadminloginazure}:${dbadminpass}" > /root/.pgpass
        chmod 600 /root/.pgpass
        psql -h $dbIP -U $dbadminloginazure -c "CREATE DATABASE ${wordpressdbname};" postgres
        psql -h $dbIP -U $dbadminloginazure -c "CREATE USER ${wordpressdbuser} WITH PASSWORD '${wordpressdbpass}';" postgres
        psql -h $dbIP -U $dbadminloginazure -c "GRANT ALL ON DATABASE ${wordpressdbname} TO ${wordpressdbuser};" postgres
        rm -f /root/.pgpass
    fi
}

function config_varnish
{
   # Configure varnish startup for 16.04
   VARNISHSTART="ExecStart=\/usr\/sbin\/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f \/etc\/varnish\/wordpress.vcl -S \/etc\/varnish\/secret -s malloc,1024m -p thread_pool_min=200 -p thread_pool_max=4000 -p thread_pool_add_delay=2 -p timeout_linger=100 -p timeout_idle=30 -p send_timeout=1800 -p thread_pools=4 -p http_max_hdr=512 -p workspace_backend=512k"
   sed -i "s/^ExecStart.*/${VARNISHSTART}/" /lib/systemd/system/varnish.service

   # Configure varnish VCL for WordPress
   cat <<EOF >> /etc/varnish/wordpress.vcl
vcl 4.0;

import std;
import directors;
backend default {
    .host = "localhost";
    .port = "81";
    .first_byte_timeout = 3600s;
    .connect_timeout = 600s;
    .between_bytes_timeout = 600s;
}

sub vcl_recv {
    # Varnish does not support SPDY or HTTP/2.0 untill we upgrade to Varnish 5.0
    if (req.method == "PRI") {
        return (synth(405));
    }

    if (req.restarts == 0) {
      if (req.http.X-Forwarded-For) {
        set req.http.X-Forwarded-For = req.http.X-Forwarded-For + ", " + client.ip;
      } else {
        set req.http.X-Forwarded-For = client.ip;
      }
    }

    # Non-RFC2616 or CONNECT HTTP requests methods filtered. Pipe requests directly to backend
    if (req.method != "GET" &&
        req.method != "HEAD" &&
        req.method != "PUT" &&
        req.method != "POST" &&
        req.method != "TRACE" &&
        req.method != "OPTIONS" &&
        req.method != "DELETE") {
      return (pipe);
    }

    # Varnish don't mess with healthchecks
    if (req.url ~ "^/admin/tool/heartbeat" || req.url ~ "^/healthcheck.php")
    {
        return (pass);
    }

    # Pipe requests to backup.php straight to backend - prevents problem with progress bar long polling 503 problem
    # This is here because backup.php is POSTing to itself - Filter before !GET&&!HEAD
    if (req.url ~ "^/backup/backup.php")
    {
        return (pipe);
    }

    # Varnish only deals with GET and HEAD by default. If request method is not GET or HEAD, pass request to backend
    if (req.method != "GET" && req.method != "HEAD") {
      return (pass);
    }

    ### Rules for WordPress and Totara sites ###
    # WordPress doesn't require Cookie to serve following assets. Remove Cookie header from request, so it will be looked up.
    if ( req.url ~ "^/altlogin/.+/.+\.(png|jpg|jpeg|gif|css|js|webp)$" ||
         req.url ~ "^/pix/.+\.(png|jpg|jpeg|gif)$" ||
         req.url ~ "^/theme/font.php" ||
         req.url ~ "^/theme/image.php" ||
         req.url ~ "^/theme/javascript.php" ||
         req.url ~ "^/theme/jquery.php" ||
         req.url ~ "^/theme/styles.php" ||
         req.url ~ "^/theme/yui" ||
         req.url ~ "^/lib/javascript.php/-1/" ||
         req.url ~ "^/lib/requirejs.php/-1/"
        )
    {
        set req.http.X-Long-TTL = "86400";
        unset req.http.Cookie;
        return(hash);
    }

    # Perform lookup for selected assets that we know are static but WordPress still needs a Cookie
    if(  req.url ~ "^/theme/.+\.(png|jpg|jpeg|gif|css|js|webp)" ||
         req.url ~ "^/lib/.+\.(png|jpg|jpeg|gif|css|js|webp)" ||
         req.url ~ "^/pluginfile.php/[0-9]+/course/overviewfiles/.+\.(?i)(png|jpg)$"
      )
    {
         # Set internal temporary header, based on which we will do things in vcl_backend_response
         set req.http.X-Long-TTL = "86400";
         return (hash);
    }

    # Serve requests to SCORM checknet.txt from varnish. Have to remove get parameters. Response body always contains "1"
    if ( req.url ~ "^/lib/yui/build/wordpress-core-checknet/assets/checknet.txt" )
    {
        set req.url = regsub(req.url, "(.*)\?.*", "\1");
        unset req.http.Cookie; # Will go to hash anyway at the end of vcl_recv
        set req.http.X-Long-TTL = "86400";
        return(hash);
    }

    # Requests containing "Cookie" or "Authorization" headers will not be cached
    if (req.http.Authorization || req.http.Cookie) {
        return (pass);
    }

    # Almost everything in WordPress correctly serves Cache-Control headers, if
    # needed, which varnish will honor, but there are some which don't. Rather
    # than explicitly finding them all and listing them here we just fail safe
    # and don't cache unknown urls that get this far.
    return (pass);
}

sub vcl_backend_response {
    # Happens after we have read the response headers from the backend.
    # 
    # Here you clean the response headers, removing silly Set-Cookie headers
    # and other mistakes your backend does.

    # We know these assest are static, let's set TTL >0 and allow client caching
    if ( beresp.http.Cache-Control && bereq.http.X-Long-TTL && beresp.ttl < std.duration(bereq.http.X-Long-TTL + "s", 1s) && !beresp.http.WWW-Authenticate )
    { # If max-age < defined in X-Long-TTL header
        set beresp.http.X-Orig-Pragma = beresp.http.Pragma; unset beresp.http.Pragma;
        set beresp.http.X-Orig-Cache-Control = beresp.http.Cache-Control;
        set beresp.http.Cache-Control = "public, max-age="+bereq.http.X-Long-TTL+", no-transform";
        set beresp.ttl = std.duration(bereq.http.X-Long-TTL + "s", 1s);
        unset bereq.http.X-Long-TTL;
    }
    else if( !beresp.http.Cache-Control && bereq.http.X-Long-TTL && !beresp.http.WWW-Authenticate ) {
        set beresp.http.X-Orig-Pragma = beresp.http.Pragma; unset beresp.http.Pragma;
        set beresp.http.Cache-Control = "public, max-age="+bereq.http.X-Long-TTL+", no-transform";
        set beresp.ttl = std.duration(bereq.http.X-Long-TTL + "s", 1s);
        unset bereq.http.X-Long-TTL;
    }
    else { # Don't touch headers if max-age > defined in X-Long-TTL header
        unset bereq.http.X-Long-TTL;
    }

    # Here we set X-Trace header, prepending it to X-Trace header received from backend. Useful for troubleshooting
    if(beresp.http.x-trace && !beresp.was_304) {
        set beresp.http.X-Trace = regsub(server.identity, "^([^.]+),?.*$", "\1")+"->"+regsub(beresp.backend.name, "^(.+)\((?:[0-9]{1,3}\.){3}([0-9]{1,3})\)","\1(\2)")+"->"+beresp.http.X-Trace;
    }
    else {
        set beresp.http.X-Trace = regsub(server.identity, "^([^.]+),?.*$", "\1")+"->"+regsub(beresp.backend.name, "^(.+)\((?:[0-9]{1,3}\.){3}([0-9]{1,3})\)","\1(\2)");
    }

    # Gzip JS, CSS is done at the ngnix level doing it here dosen't respect the no buffer requsets
    # if (beresp.http.content-type ~ "application/javascript.*" || beresp.http.content-type ~ "text") {
    #    set beresp.do_gzip = true;
    #}
}

sub vcl_deliver {

    # Revert back to original Cache-Control header before delivery to client
    if (resp.http.X-Orig-Cache-Control)
    {
        set resp.http.Cache-Control = resp.http.X-Orig-Cache-Control;
        unset resp.http.X-Orig-Cache-Control;
    }

    # Revert back to original Pragma header before delivery to client
    if (resp.http.X-Orig-Pragma)
    {
        set resp.http.Pragma = resp.http.X-Orig-Pragma;
        unset resp.http.X-Orig-Pragma;
    }

    # (Optional) X-Cache HTTP header will be added to responce, indicating whether object was retrieved from backend, or served from cache
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
    } else {
        set resp.http.X-Cache = "MISS";
    }

    # Set X-AuthOK header when totara/varnsih authentication succeeded
    if (req.http.X-AuthOK) {
        set resp.http.X-AuthOK = req.http.X-AuthOK;
    }

    # If desired "Via: 1.1 Varnish-v4" response header can be removed from response
    unset resp.http.Via;
    unset resp.http.Server;

    return(deliver);
}

sub vcl_backend_error {
    # More comprehensive varnish error page. Display time, instance hostname, host header, url for easier troubleshooting.
    set beresp.http.Content-Type = "text/html; charset=utf-8";
    set beresp.http.Retry-After = "5";
    synthetic( {"
  <!DOCTYPE html>
  <html>
    <head>
      <title>"} + beresp.status + " " + beresp.reason + {"</title>
    </head>
    <body>
      <h1>Error "} + beresp.status + " " + beresp.reason + {"</h1>
      <p>"} + beresp.reason + {"</p>
      <h3>Guru Meditation:</h3>
      <p>Time: "} + now + {"</p>
      <p>Node: "} + server.hostname + {"</p>
      <p>Host: "} + bereq.http.host + {"</p>
      <p>URL: "} + bereq.url + {"</p>
      <p>XID: "} + bereq.xid + {"</p>
      <hr>
      <p>Varnish cache server
    </body>
  </html>
  "} );
   return (deliver);
}

sub vcl_synth {

    #Redirect using '301 - Permanent Redirect', permanent redirect
    if (resp.status == 851) { 
        set resp.http.Location = req.http.x-redir;
        set resp.http.X-Varnish-Redirect = true;
        set resp.status = 301;
        return (deliver);
    }

    #Redirect using '302 - Found', temporary redirect
    if (resp.status == 852) { 
        set resp.http.Location = req.http.x-redir;
        set resp.http.X-Varnish-Redirect = true;
        set resp.status = 302;
        return (deliver);
    }

    #Redirect using '307 - Temporary Redirect', !GET&&!HEAD requests, dont change method on redirected requests
    if (resp.status == 857) { 
        set resp.http.Location = req.http.x-redir;
        set resp.http.X-Varnish-Redirect = true;
        set resp.status = 307;
        return (deliver);
    }

    #Respond with 403 - Forbidden
    if (resp.status == 863) {
        set resp.http.X-Varnish-Error = true;
        set resp.status = 403;
        return (deliver);
    }
}
EOF

    # Restart Varnish
    systemctl daemon-reload
    service varnish restart

}

function config_syslog_on_controller
{
    mkdir /var/log/sitelogs
    chown syslog.adm /var/log/sitelogs
    cat <<EOF >> /etc/rsyslog.conf
\$ModLoad imudp
\$UDPServerRun 514
EOF
    cat <<EOF >> /etc/rsyslog.d/40-sitelogs.conf
local1.*   /var/log/sitelogs/wordpress/access.log
local1.err   /var/log/sitelogs/wordpress/error.log
local2.*   /var/log/sitelogs/wordpress/cron.log
EOF
}

# Long fail2ban config command moved here
function config_fail2ban
{
    cat <<EOF > /etc/fail2ban/jail.conf
# Fail2Ban configuration file.
#
# This file was composed for Debian systems from the original one
# provided now under /usr/share/doc/fail2ban/examples/jail.conf
# for additional examples.
#
# Comments: use '#' for comment lines and ';' for inline comments
#
# To avoid merges during upgrades DO NOT MODIFY THIS FILE
# and rather provide your changes in /etc/fail2ban/jail.local
#

# The DEFAULT allows a global definition of the options. They can be overridden
# in each jail afterwards.

[DEFAULT]

# "ignoreip" can be an IP address, a CIDR mask or a DNS host. Fail2ban will not
# ban a host which matches an address in this list. Several addresses can be
# defined using space separator.
ignoreip = 127.0.0.1/8

# "bantime" is the number of seconds that a host is banned.
bantime  = 600

# A host is banned if it has generated "maxretry" during the last "findtime"
# seconds.
findtime = 600
maxretry = 3

# "backend" specifies the backend used to get files modification.
# Available options are "pyinotify", "gamin", "polling" and "auto".
# This option can be overridden in each jail as well.
#
# pyinotify: requires pyinotify (a file alteration monitor) to be installed.
#            If pyinotify is not installed, Fail2ban will use auto.
# gamin:     requires Gamin (a file alteration monitor) to be installed.
#            If Gamin is not installed, Fail2ban will use auto.
# polling:   uses a polling algorithm which does not require external libraries.
# auto:      will try to use the following backends, in order:
#            pyinotify, gamin, polling.
backend = auto

# "usedns" specifies if jails should trust hostnames in logs,
#   warn when reverse DNS lookups are performed, or ignore all hostnames in logs
#
# yes:   if a hostname is encountered, a reverse DNS lookup will be performed.
# warn:  if a hostname is encountered, a reverse DNS lookup will be performed,
#        but it will be logged as a warning.
# no:    if a hostname is encountered, will not be used for banning,
#        but it will be logged as info.
usedns = warn

#
# Destination email address used solely for the interpolations in
# jail.{conf,local} configuration files.
destemail = root@localhost

#
# Name of the sender for mta actions
sendername = Fail2Ban

#
# ACTIONS
#

# Default banning action (e.g. iptables, iptables-new,
# iptables-multiport, shorewall, etc) It is used to define
# action_* variables. Can be overridden globally or per
# section within jail.local file
banaction = iptables-multiport

# email action. Since 0.8.1 upstream fail2ban uses sendmail
# MTA for the mailing. Change mta configuration parameter to mail
# if you want to revert to conventional 'mail'.
mta = sendmail

# Default protocol
protocol = tcp

# Specify chain where jumps would need to be added in iptables-* actions
chain = INPUT

#
# Action shortcuts. To be used to define action parameter

# The simplest action to take: ban only
action_ = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]

# ban & send an e-mail with whois report to the destemail.
action_mw = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
              %(mta)s-whois[name=%(__name__)s, dest="%(destemail)s", protocol="%(protocol)s", chain="%(chain)s", sendername="%(sendername)s"]

# ban & send an e-mail with whois report and relevant log lines
# to the destemail.
action_mwl = %(banaction)s[name=%(__name__)s, port="%(port)s", protocol="%(protocol)s", chain="%(chain)s"]
               %(mta)s-whois-lines[name=%(__name__)s, dest="%(destemail)s", logpath=%(logpath)s, chain="%(chain)s", sendername="%(sendername)s"]

# Choose default action.  To change, just override value of 'action' with the
# interpolation to the chosen action shortcut (e.g.  action_mw, action_mwl, etc) in jail.local
# globally (section [DEFAULT]) or per specific section
action = %(action_)s

#
# JAILS
#

# Next jails corresponds to the standard configuration in Fail2ban 0.6 which
# was shipped in Debian. Enable any defined here jail by including
#
# [SECTION_NAME]
# enabled = true

#
# in /etc/fail2ban/jail.local.
#
# Optionally you may override any other parameter (e.g. banaction,
# action, port, logpath, etc) in that section within jail.local

[ssh]

enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 6

[dropbear]

enabled  = false
port     = ssh
filter   = dropbear
logpath  = /var/log/auth.log
maxretry = 6

# Generic filter for pam. Has to be used with action which bans all ports
# such as iptables-allports, shorewall
[pam-generic]

enabled  = false
# pam-generic filter can be customized to monitor specific subset of 'tty's
filter   = pam-generic
# port actually must be irrelevant but lets leave it all for some possible uses
port     = all
banaction = iptables-allports
port     = anyport
logpath  = /var/log/auth.log
maxretry = 6

[xinetd-fail]

enabled   = false
filter    = xinetd-fail
port      = all
banaction = iptables-multiport-log
logpath   = /var/log/daemon.log
maxretry  = 2


[ssh-ddos]

enabled  = false
port     = ssh
filter   = sshd-ddos
logpath  = /var/log/auth.log
maxretry = 6


# Here we use blackhole routes for not requiring any additional kernel support
# to store large volumes of banned IPs

[ssh-route]

enabled = false
filter = sshd
action = route
logpath = /var/log/sshd.log
maxretry = 6

# Here we use a combination of Netfilter/Iptables and IPsets
# for storing large volumes of banned IPs
#
# IPset comes in two versions. See ipset -V for which one to use
# requires the ipset package and kernel support.
[ssh-iptables-ipset4]

enabled  = false
port     = ssh
filter   = sshd
banaction = iptables-ipset-proto4
logpath  = /var/log/sshd.log
maxretry = 6

[ssh-iptables-ipset6]

enabled  = false
port     = ssh
filter   = sshd
banaction = iptables-ipset-proto6
logpath  = /var/log/sshd.log
maxretry = 6


#
# HTTP servers
#

[apache]

enabled  = false
port     = http,https
filter   = apache-auth
logpath  = /var/log/apache*/*error.log
maxretry = 6

# default action is now multiport, so apache-multiport jail was left
# for compatibility with previous (<0.7.6-2) releases
[apache-multiport]

enabled   = false
port      = http,https
filter    = apache-auth
logpath   = /var/log/apache*/*error.log
maxretry  = 6

[apache-noscript]

enabled  = false
port     = http,https
filter   = apache-noscript
logpath  = /var/log/apache*/*error.log
maxretry = 6

[apache-overflows]

enabled  = false
port     = http,https
filter   = apache-overflows
logpath  = /var/log/apache*/*error.log
maxretry = 2

# Ban attackers that try to use PHP's URL-fopen() functionality
# through GET/POST variables. - Experimental, with more than a year
# of usage in production environments.

[php-url-fopen]

enabled = false
port    = http,https
filter  = php-url-fopen
logpath = /var/www/*/logs/access_log

# A simple PHP-fastcgi jail which works with lighttpd.
# If you run a lighttpd server, then you probably will
# find these kinds of messages in your error_log:
#   ALERT – tried to register forbidden variable ‘GLOBALS’
#   through GET variables (attacker '1.2.3.4', file '/var/www/default/htdocs/index.php')

[lighttpd-fastcgi]

enabled = false
port    = http,https
filter  = lighttpd-fastcgi
logpath = /var/log/lighttpd/error.log

# Same as above for mod_auth
# It catches wrong authentifications

[lighttpd-auth]

enabled = false
port    = http,https
filter  = suhosin
logpath = /var/log/lighttpd/error.log

[nginx-http-auth]

enabled = false
filter  = nginx-http-auth
port    = http,https
logpath = /var/log/nginx/error.log

# Monitor roundcube server

[roundcube-auth]

enabled  = false
filter   = roundcube-auth
port     = http,https
logpath  = /var/log/roundcube/userlogins


[sogo-auth]

enabled  = false
filter   = sogo-auth
port     = http, https
# without proxy this would be:
# port    = 20000
logpath  = /var/log/sogo/sogo.log


#
# FTP servers
#

[vsftpd]

enabled  = false
port     = ftp,ftp-data,ftps,ftps-data
filter   = vsftpd
logpath  = /var/log/vsftpd.log
# or overwrite it in jails.local to be
# logpath = /var/log/auth.log
# if you want to rely on PAM failed login attempts
# vsftpd's failregex should match both of those formats
maxretry = 6


[proftpd]

enabled  = false
port     = ftp,ftp-data,ftps,ftps-data
filter   = proftpd
logpath  = /var/log/proftpd/proftpd.log
maxretry = 6


[pure-ftpd]

enabled  = false
port     = ftp,ftp-data,ftps,ftps-data
filter   = pure-ftpd
logpath  = /var/log/syslog
maxretry = 6


[wuftpd]

enabled  = false
port     = ftp,ftp-data,ftps,ftps-data
filter   = wuftpd
logpath  = /var/log/syslog
maxretry = 6


#
# Mail servers
#

[postfix]

enabled  = false
port     = smtp,ssmtp,submission
filter   = postfix
logpath  = /var/log/mail.log


[couriersmtp]

enabled  = false
port     = smtp,ssmtp,submission
filter   = couriersmtp
logpath  = /var/log/mail.log


#
# Mail servers authenticators: might be used for smtp,ftp,imap servers, so
# all relevant ports get banned
#

[courierauth]

enabled  = false
port     = smtp,ssmtp,submission,imap2,imap3,imaps,pop3,pop3s
filter   = courierlogin
logpath  = /var/log/mail.log


[sasl]

enabled  = false
port     = smtp,ssmtp,submission,imap2,imap3,imaps,pop3,pop3s
filter   = postfix-sasl
# You might consider monitoring /var/log/mail.warn instead if you are
# running postfix since it would provide the same log lines at the
# "warn" level but overall at the smaller filesize.
logpath  = /var/log/mail.log

[dovecot]

enabled = false
port    = smtp,ssmtp,submission,imap2,imap3,imaps,pop3,pop3s
filter  = dovecot
logpath = /var/log/mail.log

# To log wrong MySQL access attempts add to /etc/my.cnf:
# log-error=/var/log/mysqld.log
# log-warning = 2
[mysqld-auth]

enabled  = false
filter   = mysqld-auth
port     = 3306
logpath  = /var/log/mysqld.log


# DNS Servers


# These jails block attacks against named (bind9). By default, logging is off
# with bind9 installation. You will need something like this:
#
# logging {
#     channel security_file {
#         file "/var/log/named/security.log" versions 3 size 30m;
#         severity dynamic;
#         print-time yes;
#     };
#     category security {
#         security_file;
#     };
# };
#
# in your named.conf to provide proper logging

# !!! WARNING !!!
#   Since UDP is connection-less protocol, spoofing of IP and imitation
#   of illegal actions is way too simple.  Thus enabling of this filter
#   might provide an easy way for implementing a DoS against a chosen
#   victim. See
#    http://nion.modprobe.de/blog/archives/690-fail2ban-+-dns-fail.html
#   Please DO NOT USE this jail unless you know what you are doing.
#[named-refused-udp]
#
#enabled  = false
#port     = domain,953
#protocol = udp
#filter   = named-refused
#logpath  = /var/log/named/security.log

[named-refused-tcp]

enabled  = false
port     = domain,953
protocol = tcp
filter   = named-refused
logpath  = /var/log/named/security.log

# Multiple jails, 1 per protocol, are necessary ATM:
# see https://github.com/fail2ban/fail2ban/issues/37
[asterisk-tcp]

enabled  = false
filter   = asterisk
port     = 5060,5061
protocol = tcp
logpath  = /var/log/asterisk/messages

[asterisk-udp]

enabled  = false
filter	 = asterisk
port     = 5060,5061
protocol = udp
logpath  = /var/log/asterisk/messages


# Jail for more extended banning of persistent abusers
# !!! WARNING !!!
#   Make sure that your loglevel specified in fail2ban.conf/.local
#   is not at DEBUG level -- which might then cause fail2ban to fall into
#   an infinite loop constantly feeding itself with non-informative lines
[recidive]

enabled  = false
filter   = recidive
logpath  = /var/log/fail2ban.log
action   = iptables-allports[name=recidive]
           sendmail-whois-lines[name=recidive, logpath=/var/log/fail2ban.log]
bantime  = 604800  ; 1 week
findtime = 86400   ; 1 day
maxretry = 5
EOF
}
