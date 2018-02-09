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
import java.lang.ThreadLocal;

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

// see http://www.javadoc.io/doc/com.google.code.gson/gson/2.8.2
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.GsonBuilder;
import com.google.gson.Gson;


public class JavaLambdaStringEngine {

	/* no need for mutex because this shall never be used in
     * multi-threaded environment anyways.
     */
	private static Map<String, Pair<Supplier<Object>, Integer, JsonObject, Integer>> lambdas =
        new HashMap<String, Pair<Supplier<Object>, Integer, JsonObject, Integer>>();

    private static Pattern importPattern = Pattern.compile("^ *import  *(.*?) *;");

	private static ThreadLocal<JsonObject> threadJsonObject = new ThreadLocal<JsonObject>();

	public static JsonObject getConfig() {
		return threadJsonObject.get();
	}

	public static void setConfig(JsonObject obj) {
		threadJsonObject.set(obj);
	}

    public static OtpErlangTuple load(OtpErlangBinary nameBinary, OtpErlangBinary codeBinary, OtpErlangBinary configBinary) {
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
                String config = byteArrayToString(configBinary.binaryValue());
				Gson gson = new GsonBuilder().setPrettyPrinting().create();
				JsonElement jsonElem = gson.fromJson(config, JsonElement.class);
				JsonObject jsonObj = null;
                try {
                    jsonObj = jsonElem.getAsJsonObject();
                } catch (Exception e) {
                    jsonObj = new JsonObject();
                }

                String key = byteArrayToString(nameBinary.binaryValue()) + "/" + String.valueOf(arity);
                lambdas.put(key, new Pair<Supplier<Object>, Integer, JsonObject, Integer>(
                            lambda, new Integer(code.hashCode()),
                            jsonObj, new Integer(config.hashCode())));
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
        return lambdas.containsKey(key);
    }

    public static OtpErlangObject invokeRaw(String entryMethod,
            OtpErlangBinary nameBinary, OtpErlangBinary codeBinary,
            OtpErlangBinary configBinary,
            Object[] args) {
        String name = byteArrayToString(nameBinary.binaryValue());
        String key = name + "/" + String.valueOf(args.length);
        String code = byteArrayToString(codeBinary.binaryValue());

        if (! lambdas.containsKey(key)) {
            OtpErlangTuple loadResult = load(nameBinary, codeBinary, configBinary);
            if (! ((OtpErlangAtom) loadResult.elementAt(0)).atomValue().equals("ok")) {
                // if compilation fails then return error,
                // but this should never happen
                return loadResult;
            }
        }

        if (lambdas.containsKey(key)) {
            Pair<Supplier<Object>, Integer, JsonObject, Integer> p = lambdas.get(key);
            // has the code changed?
            if (p.b.intValue() != code.hashCode()) {
                OtpErlangTuple loadResult = load(nameBinary, codeBinary, configBinary);
                if (((OtpErlangAtom) loadResult.elementAt(0)).atomValue().equals("ok")) {
                    // compilation succeeded, so get the latest value
                    p = lambdas.get(key);
                } else {
                    // if compilation fails then return error,
                    // but this should never happen
                    return loadResult;
                }
            }
            String config = byteArrayToString(configBinary.binaryValue());
			if (p.d.intValue() != config.hashCode()) {
				Gson gson = new GsonBuilder().setPrettyPrinting().create();
				JsonElement tjsonElem = gson.fromJson(config, JsonElement.class);
				JsonObject tjsonObj = null;
                try {
                    tjsonObj = tjsonElem.getAsJsonObject();
                } catch (Exception e) {
                    tjsonObj = new JsonObject();
                }
                // p.c = tjsonObj;
                p = new Pair<Supplier<Object>, Integer, JsonObject, Integer>(
                        p.a, p.b, tjsonObj, config.hashCode());
                // save updated pair to hashmap
                lambdas.put(key, p);
            }
            Supplier<Object> lambda = p.a;
            JsonObject jsonObj = p.c;

            return runLambda(entryMethod, lambda, jsonObj, args);
        } else {
            OtpErlangObject[] resultElements = {
                new OtpErlangAtom("error"),
                new OtpErlangAtom("not_found")
            };
            return new OtpErlangTuple(resultElements);
        }
    }

    // it is possible that arguments is say [1,2] then Erlang will
    // treat this as OtpErlangString instead, which is wrong.
    // Hence this workaround to
    public static OtpErlangObject invoke(OtpErlangBinary nameBinary, OtpErlangBinary codeBinary,
                                         OtpErlangBinary configBinary,
                                         OtpErlangString arguments) {
        char[] chars = arguments.stringValue().toCharArray();
        OtpErlangObject[] args = new OtpErlangObject[chars.length];
        for (int i = 0; i < chars.length; i++) {
            args[i] = new OtpErlangLong((long) chars[i]);
        }
        return invoke(nameBinary, codeBinary, configBinary, new OtpErlangList(args));
    }

    public static OtpErlangObject invoke(OtpErlangBinary nameBinary, OtpErlangBinary codeBinary,
                                         OtpErlangBinary configBinary,
                                         OtpErlangList arguments) {
        Object[] args = arguments.elements();
        OtpErlangObject result = invokeRaw("main", nameBinary, codeBinary, configBinary, args);
        return result;
    }
    public static OtpErlangObject evaluate(OtpErlangBinary codeBinary) {
        try {
            String code = byteArrayToString(codeBinary.binaryValue());
            Supplier<Object> lambda = compileLambda(code);
            return runLambda("main", lambda, new JsonObject(), new OtpErlangObject[0]);
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

    private static OtpErlangObject runLambda(String entryMethod, Supplier<Object> lambda, JsonObject jsonObj, Object[] args) {
        Object obj = lambda.get();
        Class[] argumentTypes = new Class[args.length];
        for (int i = 0; i < args.length; i++) {
            argumentTypes[i] = args[i].getClass();
        }
        try {
			setConfig(jsonObj);
            Method method = obj.getClass().getDeclaredMethod(entryMethod, argumentTypes);
            // method in anonymous class eventhough public is not accessible
            method.setAccessible(true);
            Object result = method.invoke(obj, args);
            if (result instanceof String) {
                return new OtpErlangBinary(result.toString().getBytes(StandardCharsets.UTF_8));
                // TODO how about other data types?
            } else {
                return (OtpErlangObject) result;
            }
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
