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
import traceback

import logging
import logging.handlers
#logging.basicConfig(format='%(levelname)s:%(message)s', level=logging.INFO)
#LOG = logging.getLogger(os.path.basename(__name__))

# Cannot read more than 10 MB from STDIN
MAX_STDIN_DATA_OCTETS = 10 * 1024 * 1024

def is_valid_erlang_type(x):
    """Is the variable a valid Erlang type"""
    # Note that str is intentionally not allowed,
    # because str when sent back to Erlang are nothing
    # but Erlang list of integers
    return isinstance(x, term.Atom) or \
            isinstance(x, term.List) or \
            isinstance(x, term.Pid) or \
            isinstance(x, term.Reference) or \
            isinstance(x, term.Binary) or \
            isinstance(x, term.Fun) or \
            isinstance(x, tuple) or \
            isinstance(x, int) or \
            isinstance(x, float) or \
            isinstance(x, dict)

def convert_to_erlang_type(x):
    if isinstance(x, str):
        return term.Binary(x.encode('utf-8'))
    elif isinstance(x, bytes):
        return term.Binary(x)
    elif isinstance(x, list) or isinstance(x, set):
        new_value = term.List()
        for e in x:
            new_value.append(convert_to_erlang_type(e))
        return new_value
    elif isinstance(x, tuple):
        new_value = ()
        for e in x:
            new_value = new_value + (convert_to_erlang_type(e),)
        return new_value
    elif isinstance(x, dict):
        new_value = {}
        for k,v in x:
            new_value[convert_to_erlang_type(k)] = convert_to_erlang_type(v)
        return new_value
    elif isinstance(x, bool):
        if x:
            return term.Atom('true')
        else:
            return term.Atom('false')
    else:
        return x

def erlang_error(msg : str):
    return (term.Atom('error'), term.Binary(msg.encode('utf-8')))

