# JavaNode

JavaNode is an Erlang node which can Java functions (that is class static
methods) present in jar dynamically. Additionally, it allows dynamic
compilation, execution and evaluation of Java lambda anonymous classes.
It is important to note that the input arguments to any of the methods
must be com.ericsson.otp.erlang.OtpErlangBinary, OtpErlangAtom, etc.
The complete list of data types and their mapping onto the Erlan
world is covered
[here](http://erlang.org/doc/apps/jinterface/jinterface_users_guide.html).

> Note that this work is heavily inspired from
> <https://github.com/mookjp/jinterface-example>

## Building

There is a gnu Makefile, which can be used as follows, alternatively
you could use the commands (as indicated in that file) directly as well.

    make release

## Running Tests

The unit tests are powered by junit and can be executed as follows:

    make test


