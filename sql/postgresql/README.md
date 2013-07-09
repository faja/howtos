####HA POSTGRES CLUSTER by STREAMING REPLICATION + PGPOOL-II
---

###OVERVIEW

In this manual i use ubuntu 12.04, postgres-9.1 and pgpool2-3.1

Hosts:
 * master  192.168.200.2
 * slave1  192.168.200.3
 * slave2  192.168.200.4
 * app     192.168.200.5

Users:
 * postgres - system user which runs all postgresql servers and pgpool service
 * repl - db user for replication
 * pgpool - db user for pgpool checks



Diagram:
```
  .-----.                  .--------.
  |     |           W      |   DB   |
  | APP |-----+----------->| MASTER |----.
  |     |     |            |        |    |
  `-----`     |            `--------`    | STREAMING REPLICATION
              |            .--------.    |
              |     R      |   DB   |    |
              +----------->| SLAVE1 |<---+      
              |            |        |    |
              |            `--------`    |
              |            .--------.    |
              |     R      |   DB   |    |
              `----------->| SLAVE2 |<---`
                           |        |
                           `--------`
```

after failover

```
  .-----.                  .--------.
  |     |                  |   DB   |
  | APP |-----+----        | MASTER |
  |     |     |            |  FAIL  |
  `-----`     |            `--------`
              |            .--------.
              |    W/R     |   DB   |
              +----------->| SLAVE1 |---.          
              |            |        |   |
              |            `--------`   |
              |            .--------.   | STREAMING REPLICATION
              |     R      |   DB   |   |
              `----------->| SLAVE2 |<--`
                           |        |
                           `--------`

```
###STEP 1

Let's start from installing postgresql server on all machines, and generate ssh keys.   
User 'postgres' have to be able to ssh:
* from app to slave1
* from app to slave2
* from slave1 to slave2
* from master to slave1 and slave2 (optionally, to copy base_backup.tar)

```
master# apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
master# /etc/init.d/postgresql stop
master# su - postgres
  postgres@master$ ssh-keygen -trsa -b 4096
```

```
slave1# apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
slave1# /etc/init.d/postgresql stop
slave1# su - postgres
  postgres@slave1$ ssh-keygen -trsa -b 4096
```

```
slave2# apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
slave2# /etc/init.d/postgresql stop
slave2# su - postgres
  postgres@slave2$ ssh-keygen -trsa -b 4096
```

```
app# apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
app# /etc/init.d/postgresql stop
app# su - postgres
  postgres@app$ ssh-keygen -trsa -b 4096
```

Right now add id_rsa.pub file to ~/.ssh/authorized_keys on appropriate hosts, and test connections:
* from master to slave1 and slave2
 ```
 postgres@master$ ssh slave1
 postgres@master$ ssh slave2
 ```

* from slave1 to slave2
 ```
 postgres@slave1$ ssh slave2
 ```

* from app to slave1 and slave2
 ```
 postgres@app$ ssh slave1
 postgres@app$ ssh slave2
 ```


Ok that was easy:) Let's prepare master host.

###STEP 2 - MASTER
postgresql.conf
```
master# vim /etc/postgresql/9.1/main/postgresql.conf
```
```
  ...
  listen_addresses = '*'
  wal_level = hot_standby
  max_wal_senders = 2
  wal_keep_segments = 50
  hot_standby = on
  archive_mode = on
  archive_command = 'test ! -f /var/lib/postgresql/9.1/archiving_active || cp -i %p /var/lib/postgresql/9.1/archive/%f'
  ...
```

Next, we have to add 'repl' and 'pgpool' users in pg_hba.conf file and in postgres
```
master# echo host replication repl 192.168.200.3/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
master# echo host replication repl 192.168.200.4/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
master# echo host all pgpool 192.168.200.5/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
```
right now we can start postgresql server and add users
```
master# /etc/init.d/postgresql start
master# su - postgres
postgres@master$ psql
  postgres=# CREATE USER repl REPLICATION ENCRYPTED PASSWORD 'repl';
  postgres=# CREATE USER pgpool LOGIN ENCRYPTED PASSWORD 'pgpool';
```
Of course you have to add user needed by your application as well,   
for test purpose we can add below line to pg_hba.conf file
```
  host all postgres 192.168.200.5/32 trust
```

