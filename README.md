# BeamParticle

[![Build Status](https://travis-ci.org/beamparticle/beamparticle.svg?branch=master)](https://travis-ci.org/beamparticle/beamparticle.svg?branch=master)
[![Software License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

Operate at the speed of [BEAM](http://erlang.org/faq/implementations.html)
with [BeamParticle](http://beamparticle.org).

## Overview

> BEAM stands for Bogdan/Björn's Erlang Abstract Machine.

This project is an attempt to make the Erlang virtual machine
BEAM more approachable and re-programmable in a
manner which otherwise is complex. Although, (Erlang) BEAM supports
hot code-loading and many of the advanced constructs, but
using that correctly is not without challanges. This
project tries to take some simple decisions thereby
making the life of developer easy in realising dynamic
code patching and reprogrammability more approachable.
This project can be used as a standalone engine or can be
embedded in another Erlang project, while much of what
will be demonstrated is based out of its standalone deployment.

## The Design

> Documentation and testing is lacking, but you will see some
> action both on those fronts. Till then happy hacking around.

### Flexible Non-Restrictive

The websocket interface is provided to train the system, while
Google LevelDB is used for storing and
retrieving Erlang functions. Additionally, the functions are
cached in memory, so subsequent invocation shall be much faster.

At present there is no restriction on function execution, so
anyone with access can simply run any function available within
this framework. Having said that there is HTTP Basic authentication
both at websocket and HTTPS REST interface for simple checks.
But once you are authenticated all the functions are available
for execution.

### Components

The framework has the following components:

* core - Set of utilities for running Erlang/OTP functions.
* websocket - A simple websocket interface to train beampacket
  and tell it about functions.
* https rest - A HTTPS REST interface, where the functions
  defined through the websocket interface are served
  as endpoint (HTTP POST with application/json body).
* storage - There is a local Google leveldb which is extensively
  used primarily to meet the time-to-market requirement.
  This shall change as time progresses towards a better strategy.

## The Future

It is very hard to predict where this project will move on.
This is a very humble beginning, where it is not entirely
clear how this project shall find use in the larger audience.

## Similar Projects

We are not aware of projects which tries to do this as-it-is, but
then intenet is too vast for us to comment. Do leave a comment
in case you find any similar open source or commercial projects.


## Software Dependencies

This framework supports *Gnu/Linux* and *MacOSX* operating system, but with
little change it can be made to build on any of the POSIX compliant
operating system when Erlang/OTP is available. This project depends upon
a lot of open source dependencies, which are listed in rebar.config.

## Development Environment Setup

Although the installation for various GNU/Linux distributions differ but
the dependencies are easily available on any one of them.

### Ubuntu or Debian

The following commands were tested on Ubuntu 16.04 and Debian 9
but things should be similar (if not same) on other releases and Debian.

The following commands needs to be as a system administrator or with sudo
(as shown below) so that the relavent packages are installed in the
system.

If your system is not updated then probably it is a good idea to do that
before installing anything else.

    sudo apt-get update

Install the build essential and deps for Erlang/OTP

    sudo apt-get install -y wget build-essentials \
        libsctp1 libwxgtk3.0 libssl-dev

Get Erlang/OTP 20+ from ErlangSolutions at
<https://www.erlang-solutions.com/resources/download.html>.

Say you downloaded Erlang/OTP 20.1 then install it for ubuntu
as follows:

    wget https://packages.erlang-solutions.com/erlang/esl-erlang/FLAVOUR_1_general/esl-erlang_20.1-1~ubuntu~xenial_amd64.deb
    sudo dpkg -i esl-erlang_20.1-1~ubuntu~xenial_amd64.deb

Alternatively, you can install the erlang from Ubuntu or Debian repo as well.

## Build and Test

After you are done setting up the development environment the build is
pretty straight-forward (see below).

    git clone https://github.com/beamparticle/beamparticle
    cd beamparticle
    make release

In case you want to build a package then use the deb-package makefile
target towards the same (see below).

    make deb-package

> There are no automated test as of date, but you will soon
> see some action there.
> You are always welcome to raise a pull request and contribute
> as well.

## Websocket Browser Support

* Chrome
* Firefox

Note that Safari do not work due to bug <https://bugs.webkit.org/show_bug.cgi?id=80362>.
The request from Safari do not include the Authorization header, which is the source
of an issue.

## Thanks

Thanks for evaluating and contributing to this project and hope you
find it useful.  Feel free to create issues for bugs or new features.

Erlang/OTP is a very old programming language and a very powerful one
as well (though under utilized). The objective of the framework is
to try to leverage some part of the power and give back to
the community a reprogrammable engine with the power of BEAM.

A special note of thanks to [redBus](http://www.redbus.com) for
integrating it within its production environment and allowing
[github: neeraj9](https://github.com/neeraj9) to introduce this
to a much larger audience.

## Authors

* Neeraj Sharma {[github: neeraj9](https://github.com/neeraj9)}
