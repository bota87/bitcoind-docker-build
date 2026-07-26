ARG OS=debian
ARG OS_VER=bookworm-slim
FROM ${OS}:${OS_VER} AS os-base

# Install dependencies
RUN DEBIAN_FRONTEND=noninteractive \
    apt-get update -qq && apt-get install -yqq \
		curl unzip jq bash-completion && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

FROM os-base AS bitcoind-install

ARG TARGETPLATFORM
ARG BITCOIN_VERSION=29.3

# Chiavi dei builder di Bitcoin Core, nel formato <nome-file>:<fingerprint>.
# I file vengono da bitcoin-core/guix.sigs (builder-keys/); la fingerprint e'
# l'ancoraggio di fiducia e viene confrontata prima di importare la chiave.
#
# Set scelto misurando quante GOODSIG ciascuna chiave produce oggi sulle
# release 26.2 -> 31.1 (il numero a fianco e' su 9 release recenti, 29.0+).
# Il criterio deve essere GOODSIG e non "ha firmato": una chiave scaduta
# produce EXPKEYSIG, che non viene conteggiata, quindi contribuisce zero
# anche se compare tra i firmatari (e' il caso di glozow, esclusa apposta).
#
# Su quel campione il minimo e' 5 chiavi valide per release (7 dalla 29.0 in
# poi), da cui la soglia di 4 qui sotto. Cambiando una chiave, rimisurare il
# pavimento: una soglia sopra il pavimento blocca release legittime.
ARG BITCOIN_SIGNERS="\
achow101:152812300785C96444D3334D17565732E08E5E41 \
Emzy:9EDAFF80E080659604F4A76B2EBB056FD847F8A7 \
pinheadmz:E61773CD6E01040E2F1BD78CE7E2984B6289C93A \
guggero:F4FC70F07310028424EFC20A8E4256593F177720 \
hebasto:D1DBF2C4B96F2DEBF4C16654410108112E7EA81F \
Sjors:ED9BDF7AD6A55E232E84524257FF9BDBCC301009 \
fanquake:E777299FC265DD04793070EB944D35F9AC3DB76A \
willcl-ark:67AA5B46E7AF78053167FE343B8F814A784218F8 \
sipsorcery:9D3CC86A72F8494342EA5FD10A41BDC3F4FAFF1C \
sedited:A8FC55F3B04BA3146F3492E79303B33A305224CB"
ARG BITCOIN_MIN_SIGS=4
ARG GUIX_SIGS_RAW=https://raw.githubusercontent.com/bitcoin-core/guix.sigs/main/builder-keys

# Install Bitcoin Core binaries, previa verifica della firma GPG e dello SHA256.
# gnupg viene installato e rimosso nello stesso RUN, per non lasciarlo nell'immagine.
RUN set -eu; \
    case "${TARGETPLATFORM}" in \
      linux/amd64) ARCH=x86_64-linux-gnu ;; \
      linux/arm64) ARCH=aarch64-linux-gnu ;; \
      *) echo "TARGETPLATFORM non supportata: ${TARGETPLATFORM}" >&2; exit 1 ;; \
    esac; \
    DEBIAN_FRONTEND=noninteractive apt-get update -qq; \
    DEBIAN_FRONTEND=noninteractive apt-get install -yqq --no-install-recommends gnupg; \
    GNUPGHOME="$(mktemp -d)"; export GNUPGHOME; \
    cd /tmp; \
    BASE="https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}"; \
    TARBALL="bitcoin-${BITCOIN_VERSION}-${ARCH}.tar.gz"; \
    curl -fsSL -O "${BASE}/${TARBALL}"; \
    curl -fsSL -O "${BASE}/SHA256SUMS"; \
    curl -fsSL -O "${BASE}/SHA256SUMS.asc"; \
    for entry in ${BITCOIN_SIGNERS}; do \
      name="${entry%%:*}"; fpr="${entry#*:}"; \
      curl -fsSL -o builder.gpg "${GUIX_SIGS_RAW}/${name}.gpg"; \
      gpg --batch --show-keys --with-colons builder.gpg | grep -q "^fpr:::::::::${fpr}:" \
        || { echo "fingerprint inattesa per ${name}, attesa ${fpr}" >&2; exit 1; }; \
      gpg --batch --quiet --import builder.gpg; \
      rm builder.gpg; \
    done; \
    status="$(gpg --batch --verify --status-fd 1 SHA256SUMS.asc SHA256SUMS 2>/dev/null || true)"; \
    good="$(printf '%s\n' "${status}" | grep -c '^\[GNUPG:\] GOODSIG' || true)"; \
    expired="$(printf '%s\n' "${status}" | grep -c '^\[GNUPG:\] EXPKEYSIG' || true)"; \
    echo "SHA256SUMS: ${good} firme valide da chiavi pinnate, ${expired} da chiavi scadute"; \
    [ "${good}" -ge "${BITCOIN_MIN_SIGS}" ] || { \
      echo "servono almeno ${BITCOIN_MIN_SIGS} firme valide da chiavi pinnate, trovate ${good}." >&2; \
      echo "se il conteggio e' calato per scadenze (${expired}), ruotare le chiavi in BITCOIN_SIGNERS." >&2; \
      exit 1; }; \
    grep -F "  ${TARBALL}" SHA256SUMS | sha256sum -c -; \
    tar -zxf "${TARBALL}"; \
    install -v -t /usr/bin "bitcoin-${BITCOIN_VERSION}/bin/"*; \
    DEBIAN_FRONTEND=noninteractive apt-get purge -yqq gnupg; \
    DEBIAN_FRONTEND=noninteractive apt-get autoremove -yqq; \
    apt-get clean; \
    rm -rf "${GNUPGHOME}" /var/lib/apt/lists/* /tmp/* /var/tmp/*

# bash completion per bitcoind, bitcoin-cli e bitcoin-tx, prese dal tag della
# versione installata: quelle di master descrivono RPC che qui possono non esistere.
RUN set -eu; \
    GH_RAW="https://raw.githubusercontent.com/bitcoin/bitcoin/v${BITCOIN_VERSION}/contrib/completions/bash"; \
    for c in bitcoin-cli bitcoind bitcoin-tx; do \
      curl -fsSL "${GH_RAW}/${c}.bash" -o "/usr/share/bash-completion/completions/${c}"; \
    done

# zmqpubrawblock
EXPOSE 28332/tcp
# zmqpubrawtx
EXPOSE 28333/tcp

ENTRYPOINT ["bitcoind"]
