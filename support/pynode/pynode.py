#!/usr/bin/env python3
#

import gevent
from gevent import monkey
monkey.patch_all()

import Pyrlang
from Pyrlang import Atom
from Pyrlang.process import Process
from Pyrlang import term, gen

import sys


class MyProcess(Process):
    def __init__(self, node) -> None:
        Process.__init__(self, node)
        node.register_name(self, term.Atom('pythonserver'))

    def handle_inbox(self):
        while True:
            # Do a selective receive but the filter says always True
            msg = self.inbox_.receive(filter_fn=lambda _: True)
            if msg is None:
                gevent.sleep(0.1)
                continue
            print("Incoming", msg)
            self.handle_one_inbox_message(msg)

    def handle_one_inbox_message(self, msg) -> None:
        gencall = gen.parse_gen_message(msg)
        if isinstance(gencall, str):
            print("MyProcess:", gencall)
            return

        # Handle the message in 'gencall' using its sender_, ref_ and
        # message_ fields

        if True:
            # Send a reply
            gencall.reply(local_pid=self.pid_,
                          result="ok")

        else:
            # Send an error exception which will crash Erlang caller
            gencall.reply_exit(local_pid=self.pid_,
                               reason="error")


def main():
    nodename = sys.argv[1]
    cookie = sys.argv[2]
    erlangnodename = sys.argv[3]
    numworkers = int(sys.argv[4])
    node = Pyrlang.Node(nodename, cookie)
    node.start()

    #pid = node.register_new_process(None)
    #node.send(pid, (Atom(erlangnodename), Atom('shell')), Atom('hello'))

    #while True:
    #    # Sleep gives other greenlets time to run
    #    gevent.sleep(0.1)

    gen_server = MyProcess(node)
    gen_server.handle_inbox()
    


if __name__ == "__main__":
    main()
