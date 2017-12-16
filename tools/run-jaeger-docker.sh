#!/bin/sh
#
# The easiest way to run Jaeger is via docker, but then it is
# better to move into something better for scalable deployment.
#
# see http://jaeger.readthedocs.io/en/latest/getting_started/

docker run -d -e COLLECTOR_ZIPKIN_HTTP_PORT=9411 -p5775:5775/udp -p6831:6831/udp -p6832:6832/udp \
      -p5778:5778 -p16686:16686 -p14268:14268 -p9411:9411 jaegertracing/all-in-one:latest
