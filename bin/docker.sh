#!/bin/bash
#
# See ./build for usage
#

build_image() {
    rm -f Dockerfile
    cat > Dockerfile <<EOF
FROM $build_image_base
MAINTAINER "$build_maintainer"
ADD . $build_guest_conf
RUN "$build_run"
# Reasonable default for CMD so user doesn't have to specify
CMD /bin/bash
EOF
    local tag=$build_image_name:$build_version
    local latest=$build_image_name:latest
    docker build --rm=true --tag="$tag" .
    docker tag -f "$tag" "$latest"
    # Can't push multiple tags at once:
    # https://github.com/docker/docker/issues/7336
    cat <<EOF
Built: $build_image_name:$build_version
To push to the docker hub:
    docker push '$tag'
    docker push '$latest'
EOF
    cd /
    rm -rf "$build_dir"
}

build_image_clean() {
    if ! build_image_exists "$build_image_name"; then
        return 0
    fi
    local images=$build_image_exists
    local f=
    # Remove none running containers.
    for f in $(docker ps -a \
            | perl -n -e "m{^(\w+)\s.*\s\Q$build_image_name\E[\s:]} && print(qq{\$1\n})"); do
        docker rm "$f"
    done
    for f in $images; do
        docker rmi "$f" 2>/dev/null || true
    done
}

build_image_exists() {
    local img=$1
    build_image_exists=$(docker images -a | perl -ne "m{^${img/:/ +}\\b} && print((split)[2], qq{\\n})")
    [[ -n $build_image_exists ]]
}

build_init_type() {
    build_is_docker=1
    build_type=docker
}

build_root_setup() {
    export HOME=/root
    if [[ ! -f /.bashrc ]]; then
        cat > /.bashrc << 'EOF'
export HOME=/root
cd $HOME
. /root/.bash_profile
EOF
    fi
    if [[ ! -f /root/.bash_profile ]]; then
        cp -a /etc/skel/.??* /root
    fi
    if ! id -u $build_exec_user >& /dev/null; then
        groupadd -g 1000 $build_exec_user
        useradd -m -g $build_exec_user -u 1000 $build_exec_user
    fi
    local x=/etc/sudoers.d/$build_exec_user
    if [[ ! -f $x ]]; then
        build_yum install sudo
        echo "$build_exec_user ALL=(ALL) NOPASSWD: ALL" > "$x"
        chmod 440 "$x"
    fi
}