## README

The Erlang Go node is powered via ergonode. This is a great
project which enables Erlang Go node. The rest of the tooling
and go code is part of the beamparticle project.


## Installing Dependencies

    sudo apt-get install -y golang-1.9-go
    sudo ln -s /usr/lib/go-1.9/bin/go /usr/bin/

For debian stretch, you can install golang 1.8 as follows:

    sudo apt-get install -y -t stretch-backports golang-go

## Building

    make release
