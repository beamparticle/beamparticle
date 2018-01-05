/*
 * see https://github.com/joedevivo/gen_java/blob/master/src/main/java/com/devivo/gen_java/ErlangModFunArgs.java
 */
package com.beamparticle;

import com.ericsson.otp.erlang.*;

public class ErlangModFunArgs {

    private OtpErlangAtom module = null;
    private OtpErlangAtom function = null;
    private OtpErlangList args = null;
    // private ErlangFunctionCacheKey key = null;

    public ErlangModFunArgs(OtpErlangAtom m, OtpErlangAtom f, OtpErlangList l) {
        this.module = m;
        this.function = f;
        this.args = l;
        /*
        this.key = new ErlangFunctionCacheKey(
            m.atomValue(),
            f.atomValue(),
            argsToClasses(l)
        );
        */
    }

    //public ErlangFunctionCacheKey getKey() {
    //    return this.key;
    //}

    public OtpErlangAtom getModule() {
        return this.module;
    }

    public OtpErlangAtom getFunction() {
        return this.function;
    }

    public OtpErlangList getArgs() {
        return this.args;
    }

    public boolean match(String m, String f, int arity) {
        return this.module.atomValue().equals(m)
            && this.function.atomValue().equals(f)
            && this.args.arity() == arity;
    }

    private static Class[] argsToClasses(OtpErlangList l) {
        Class[] classes = new Class[l.arity()];
        for (int i = 0; i < l.arity(); i++) {
            classes[i] = l.elementAt(i).getClass();
        }
        return classes;
    }
}
