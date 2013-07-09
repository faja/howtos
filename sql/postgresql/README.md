
HA POSTGRES CLUSTER by STREAMING REPLICATION + PGPOOL-II


OVERVIEW

In this manual i use ubuntu 12.04, postgres-9.1 and pgpool2-3.1

Hosts:
 * master  192.168.200.2
 * slave   192.168.200.3
 * slave2  192.168.200.4
 * app     192.168.200.5



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


AFTER FAILOVER

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


-- MASTER --

First step is to install and configure postgresql server

  # apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
  # /etc/init.d/postgresql stop
  # vim /etc/postgresql/9.1/main/postgresql.conf
    
    ...
    listen_addresses = '*'
    wal_level = hot_standby
    max_wal_senders = 2
    wal_keep_segments = 50
    hot_standby = on
    archive_mode = on
    archive_command = 'test ! -f /var/lib/postgresql/9.1/archiving_active || cp -i %p /var/lib/postgresql/9.1/archive/%f'
    ...

Next, we have to add 'repl' and 'pgpool' users in pg_hba.conf file and in postgres

  # echo host replication repl 192.168.200.3/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
  # echo host replication repl 192.168.200.4/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
  # echo host all pgpool 192.168.200.5/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf

right now we can start postgresql server and add users:
  # /etc/init.d/postgresql start
  # su - postgres
  $ psql
  postgres=# CREATE USER repl REPLICATION ENCRYPTED PASSWORD 'repl';
  postgres=# CREATE USER pgpool LOGIN ENCRYPTED PASSWORD 'pgpool';

Of course you need to add user for your application, for test purpose we can add:
  host all postgres 192.168.200.5/32 trust
to pg_hba.conf file

Create 'base backup':
  # su - postgres
  $ cd /var/lib/postgresql/9.1/
  $ mkdir archive
  $ touch archiving_active
  $ psql -c "select pg_start_backup('base_backup');"
  $ tar -cvf base_backup.tar --exclude=pg_xlog --exclude=postmaster.pid main/
  $ psql -c "select pg_stop_backup();"
  $ tar -rf base_backup.tar archive
if you want you can disable archiving by:
  $ rm archiving_active
 
Right now we have master server up and running and base backup to restore it on slaves.

Note about SSH KEYS:
'postgres' user have to be able to ssh without password:
 * from app to slave1
 * from app to slave2
 * from slave1 to slave2
 * from master to slave1 and slave2 (optionally, to copy base_backup.tar)

So very important step is generate ssh keys and add public one to appropriate authorized_keys on hosts.
  # su - postgres
  $ ssh-keygen -trsa -b 4096

now, you can add master's id_rsa.pub to authorized_keys on slave1 and slave2, and copy there base_backup.tar


   $ scp base_backup.tar 192.168.200.3:~
   $ scp base_backup.tar 192.168.200.4:~





-- SLAVE 1 --

1) install and configure postgresql

  # apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
  # /etc/init.d/postgresql stop
  # vim /etc/postgresql/9.1/main/postgresql.conf

    # important options
    ...
    listen_addresses = '*'         # we want to listen on all interfaces
    wal_level = hot_standby        # we want to allow slaves to grab data from master
    max_wal_senders = 2            # how many "sender" processes master can run
    wal_keep_segments = 50         # how many WAL files we want to store
    hot_standby = on               # this one is for slaves, but could be placed on master config as well
    ...

2) add 'repl' and 'pgpool' users to pg_hba
  # echo host replication repl 192.168.200.4/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf
  # echo host all pgpool 192.168.200.5/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf


+ add user app

3) replication

  # su - postgres
  $ cd /var/lib/postgresql/9.1
  $ mv ~/base_backup.tar .
  $ rm -rf main/
  $ tar -xvf base_backup.tar
  $ mkdir main/pg_xlog
  $ vim main/recovery.conf
    standby_mode = 'on'
    primary_conninfo = 'host=192.168.200.2 port=5432 user=repl password=repl'
    restore_command = 'cp /var/lib/postgresql/9.1/archive/%f %p'
    recovery_target_timeline='latest'
    trigger_file = '/tmp/pgsql.trigger'
  $


root@slave:~# /etc/init.d/postgresql start

4) # ps -u postgres u

    postgres: wal receiver process   streaming

-- SLAVE 2 --

1) install and configure postgresql

  # apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
  # /etc/init.d/postgresql stop
  # vim /etc/postgresql/9.1/main/postgresql.conf
    # important options
    ...
    listen_addresses = '*'
    hot_standby = on
    ...

2) add 'pgpool' users to pg_hba
  # echo host all pgpool 192.168.200.5/32 md5 >> /etc/postgresql/9.1/main/pg_hba.conf

3) replication 

  # su - postgres
  $ cd /var/lib/postgresql/9.1
  $ rm -rf main/
  $ mv ~/base_backup.tar .
  $ tar -xvf base_backup.tar
  $ mkdir main/pg_xlog
  $ vim main/recovery.conf

    standby_mode = 'on'
    primary_conninfo = 'host=192.168.200.2 port=5432 user=repl password=repl'
    restore_command = 'cp /var/lib/postgresql/9.1/archive/%f %p'
    recovery_target_timeline='latest'

postgres@slave2:~/9.1$ /etc/init.d/postgresql start

4) # ps -u postgres u

 postgres: wal receiver process   streaming


-- APP --

1) install postgres and pgpool

  # apt-get -y install postgresql-9.1 postgresql-server-dev-9.1
  # /etc/init.d/postgresql stop
  # apt-get -y install pgpool2 postgresql-9.1-pgpool2                                                                                                                                                                      
  # /etc/init.d/pgpool2 stop

2) conf pgpool
  # cd /etc/pgpool2/
  # cp pgpool.conf{,.back}
  # cp pcp.conf{,.back}
  # echo pgpool:`pg_md5 pgpool` >> pcp.conf
  # vim pgpool.conf

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

  
3) add failover.sh 

  # su - postgres
  $ mkdir bin
  $ vim bin/failover.sh
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
     
  $ chmod u+x bin/failover.sh
    

3) ssh keys
   
   generate ssh key and add it to authorized_keys on slave1 and slave2
     $ ssh-keygen -t rsa -b 4096
   user postgres have to able to ssh to slave1 and 2 without password

   test it:
     $ ssh 192.168.200.3
     $ ssh 192.168.200.4


IMPORTANT THING! ssh z roznych na rozne chosty trzeba
so be sure you can run on app host scp

  scp slave1:/sadasd/ slave2:/asdsad

4) start pgpool
# /etc/init.d/pgpool2 start

5) test pgpool

# pcp_node_count 10 localhost 9898 pgpool pgpool
# pcp_node_info 10 localhost 9898 pgpool pgpool 0
# pcp_node_info 10 localhost 9898 pgpool pgpool 1
# pcp_node_info 10 localhost 9898 pgpool pgpool 2

