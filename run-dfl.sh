
# Login to rocky vm, then run these commands



podman run --rm -it --privileged -v /dev:/dev quay.io/silicom/opae-runtime /bin/bash
podman run --rm -it --privileged -v /dev:/dev quay.io/silicom/opae-runtime fpgainfo
