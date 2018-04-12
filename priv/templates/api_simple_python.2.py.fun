#!python
#
# api_simple_python
#
# Author: ??

"""
Demonstrate logging via stdout and stderr. Take special note of
usage of traceback, which gives very nicely formatted call
traceback in case of errors.
"""
import json
import sys
import traceback

from Pyrlang import term

def process(message):
    """TODO
       process input message, which is a python dict
       and return a dictionary back again which is
       then serialized and sent back to the client.
    """
    return message

def main(data_binary, context_binary):
    data = data_binary.bytes_.decode('utf-8')
    context = context_binary.bytes_.decode('utf-8')
    result = handle_event(data, context)
    return term.Binary(result.encode('utf-8'))

def handle_event(data, context):
    try:
        json_value = json.loads(data)
        message = json_value['message']
        sys.stdout.write('Sample log message on stdout. Received message={}\n'.format(message))
        json_response = process(message)
        return json.dumps(json_response)
    except Exception as e:
        sys.stderr.write('Sample log message on stderr. Received message={}\n'.format(e))
        traceback_lines = traceback.format_exception(None, e, e.__traceback__)
        print(''.join(traceback_lines),
              file=sys.stderr, flush=True)
        return str(e)
