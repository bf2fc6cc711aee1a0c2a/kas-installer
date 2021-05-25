OPSDK_VERSION=v1.7.2
OPSDK=bin/operator-sdk

export ARCH=$(case $(uname -m) in x86_64) echo -n amd64 ;; aarch64) echo -n arm64 ;; *) echo -n $(uname -m) ;; esac)
export OS=$(uname | awk '{print tolower($0)}')
export OPERATOR_SDK_DL_URL=https://github.com/operator-framework/operator-sdk/releases/download/${OPSDK_VERSION}

if ! [ -f ${OPSDK} ] ; then
    mkdir -v bin
    curl -L -o ${OPSDK} ${OPERATOR_SDK_DL_URL}/operator-sdk_${OS}_${ARCH}
    chmod -v +x ${OPSDK}
fi

echo -n "Checking for OLM... "
${OPSDK} olm status >/dev/null 2>&1

if [ $? -ne 0 ] ; then
    echo "[ NOT FOUND ]"
    echo "Installing OLM..."
    ${OPSDK} olm install

    if [ $? -ne 0 ] ; then
        echo "Error installing OLM"
        exit 1
    fi
else
    echo "[ OK ]"
fi
