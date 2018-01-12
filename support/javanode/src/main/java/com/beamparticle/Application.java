package com.beamparticle;

import java.io.Reader;
import java.io.InputStreamReader;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;

import java.nio.charset.StandardCharsets;

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
                Reader rd = new InputStreamReader(System.in);
                // Reader rd = new InputStreamReader(System.in, StandardCharsets.UTF_8);
                char[] cbuf = new char[1024];
                while(true) {
                    rd.ready(); // throw IOException when error
                    // The intent is to just read something till the pipe is
                    // closed, so this process can terminate.
                    if (rd.read(cbuf, 0, cbuf.length) <= 0) {
                        // if cannot read then stdin is closed, so terminate
                        break;
                    }
                }
            } catch (UnsupportedEncodingException e) {
                e.printStackTrace();
            } catch (IOException e) {
                e.printStackTrace();
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
