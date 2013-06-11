### Overview

Front-end load balancer is responsible for:
* terminate the ssl connection
* authenticate the client request
* set the authentication information in proxy request headers
* pass the request to back-end puppet workers


Worker is responsible for:
* compiling the catalog

```
.--------.     .---------------.          .---------------.
| client |---->| LOAD BALANCER |----+---->| puppet master |
`--------'     |  + puppet CA  |    |     |   worker 1    |
               `---------------'    |     `---------------'
                                    |     .---------------.
                                    `---->| puppet master |
                                          |    worker 2   |
                                          `---------------'

```

On all servers puppet and nginx have to be installed (take a look here: https://github.com/faja/howtos/tree/master/puppet/puppet_master_with_nginx for details)   


### LOAD BALANCER
* nginx.conf
```
...
http {
  ...
  # passenger for puppet
  passenger_root  /usr/lib/ruby/gems/1.8/gems/passenger-4.0.5;
  passenger_ruby  /usr/bin/ruby;
  passenger_max_pool_size 15;
  include /etc/nginx/conf.d/puppet_ca.conf;
}
```
* puppet_ca.conf
```
upstream puppet_workers {
  server 192.168.2.4:8140 weight=10 max_fails=1 fail_timeout=10s;
  server 192.168.2.5:8140 weight=10 max_fails=1 fail_timeout=10s;
}

server {
  listen                     8140 ssl;
  server_name                puppet puppet.your.domain.com;

  access_log                 /var/log/nginx/puppet_access.log;
  error_log                  /var/log/nginx/puppet_error.log;

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

  location / {
    proxy_set_header X-CLIENT-DN $ssl_client_s_dn;
    proxy_set_header X-CLIENT-VERIFY $ssl_client_verify;
    proxy_set_header Host $host;
    proxy_pass http://puppet_workers;
  }

  location ~ ^(/.*?)/(certificate.*?)/(.*)$ {
    passenger_enabled          on;
    passenger_set_cgi_param    HTTP_X_CLIENT_DN $ssl_client_s_dn;
    passenger_set_cgi_param    HTTP_X_CLIENT_VERIFY $ssl_client_verify;
    root                       /etc/puppet/rack/public;
  }
}
```
### BACK-END WORKER
* nginx.conf
```
...
http {
  ...
  # passenger for puppet
  passenger_root  /usr/lib/ruby/gems/1.8/gems/passenger-4.0.5;
  passenger_ruby  /usr/bin/ruby;
  passenger_max_pool_size 15;
  include /etc/nginx/conf.d/puppet_worker.conf;
```

* puppet_worker.conf
```
server {
  listen                     8140 default;

  access_log                 /var/log/nginx/puppet_access.log;
  error_log                  /var/log/nginx/puppet_error.log;

  location / {
    ## allow traffic only from LB
    allow 192.168.2.2;
    deny all;
    passenger_enabled          on;
    passenger_set_cgi_param    HTTP_X_CLIENT_DN $http_x_client_dn;
    passenger_set_cgi_param    HTTP_X_CLIENT_VERIFY $http_x_client_verify;
    root                       /etc/puppet/rack/public;
  }
}
```
