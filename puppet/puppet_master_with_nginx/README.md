### puppet master with nginx and passenger
OS: CentOS 6

#### installation

Very first step is to build nginx with passanger support.   
To do this:
* install rake, rack and passenger gems   
```
# gem install rake rack passenger
```
* install packages needed to build nginx with passenger support   
```
# yum install gcc gcc-c++ make rpm-build pcre-devel openssl-devel curl-devel pam-devel zlib-devel
```

* download the freshest source rpm from: http://nginx.org/packages/rhel/6/SRPMS/   
```
# cd /usr/src
# wget http://nginx.org/packages/rhel/6/SRPMS/nginx-1.4.1-1.el6.ngx.src.rpm
```
* install src.rpm
```
# rpm -ivh nginx-1.4.1-1.el6.ngx.src.rpm
# cd /root/rpmbuild/SPECS/
# cp nginx.spec{,.back}
```

* add ```--add-module=`passenger-config --root`/ext/nginx \``` to ```./configuration``` at ```%build``` stage   
diff should be looks like:
```
# diff nginx.spec nginx.spec.back 
92d91
<               --add-module=`passenger-config --root`/ext/nginx \
129d127
<               --add-module=`passenger-config --root`/ext/nginx \
```
* build and install nginx rpm:
```
# rpmbuild -bb nginx.spec
# cd /root/rpmbuild/RPMS/x86_64
# rpm -ivh nginx-1.4.1-1.el6.ngx.x86_64.rpm
# rpm -ivh nginx-debug-1.4.1-1.el6.ngx.x86_64.rpm
```


#### configuration
* create rack dir and copy config.ru there
```
# cd /etc/puppet && mkdir -p rack/public
# cd rack
# cp `rpm -ql puppet-3.1.1-1.el6.noarch |grep config.ru` .
# chown -R puppet:puppet /etc/puppet
```
common mistake is to copy ```config.ru``` to ```/etc/puppet/rack/public```, so be sure to copy it to ```/etc/puppet/rack```   

* check passenger root, which will be used in ```passanger_root``` nginx config option
```
# passenger-config --root
```
* add passenger options into nginx's ```http{}``` block
```
http {
...
passenger_root           /usr/lib/ruby/gems/1.8/gems/passenger-4.0.5;
passenger_ruby           /usr/bin/ruby;
passenger_max_pool_size  15;
include                  /etc/nginx/conf.d/puppet.conf;
...
}
```

* add puppet.conf file
```
# cat > /etc/nginx/conf.d/puppet.conf
server {
  listen                     8140 ssl;
  server_name                puppet puppet.your.domain.com;

  passenger_enabled          on;
  passenger_set_cgi_param    HTTP_X_CLIENT_DN $ssl_client_s_dn; 
  passenger_set_cgi_param    HTTP_X_CLIENT_VERIFY $ssl_client_verify; 

  access_log                 /var/log/nginx/puppet_access.log;
  error_log                  /var/log/nginx/puppet_error.log;

  root                       /etc/puppet/rack/public;

  ssl_certificate            /var/lib/puppet/ssl/certs/puppet.your.domain.com.pem;
  ssl_certificate_key        /var/lib/puppet/ssl/private_keys/puppet.your.domain.com.pem;
  ssl_crl                    /var/lib/puppet/ssl/ca/ca_crl.pem;
  ssl_client_certificate     /var/lib/puppet/ssl/certs/ca.pem;
  ssl_ciphers                SSLv3:TLSv1;
  ssl_prefer_server_ciphers  on;
  ssl_verify_client          optional;
  ssl_verify_depth           1;
  ssl_session_cache          shared:SSL:128m;
  ssl_session_timeout        5m;
}
```

* nginx service
```
 # /etc/init.d/puppetmaster stop   
 # chkconfig puppetmaster off   
 # chkconfig nginx on   
 # /etc/init.d/nginx restart
```

#### test
* run on client host ```# puppet agent --test```
* take a look on logs
