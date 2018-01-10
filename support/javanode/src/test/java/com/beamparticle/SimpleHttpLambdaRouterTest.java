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
 * Tests simple http lambda router.
 * @see SimpleHttpLambdaRouter
 */
public class SimpleHttpLambdaRouterTest {

    /**
     * Ensure basic evaluation works flawlessly.
     *
     * Notice that the code has various import at the beginning, with
     * each import on a separate line.
     */
    @Test
    public void basicTest() {
        OtpErlangBinary nameBinary = new OtpErlangBinary(
                new String("com.beamparticle.TestHttpLambda").getBytes(StandardCharsets.UTF_8));
        String data = new String("{\"a\": 1}");
        String context = new String("{\"path\": \"/v2/hello\"}");
        OtpErlangBinary dataBinary = new OtpErlangBinary(
                data.getBytes(StandardCharsets.UTF_8));
        OtpErlangBinary contextBinary = new OtpErlangBinary(
                context.getBytes(StandardCharsets.UTF_8));
        OtpErlangObject result =
            SimpleHttpLambdaRouter.invoke(nameBinary, dataBinary, contextBinary);
        OtpErlangObject[] entries = new OtpErlangObject[2];
        entries[0] = new OtpErlangAtom("ok");
        entries[1] = dataBinary;
        OtpErlangTuple expectedResult = new OtpErlangTuple(entries);
		assertEquals(expectedResult, result);
    }
}
