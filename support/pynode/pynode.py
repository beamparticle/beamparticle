#!/usr/bin/env python3
#
# NOTE: If you use sys.stderr then the output will go back to
#       the connected Erlang node, which is running this app
#       as python node.
#
# Author: Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in>
#

import gevent
from gevent import monkey
monkey.patch_all()
# This do not work as expected
#monkey.patch_sys(stdin=True, stdout=False, stderr=False)

import Pyrlang
from Pyrlang import Atom
from Pyrlang.process import Process
from Pyrlang import term, gen

import inspect
from inspect import signature

import sys
import os
import select
import struct
import copy

import logging
import logging.handlers
#logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.INFO)
#LOG = logging.getLogger(os.path.basename(__name__))

# Cannot read more than 10 MB from STDIN
MAX_STDIN_DATA_OCTETS = 10 * 1024 * 1024

class MyProcess(Process):
    def __init__(self, node, logger) -> None:
        Process.__init__(self, node)
        node.register_name(self, term.Atom('pythonserver'))
        self.logger = logger
        self.dynamic_functions = {}
        self.code_globals = {}
        self.code_locals = {}

    def load(self, fnamebin, codebin):
        try:
            dynamic_function_name = fnamebin.bytes_.decode('utf-8')
            code = codebin.bytes_.decode('utf-8')
            c = compile(code, '<string>', 'exec')
            code_locals = {}
            exec(c, self.code_globals, code_locals)
            # lets find out whether the function (with given name) exists
            # in the code and also its arity (that is its number of parameters)
            if dynamic_function_name in code_locals:
                # copy locals to globals because otherwise
                # eval('..', globals, locals) will fail since
                # the depending functions will not be available in globals
                self.code_globals.update(code_locals)
                self.code_locals.update(code_locals)
                self.dynamic_functions[dynamic_function_name] = code

                sig = signature(self.code_locals[dynamic_function_name])
                function_arity = len(sig.parameters)
                return (term.Atom('ok'), function_arity)
            else:
                # the code compiled but function do not exist
                return (term.Atom('error'), term.Atom('not_found'))
        except Exception as E:
            return (term.Atom('error'), str(E))

    def eval(self, codebin):
        try:
            code = codebin.bytes_.decode('utf-8')
            c = compile(code, '<string>', 'exec')
            code_locals = {}
            # do not pollute code_globals for temporary script
            # executions
            code_globals = copy.deepcopy(self.code_globals)
            exec(c, code_globals, code_locals)
            if 'main' in code_locals:
                main_fun = code_locals['main']
                if inspect.isfunction(main):
                    sig = signature(main_fun)
                    main_fun_arity = len(sig.parameters)
                    if main_fun_arity == 0:
                        # without promoting locals to temporary globals
                        # the import statements do not work
                        code_globals.update(code_locals)
                        result = eval('main()', code_globals, code_locals)
                        self.logger.debug('result = {0}'.format(result))
                        return result
            return (term.Atom('error'), "Missing function main(). Note that it do not take any arguments")
        except Exception as E:
            return (term.Atom('error'), str(E))

    def handle_inbox(self):
        while True:
            # unfortunately self.inbox_.receive(...) unnecessarily consumes CPU
            # till that is fixed, do not use this for now.
            msg = self.inbox_.get()
            # Do a selective receive but the filter says always True
            #msg = self.inbox_.receive(filter_fn=lambda _: True)
            #if msg is None:
            #    gevent.sleep(0.1)
            #    continue
            self.logger.info("Incoming {0}".format(msg))
            try:
                self.handle_one_inbox_message(msg)
            except Exception as e:
                gencall.reply_exit(local_pid=self.pid_,
                                   reason=(
                                       term.Atom('error'),
                                       term.Binary(str(e).encode('utf-8'))))

    def handle_one_inbox_message(self, msg) -> None:
        gencall = gen.parse_gen_message(msg)
        if isinstance(gencall, str):
            self.logger.info("MyProcess: {0}".format(gencall))
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
                elif module_name == 'MyProcess' and function_name == 'eval':
                    result = self.eval(*arguments)
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


def run_gen_server(gen_server):
    gen_server.handle_inbox()


def read_nonblock(fd, numbytes):
    print("numbytes = {0}".format(numbytes))
    data = bytearray()
    bytes_read = 0
    while True:
        (readfds, _, errorfds) = select.select([fd], [], [fd], None)
        if errorfds == [fd]:
            return None
        elif readfds == [fd]:
            tmpdata = os.read(fd, numbytes - bytes_read)
            if not tmpdata:
                return None
            bytes_read = bytes_read + len(tmpdata)
            data.extend(tmpdata)
            if bytes_read >= numbytes:
                return data
        else:
            gevent.sleep(0.1)



