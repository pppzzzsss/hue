#!/bin/bash

set -ex

WORK_DIR=$(dirname $(readlink -f $0))
HUE_SRC=$(realpath $WORK_DIR/../..)
BUILD_DIR=$(realpath $HUE_SRC/../containerbuild$GBN)
HUE_DIR=$WORK_DIR/hue
APACHE_DIR=$WORK_DIR/huelb
BASEHUE_DIR=$WORK_DIR/base/hue
BASEHUELB_DIR=$WORK_DIR/base/huelb
HUEBASE_VERSION=huebase_centos:7.6
HUELBBASE_VERSION=huelb_httpd:2.4.7.6
HUEUSER="hive"

if [ -z "$REGISTRY" ]; then
  REGISTRY=${REGISTRY:-"docker.io/hortonworks"}
  BASEOS_URL=${REGISTRY:-"docker.io/centos:centos7"}
else
  if [[ $REGISTRY == *cdh ]]; then
    BASEOS_URL=$(echo $(echo $REGISTRY | cut -d '/' -f 1)/cloudera_base/centos:7.6.1810)
  fi
fi

compile_hue() {
  mkdir -p $BUILD_DIR
  cd $HUE_SRC
  PREFIX=$BUILD_DIR make install
  cd $BUILD_DIR/hue
  APPS=$(find apps -maxdepth 2 -name "src" -type d|cut -d"/" -f2|sort| sed 's/[^ ]* */apps\/&/g')
  ./build/env/bin/python tools/app_reg/app_reg.py --install $APPS --relative-paths
  bash tools/relocatable.sh
}

find_git_state() {
  cd $HUE_SRC
  export GBRANCH=$(git ls-remote  --get-url)"/commits/"$(git rev-parse --abbrev-ref HEAD)
  export GSHA=$(git ls-remote  --get-url)"/commit/"$(git rev-list --no-walk HEAD)
  export VERSION=$(grep "VERSION=" VERSION | cut -d"=" -f2 | cut -d'"' -f2)
}

subst_var() {
  file_name=$1
  if [[ -e $file_name ]]; then
    if [[ "$file_name" == *"_template" ]]; then
      out_name="${file_name::-9}.conf"
    fi
  fi

  eval "cat <<EOF
$(<$file_name)
EOF
" | tee $out_name 2> /dev/null
}

docker_hue_build() {
  export HUE_USER="hive"
  export HUE_CONF="/etc/hue"
  export HUE_HOME="/opt/${HUEUSER}"
  export HUE_CONF_DIR="${HUE_CONF}/conf"
  export HUE_LOG_DIR="/var/log/${HUEUSER}"
  export UUID_GEN=$(uuidgen | cut -d"-" -f5)

  cd $HUE_DIR
  cp -a $BUILD_DIR/hue $HUE_DIR
  rm -f $HUE_DIR/hue/desktop/conf/*

  for f in $(find $HUE_DIR/supervisor-files -name "*_template"); do
    subst_var $f
  done

  sed -i -e "s#\${HUEBASE_VERSION}#${HUEBASE_VERSION}#g" $HUE_DIR/Dockerfile
  docker build -f $HUE_DIR/Dockerfile -t ${REGISTRY}/hue:$GBN \
    --build-arg GBN=$GBN \
    --build-arg GSHA="$GSHA" \
    --build-arg GBRANCH=$GBRANCH \
    --build-arg VERSION=$VERSION \
    --build-arg HUEUSER=$HUEUSER \
    --build-arg HUE_CONF=$HUE_CONF \
    .
}

docker_huelb_build() {
  export HUE_USER="hive"
  export HUE_CONF="/etc/hue"
  export HUE_HOME="/opt/${HUEUSER}"
  export HUE_CONF_DIR="${HUE_CONF}/conf"
  export HUE_LOG_DIR="/var/log/${HUEUSER}"

  cd $APACHE_DIR
  cp -a $BUILD_DIR/hue/build/static $APACHE_DIR

  for f in $(find $APACHE_DIR -name "*_template"); do
    subst_var $f
  done

  sed -i -e "s#\${HUELBBASE_VERSION}#${HUELBBASE_VERSION}#g" $APACHE_DIR/Dockerfile
  docker build -f $APACHE_DIR/Dockerfile -t ${REGISTRY}/huelb:$GBN \
    --build-arg GBN=$GBN \
    --build-arg GSHA="$GSHA" \
    --build-arg GBRANCH=$GBRANCH \
    --build-arg VERSION=$VERSION \
    --build-arg HUEUSER=$HUEUSER \
    --build-arg HUE_CONF=$HUE_CONF \
    .
}

build_huebase() {
  cd $BASEHUE_DIR
  docker build -f $BASEHUE_DIR/Dockerfile -t ${REGISTRY}/$HUEBASE_VERSION .
  docker tag ${REGISTRY}/$HUEBASE_VERSION $HUEBASE_VERSION
  docker push ${REGISTRY}/$HUEBASE_VERSION
  docker pull ${REGISTRY}/$HUEBASE_VERSION
}

build_huelbbase() {
  cd $BASEHUELB_DIR
  docker build -f $BASEHUELB_DIR/Dockerfile -t ${REGISTRY}/$HUELBBASE_VERSION .
  docker tag ${REGISTRY}/$HUELBBASE_VERSION $HUELBBASE_VERSION
  docker push ${REGISTRY}/$HUELBBASE_VERSION
  docker pull ${REGISTRY}/$HUELBBASE_VERSION
}

pull_hueos() {
  docker pull ${BASEOS_URL}

  FROMOS_URL=$(echo "$BASEOS_URL as base-centos-jdk")
  sed -i -e "s#\${BASEOS_URL}#${FROMOS_URL}#g" $BASEHUE_DIR/Dockerfile
}

pull_huelbos() {
  docker pull ${BASEOS_URL}

  FROMOS_URL=$(echo "$BASEOS_URL as base-centos-jdk")
  sed -i -e "s#\${BASEOS_URL}#${FROMOS_URL}#g" $BASEHUELB_DIR/Dockerfile
}

pull_base_images() {
  set +e

  docker pull ${REGISTRY}/$HUEBASE_VERSION
  if [[ $? != 0 ]]; then
    pull_hueos
    build_huebase
  fi
  docker tag ${REGISTRY}/$HUEBASE_VERSION $HUEBASE_VERSION

  docker pull ${REGISTRY}/$HUELBBASE_VERSION
  if [[ $? != 0 ]]; then
    pull_huelbos
    build_huelbbase
  fi
  docker tag ${REGISTRY}/$HUELBBASE_VERSION $HUELBBASE_VERSION
  set -e
}

compile_hue
find_git_state
pull_base_images
docker_hue_build
docker_huelb_build
