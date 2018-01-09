package com.beamparticle;

import com.ericsson.otp.erlang.OtpErlangAtom;
import com.ericsson.otp.erlang.OtpErlangDecodeException;
import com.ericsson.otp.erlang.OtpErlangExit;
import com.ericsson.otp.erlang.OtpErlangLong;
import com.ericsson.otp.erlang.OtpErlangMap;
import com.ericsson.otp.erlang.OtpErlangObject;
import com.ericsson.otp.erlang.OtpErlangString;
import com.ericsson.otp.erlang.OtpMbox;
import com.ericsson.otp.erlang.OtpNode;

import java.io.IOException;
import java.util.Arrays;
import java.util.stream.Collectors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.lang.reflect.Method;

// see http://erlang.org/doc/apps/jinterface/jinterface_users_guide.html

public class JavaLambdaNode {

	final OtpNode otpNode;

    // nodeName = "java-beamparticle@127.0.0.1";
    // cookie = "SomeCookie";
    // erlangNodeName = "beamparticle@127.0.0.1";
    public JavaLambdaNode(final String nodeName, final String cookie, final String erlangNodeName) throws IOException {
        otpNode = new OtpNode(nodeName, cookie);

        // you can send messages to the remote as follows
        // otpMbox.send("remote-process-name", erlangNodeName, tuple);

        String mailboxName = "javaserver";
        OtpMbox otpMbox = otpNode.createMbox(mailboxName);
		boolean keepRunning = true;
        while (keepRunning) {
            System.out.println("Mailbox " + mailboxName + " is listening...");
            try {

                OtpErlangObject msg = otpMbox.receive();

                if (msg instanceof OtpErlangAtom) {
                    System.out.println("Java program got an atom message: " +  toString(msg));
					OtpErlangAtom erlangAtom = (OtpErlangAtom) msg;
					String atom = erlangAtom.atomValue();
					if (atom.equals("stop")) {
						keepRunning = false;
						System.out.println("shutting down, due to 'stop' message.");
						otpNode.closeMbox(otpMbox);
						otpNode.close();
						System.exit(0);
					} else {
						System.out.println("unknown atom received " + atom);
					}
                } else {
                    ErlangGenServer gen_server = null;
                    try {
                        gen_server = new ErlangGenServer(otpMbox, msg, erlangNodeName);
                    } catch (ErlangRemoteException erlException) {
                        erlException.send(otpMbox);
                    } catch (Exception e) {
                        System.out.println("received '" + msg.toString()
                                + "' but didn't know how to process it. Exception: "
                                + e.getMessage());
                    }

                    if (gen_server != null) {
                        try {
                            Class c = Class.forName(gen_server.getMFA().getModule().atomValue());
							Class[] argumentTypes = new Class[gen_server.getMFA().getArgs().arity()];
							for (int i = 0; i < gen_server.getMFA().getArgs().arity(); ++i) {
                                argumentTypes[i] = gen_server.getMFA().getArgs().elements()[i].getClass();
							}
                            Method method = c.getDeclaredMethod(
                                    gen_server.getMFA().getFunction().atomValue(),
                                    argumentTypes);
                            gen_server.setMethod(method);
                            gen_server.run();
						} catch (ClassNotFoundException e) {
                            e.printStackTrace();
                            new ErlangRemoteException(gen_server.getFromPid(),
                                    gen_server.getFromRef(), e).send(otpMbox);
						} catch (NoSuchMethodException e) {
                            e.printStackTrace();
						}
                    }
                }
            } catch (OtpErlangExit otpErlangExit) {
                System.out.println(otpErlangExit.getMessage());
                System.exit(1);
            } catch (OtpErlangDecodeException e) {
                System.out.println(e.getMessage());
            }
        }
    }

    private String toString(OtpErlangObject o) {

        if (o instanceof OtpErlangAtom) {
            return ((OtpErlangAtom) o).atomValue();
        }
        if (o instanceof OtpErlangString) {
            return ((OtpErlangString) o).stringValue();
        }
//        if (o instanceof OtpErlangInt) {
//            return ((OtpErlangInt) o).bigIntegerValue().toString();
//        }
//        if (o instanceof OtpErlangDouble) {
//            return String.valueOf(((OtpErlangDouble) o).doubleValue());
//        }
        if (o instanceof OtpErlangLong) {
            return String.valueOf(((OtpErlangLong) o).longValue());
        }

        return "NON-SUPPORTED-VALUE";
    }
}
