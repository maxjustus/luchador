luchador
========

Luchador is a project that utilizes the speed of Lua and Memcached to bring page caching to Nginx. It does this in an easy to configure fashion unlike Varnish.

The goal of Luchador is to be easy to use as well as close in speed with Varnish.

How to setup
============

Dependencies
------------

Luchador has a few dependencies:
* luarocks
* lzlib
* lua-messagepack
* lua-resty-memcached (https://github.com/agentzh/lua-resty-memcached/archive/v#{lua_memcached_version}.tar.gz)
* nginx with lua configured
* luajit
* lua-nginx-module https://github.com/openresty/lua-nginx-module


Vanilla Setup
-------------

After all of those files are installed then someone needs to run a make install on the server


Heroku
------

TBD


Chef Recipe
------------

TBD

Speed
======

this is where we can put results from speed differences vs varnish vs plain caching.

Maintainers
============
