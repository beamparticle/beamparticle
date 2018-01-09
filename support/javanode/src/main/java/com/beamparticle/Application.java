package com.beamparticle;

import java.io.Reader;
import java.io.InputStreamReader;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;

public class Application {

    public static void main(String[] args) throws InterruptedException, IOException {
        // args[0] = name of the node
        // args[1] = cookie for node
        // args[2] = name of the parent erlang node
        // args[3] = Log file fullpath
        // args[4] = Log level ("INFO", "DEBUG", "WARNING", "ERROR")
        System.out.println("Java node launched with name=" + args[0]);

        Thread stdin_monitor_thread = new Thread(() -> {
            try {
                Reader rd = new InputStreamReader(System.in, "utf-8");
                char[] cbuf = new char[1024];
                while(rd.ready()) {
                    // first 4 bytes are length of data, which is to
                    // follow in network byte order (big-endian), but
                    // char in java is 2 octets big so 2*2 = 4 bytes
                    //char cbuf[] = new char[2];
                    //int bytes_read = rd.read(cbuf);
                    //byte[] bytes = toBytes(cbuf);
                    //int data_octets = java.nio.ByteBuffer.wrap(bytes).getInt();

                    // The above is the correct approach, but then we are not
                    // bothered with the message interchange at present, so
                    // lets just read into any buffer and ignore it.
                    // The intent is to just read something till the pipe is
                    // closed, so this process can terminate.
                    rd.read(cbuf);
                }
            } catch (UnsupportedEncodingException e) {
            } catch (IOException e) {
            }
            System.err.println("Peer terminated, so go down as well");
            System.exit(0);
        });

        // start a thread to monitor stdin, so as to terminate
        // when the connection with peer (in this Erlang node)
        // is terminated.
        stdin_monitor_thread.start();

        JavaLambdaNode lambdaNode = new JavaLambdaNode(
			args[0], args[1], args[2]);
    }

    private byte[] toBytes(char[] cbuf) {
        byte[] bytes = new byte[cbuf.length * 2];
        // TODO check the encoding and look at which byte is
        // sent first in char, which is 2 octets. The following
        // code is inspired from resources on the internet, so
        // must be validated.
        for (int i = 0; i < cbuf.length; i++) {
            bytes[i] = (byte)((cbuf[i] & 0xff00) >> 8);
            bytes[i + 1] = (byte)(cbuf[i] & 0x00ff);
        }
        return bytes;
    }
}
