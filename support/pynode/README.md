## README

The Erlang Python node is powered via Pyrlang. This is a great
project which enables Erlang Python node. The rest of the tooling
and python scripting is part of the beamparticle project.


## Installing Dependencies


    sudo apt-get install -y python3-pip python3-gevent \
        python3-greenlet python3-jinja2 python3-markupsafe \
        python3-pil python3-pygments

There are many other great python packages, but at least install few additional
great ones as shown below.

    sudo apt-get install -y python3-numpy python3-pandas python3-requests

Alternatively, you can use pip3 for installing python packages as well as follows:

    sudo apt-get install python3-pip
    sudo pip3 install gevent greenlet jinja2 markupsafe \
         Pillow pygments numpy pandas requests nltk rake-nltk adapt-parser

## Building Pyrlang

    cd Pyrlang \
        && python3 -m compileall Pyrlang

