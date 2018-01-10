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

import pl.joegreen.lambdaFromString.LambdaCreationRuntimeException;
import pl.joegreen.lambdaFromString.LambdaFactoryConfiguration;
import pl.joegreen.lambdaFromString.LambdaFactory;
import pl.joegreen.lambdaFromString.TypeReference;


public class JavaLambdaStringEngine {

	/* no need for mutex because this shall never be used in
     * multi-threaded environment anyways.
     */
	private static Map<String, Supplier<Object>> lambdas = new HashMap<String, Supplier<Object>>();

    private static Pattern importPattern = Pattern.compile("^ *import  *(.*?) *;");

    public static OtpErlangTuple load(OtpErlangBinary nameBinary, OtpErlangBinary codeBinary) {
        try {
            String code = byteArrayToString(codeBinary.binaryValue());
            Supplier<Object> lambda = compileLambda(code);

            /* find the arity */
            Object obj = lambda.get();
            Method[] methods = obj.getClass().getMethods();
            int arity = -1;
            for (Method method : methods) {
                String methodName = method.getName();
                /* match the first public method main */
                if (methodName.equals("main")) {
                    if (arity >= 0) {
                        OtpErlangObject[] elements = {
                            new OtpErlangAtom("error"),
                            new OtpErlangAtom("multiple_entry")};
                        return new OtpErlangTuple(elements);
                    }
                    Type[] pType = method.getGenericParameterTypes();
                    arity = pType.length;
                }
            }
            if (arity >= 0) {
                String key = byteArrayToString(nameBinary.binaryValue()) + "/" + String.valueOf(arity);
                lambdas.put(key, lambda);
                OtpErlangObject[] elements = {
                            new OtpErlangAtom("ok"),
                            new OtpErlangLong(arity)
                        };
                return new OtpErlangTuple(elements);
            } else {
                OtpErlangObject[] elements = {
                            new OtpErlangAtom("error"),
                            new OtpErlangAtom("not_found")
                        };
                return new OtpErlangTuple(elements);
            }
        } catch (LambdaCreationRuntimeException e) {
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        }
    }

    public static boolean hasFunction(String name, int arity) {
        String key = name + "/" + String.valueOf(arity);

        if (lambdas.containsKey(key)) {
            Supplier<Object> lambda = lambdas.get(key);
            return true;
        } else {
            return false;
        }
    }

    public static OtpErlangObject invoke(OtpErlangBinary nameBinary, OtpErlangList arguments) {
        OtpErlangObject[] args = arguments.elements();
        String name = byteArrayToString(nameBinary.binaryValue());
        String key = name + "/" + String.valueOf(args.length);

        if (lambdas.containsKey(key)) {
            Supplier<Object> lambda = lambdas.get(key);
            return runLambda(lambda, args);
        } else {
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangAtom("not_found")
            };
            return new OtpErlangTuple(resultElements);
        }
    }

    public static OtpErlangObject evaluate(OtpErlangBinary codeBinary) {
        try {
            String code = byteArrayToString(codeBinary.binaryValue());
            Supplier<Object> lambda = compileLambda(code);
            return runLambda(lambda, new OtpErlangObject[0]);
        } catch (LambdaCreationRuntimeException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        }
    }

    public static OtpErlangObject unload(OtpErlangBinary nameBinary, OtpErlangLong arity) {
        try {
            String name = byteArrayToString(nameBinary.binaryValue());
            String key = name + "/" + String.valueOf(arity.intValue());
            lambdas.remove(key);
            return new OtpErlangAtom("ok");
        } catch (OtpErlangRangeException e) {
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangBinary(e.toString().getBytes(StandardCharsets.UTF_8))
            };
            return new OtpErlangTuple(resultElements);
        }
    }

    public static OtpErlangAtom reset() {
        lambdas.clear();
        return new OtpErlangAtom("ok");
    }

    private static Supplier<Object> compileLambda(String code)
        throws LambdaCreationRuntimeException {

        String[] parts = code.split("\n");
        List<String> importStatements = new LinkedList<String>();
        List<String> otherStatements = new LinkedList<String>();
        int numImports = 0;
        for (String line : parts) {
            Matcher m = importPattern.matcher(line);
            if (m.matches()) {
                importStatements.add(m.group(1));
                ++numImports;
            } else {
                otherStatements.add(line);
            }
        }
        String[] imports = importStatements.toArray(new String[numImports]);
        String sourcecode = String.join("\n", otherStatements);

        LambdaFactoryConfiguration changedConfiguration = LambdaFactoryConfiguration.get()
            .withImports(imports);
        LambdaFactory factory = LambdaFactory.get(changedConfiguration);
        Supplier<Object> lambda = factory.createLambdaUnchecked(
                sourcecode, new TypeReference<Supplier<Object>>() {});

        return lambda;
    }

    private static OtpErlangObject runLambda(Supplier<Object> lambda, OtpErlangObject[] args) {
        Object obj = lambda.get();
        Class[] argumentTypes = new Class[args.length];
        for (int i = 0; i < args.length; i++) {
            argumentTypes[i] = args[i].getClass();
        }
        try {
            Method method = obj.getClass().getDeclaredMethod("main", argumentTypes);
            // method in anonymous class eventhough public is not accessible
            method.setAccessible(true);
            return (OtpErlangObject) method.invoke(obj, args);
        } catch (NoSuchMethodException e) {
            e.printStackTrace();
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangAtom("not_found")
            };
            return new OtpErlangTuple(resultElements);
        } catch (IllegalAccessException e) {
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
        }
    }

    public static String byteArrayToString(byte[] bytes) {
        return new String(bytes, StandardCharsets.UTF_8);
    }
}
