.. _faq:

==========================
Frequently Asked Questions
==========================


General
=======

.. _cite:

What is the Erlang setup for developer?
---------------------------------------

* Erlang/OTP - http://erlang.org
* Concurrent Programming in erlang - http://erlang.org/download/erlang-book-part1.pdf
* After some learning of erlang read - http://www.erlang-in-anger.com/


How do I build this project on Ubuntu?
--------------------------------------

The following packages must be installed otherwise the NIF (c code) for
eleveldb will fail to build. Note that libssl-dev is required
by snappy (a requirement of eleveldb).

    sudo apt-get install build-essential
    sudo apt-get install libssl-dev

Clean the project as follows:

    ./rebar3 clean beampacket

The following command will clean the complete project.

    ./rebar3 clean -a

Make a release build in the local system.

    ./rebar3 release

Run a production build in the local system.

    ./rebar3 as prod tar
    
How do I run app in shell mode?
-------------------------------

    ./rebar3 shell --apps beampacket

How do I run shell with all the code but not start app?
-------------------------------------------------------

    erl -pa _build/default/lib/*/ebin/* 
    
How do I test and create code coverage?
---------------------------------------

**TODO**
    
How do I run EUnit tests?
-------------------------

**TODO**

How do I generate code documentation?
-------------------------------------

The code documentation is generated via `edoc<http://erlang.org/doc/apps/edoc/chapter.html>` as follows:

    ./rebar3 edoc

The output is generated in doc/ subfolder.

