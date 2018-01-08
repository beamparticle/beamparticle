#!/bin/sh

cd support/javanode \
    && ./gradlew clean build \
    && cd - \
    && rm -rf priv/javanode \
    && unzip support/javanode/build/distributions/javanode.zip -d priv
