FROM cimg/base:2024.01

USER root

RUN curl -sSL --output /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v2.9.3/argocd-linux-amd64" \
    && chmod +x /usr/local/bin/argocd

USER circleci
