FROM cimg/base:2024.02

USER root

RUN curl -sSL --output /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v2.10.6/argocd-linux-amd64" \
    && chmod +x /usr/local/bin/argocd

USER circleci
