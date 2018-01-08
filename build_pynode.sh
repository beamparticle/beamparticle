#!/bin/sh

cd support/pynode \
    && make release \
    && cd - \
    && rm -rf priv/pynode \
    && mkdir -p priv/pynode/bin \
    && mkdir -p priv/pynode/lib \
    && cp -p support/pynode/pynode priv/pynode/bin/ \
    && cp -p support/pynode/pynode.py priv/pynode/lib/ \
    && cp -p support/pynode/*.zip priv/pynode/lib/
