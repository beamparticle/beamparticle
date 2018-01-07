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
        self.dynamic_functions = {}
        self.code_globals = {}
        self.code_locals = {}

    def load(self, fnamebin, codebin):
        try:
            dynamic_function_name = fnamebin.bytes_.decode('utf-8')
            code = codebin.bytes_.decode('utf-8')
            c = compile(code, '<string>', 'exec')
            exec(c, self.code_globals, self.code_locals)
            # copy locals to globals because otherwise
            # eval('..', globals, locals) will fail since
            # the depending functions will not be available in globals
            self.code_globals.update(self.code_locals)
            self.dynamic_functions[dynamic_function_name] = code
            return (term.Atom('ok'))
        except Exception as E:
            return (term.Atom('error'), str(E))

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
            # gencall is of type gen.GenIncomingMessage
            if type(gencall.message_) != tuple or len(gencall.message_) != 3:
                error_message = term.Binary(
                        "Only {M :: binary(), F :: binary(), Args :: tuple()} messages allowed".encode('utf-8'))
                gencall.reply(local_pid=self.pid_,
                              result=(term.Atom('error'), error_message))
            else:
                (module, function, arguments) = gencall.message_
                module_name = module.bytes_.decode('utf-8')
                function_name = function.bytes_.decode('utf-8')
                if module_name == 'MyProcess' and function_name == 'load':
                    result = self.load(*arguments)
                elif module_name == '__dynamic__':
                    try:
                        # Arguments must be a tuple because using List
                        # can result into Erlang([1,2]) -> '\x01\x02'
                        # which is not expected
                        if not isinstance(arguments, tuple):
                            raise Exception('Arguments must be a tuple but is ' + str(type(arguments)))
                        #fun_ref = self.code_locals[function_name]
                        #result = fun_ref(*arguments)
                        # Instead lets run within the context, so that
                        # local functions and imports are available during
                        # the execution
                        call_arguments = []
                        for i in range(0, len(arguments)):
                            argname = 'arg' + str(i) + '__'
                            # save arguments to code_locals
                            self.code_locals[argname] = arguments[i]
                            call_arguments.append(argname)
                        call_command = \
                                function_name + '(' \
                                + ','.join(call_arguments) \
                                + ')'
                        #print('call_command=' + call_command)
                        #print('code_locals=' + str(self.code_locals))
                        #print('code_globals=' + str(self.code_globals))
                        result = eval(call_command,
                                self.code_globals,
                                self.code_locals)
                        # cleanup code_locals to save memory
                        for i in range(0, len(arguments)):
                            argname = 'arg' + str(i) + '__'
                            del self.code_locals[argname]
                    except Exception as E:
                        result = (term.Atom('error'), term.Binary(str(E).encode('utf-8')))
                else:
                    # DONT allow generic calls directly, instead
                    # let user define dynamic functions and then within
                    # that call those functions if required

                    #fun_ref = eval(module_name + '.' + function_name,
                    #        self.code_globals,
                    #        self.code_locals)
                    #result = fun_ref(*arguments)
                    result = (term.Atom('error'), term.Binary('only dynamic calls allowed'.encode('utf-8')))
                # Send a reply
                gencall.reply(local_pid=self.pid_,
                             result=result)
        else:
            # Send an error exception which will crash Erlang caller
            gencall.reply_exit(local_pid=self.pid_,
                               reason=term.Atom('error'))


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

    # Lets run single mailbox at present
    gen_server = MyProcess(node)
    gen_server.handle_inbox()
    


if __name__ == "__main__":
    main()
