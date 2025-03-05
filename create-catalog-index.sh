#!/bin/bash

OCP_MAJOR_VERSION="4.17"

INDEXES=("registry.redhat.io/redhat/redhat-operator-index:v${OCP_MAJOR_VERSION}" "registry.redhat.io/redhat/community-operator-index:v${OCP_MAJOR_VERSION}")
INCLUDE_OPERATORS=("kubernetes-nmstate-operator" "metallb-operator" "3scale-operator" "patch-operator" "ipfs-operator")

MIRROR_REGISTRY="disconn-harbor.d70.kemo.labs"
MIRROR_PATH="man-mirror"

INDEX_DIR="/tmp/opm-index-${OCP_MAJOR_VERSION}"
AUTH_FILE="/root/.combined-mirror-ps.json"

mkdir -p ${INDEX_DIR}/{combined,yaml}
echo "" > ${INDEX_DIR}/combined/filtered-olm.json

for INDEX in "${INDEXES[@]}"; do
        INDEX_NAME=$(echo $INDEX | rev | cut -d'/' -f 1 | rev | cut -d':' -f 1)
        MIRROR_IMAGE_URI="${MIRROR_REGISTRY}/${MIRROR_PATH}/${INDEX_NAME}:v${OCP_MAJOR_VERSION}"
        mkdir -p ${INDEX_DIR}/${INDEX_NAME}/{orig,filtered}

        echo "Rendering upstream index for ${INDEX_NAME} ..."
        opm render ${INDEX} -o json > ${INDEX_DIR}/${INDEX_NAME}/orig/index.json

        echo "Separating index files..."
        jq -r 'select(.schema == "olm.channel")' ${INDEX_DIR}/${INDEX_NAME}/orig/index.json > ${INDEX_DIR}/${INDEX_NAME}/orig/channels.json
        jq -r 'select(.schema == "olm.bundle")' ${INDEX_DIR}/${INDEX_NAME}/orig/index.json > ${INDEX_DIR}/${INDEX_NAME}/orig/bundles.json
        jq -r 'select(.schema == "olm.package")' ${INDEX_DIR}/${INDEX_NAME}/orig/index.json > ${INDEX_DIR}/${INDEX_NAME}/orig/packages.json
        jq -r 'select(.schema == "olm.deprecations")' ${INDEX_DIR}/${INDEX_NAME}/orig/index.json > ${INDEX_DIR}/${INDEX_NAME}/orig/deprecations.json

        # Filter through operators
        JQ_PACKAGE_FILTER="select("
        JQ_FILTER="select("
        for OP in "${INCLUDE_OPERATORS[@]}"; do
                JQ_FILTER="${JQ_FILTER} .package == \"${OP}\" or"
                JQ_PACKAGE_FILTER="${JQ_PACKAGE_FILTER} .name == \"${OP}\" or"
        done

        JQ_FILTER="${JQ_FILTER::-3})"
        JQ_PACKAGE_FILTER="${JQ_PACKAGE_FILTER::-3})"

        echo "" > ${INDEX_DIR}/${INDEX_NAME}/filtered/${INDEX_NAME}.json

        echo "Generating dockerfile..."
        opm generate dockerfile ${INDEX_DIR}/${INDEX_NAME}/filtered

        echo "Filtering operators..."
        jq -r ''"${JQ_FILTER}"'' ${INDEX_DIR}/${INDEX_NAME}/orig/channels.json >> ${INDEX_DIR}/${INDEX_NAME}/filtered/${INDEX_NAME}.json
        jq -r ''"${JQ_FILTER}"'' ${INDEX_DIR}/${INDEX_NAME}/orig/channels.json >> ${INDEX_DIR}/combined/filtered-olm.json

        jq -r ''"${JQ_FILTER}"'' ${INDEX_DIR}/${INDEX_NAME}/orig/bundles.json >> ${INDEX_DIR}/${INDEX_NAME}/filtered/${INDEX_NAME}.json
        jq -r ''"${JQ_FILTER}"'' ${INDEX_DIR}/${INDEX_NAME}/orig/bundles.json >> ${INDEX_DIR}/combined/filtered-olm.json

        jq -r ''"${JQ_PACKAGE_FILTER}"'' ${INDEX_DIR}/${INDEX_NAME}/orig/packages.json >> ${INDEX_DIR}/${INDEX_NAME}/filtered/${INDEX_NAME}.json
        jq -r ''"${JQ_PACKAGE_FILTER}"'' ${INDEX_DIR}/${INDEX_NAME}/orig/packages.json >> ${INDEX_DIR}/combined/filtered-olm.json

        echo "Validating Index Catalog..."
        opm validate ${INDEX_DIR}/${INDEX_NAME}/filtered/ && echo "OK!"

        podman build --no-cache -f ${INDEX_DIR}/${INDEX_NAME}/filtered.Dockerfile -t ${MIRROR_IMAGE_URI} ${INDEX_DIR}/${INDEX_NAME} && podman push --authfile ${AUTH_FILE} ${MIRROR_IMAGE_URI}

        echo "Generating CatalogSource YAML..."
        cat > ${INDEX_DIR}/yaml/${INDEX_NAME}.yaml <<EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  annotations:
    target.workload.openshift.io/management: '{"effect": "PreferredDuringScheduling"}'
  name: ${INDEX_NAME}
  namespace: openshift-marketplace
spec:
  displayName: ${INDEX_NAME}
  grpcPodConfig:
    extractContent:
      cacheDir: /tmp/cache
      catalogDir: /configs
    memoryTarget: 30Mi
    nodeSelector:
      kubernetes.io/os: linux
      node-role.kubernetes.io/master: ''
    priorityClassName: system-cluster-critical
    securityContextConfig: restricted
    tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
        operator: Exists
      - effect: NoExecute
        key: node.kubernetes.io/unreachable
        operator: Exists
        tolerationSeconds: 120
      - effect: NoExecute
        key: node.kubernetes.io/not-ready
        operator: Exists
        tolerationSeconds: 120
  image: ${MIRROR_IMAGE_URI}
  publisher: Private
  sourceType: grpc
  updateStrategy:
    registryPoll:
      interval: 10m
EOF

done

#echo "Validating Combined Catalog..."
#opm validate ${INDEX_DIR}/combined/ && echo "OK!"

echo "Apply the Catalog with:"
echo "oc apply -R -f ${INDEX_DIR}/yaml/"
