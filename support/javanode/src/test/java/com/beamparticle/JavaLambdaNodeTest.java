/*
 *
 * The java docs within this file follows guidelines setforth at
 * http://www.oracle.com/technetwork/articles/java/index-137868.html
 *
 * %CopyrightBegin%
 *
 * Copyright Neeraj Sharma <neeraj.sharma@alumni.iitg.ernet.in> 2017.
 * All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * %CopyrightEnd%
 *
 */
package com.beamparticle;

import java.nio.charset.StandardCharsets;

import com.ericsson.otp.erlang.OtpNode;
import com.ericsson.otp.erlang.OtpMbox;
import com.ericsson.otp.erlang.OtpErlangObject;
import com.ericsson.otp.erlang.OtpErlangAtom;
import com.ericsson.otp.erlang.OtpErlangBinary;
import com.ericsson.otp.erlang.OtpErlangLong;
import com.ericsson.otp.erlang.OtpErlangTuple;
import com.ericsson.otp.erlang.OtpErlangList;
import com.ericsson.otp.erlang.OtpErlangRef;
import com.ericsson.otp.erlang.OtpExternal;
import com.ericsson.otp.erlang.OtpErlangExit;
import com.ericsson.otp.erlang.OtpErlangDecodeException;

import java.io.IOException;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests the lambda Java Erlang dynamic node.
 * The lambda Java Erlang node is tested with respect to
 * its interraction with messaging and so must so that it
 * can compile and execute dynamic and functions present
 * in jars.
 *
 * The intent of this test suite is to ensure that the
 * Java node works as expected and can be controlled by
 * Erlang node for running java functions.
 *
 *
 * IMPORTANT: epmd must be running to ensure that the
 *            test passes. Which can be an issue
 *            considering that this may not be easy
 *            in CI environment.
 *
 * @see JavaLambdaNode
 */
public class JavaLambdaNodeTest {

    // TODO: do we need this?
    public JavaLambdaNodeTest() {
    }

    /**
     * Ensure basic evaluation works flawlessly.
     *
     * Notice that the code has various import at the beginning, with
     * each import on a separate line.
     */
    @Test
    public void basicTest() {

        String nodeName = "java-test@127.0.0.1";
        String cookie = "SomeCookie";
        String erlangNodeName = "erlang-test@127.0.0.1";
        Thread app_thread = new Thread(() -> {
            // this is a blocking call
            try {
                JavaLambdaNode lambdaNode = new JavaLambdaNode(
                        nodeName, cookie, erlangNodeName);
            } catch (IOException e) {
                e.printStackTrace();
            }
        });

        app_thread.start();

        try {
            OtpNode otpNode = new OtpNode(erlangNodeName, cookie);
            String mailboxName = "localserver";
            OtpMbox otpMbox = otpNode.createMbox(mailboxName);

            // send request to the application node

            String name = "adder";
            String code = "import com.ericsson.otp.erlang.OtpErlangObject;\n"
                + "import com.ericsson.otp.erlang.OtpErlangLong;\n"
                + "() -> new Object() {\n"
                + "    public OtpErlangLong main(OtpErlangLong aLong, OtpErlangLong bLong) {\n"
                + "        java.math.BigInteger a = aLong.bigIntegerValue();\n"
                + "        java.math.BigInteger b = bLong.bigIntegerValue();\n"
                + "        java.math.BigInteger result = a.add(b);\n"
                + "        return new OtpErlangLong(result);\n"
                + "    }\n"
                + "}";
            OtpErlangBinary nameBinary = new OtpErlangBinary(name.getBytes(StandardCharsets.UTF_8));
            OtpErlangBinary codeBinary = new OtpErlangBinary(code.getBytes(StandardCharsets.UTF_8));

            OtpErlangObject[] genserverElements = new OtpErlangObject[3];
            genserverElements[0] = new OtpErlangAtom("$gen_call");

            OtpErlangObject[] callElements = new OtpErlangObject[2];
            callElements[0] = otpMbox.self();
            int tag = OtpExternal.newerRefTag;
            int[] ids = {0, 1, 2};
            callElements[1] = new OtpErlangRef(tag, erlangNodeName, ids, 0);
            genserverElements[1] = new OtpErlangTuple(callElements);

            OtpErlangObject[] requestElements = new OtpErlangObject[3];
            requestElements[0] = new OtpErlangAtom("com.beamparticle.JavaLambdaStringEngine");
            requestElements[1] = new OtpErlangAtom("load");
            OtpErlangObject[] requestBodyElements = new OtpErlangObject[2];
            requestBodyElements[0] = nameBinary;
            requestBodyElements[1] = codeBinary;
            requestElements[2] = new OtpErlangList(requestBodyElements);
            genserverElements[2] = new OtpErlangTuple(requestElements);

            OtpErlangTuple request = new OtpErlangTuple(genserverElements);
            try {
                otpMbox.send("javaserver", nodeName, request);
                OtpErlangObject o = otpMbox.receive();
                // TODO validate the response received.
            } catch (OtpErlangExit e) {
                e.printStackTrace();
                assertTrue(false);
            } catch (OtpErlangDecodeException e) {
                e.printStackTrace();
                assertTrue(false);
            }

            app_thread.stop();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
