/*
 *
 * Original version is at the following url:
 *
 * see https://github.com/joedevivo/gen_java/blob/master/src/main/java/com/devivo/gen_java/ErlangRemoteProcedureCallMessage.java
 */
package com.beamparticle;

import com.ericsson.otp.erlang.*;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;

// { '$gen_call', {Pid::pid, Ref::ref}, {Mod::atom, Fun::atom, List::list()}}
public class ErlangGenServer implements Runnable {

    private final OtpMbox otpMbox;
    private final String erlangNodeName;
    private OtpErlangPid fromPid;
    private OtpErlangRef fromRef;

    private ErlangModFunArgs mfa = null;
    // private OtpErlangPid remoteGroupLeaderPid = null;
    private Method method;

    // Contructor Deconstructs Erlang rpc:call into it's components
    // { '$gen_call', {Pid::pid, Ref::ref}, {Mod::atom, Fun::atom, List::list()}}
    public ErlangGenServer(OtpMbox mbox, OtpErlangObject msg, String erlangNodeName) throws Exception {
        this.otpMbox = mbox;
        this.erlangNodeName = erlangNodeName;
        // If it's not a tuple, it's already wrong
        if (msg instanceof OtpErlangTuple) {
            OtpErlangTuple genServerCall = (OtpErlangTuple) msg;

            // Validate Arity
            int arity = genServerCall.arity();
            if (arity != 3) {
                throw new Exception("message has invalid arity. expected 3, got " + arity);
            }

            //Validate gen_call as first element:
            OtpErlangAtom gen_call = (OtpErlangAtom)(genServerCall.elementAt(0));
            String gen_call_string = gen_call.atomValue();
            if (!gen_call_string.equals("$gen_call")) {
                throw new Exception("message should start with '$gen_call': " + msg.toString());
            }

            // Validate second element: {Pid::pid, Ref::ref}
            OtpErlangTuple fromTuple = (OtpErlangTuple)(genServerCall.elementAt(1));
            int fromArity = fromTuple.arity();
            if (fromArity != 2) {
                throw new Exception("message's 'from' tuple should have 2 elements, has " + fromArity + ": " + msg.toString());
            }

            this.fromPid = (OtpErlangPid)(fromTuple.elementAt(0));
            this.fromRef = (OtpErlangRef)(fromTuple.elementAt(1));

            // Validate the call tuple: {Mod::atom, Fun::atom, List::list()}
            OtpErlangTuple callTuple = (OtpErlangTuple)(genServerCall.elementAt(2));
            int callArity = callTuple.arity();
            if (callArity != 3) {
                throw new ErlangRemoteException(this.fromPid, this.fromRef, "message's 'call' tuple should have 3 elements, has " + callArity + ": " + msg.toString());
            }

            try {
                this.mfa = new ErlangModFunArgs(
                    (OtpErlangAtom)(callTuple.elementAt(0)),
                    (OtpErlangAtom)(callTuple.elementAt(1)),
                    (OtpErlangList)(callTuple.elementAt(2)));
                // this.remoteGroupLeaderPid = (OtpErlangPid)(callTuple.elementAt(4));
            } catch (Exception e) {
                throw new ErlangRemoteException(this.fromPid, this.fromRef, e);
            }

        } else {
            // error case for non rex call
            throw new Exception("Invalid message: " + msg.toString());
        }
    }

    public OtpErlangPid getFromPid() {
        return this.fromPid;
    }

    public OtpErlangRef getFromRef() {
        return this.fromRef;
    }

    public ErlangModFunArgs getMFA() {
        return this.mfa;
    }

    public OtpErlangTuple wrapResponse(OtpErlangObject resp) {
        OtpErlangObject[] elements = new OtpErlangObject[2];
        elements[0] = this.fromRef;
        elements[1] = resp;
        return new OtpErlangTuple(elements);
    }

    public OtpErlangObject toErlangBadRPC() {
        // Bad RPC calls look like this:
        //{badrpc,{'EXIT',{undef,[{Module,Fun,[],[]},
        //                {rpc,'-handle_call_call/6-fun-0-',5,
        //                     [{file,"rpc.erl"},{line,205}]}]}}}
        OtpErlangObject[] fileTuple = new OtpErlangObject[2];
        fileTuple[0] = new OtpErlangAtom("file");
        fileTuple[1] = new OtpErlangString("rpc.erl");

        OtpErlangObject[] lineTuple = new OtpErlangObject[2];
        lineTuple[0] = new OtpErlangAtom("line");
        lineTuple[1] = new OtpErlangInt(205);

        OtpErlangObject[] trace = new OtpErlangObject[2];
        trace[0] = new OtpErlangTuple(fileTuple);
        trace[1] = new OtpErlangTuple(lineTuple);

        OtpErlangObject[] rpcTuple = new OtpErlangObject[4];
        rpcTuple[0] = new OtpErlangAtom("rpc");
        rpcTuple[1] = new OtpErlangAtom("-handle_call_call/6-fun-0-");
        rpcTuple[2] = new OtpErlangInt(5);
        rpcTuple[3] = new OtpErlangList(trace);

        OtpErlangObject[] mfaTuple = new OtpErlangObject[4];
        mfaTuple[0] = this.mfa.getModule();
        mfaTuple[1] = this.mfa.getFunction();
        mfaTuple[2] = this.mfa.getArgs();
        mfaTuple[3] = new OtpErlangList();

        OtpErlangObject[] undefList = new OtpErlangObject[2];
        undefList[0] = new OtpErlangTuple(mfaTuple);
        undefList[1] = new OtpErlangTuple(rpcTuple);

        OtpErlangObject[] undefTuple = new OtpErlangObject[2];
        undefTuple[0] = new OtpErlangAtom("undef");
        undefTuple[1] = new OtpErlangList(undefList);

        OtpErlangObject[] exitTuple = new OtpErlangObject[2];
        exitTuple[0] = new OtpErlangAtom("EXIT");
        exitTuple[1] = new OtpErlangTuple(undefTuple);

        OtpErlangObject[] badrpcTuple = new OtpErlangObject[2];
        badrpcTuple[0] = new OtpErlangAtom("badrpc");
        badrpcTuple[1] = new OtpErlangTuple(exitTuple);
        return new OtpErlangTuple(badrpcTuple);
    }

    public void send(OtpErlangObject resp) {
        this.otpMbox.send(this.fromPid, wrapResponse(resp));
    }

    @Override
    public void run() {
        OtpErlangObject result = new OtpErlangAtom("null");
        try {
            result = (OtpErlangObject) this.method.invoke(null, getMFA().getArgs().elements());
        } catch (Exception e) {
            // This could "technically" throw a InvocationTargetException or an
            // IllegalAccessException. We'll write defensive code for that eventually
            System.out.println(e.getClass().getName() + " : " + e.getMessage());
            result = error(e.getClass().getName() + " : " + e.getMessage());
        }
        this.send(result);
    }

    public void setMethod(Method method) {
        this.method = method;
    }

    public static OtpErlangTuple error(String s) {
        OtpErlangObject[] errorTuple = new OtpErlangObject[2];
        errorTuple[0] = new OtpErlangAtom("error");
        errorTuple[1] = new OtpErlangString(s);
        return new OtpErlangTuple(errorTuple);
    }

}
