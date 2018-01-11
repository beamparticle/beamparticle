/*
 *
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

import com.ericsson.otp.erlang.OtpErlangAtom;
import com.ericsson.otp.erlang.OtpErlangDecodeException;
import com.ericsson.otp.erlang.OtpErlangExit;
import com.ericsson.otp.erlang.OtpErlangLong;
import com.ericsson.otp.erlang.OtpErlangMap;
import com.ericsson.otp.erlang.OtpErlangBinary;
import com.ericsson.otp.erlang.OtpErlangList;
import com.ericsson.otp.erlang.OtpErlangObject;
import com.ericsson.otp.erlang.OtpErlangString;
import com.ericsson.otp.erlang.OtpErlangTuple;
import com.ericsson.otp.erlang.OtpErlangRangeException;

import java.nio.charset.StandardCharsets;

import java.io.IOException;

import java.util.Arrays;
import java.util.stream.Collectors;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Type;

import java.util.function.Supplier;
import java.util.HashMap;
import java.util.Map;
import java.util.List;
import java.util.LinkedList;
import java.util.regex.Pattern;
import java.util.regex.Matcher;

public class SimpleHttpLambdaRouter {

    /*
     * Note that data and context are typically serialized json text strings
     *
     * nameBinary is either name of dynamic anonymous class
     * which has a public function handleEvent(Object data, Object context).
     */
    public static OtpErlangObject invoke(
            OtpErlangBinary nameBinary,
            OtpErlangBinary codeBinary,
            OtpErlangBinary dataBinary,
            OtpErlangBinary contextBinary) {
        String name = JavaLambdaStringEngine.byteArrayToString(
                nameBinary.binaryValue());
        String data = JavaLambdaStringEngine.byteArrayToString(
                dataBinary.binaryValue());
        String context = JavaLambdaStringEngine.byteArrayToString(
                contextBinary.binaryValue());

        Object[] args = new Object[2];
        args[0] = data;
        args[1] = context;
        return JavaLambdaStringEngine.invokeRaw(
                "handleEvent", nameBinary, codeBinary, args);
    }

    /*
     * Note that data and context are typically serialized json text strings
     *
     * nameBinary is fully resolved java class (e.g. com.beamparticle...) which has
     * a public function handleEvent(Object data, Object context).
     */
    public static OtpErlangObject invokeCompiled(
            OtpErlangBinary nameBinary,
            OtpErlangBinary dataBinary,
            OtpErlangBinary contextBinary) {
        String name = JavaLambdaStringEngine.byteArrayToString(
                nameBinary.binaryValue());
        String data = JavaLambdaStringEngine.byteArrayToString(
                dataBinary.binaryValue());
        String context = JavaLambdaStringEngine.byteArrayToString(
                contextBinary.binaryValue());

        try {
            Class c = Class.forName(name);
            Object t = c.newInstance();
            Class[] argumentTypes = new Class[2];
            argumentTypes[0] = Object.class;
            argumentTypes[1] = Object.class;
            Method method = c.getDeclaredMethod(
                    "handleEvent",
                    argumentTypes);
            method.setAccessible(true);
            Object r = method.invoke(t, data, context);
            return new OtpErlangBinary(
                    r.toString().getBytes(StandardCharsets.UTF_8));
        } catch (ClassNotFoundException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        } catch (NoSuchMethodException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        } catch (InvocationTargetException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        } catch (InstantiationException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        } catch (IllegalAccessException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        }
    }
}