class MyProcess(Process):
    def __init__(self, node, logger) -> None:
        Process.__init__(self, node)
        node.register_name(self, term.Atom('pythonserver'))
        self.logger = logger
        self.dynamic_functions = {}
        #self.code_globals = {}
        # There is no need to share code amoungst different
        # dynamic functions at present
        #self.code_locals = {}

    def load(self, namebin, codebin):
        try:
            dynamic_function_name = namebin.bytes_.decode('utf-8')
            self.logger.info('loading {0}'.format(dynamic_function_name))
            code = codebin.bytes_.decode('utf-8')
            c = compile(code, '<string>', 'exec')
            code_locals = {}
            exec(c, code_locals, code_locals)
            # lets find out whether the function (with given name) exists
            # in the code and also its arity (that is its number of parameters)
            if ('main' in code_locals) and callable(code_locals['main']):
                sig = signature(code_locals['main'])
                function_arity = len(sig.parameters)
                # copy locals to globals because otherwise
                # eval('..', globals, locals) will fail since
                # the depending functions will not be available in globals
                full_function_name = dynamic_function_name + '/' + str(function_arity)
                self.dynamic_functions[full_function_name] = (code_locals, hash(codebin.bytes_), codebin)
                self.logger.debug(' saved = ' + str(self.dynamic_functions))
                return (term.Atom('ok'), function_arity)
            else:
                # the code compiled but function do not exist
                return (term.Atom('error'), term.Atom('not_found'))
        except Exception as e:
            print(traceback.format_exception(None,
                                             e, e.__traceback__),
                                             file=sys.stderr, flush=True)
            return erlang_error(str(e))

    def evaluate(self, codebin):
        try:
            code = codebin.bytes_.decode('utf-8')
            c = compile(code, '<string>', 'exec')
            code_locals = {}
            exec(c, code_locals, code_locals)
            if ('main' in code_locals) and (callable(code_locals['main'])):
                main_fun = code_locals['main']
                if inspect.isfunction(main):
                    sig = signature(main_fun)
                    main_fun_arity = len(sig.parameters)
                    if main_fun_arity == 0:
                        # without promoting locals to temporary globals
                        # the import statements do not work
                        eval_result = eval('main()', code_locals, code_locals)
                        self.logger.debug('result = {0}'.format(eval_result))
                        result = convert_to_erlang_type(eval_result)
                        if is_valid_erlang_type(result):
                            return result
                        else:
                            return erlang_error("Invalid result type = {}".format(type(result)))
            return erlang_error("Missing function main(). Note that it do not take any arguments")
        except Exception as e:
            print(traceback.format_exception(None,
                                             e, e.__traceback__),
                                             file=sys.stderr, flush=True)
            return erlang_error(str(e))

    def invoke(self, entry_fname, namebin, codebin, arguments):
        """entry_fname is either 'main' or 'handle_event'"""
        try:
            name = namebin.bytes_.decode('utf-8')
            if not isinstance(arguments, tuple):
                raise Exception('Arguments must be a tuple but is ' + str(type(arguments)))
            self.logger.debug(' retrieved = ' + str(self.dynamic_functions))
            name_with_arity = name + '/' + str(len(arguments))
            if name_with_arity not in self.dynamic_functions:
                # lazy load the function and compile it
                load_result = self.load(namebin, codebin)
                if load_result[0] != term.Atom('ok'):
                    return load_result
                entry = self.dynamic_functions[name_with_arity]
            else:
                entry = self.dynamic_functions[name_with_arity]
                stored_code_hash = entry[1]
                if hash(codebin.bytes_) != stored_code_hash:
                    # compile and save the function because
                    # the hashes do not match
                    load_result = self.load(namebin, codebin)
                    if load_result[0] != term.Atom('ok'):
                        return load_result
                    # re-assign entry to updated one
                    entry = self.dynamic_functions[name_with_arity]
            code_locals = entry[0]
            if (entry_fname in code_locals) and (callable(code_locals[entry_fname])):
                main_fun = code_locals[entry_fname]
                self.logger.info('main_fun = {0}'.format(main_fun))
                if inspect.isfunction(main_fun):
                    sig = signature(main_fun)
                    main_fun_arity = len(sig.parameters)
                    if main_fun_arity == len(arguments):
                        # without promoting locals to temporary globals
                        # the import statements do not work
                        call_arguments = []
                        for i in range(0, len(arguments)):
                            argname = 'arg' + str(i) + '__'
                            # save arguments to code_locals
                            code_locals[argname] = arguments[i]
                            call_arguments.append(argname)
                        call_command = \
                                entry_fname + '(' \
                                + ','.join(call_arguments) \
                                + ')'
                        self.logger.info('call_command, = {0}'.format(call_command))
                        eval_result = eval(call_command, code_locals, code_locals)
                        self.logger.debug('response = {0}'.format(eval_result))
                        result = convert_to_erlang_type(eval_result)
                        # cleanup code_locals to save memory
                        for i in range(0, len(arguments)):
                            argname = 'arg' + str(i) + '__'
                            del code_locals[argname]
                        # send back the result
                        if is_valid_erlang_type(result):
                            return result
                        else:
                            return erlang_error("Invalid result type = {}".format(type(result)))
                    else:
                        return erlang_error('{0}.{1} takes {2} arguments only'.format(
                            name, entry_fname, main_fun_arity))
            return erlang_error('Missing function {0}.{1}().'.format(name, entry_fname))
        except Exception as e:
            print(traceback.format_exception(None,
                                             e, e.__traceback__),
                                             file=sys.stderr, flush=True)
            return erlang_error(str(e))

    def invoke_main(self, namebin, codebin, arguments):
        return self.invoke('main', namebin, codebin, arguments)

    def invoke_simple_http(self, namebin, codebin, databin, contextbin):
        try:
            name = namebin.bytes_.decode('utf-8')
            if not isinstance(databin, term.Binary):
                return erlang_error('{0}(data) must be binary, but is {1}'.format(
                    name, type(databin)))
            if not isinstance(contextbin, term.Binary):
                return erlang_error('{0}(context) must be binary, but is {1}'.format(
                    name, type(contextbin)))
            data = databin.bytes_.decode('utf-8')
            context = contextbin.bytes_.decode('utf-8')
            transformed_args = (data, context)
            return self.invoke('handle_event', namebin, codebin, transformed_args)
        except Exception as e:
            print(traceback.format_exception(None,
                                             e, e.__traceback__),
                                             file=sys.stderr, flush=True)
            return erlang_error(str(e))

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
                print(traceback.format_exception(None,
                                                 e, e.__traceback__),
                                                 file=sys.stderr, flush=True)
                gencall.reply_exit(local_pid=self.pid_,
                                   reason=erlang_error(str(e)))

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
                error_message = "Only {M :: binary(), F :: binary(), Args :: tuple()} messages allowed"
                gencall.reply(local_pid=self.pid_,
                              result=erlang_error(error_message))
            else:
                (module, function, arguments) = gencall.message_
                module_name = module.bytes_.decode('utf-8')
                function_name = function.bytes_.decode('utf-8')
                self.logger.info('{0}.{1}({2})'.format(module_name, function_name, arguments))
                try:
                    if module_name == 'MyProcess' and function_name == 'load':
                        result = self.load(*arguments)
                    elif module_name == 'MyProcess' and function_name == 'eval':
                        result = self.evaluate(*arguments)
                    elif module_name == 'MyProcess' and function_name == 'invoke':
                        result = self.invoke_main(*arguments)
                    elif module_name == 'MyProcess' and function_name == 'invoke_simple_http':
                        result = self.invoke_simple_http(*arguments)
                    else:
                        # DONT allow generic calls directly, instead
                        # let user define dynamic functions and then within
                        # that call those functions if required

                        #fun_ref = eval(module_name + '.' + function_name,
                        #        self.code_globals,
                        #        self.code_locals)
                        #result = fun_ref(*arguments)
                        result = erlang_error('only dynamic calls allowed')
                except Exception as e:
                    print(traceback.format_exception(None,
                                                     e, e.__traceback__),
                                                     file=sys.stderr, flush=True)
                    result = erlang_error(str(e))
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
