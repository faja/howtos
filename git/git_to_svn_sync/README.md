GIT -> SVN and sync
-----
goal
------
We have already existing git repo, and our goal is to put it to svn, and keep it synchronized after any commit/push to git.


info
-----
repo name : repo1  
git user : git  
git repos dir : /home/git/repositories  
svn repos dir : /home/svn/repositories  

note: below example assumes that git and svn repo are on the same server, if not, please use appropriate protocol scheme e.g. git@... https://...

howto
------
Ok, create svn repo first, as root:
```
# cd /home/svn/repositories/
# svnadmin create repo1
# chown -R git repo1
```

next, as git user:
```
    $ cd 
    $ mkdir -p tmp/git_svn_sync
    $ cd tmp/git_svn_sync
    $ git clone file:///home/git/repositories/repo1.git
    $ cd repo1
    $ rm -rf .git
    $ svn import . file:///home/svn/repositories/repo1 -m "init commit"
    $ cd ..
    $ rm -rf repo1
    $ git svn clone file:///home/svn/repositories/repo1
    $ cd repo1
    $ git remote add origin file:///home/git/repositories/repo1.git/
    $ echo '[user]
        name = git_sync
        email = null@example.com' >> .git/config
    $ 
        
```
now, after some commits, to sync them to svn, as git user:
```
    $ cd
    $ cd tmp/git_svn_sync/repo1
    $ git pull --no-commit origin master
    $ git commit -m "sync commit"
    $ git svn dcommit
```

To automate sync process, add [post-receive](post-receive) hook to /home/git/repositories/repo1.git/hooks/.  
Sync logs will be available in /home/git/tmp/git_svn_sync/repo1.sync.log.  
If something goes wrong during the push (e.g. due to some conflict), such warning message will be printed:
```
  remote: WARNING! Problem occured during git->svn synchronization.
  remote: Please contact with git/svn administrator.
```
