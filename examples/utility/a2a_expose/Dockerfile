FROM alpine:3.21

ARG TARGETARCH
ARG KUBECTL_VERSION=v1.35.0
ARG KUBELOGIN_VERSION=v0.2.20

WORKDIR /tmp
RUN apk add --no-cache bash ca-certificates coreutils curl jq openssl unzip \
    && case "${TARGETARCH:-amd64}" in \
         amd64|arm64) tool_arch="${TARGETARCH:-amd64}" ;; \
         *) printf 'Unsupported architecture: %s\n' "${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${tool_arch}/kubectl" \
    && curl -fsSLO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${tool_arch}/kubectl.sha256" \
    && printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum -c - \
    && install -m 0755 kubectl /usr/local/bin/kubectl \
    && archive="kubelogin-linux-${tool_arch}.zip" \
    && curl -fsSLO "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/${archive}" \
    && curl -fsSLO "https://github.com/Azure/kubelogin/releases/download/${KUBELOGIN_VERSION}/${archive}.sha256" \
    && sha256sum -c "${archive}.sha256" \
    && unzip -q "${archive}" -d kubelogin \
    && install -m 0755 "kubelogin/bin/linux_${tool_arch}/kubelogin" /usr/local/bin/kubelogin \
    && rm -f kubectl kubectl.sha256 "${archive}" "${archive}.sha256" \
    && rm -r kubelogin

WORKDIR /opt/ram-a2a
COPY --chmod=755 expose-a2a.sh ./
RUN sed -i 's/\r$//' expose-a2a.sh

ENTRYPOINT ["/bin/bash", "/opt/ram-a2a/expose-a2a.sh"]