def monitor_stdin(logger):
    """Start monitoring STDIN and terminate once the pipe
       is closed. Note that once the Erlang node terminates,
       it closes STDIN, which must be monitored by the python
       node and terminate appropriately. There will be no other
       indicator (except that STDOUT will also be closed)
       to indicate termination of the original Erlang node.

       Note that STDIN can also be used as a mechanism to
       transfer information as Erlang: {packet, 4}, wherein
       each message has a packet size in 4 octets in network
       byte order, while the payload of the data follows
       subsequently.

       see http://theerlangelist.com/article/outside_elixir
    """
    while True:
        # you could run select on stdin as well if you want
        # explicit non-blocking on stdin,
        # else apply monkey.patch_sys() as at the top
        #
        # select.select([sys.stdin], [], [sys.stdin], 0) == ([sys.stdin], [], [])
        # select.select([sys.stdin], [], [sys.stdin], 0) == ([], [], [sys.stdin])
        # select.select([sys.stdin], [], [sys.stdin], 0) == ([sys.stdin], [], [sys.stdin])
        #
        (readfds, _, errorfds) = select.select([sys.stdin], [], [sys.stdin], None)
        if errorfds == [sys.stdin]:
            # STDIN is closed, so die
            logger.info('terminate because peer closed STDIN')
            sys.exit(0)
        elif readfds == [sys.stdin]:
            #data_len = sys.stdin.read(4)
            buff = read_nonblock(sys.stdin.fileno(), 4)
            if not buff:
                # STDIN is closed, so die
                logger.info('terminate because peer closed STDIN')
                sys.exit(0)
            # buff is bytearray
            # if buff was bytes then the following would work
            #data_len = int.from_bytes(buff, byteorder='big')
            (data_len,) = struct.unpack('>L', buff)
            logger.debug("STDIN data_len = {0}".format(data_len))
            data_len = min(data_len, MAX_STDIN_DATA_OCTETS)
            data = read_nonblock(sys.stdin.fileno(), data_len)
            # data is bytearray
            if not data:
                # STDIN is closed, so die
                logger.info('terminate because peer closed STDIN')
                sys.exit(0)
        else:
            gevent.sleep(0.1)

def main():
    nodename = sys.argv[1]
    cookie = sys.argv[2]
    erlangnodename = sys.argv[3]
    numworkers = int(sys.argv[4])
    if len(sys.argv) > 5:
        abs_log_filename = sys.argv[5]
        if len(sys.argv) > 6:
            loglevel = sys.argv[6]
        else:
            loglevel = 'INFO'
        log_numeric_level = getattr(logging, loglevel.upper())
        # DONT do basicConfig, else that will setup a default handler
        # and logging.root.handlers will already have one entry and start
        # sending logs to sys.stderr, which will be received by Erlang node
        # irrespective of the rotating file handler, so duplicate
        # messages shall be seen there.
        #logging.basicConfig(format='%(levelname)s:%(message)s', level=log_numeric_level)
        logger = logging.getLogger(os.path.basename(__name__))
        handler = logging.handlers.RotatingFileHandler(
                abs_log_filename,
                maxBytes=1*1024*1024,
                backupCount=20,
                encoding='utf-8')
        appname = 'py'
        appname = os.path.basename(sys.argv[0])
        pidstr = str(os.getpid())
        format_str = '%(asctime)s %(levelname)s ' \
                + appname + '[' +  pidstr +  '] %(message)s'
        # sys.stderr.write('format_str = %s\n' % format_str)
        fmt = logging.Formatter(format_str,
                datefmt='%Y-%m-%d %H:%M:%S')
        handler.setFormatter(fmt)
        handler.setLevel(log_numeric_level)
        logger.addHandler(handler)
        logger.setLevel(log_numeric_level)
    else:
        logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.INFO)
        logger = logging.getLogger(os.path.basename(__name__))


    # Disable for now
    # setup stderr to warning level
    #errorhandler = logging.StreamHandler(stream=sys.stderr)
    #errorhandler.setLevel(logging.WARN)
    #fmt = logging.Formatter('%(asctime)s %(levelname)s:%(message)s',
    #        datefmt='%Y-%m-%dT%H:%M:%S')
    #errorhandler.setFormatter(fmt)
    #logger.addHandler(errorhandler)

    node = Pyrlang.Node(nodename, cookie)
    node.start()

    #pid = node.register_new_process(None)
    #node.send(pid, (Atom(erlangnodename), Atom('shell')), Atom('hello'))

    # Lets run single mailbox at present
    gen_server = MyProcess(node, logger)
    
    gevent.joinall([
        gevent.spawn(run_gen_server, gen_server),
        gevent.spawn(monitor_stdin, logger)
        ])


if __name__ == "__main__":
    main()
