# Slam Stack — Backup Runner Image
# Alpine-based image with talosctl, age, cosign, s3cmd
FROM alpine:3.21 AS tools

RUN apk add --no-cache curl bash python3 py3-pip coreutils

# Install talosctl
ARG TALOS_VERSION=v1.9.3
RUN curl -sL "https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-amd64" \
    -o /usr/local/bin/talosctl && chmod +x /usr/local/bin/talosctl

# Install age
ARG AGE_VERSION=v1.2.0
RUN curl -sL "https://github.com/FiloSottile/age/releases/download/${AGE_VERSION}/age-${AGE_VERSION}-linux-amd64.tar.gz" \
    | tar xz -C /usr/local/bin age age-keygen

# Install cosign
ARG COSIGN_VERSION=v2.4.1
RUN curl -sL "https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64" \
    -o /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign

# Install s3cmd
RUN pip install --break-system-packages s3cmd

FROM alpine:3.21
RUN apk add --no-cache bash coreutils python3

COPY --from=tools /usr/local/bin/talosctl /usr/local/bin/
COPY --from=tools /usr/local/bin/age /usr/local/bin/age-keygen /usr/local/bin/
COPY --from=tools /usr/local/bin/cosign /usr/local/bin/
COPY --from=tools /usr/local/bin/s3cmd /usr/local/bin/
COPY --from=tools /usr/lib/python3* /usr/lib/

COPY scripts/backup-verify.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

USER 10000:10000
