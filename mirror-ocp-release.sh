#!/bin/bash

# Mirror registries must support pushing without a tag (only a shasum)

# Download oc binary
# https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/latest/

# Make a joined container pull secret containing all RH credentials as well as your own
# ./join-auths.sh private-ps.json red-hat-ps.json > ~/.combined-mirror-ps.json

AUTH_FILE="/root/.combined-mirror-ps.json"

OCP_MAJOR_RELEASE="4.17"
OCP_RELEASE="${OCP_MAJOR_RELEASE}.16"

LOCAL_REGISTRY="disconn-harbor.d70.kemo.labs"
LOCAL_REGISTRY_PATH_OCP_RELEASE="man-mirror/ocp"

DRY_RUN="true"
MIRROR_METHOD="direct" # direct or file

# No need to change these things - probably
OCP_BASE_REGISTRY_PATH="${LOCAL_REGISTRY}/${LOCAL_REGISTRY_PATH_OCP_RELEASE}"
TARGET_SAVE_PATH="/tmp/ocp-mirror-${OCP_RELEASE}"
ARCHITECTURE="x86_64" # x86_64, aarch64, s390x, ppc64le
PRODUCT_REPO="openshift-release-dev"
RELEASE_NAME="ocp-release"
UPSTREAM_PATH="${PRODUCT_REPO}/${RELEASE_NAME}"
SKIP_TLS_VERIFY="false"

# Check for needed binaries
if [ ! $(which oc) ]; then echo "oc not found!" && exit 1; fi

# Make the save path directory
mkdir -p ${TARGET_SAVE_PATH}

# Mirror OpenShift release
if [ "$MIRROR_RELEASE" == "true" ]; then
        echo "Mirroring OpenShift Release..."

        MIRROR_CMD="oc adm release mirror -a ${AUTH_FILE} --print-mirror-instructions=none --from=quay.io/${UPSTREAM_PATH}:${OCP_RELEASE}-${ARCHITECTURE}"
        if [ "${MIRROR_METHOD}" == "direct" ]; then MIRROR_CMD="${MIRROR_CMD} --to=${OCP_BASE_REGISTRY_PATH} --to-release-image=${OCP_BASE_REGISTRY_PATH}:${OCP_RELEASE}-${ARCHITECTURE}"; fi
        if [ "${MIRROR_METHOD}" == "file" ]; then MIRROR_CMD="${MIRROR_CMD} --to-dir=${TARGET_SAVE_PATH}"; fi
        if [ "${DRY_RUN}" == "true" ]; then MIRROR_CMD="${MIRROR_CMD} --dry-run"; fi
        $MIRROR_CMD
fi
