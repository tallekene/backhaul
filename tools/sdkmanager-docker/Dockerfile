# Runs Garmin's Connect IQ SDK Manager on a host that no longer ships
# webkit2gtk-4.0.
#
# The manager is the only way to download device definitions (the endpoint
# behind it, api.gcs.garmin.com/ciq-product-onboarding/devices, 401s without a
# Garmin sign-in), and it links libwebkit2gtk-4.0 + libsoup-2.4. Arch dropped
# webkit2gtk-4.0 because it is EOL upstream, and 4.1 cannot substitute: it
# requires libsoup-3, which cannot coexist with libsoup-2 in one process.
#
# Ubuntu 22.04 still carries the 4.0 stack, so the manager runs here and writes
# devices into the bind-mounted ~/.Garmin on the host, where the natively
# installed SDK picks them up.
FROM ubuntu:22.04

RUN apt-get update && apt-get install -y --no-install-recommends \
        libwebkit2gtk-4.0-37 \
        libgtk-3-0 \
        libgl1 \
        libnss3 \
        libasound2 \
        ca-certificates \
        fonts-dejavu-core \
        xdg-utils \
        libcurl4 \
        libsm6 \
        libice6 \
        libusb-1.0-0 \
        openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

# The container runs as the host user's uid so that files written into the
# mounted ~/.Garmin stay owned by them. That uid has no passwd entry here, so
# HOME is set explicitly and made world-writable.
RUN mkdir -p /home/dev && chmod 777 /home/dev
ENV HOME=/home/dev

ENTRYPOINT ["/home/dev/.Garmin/ConnectIQ/sdkmanager/bin/sdkmanager"]