Create 'base backup':
```
master# su - postgres
  postgres@master$ cd /var/lib/postgresql/9.1/
  postgres@master$ mkdir archive
  postgres@master$ touch archiving_active
  postgres@master$ psql -c "select pg_start_backup('base_backup');"
  postgres@master$ tar -cvf base_backup.tar --exclude=pg_xlog --exclude=postmaster.pid main/
  postgres@master$ psql -c "select pg_stop_backup();"
  postgres@master$ tar -rf base_backup.tar archive
```
if you want you can disable archiving now
```
  postgres@master$ rm archiving_active
```
Ok so, we have master server up and running and we have base backup to restore it on slaves.
```
  postgres@master$ scp base_backup.tar slave1:~
  postgres@master$ scp base_backup.tar slave2:~
```



### STEP 3 - SLAVE1

postgresql.conf
```
slave1# vim /etc/postgresql/9.1/main/postgresql.conf
```
```
  # important options
  ...
  listen_addresses = '*'
  wal_level = hot_standby
  max_wal_senders = 2
  wal_keep_segments = 50
  hot_standby = on
  ...
```

add 'repl' and 'pgpool' users to pg_hba.conf file
```
slave1# echo host replication repl 192.168.200.4/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
slave1# echo host all pgpool 192.168.200.5/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
```
And like on master add your app user as well.   
For test purpose we can add below line to pg_hba.conf file:
```
  host all postgres 192.168.200.5/32 trust
```

Replication:
```
slave1# su - postgres
  postgres@slave1$ cd /var/lib/postgresql/9.1
  postgres@slave1$ mv ~/base_backup.tar .
  postgres@slave1$ rm -rf main/
  postgres@slave1$ tar -xvf base_backup.tar
  postgres@slave1$ mkdir main/pg_xlog
  postgres@slave1$ vim main/recovery.conf
```
```
  standby_mode = 'on'
  primary_conninfo = 'host=192.168.200.2 port=5432 user=repl password=repl'
  restore_command = 'cp /var/lib/postgresql/9.1/archive/%f %p'
  recovery_target_timeline='latest'
  trigger_file = '/tmp/pgsql.trigger'
```

start postgresql server
```
slave1# /etc/init.d/postgresql start
```
and check if replication is working
```
slave1# ps -u postgres u
    ...
    postgres: wal receiver process   streaming
    ...
```

### STEP 3 - SLAVE2


postgresql.conf
```
slave2# vim /etc/postgresql/9.1/main/postgresql.conf
```
```
  # important options
  ...
  listen_addresses = '*'
  hot_standby = on
  ...
```

add 'pgpool' user to pg_hba.conf file
```
slave2# echo host all pgpool 192.168.200.5/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
```
And like on master add your app user as well.   
For test purpose we can add below line to pg_hba.conf file:
```
  host all postgres 192.168.200.5/32 trust
```

Replication:
```
slave2# su - postgres
  postgres@slave2$ cd /var/lib/postgresql/9.1
  postgres@slave2$ mv ~/base_backup.tar .
  postgres@slave2$ rm -rf main/
  postgres@slave2$ tar -xvf base_backup.tar
  postgres@slave2$ mkdir main/pg_xlog
  postgres@slave2$ vim main/recovery.conf
```
```
  standby_mode = 'on'
  primary_conninfo = 'host=192.168.200.2 port=5432 user=repl password=repl'
  restore_command = 'cp /var/lib/postgresql/9.1/archive/%f %p'
  recovery_target_timeline='latest'
```

start postgresql server
```
slave2# /etc/init.d/postgresql start
```
and check if replication is working
```
slave2# ps -u postgres u
    ...
    postgres: wal receiver process   streaming
    ...
```

