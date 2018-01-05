package com.beamparticle;

import java.io.IOException;

public class Application {

    public static void main(String[] args) throws InterruptedException, IOException {
        // args[0] = name of the node
        // args[1] = cookie for node
        // args[2] = name of the parent erlang node
        System.out.println("Java node launched with name=" + args[0]);
        JavaLambdaNode lambdaNode = new JavaLambdaNode();
        lambdaNode.start(args[0], args[1], args[2]);
    }
}
