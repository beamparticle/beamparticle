#!java
//
// api_simple_java
//
// Sample Java 8 function to return what was passed in as the first argument.
// Notice that this template works for the /api/<thisfun> interface, where
// json input is passed in the first argument postBody, while the response
// is a binary or a string, which must be json as well.
// Notice that the second argument, which is context would hold additional
// information as a serialized json (say query params as qs).
// Additionally, this function can be used to test stdout and stderr logs.

import java.nio.charset.StandardCharsets;

import com.ericsson.otp.erlang.OtpErlangAtom;
import com.ericsson.otp.erlang.OtpErlangBinary;

() -> new Object(){
    public OtpErlangBinary main(OtpErlangBinary postBody, OtpErlangBinary context) {
        String bodyStr = new String(postBody.binaryValue(), StandardCharsets.UTF_8);
        String contextStr = new String(context.binaryValue(), StandardCharsets.UTF_8);
        String result = handleEvent(bodyStr, contextStr);
        return new OtpErlangBinary(result.getBytes(StandardCharsets.UTF_8));
    }

    public String handleEvent(String postBody, String context) {
        System.out.println("hello stdout");
        System.err.println("stderr is now available in programmer interface");
        // TODO: (a) deserialize the postBody
        //       (b) process it
        //       (c) return a serialized json response as string
        return postBody.toString();
    }
}