### STEP 4 - APP

install pgpool
```
app# apt-get -y install pgpool2 postgresql-9.1-pgpool2                                                                                                                                                                      
app# /etc/init.d/pgpool2 stop
```

prepare pgpool configuration
```
app# cd /etc/pgpool2/
app# cp pgpool.conf{,.back}
app# cp pcp.conf{,.back}
app# echo pgpool:`pg_md5 pgpool` >> pcp.conf
app# vim pgpool.conf
```
```
    #-------------#
    # CONNECTIONS #
    #-------------#
    listen_addresses = 'localhost'
    port = 5432
    socket_dir = '/var/run/postgresql'
    pcp_port = 9898
    pcp_socket_dir = '/var/run/postgresql'

    #---------#
    # BACKEND #
    #---------#
    backend_hostname0 = '192.168.200.2'
    backend_port0 = 5432
    backend_weight0 = 0
    backend_data_directory0 = '/var/lib/postgresql/9.1/main'
    backend_flag0 = 'ALLOW_TO_FAILOVER'

    backend_hostname1 = '192.168.200.3'
    backend_port1 = 5432
    backend_weight1 = 1
    backend_data_directory1 = '/var/lib/postgresql/9.1/main'
    backend_flag1 = 'ALLOW_TO_FAILOVER'

    backend_hostname2 = '192.168.200.4'
    backend_port2 = 5432
    backend_weight2 = 1
    backend_data_directory2 = '/var/lib/postgresql/9.1/main'
    backend_flag2 = 'ALLOW_TO_FAILOVER'

    #------#
    # AUTH #
    #------#
    enable_pool_hba = off
    pool_passwd = ''
    authentication_timeout = 60

    #-----#
    # SSL #
    #-----#
    ssl = off

    #-------#
    # POOLS #
    #-------#
    num_init_children = 32
    max_pool = 4
    child_life_time = 300
    child_max_connections = 0
    connection_life_time = 0
    client_idle_limit = 0

    #------#
    # LOGS #
    #------#
    log_destination = 'stderr'
    print_timestamp = on
    log_connections = on
    log_hostname = off
    log_statement = on
    log_per_node_statement = on
    log_standby_delay = 'none'
    syslog_facility = 'LOCAL0'
    syslog_ident = 'pgpool'
    debug_level = 0

    #----------------#
    # FILE LOCATIONS #
    #----------------#
    pid_file_name = '/var/run/postgresql/pgpool.pid'
    logdir = '/var/log/postgresql'

    #--------------------#
    # CONNECTION POOLING #
    #--------------------#
    connection_cache = on
    reset_query_list = 'ABORT; DISCARD ALL'

    #------------------#
    # REPLICATION MODE #
    #------------------#
    replication_mode = off
    replicate_select = off
    insert_lock = on
    lobj_lock_table = ''
    replication_stop_on_mismatch = off
    failover_if_affected_tuples_mismatch = off


    #---------------------#
    # LOAD BALANCING MODE #
    #---------------------#
    load_balance_mode = on
    ignore_leading_white_space = on
    white_function_list = ''
    black_function_list = 'nextval,setval'


    #-------------------#
    # MASTER/SLAVE MODE #
    #-------------------#
    master_slave_mode = on
    master_slave_sub_mode = 'stream'

    sr_check_period = 0
    sr_check_user = 'pgpool'
    sr_check_password = 'pgpool'
    delay_threshold = 0

    follow_master_command = ''

    #-------------------------------#
    # PARALLEL MODE AND QUERY CACHE #
    #-------------------------------#
    parallel_mode = off
    enable_query_cache = off
    pgpool2_hostname = ''
    system_db_hostname  = 'localhost'
    system_db_port = 5432 
    system_db_dbname = 'pgpool'
    system_db_schema = 'pgpool_catalog'
    system_db_user = 'pgpool'
    system_db_password = ''

    #--------------#
    # HEALTH CHECK #
    #--------------#
    health_check_period = 0
    health_check_timeout = 20
    health_check_user = 'pgpool'
    health_check_password = 'pgpool'

    #-----------------------#
    # FAILOVER AND FAILBACK #
    #-----------------------#
    failover_command = '/var/lib/postgresql/bin/failover.sh %d %M %m'
    failback_command = ''
    fail_over_on_backend_error = on

    #-----------------#
    # ONLINE RECOVERY #
    #-----------------#
    recovery_user = 'nobody'
    recovery_password = ''
    recovery_1st_stage_command = ''
    recovery_2nd_stage_command = ''
    recovery_timeout = 90
    client_idle_limit_in_recovery = 0


    #--------#
    # OTHERS #
    #--------#
    relcache_expire = 0
```
  
