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

import com.ericsson.otp.erlang.OtpErlangObject;
import com.ericsson.otp.erlang.OtpErlangAtom;
import com.ericsson.otp.erlang.OtpErlangBinary;

import org.junit.Test;
import static org.junit.Assert.*;

/**
 * Tests the java lambda string execution engine.
 * The java lambda compiler and execution engine is tested with respect to
 * its interraction with Erlang terms, along with certain complex use cases.
 *
 * The intent of this test suite is to ensure that the clients
 * can safely use the static methods inside JavaLambdaStringEngine
 * for Erlang calls.
 *
 *
 * @see JavaLambdaStringEngine
 */
public class JavaLambdaStringEngineTest {

    // TODO: do we need this?
    public JavaLambdaStringEngineTest() {
    }

    /**
     * Ensure basic evaluation works flawlessly.
     *
     * Notice that the code has various import at the beginning, with
     * each import on a separate line.
     */
    @Test
    public void basicTest() {
		String code = "\nimport com.ericsson.otp.erlang.OtpErlangObject;\nimport com.ericsson.otp.erlang.OtpErlangAtom;\n() -> new Object(){ public OtpErlangObject main() { return new OtpErlangAtom(\"ok\"); }}";
		OtpErlangBinary codeBinary = new OtpErlangBinary(code.getBytes(StandardCharsets.UTF_8));
		OtpErlangObject result = JavaLambdaStringEngine.evaluate(codeBinary);
		OtpErlangAtom expectedResult = new OtpErlangAtom("ok");
		assertEquals(expectedResult, result);
    }
}
