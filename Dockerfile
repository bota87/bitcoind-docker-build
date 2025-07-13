ARG OS=debian
ARG OS_VER=bullseye-slim
FROM ${OS}:${OS_VER} as os-base

# Install dependencies
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update -qq && apt-get install -yqq \
		curl unzip jq bash-completion && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM os-base as bitcoind-install

ARG TARGETPLATFORM
ARG BITCOIN_VERSION=25.0
# Install Bitcoin Core binaries and libraries
RUN if [ "${TARGETPLATFORM}" = "linux/amd64" ]; then export TARGETPLATFORM=x86_64-linux-gnu; fi && \
    if [ "${TARGETPLATFORM}" = "linux/arm64" ]; then export TARGETPLATFORM=aarch64-linux-gnu; fi && \
    if [ "${TARGETPLATFORM}" = "linux/arm/v7" ]; then export TARGETPLATFORM=arm-linux-gnueabihf; fi && \
    cd /tmp && \
    curl -SLO https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-${TARGETPLATFORM}.tar.gz && \
    tar -zxf bitcoin-${BITCOIN_VERSION}-${TARGETPLATFORM}.tar.gz && \
	cd bitcoin-${BITCOIN_VERSION} && \
	install -vD bin/* /usr/bin && \
	install -vD lib/* /usr/lib && \
	cd /tmp && \
	rm bitcoin-${BITCOIN_VERSION}-${TARGETPLATFORM}.tar.gz && \
	rm -rf bitcoin-${BITCOIN_VERSION}

# bash completion for bitcoind and bitcoin-cli
# TODO andrebbero presi dal ramo della versione corretta invece che da master
ENV GH_URL https://raw.githubusercontent.com/bitcoin/bitcoin/master/
ENV BC /usr/share/bash-completion/completions/
ADD $GH_URL/contrib/completions/bash/bitcoin-cli.bash $BC/bitcoin-cli
ADD $GH_URL/contrib/completions/bash/bitcoind.bash $BC/bitcoind
ADD $GH_URL/contrib/completions/bash/bitcoin-tx.bash $BC/bitcoin-tx

# zmqpubrawblock
EXPOSE 28332/tcp
# zmqpubrawtx
EXPOSE 28333/tcp

ENTRYPOINT ["bitcoind"]