failover script
```
app# su - postgres
  postgres@app$ mkdir bin
  postgres@app$ vim bin/failover.sh
```
```
  #!/bin/sh -

  FALLING_NODE=$1
  OLD_MASTER=$2
  NEW_MASTER=$3

  SLAVE1='192.168.200.3'
  SLAVE2='192.168.200.4'

  if test $FALLING_NODE -eq 0
  then
    ssh -T $SLAVE1 touch /tmp/pgsql.trigger
    ssh -T $SLAVE1 "while test ! -f /var/lib/postgresql/9.1/main/recovery.done; do sleep 1; done; scp /var/lib/postgresql/9.1/main/pg_xlog/*history* $SLAVE2:/var/lib/postgresql/9.1/main/pg_xlog/"
    ssh -T $SLAVE2 "sed -i 's/192.168.200.2/192.168.200.3/' /var/lib/postgresql/9.1/main/recovery.conf"
    ssh -T $SLAVE2 /etc/init.d/postgresql restart
    /usr/sbin/pcp_attach_node 10 localhost 9898 pgpool pgpool 2
  fi
```
```
  postgres@app$ chmod u+x bin/failover.sh
```    

to be sure failover will success, test scp command:
```
postgres@slave1$ cd
postgres@slave1$ touch test_scp
```
```
postgres@app$ scp slave1:~/test_scp slave2:~
```
```
postgres@slave2$ cd
postgres@slave2$ ls test_scp
```

ok, and finally start pgpool
```
app# /etc/init.d/pgpool2 start
app# pcp_node_count 10 localhost 9898 pgpool pgpool
app# pcp_node_info 10 localhost 9898 pgpool pgpool 0
app# pcp_node_info 10 localhost 9898 pgpool pgpool 1
app# pcp_node_info 10 localhost 9898 pgpool pgpool 2
```


### STEP 5 - TEST:)
prepare test database
```
root@app:~# su - postgres
postgres@app:~$ psql -c "CREATE DATABASE testdb1;"
CREATE DATABASE
postgres@app:~$ psql -d testdb1 -c "CREATE TABLE testtable1 (i int);"
CREATE TABLE
postgres@app:~$ psql -d testdb1 -c "INSERT INTO testtable1 values (0);"
INSERT 0 1
postgres@app:~$ psql -d testdb1 -c "SELECT * from testtable1;"
 i
---
 0
(1 row)
```

stop server on master
```
root@master:~# /etc/init.d/postgresql stop
 * Stopping PostgreSQL 9.1 database server
   ...done.
```
test failover
```
postgres@app:~$ psql -d testdb1 -c "INSERT INTO testtable1 values (1);"
INSERT 0 1
postgres@app:~$ psql -d testdb1 -c "SELECT * from testtable1;"
 i
---
 0
 1
(2 rows)
```


### ABOUT FAILOVER
If master fails, on slave1 trigger file is created, and slave1 is promoted to be new master.
When it happend in $PGDATA/pg_xlog/ directory file TIMELINE_ID.history (eg. '00000002.history') is created.
That file is needed by second slave to change 'TIMELINE ID' and to start replicate data from new master.

### REFERENCES
* http://www.postgresql.org/docs/9.1/static/high-availability.html
* http://www.pgpool.net/docs/latest/pgpool-en.html
