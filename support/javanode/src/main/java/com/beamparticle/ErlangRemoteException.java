/*
 *
 * see https://github.com/joedevivo/gen_java/blob/master/src/main/java/com/devivo/gen_java/ErlangRemoteException.java
 */
package com.beamparticle;

import com.ericsson.otp.erlang.*;

public class ErlangRemoteException extends Exception {
    private OtpErlangPid fromPid;
    private OtpErlangRef fromRef;

    public ErlangRemoteException(OtpErlangPid fromPid, OtpErlangRef fromRef, String msg) {
        super(msg);
        this.fromPid = fromPid;
        this.fromRef = fromRef;
    }

    public ErlangRemoteException(OtpErlangPid fromPid, OtpErlangRef fromRef, Exception e) {
        super(e);
        this.fromPid = fromPid;
        this.fromRef = fromRef;
    }

    public static OtpErlangObject toErlangException(Exception e) {
        OtpErlangObject[] elements = new OtpErlangObject[2];
        elements[0] = new OtpErlangAtom("error");
        elements[1] = new OtpErlangString(e.getMessage());
        return new OtpErlangTuple(elements);
    }

    public OtpErlangObject toErlangException() {
        return toErlangException(this);
    }

    public void send(OtpMbox mbox) {
        OtpErlangObject[] elements = new OtpErlangObject[2];
        elements[0] = this.fromRef;
        elements[1] = this.toErlangException();
        mbox.send(this.fromPid, new OtpErlangTuple(elements));
    }
}
