#!/bin/bash

# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -ex

#parameters 
{
    wordpress_on_azure_configs_json_path=${1}

    . ./helper_functions.sh

    get_setup_params_from_configs_json $wordpress_on_azure_configs_json_path || exit 99

    echo $wordpressVersion              >> /tmp/vars.txt
    echo $glusterNode                   >> /tmp/vars.txt
    echo $glusterVolume                 >> /tmp/vars.txt
    echo $siteFQDN                      >> /tmp/vars.txt
    echo $httpsTermination              >> /tmp/vars.txt
    echo $dbIP                          >> /tmp/vars.txt
    echo $wordpressdbname               >> /tmp/vars.txt
    echo $wordpressdbuser               >> /tmp/vars.txt
    echo $wordpressdbpass               >> /tmp/vars.txt
    echo $adminpass                     >> /tmp/vars.txt
    echo $dbadminlogin                  >> /tmp/vars.txt
    echo $dbadminloginazure             >> /tmp/vars.txt
    echo $dbadminpass                   >> /tmp/vars.txt
    echo $storageAccountName            >> /tmp/vars.txt
    echo $storageAccountKey             >> /tmp/vars.txt
    echo $azurewordpressdbuser          >> /tmp/vars.txt
    echo $redisDns                      >> /tmp/vars.txt
    echo $redisAuth                     >> /tmp/vars.txt
    echo $elasticVm1IP                  >> /tmp/vars.txt
    echo $sshUsername                   >> /tmp/vars.txt
    echo $dbServerType                  >> /tmp/vars.txt
    echo $fileServerType                >> /tmp/vars.txt
    echo $mssqlDbServiceObjectiveName   >> /tmp/vars.txt
    echo $mssqlDbEdition	            >> /tmp/vars.txt
    echo $mssqlDbSize	                >> /tmp/vars.txt
    echo $thumbprintSslCert             >> /tmp/vars.txt
    echo $thumbprintCaCert              >> /tmp/vars.txt
    echo $azureSearchKey                >> /tmp/vars.txt
    echo $azureSearchNameHost           >> /tmp/vars.txt
    echo $tikaVmIP                      >> /tmp/vars.txt
    echo $nfsByoIpExportPath            >> /tmp/vars.txt
    echo $storageAccountType            >>/tmp/vars.txt
    echo $fileServerDiskSize            >>/tmp/vars.txt
    echo $phpVersion                    >> /tmp/vars.txt

    check_fileServerType_param $fileServerType

    #Updating php sources
   sudo add-apt-repository ppa:ondrej/php -y
   sudo apt-get update

    if [ "$dbServerType" = "mysql" ]; then
      mysqlIP=$dbIP
      mysqladminlogin=$dbadminloginazure
      mysqladminpass=$dbadminpass
    elif [ "$dbServerType" = "mssql" ]; then
      mssqlIP=$dbIP
      mssqladminlogin=$dbadminloginazure
      mssqladminpass=$dbadminpass

    elif [ "$dbServerType" = "postgres" ]; then
      postgresIP=$dbIP
      pgadminlogin=$dbadminloginazure
      pgadminpass=$dbadminpass
    else
      echo "Invalid dbServerType ($dbServerType) given. Only 'mysql' or 'postgres' or 'mssql' is allowed. Exiting"
      exit 1
    fi

    # make sure system does automatic updates and fail2ban
    sudo apt-get -y update
    sudo apt-get -y install unattended-upgrades fail2ban

    config_fail2ban

    # create gluster, nfs or Azure Files mount point
    mkdir -p /wordpress

    export DEBIAN_FRONTEND=noninteractive

    if [ $fileServerType = "gluster" ]; then
        # configure gluster repository & install gluster client
        sudo add-apt-repository ppa:gluster/glusterfs-3.10 -y               >> /tmp/apt1.log
    elif [ $fileServerType = "nfs" ]; then
        # configure NFS server and export
        setup_raid_disk_and_filesystem /wordpress /dev/md1 /dev/md1p1
        configure_nfs_server_and_export /wordpress
    fi

    sudo apt-get -y update                                                   >> /tmp/apt2.log
    sudo apt-get -y --force-yes install rsyslog git                          >> /tmp/apt3.log

    if [ $fileServerType = "gluster" ]; then
        sudo apt-get -y --force-yes install glusterfs-client                 >> /tmp/apt3.log
    elif [ "$fileServerType" = "azurefiles" ]; then
        sudo apt-get -y --force-yes install cifs-utils                       >> /tmp/apt3.log
    fi

    if [ $dbServerType = "mysql" ]; then
        sudo apt-get -y --force-yes install mysql-client                    >> /tmp/apt3.log
    elif [ "$dbServerType" = "postgres" ]; then
        sudo apt-get -y --force-yes install postgresql-client               >> /tmp/apt3.log
    fi
	
    if [ "$fileServerType" = "azurefiles" ]; then
	# install azure cli & setup container
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ wheezy main" | \
            sudo tee /etc/apt/sources.list.d/azure-cli.list
        curl -L https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add - >> /tmp/apt4.log
        sudo apt-get -y install apt-transport-https >> /tmp/apt4.log
        sudo apt-get -y update > /dev/null
        sudo apt-get -y install azure-cli >> /tmp/apt4.log
	
        # FileStorage accounts can only be used to store Azure file shares;
        # Premium_LRS will support FileStorage kind
        # No other storage resources (blob containers, queues, tables, etc.) can be deployed in a FileStorage account.
        if [ $storageAccountType != "Premium_LRS" ]; then
		az storage container create \
		    --name objectfs \
		    --account-name $storageAccountName \
		    --account-key $storageAccountKey \
		    --public-access off \
		    --fail-on-exist >> /tmp/wabs.log

		az storage container policy create \
		    --account-name $storageAccountName \
		    --account-key $storageAccountKey \
		    --container-name objectfs \
		    --name readwrite \
		    --start $(date --date="1 day ago" +%F) \
		    --expiry $(date --date="2199-01-01" +%F) \
		    --permissions rw >> /tmp/wabs.log

		sas=$(az storage container generate-sas \
		    --account-name $storageAccountName \
		    --account-key $storageAccountKey \
		    --name objectfs \
		    --policy readwrite \
		    --output tsv)
	fi
    fi

    if [ $fileServerType = "gluster" ]; then
        # mount gluster files system
        echo -e '\n\rInstalling GlusterFS on '$glusterNode':/'$glusterVolume '/wordpress\n\r' 
        setup_and_mount_gluster_wordpress_share $glusterNode $glusterVolume
    elif [ $fileServerType = "nfs-ha" ]; then
        # mount NFS-HA export
        echo -e '\n\rMounting NFS export from '$nfsHaLbIP' on /wordpress\n\r'
        configure_nfs_client_and_mount $nfsHaLbIP $nfsHaExportPath /wordpress
    elif [ $fileServerType = "nfs-byo" ]; then
        # mount NFS-BYO export
        echo -e '\n\rMounting NFS export from '$nfsByoIpExportPath' on /wordpress\n\r'
        configure_nfs_client_and_mount0 $nfsByoIpExportPath /wordpress
    fi
    
    # install pre-requisites
    sudo add-apt-repository ppa:ubuntu-toolchain-r/ppa
    sudo apt-get update > /dev/null 2>&1
    #sudo apt-get install -y --fix-missing python-software-properties unzip
    sudo apt-get install -y software-properties-common
    sudo apt-get install unzip


    # install the entire stack
    # passing php versions $phpVersion
    sudo apt-get -y  --force-yes install nginx php$phpVersion-fpm varnish >> /tmp/apt5a.log
    sudo apt-get -y  --force-yes install php$phpVersion php$phpVersion-cli php$phpVersion-curl php$phpVersion-zip >> /tmp/apt5b.log

    # WordPress requirements
    sudo apt-get -y update > /dev/null
    sudo apt-get install -y --force-yes graphviz aspell php$phpVersion-common php$phpVersion-soap php$phpVersion-json php$phpVersion-redis > /tmp/apt6.log
    sudo apt-get install -y --force-yes php$phpVersion-bcmath php$phpVersion-gd php$phpVersion-xmlrpc php$phpVersion-intl php$phpVersion-xml php$phpVersion-bz2 php-pear php$phpVersion-mbstring php$phpVersion-dev mcrypt >> /tmp/apt6.log
    PhpVer=$(get_php_version)
    if [ $dbServerType = "mysql" ]; then
        sudo apt-get install -y --force-yes php$phpVersion-mysql
    elif [ $dbServerType = "mssql" ]; then
        sudo apt-get install -y libapache2-mod-php  # Need this because install_php_mssql_driver tries to update apache2-mod-php settings always (which will fail without this)
        install_php_mssql_driver
    else
        sudo apt-get install -y --force-yes php-pgsql
    fi

    # Set up initial wordpress dirs
    mkdir -p /wordpress/html
    mkdir -p /wordpress/certs
    mkdir -p /wordpress/data

    # install WordPress 
  
    function install_wordpress_application {
        local dnsSite=$siteFQDN
        local wpTitle=Azure-WordPress
        local wpAdminUser=admin
        local wpAdminPassword=$adminpass
        local wpAdminEmail=admin@$dnsSite
        local wpPath=/wordpress/html/wordpress
        local wpDbUserId=$wordpressdbuser
        local wpDbUserPass=$wordpressdbpass
        local applicationDbName=wordpress
        local wpVersion=$wordpressVersion
        

        # Creates a Database for CMS application
        create_database $dbIP $dbadminloginazure $dbadminpass $applicationDbName $wpDbUserId $wpDbUserPass
        # Download the WordPress application compressed file
        download_wordpress $dnsSite $wpVersion
        # Links the data content folder to shared folder.. /azlamp/data
        linking_data_location 
        # Creates a wp-config file for WordPress
        create_wpconfig $dbIP $applicationDbName $dbadminloginazure $dbadminpass $dnsSite
        # Installs WP-CLI tool
        install_wp_cli
        # Install WordPress by using wp-cli commands
        install_wordpress $dnsSite $wpTitle $wpAdminUser $wpAdminPassword $wpAdminEmail $wpPath
        # Install WooCommerce plug-in
        install_plugins $wpPath
        # Generates the openSSL certificates
        generate_sslcerts $dnsSite
        # Generate the text file
        generate_text_file $dnsSite $wpAdminUser $wpAdminPassword $dbIP $wpDbUserId $wpDbUserPass $sshUsername
    }

    install_wordpress_application
    
    # chmod 755 /tmp/setup-wordpress.sh
    # /tmp/setup-wordpress.sh >> /tmp/setupwordpress.log

    # Build nginx config
    cat <<EOF > /etc/nginx/nginx.conf
user www-data;
worker_processes 2;
pid /run/nginx.pid;

events {
	worker_connections 768;
}

http {

  sendfile on;
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
  gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
EOF

    if [ "$httpsTermination" != "None" ]; then
        cat <<EOF >> /etc/nginx/nginx.conf
  map \$http_x_forwarded_proto \$fastcgi_https {                                                                                          
    default \$https;                                                                                                                   
    http '';                                                                                                                          
    https on;                                                                                                                         
  }
EOF
    fi

    cat <<EOF >> /etc/nginx/nginx.conf
  log_format wordpress_combined '\$remote_addr - \$upstream_http_x_wordpressuser [\$time_local] '
                             '"\$request" \$status \$body_bytes_sent '
                             '"\$http_referer" "\$http_user_agent"';


  include /etc/nginx/conf.d/*.conf;
  include /etc/nginx/sites-enabled/*;
}
EOF

    cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 81 default;
        server_name ${siteFQDN};
        root /wordpress/html/wordpress;
        index index.php index.html index.htm;

        # Log to syslog
        error_log syslog:server=localhost,facility=local1,severity=error,tag=wordpress;
        access_log syslog:server=localhost,facility=local1,severity=notice,tag=wordpress wordpress_combined;

        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;
EOF
    if [ "$httpsTermination" != "None" ]; then
        cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
        # Redirect to https
        if (\$http_x_forwarded_proto != https) {
                return 301 https://\$server_name\$request_uri;
        }
        rewrite ^/(.*\.php)(/)(.*)$ /\$1?file=/\$3 last;
EOF
    fi

    cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
        # Filter out php-fpm status page
        location ~ ^/server-status {
            return 404;
        }

	location / {
		try_files \$uri \$uri/index.php?\$query_string;
	}
 
    location ~ [^/]\.php(/|$) {
        fastcgi_split_path_info ^(.+?\.php)(/.*)$;
        if (!-f \$document_root\$fastcgi_script_name) {
                return 404;
        }

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
    if [ "$httpsTermination" = "VMSS" ]; then
        cat <<EOF >> /etc/nginx/sites-enabled/${siteFQDN}.conf
server {
        listen 443 ssl;
        root /wordpress/html/wordpress;
        index index.php index.html index.htm;

        ssl on;
        ssl_certificate /wordpress/certs/nginx.crt;
        ssl_certificate_key /wordpress/certs/nginx.key;

        # Log to syslog
        error_log syslog:server=localhost,facility=local1,severity=error,tag=wordpress;
        access_log syslog:server=localhost,facility=local1,severity=notice,tag=wordpress wordpress_combined;

        # Log XFF IP instead of varnish
        set_real_ip_from    10.0.0.0/8;
        set_real_ip_from    127.0.0.1;
        set_real_ip_from    172.16.0.0/12;
        set_real_ip_from    192.168.0.0/16;
        real_ip_header      X-Forwarded-For;
        real_ip_recursive   on;

        location / {
          proxy_set_header Host \$host;
          proxy_set_header HTTP_REFERER \$http_referer;
          proxy_set_header X-Forwarded-Host \$host;
          proxy_set_header X-Forwarded-Server \$host;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
          proxy_pass http://localhost:80;
        }
}
EOF
    fi

    if [ "$httpsTermination" = "VMSS" ]; then
        ### SSL cert ###
        if [ "$thumbprintSslCert" != "None" ]; then
            echo "Using VM's cert (/var/lib/waagent/$thumbprintSslCert.*) for SSL..."
            cat /var/lib/waagent/$thumbprintSslCert.prv > /wordpress/certs/nginx.key
            cat /var/lib/waagent/$thumbprintSslCert.crt > /wordpress/certs/nginx.crt
            if [ "$thumbprintCaCert" != "None" ]; then
                echo "CA cert was specified (/var/lib/waagent/$thumbprintCaCert.crt), so append it to nginx.crt..."
                cat /var/lib/waagent/$thumbprintCaCert.crt >> /wordpress/certs/nginx.crt
            fi
        else
            echo -e "Generating SSL self-signed certificate"
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /wordpress/certs/nginx.key -out /wordpress/certs/nginx.crt -subj "/C=US/ST=WA/L=Redmond/O=IT/CN=$siteFQDN"
        fi
        chown www-data:www-data /wordpress/certs/nginx.*
        chmod 0400 /wordpress/certs/nginx.*
    fi

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

   # Remove the default site. WordPress is the only site we want
   rm -f /etc/nginx/sites-enabled/default

   # restart Nginx
   sudo service nginx restart 

   # Configure varnish startup for 16.04
   VARNISHSTART="ExecStart=\/usr\/sbin\/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f \/etc\/varnish\/wordpress.vcl -S \/etc\/varnish\/secret -s malloc,1024m -p thread_pool_min=200 -p thread_pool_max=4000 -p thread_pool_add_delay=2 -p timeout_linger=100 -p timeout_idle=30 -p send_timeout=1800 -p thread_pools=4 -p http_max_hdr=512 -p workspace_backend=512k"
   sed -i "s/^ExecStart.*/${VARNISHSTART}/" /lib/systemd/system/varnish.service

   # Configure varnish VCL for wordpress
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

    if [ $dbServerType = "mysql" ]; then
        mysql -h $mysqlIP -u $mysqladminlogin -p${mysqladminpass} -e "CREATE DATABASE ${wordpressdbname} CHARACTER SET utf8;"
        mysql -h $mysqlIP -u $mysqladminlogin -p${mysqladminpass} -e "GRANT ALL ON ${wordpressdbname}.* TO ${wordpressdbuser} IDENTIFIED BY '${wordpressdbpass}';"

        echo "mysql -h $mysqlIP -u $mysqladminlogin -p${mysqladminpass} -e \"CREATE DATABASE ${wordpressdbname};\"" >> /tmp/debug
        echo "mysql -h $mysqlIP -u $mysqladminlogin -p${mysqladminpass} -e \"GRANT ALL ON ${wordpressdbname}.* TO ${wordpressdbuser} IDENTIFIED BY '${wordpressdbpass}';\"" >> /tmp/debug
    elif [ $dbServerType = "mssql" ]; then
        /opt/mssql-tools/bin/sqlcmd -S $mssqlIP -U $mssqladminlogin -P ${mssqladminpass} -Q "CREATE DATABASE ${wordpressdbname} ( MAXSIZE = $mssqlDbSize, EDITION = '$mssqlDbEdition', SERVICE_OBJECTIVE = '$mssqlDbServiceObjectiveName' )"
        /opt/mssql-tools/bin/sqlcmd -S $mssqlIP -U $mssqladminlogin -P ${mssqladminpass} -Q "CREATE LOGIN ${wordpressdbuser} with password = '${wordpressdbpass}'" 
        /opt/mssql-tools/bin/sqlcmd -S $mssqlIP -U $mssqladminlogin -P ${mssqladminpass} -d ${wordpressdbname} -Q "CREATE USER ${wordpressdbuser} FROM LOGIN ${wordpressdbuser}"
        /opt/mssql-tools/bin/sqlcmd -S $mssqlIP -U $mssqladminlogin -P ${mssqladminpass} -d ${wordpressdbname} -Q "exec sp_addrolemember 'db_owner','${wordpressdbuser}'" 
        
    else
        # Create postgres db
        echo "${postgresIP}:5432:postgres:${pgadminlogin}:${pgadminpass}" > /root/.pgpass
        chmod 600 /root/.pgpass
        psql -h $postgresIP -U $pgadminlogin -c "CREATE DATABASE ${wordpressdbname};" postgres
        psql -h $postgresIP -U $pgadminlogin -c "CREATE USER ${wordpressdbuser} WITH PASSWORD '${wordpressdbpass}';" postgres
        psql -h $postgresIP -U $pgadminlogin -c "GRANT ALL ON DATABASE ${wordpressdbname} TO ${wordpressdbuser};" postgres
        rm -f /root/.pgpass
    fi

    # Master config for syslog
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
    service rsyslog restart

    # Fire off wordpress setup
    if [ "$httpsTermination" = "None" ]; then
        siteProtocol="http"
    else
        siteProtocol="https"
    fi
    

    echo -e "\n\rDone! Installation completed!\n\r"

    
    

    if [ "$dbServerType" = "postgres" ]; then
     # Get a new version of Postgres to match Azure version
     add-apt-repository "deb http://apt.postgresql.org/pub/repos/apt/ xenial-pgdg main"
     wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
     apt-get update
     apt-get install -y postgresql-client-9.6
    fi

   # create cron entry
#    # It is scheduled for once per minute. It can be changed as needed.
#    echo '* * * * * www-data /usr/bin/php /wordpress/html/wordpress/admin/cli/cron.php 2>&1 | /usr/bin/logger -p local2.notice -t wordpress' > /etc/cron.d/wordpress-cron

   # Set up cronned sql dump
   if [ "$dbServerType" = "mysql" ]; then
      cat <<EOF > /etc/cron.d/sql-backup
22 02 * * * root /usr/bin/mysqldump -h $mysqlIP -u ${azurewordpressdbuser} -p'${wordpressdbpass}' --databases ${wordpressdbname} | gzip > /wordpress/db-backup.sql.gz
EOF
   elif [ "$dbServerType" = "postgres" ]; then
      cat <<EOF > /etc/cron.d/sql-backup
22 02 * * * root /usr/bin/pg_dump -Fc -h $postgresIP -U ${azurewordpressdbuser} ${wordpressdbname} > /wordpress/db-backup.sql
EOF
   #else # mssql. TODO It's missed earlier! Complete this!
   fi

   # Turning off services we don't need the controller running
   service nginx stop
   service php${PhpVer}-fpm stop
   service varnish stop
   service varnishncsa stop
   #service varnishlog stop

    # No need to run the commands below any more, as permissions & modes are already as such (no more "sudo -u www-data ...")
    # Leaving this code as a remark that we are explicitly leaving the ownership to root:root
#    if [ $fileServerType = "gluster" -o $fileServerType = "nfs" -o $fileServerType = "nfs-ha" ]; then
#       # make sure wordpress can read its code directory but not write
#       sudo chown -R root.root /wordpress/html/wordpress
#       sudo find /wordpress/html/wordpress -type f -exec chmod 644 '{}' \;
#       sudo find /wordpress/html/wordpress -type d -exec chmod 755 '{}' \;
#    fi
    # But now we need to adjust the data and the certs directory ownerships, and the permission for the generated config.php
    sudo chown -R www-data.www-data /wordpress/data /wordpress/certs
    

    # chmod /wordpress for Azure NetApp Files (its default is 770!)
    if [ $fileServerType = "nfs-byo" ]; then
        sudo chmod +rx /wordpress
    fi

   if [ $fileServerType = "azurefiles" ]; then
      # Delayed copy of wordpress installation to the Azure Files share

      # First rename wordpress directory to something else
      mv /wordpress /wordpress_old_delete_me
      # Then create the wordpress share
      echo -e '\n\rCreating an Azure Files share for wordpress'
      create_azure_files_wordpress_share $storageAccountName $storageAccountKey /tmp/wabs.log $fileServerDiskSize
      # Set up and mount Azure Files share. Must be done after nginx is installed because of www-data user/group
      echo -e '\n\rSetting up and mounting Azure Files share on //'$storageAccountName'.file.core.windows.net/wordpress on /wordpress\n\r'
      setup_and_mount_azure_files_wordpress_share $storageAccountName $storageAccountKey
      # Move the local installation over to the Azure Files
      echo -e '\n\rMoving locally installed wordpress over to Azure Files'
      cp -a /wordpress_old_delete_me/* /wordpress || true # Ignore case sensitive directory copy failure
      rm -rf /wordpress_old_delete_me || true # Keep the files just in case
   fi

   create_last_modified_time_update_script
   run_once_last_modified_time_update_script
   
}  > /tmp/install.log
