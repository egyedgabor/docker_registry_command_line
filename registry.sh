#!/bin/bash
set -e

uname=$(cat .env | grep "DOCKER_REGISTRY_USER" \
        | tr "=" " " | awk '{print $2}')
pass=$(cat .env | grep "DOCKER_REGISTRY_PASSWORD" \
        | tr "=" " " | awk '{print $2}')
registry=$(cat .env | grep "DOCKER_REGISTRY_URL" \
        | tr "=" " " | awk '{print $2}')
days=$(cat .env | grep "ROTATE_DAYS" \
        | tr "=" " " | awk '{print $2}')
secret=$uname:$pass
header='Accept: application/vnd.docker.distribution.manifest.v2+json'

catalog=$(curl -s -k -u $secret -X GET "$registry/v2/_catalog" \
  | jq -r ' .repositories | join ("\n")')


case "$1" in
  -c|--catalog)
    if [ "$2" != "" ]; then
      echo "ERROR: catalog no extra parameters"
      exit 1
    fi
    for image in $catalog
    do
      echo $image
    done
  ;;
  -l|--list)
    if [ "$2" != "" ]; then
      catalog="$2"
    fi
    for image in ${catalog}
    do
      echo "$image"

      tag_list=$(curl -s -k -u $secret -X GET "$registry/v2/$image/tags/list" \
        | jq -r 'select(.tags != null) | .tags | join ("\n")' | sort)

      error=$(echo $tag_list | grep NAME_UNKNOWN | wc -l)

      if [ "$2" != "" ] && [ "$error" != 0 ]; then
        echo "Image is not exists"
        exit 1
      else
        for tag in $tag_list
        do
        manifest=$(curl -l -s -k -u $secret \
          -H "$header" -I "$registry/v2/$image/manifests/$tag" 2>/dev/null \
          | grep "Docker-Content-Digest" | awk '{ print $2 }' | tr "\r" " ")
          echo "$manifest $tag"
        done
        echo ""
      fi
    done
    ;;
  -d|--delete)
  if [ "$2" = "" ]; then
    echo "ERROR: specify the images"
    exit 1
  else
    images="$2"
  fi
  if [ "$3" = "" ]; then
    echo "ERROR: specify the tags"
    exit 1
  else
    tags="$3"
  fi
  for image in $images
  do
    tag_list=$(curl -k -s -u $secret -X GET "$registry/v2/$image/tags/list" \
      | tr "," "\n" | sed 's/[\(,"}]//g' | sed 's/]//g' | tr "[" "\n" | grep -v 'name\|tags')
    error=$(echo $tag_list | grep NAME_UNKNOWN | wc -l)
    if [ "$2" != "" ] && [ "$error" != 0 ]; then
      echo "Image is not exists"
      exit 1
    else
      echo $image
      list=()
      for tag in $tag_list
      do
      manifest=$(curl -l -k -v -u $secret \
        -H "$header" -I "$registry/v2/$image/manifests/$tag" 2>/dev/null \
        | grep "Docker-Content-Digest" | awk '{ print $2 }' | tr "\r" " ")
      list+=("${tag} ${manifest}")
      done
    fi
    for tag in $tags
    do
      manifest=$(curl -l -k -v -u $secret \
        -H "$header" -I "$registry/v2/$image/manifests/$tag" 2>/dev/null \
        | grep "Docker-Content-Digest" | awk '{ print $2 }')
      check_manifest=${manifest%$'\r'}
      check=$(echo "${list[@]}" | sed 's/ sha256/,sha256/g' | tr ' ' '\n' \
      | tr ',' ' ' | grep  $check_manifest | awk '{print $1}')
      check_number=$(echo "$check" |  wc -l)
      if  [ "$check_number" != "1" ]; then
        promptyn () {
            while true; do
                read -p "$1 " yn
                case $yn in
                    [Yy]* ) return 0;;
                    [Nn]* ) return 1;;
                    * ) echo "Please answer yes or no.";;
                esac
            done
        }
        if promptyn "Do you want to delete this repositories?"$'\n\n'"$check"$'\n'"(Yy/Nn)?"; then
            echo "delete process running"
        else
            echo "exit"
            exit 1
        fi
      fi
      URL=$registry/v2/$image/manifests/$manifest
      URL=${URL%$'\r'}
      echo $URL
      curl -k -u $secret -X DELETE $URL 2>/dev/null
      echo $image
      echo "$tag deleted"
    done
  done
  ;;
  -curator|--curator)
  if [ "$2" != "" ]; then
    catalog="$2"
  fi
  for image in ${catalog}
  do
    DATE1=$(date +%Y-%m-%d)
    DAYS=$(echo $(( $days*86400 )))
    tag_list=$(curl -s -k -u $secret -X GET "$registry/v2/$image/tags/list" \
        | jq -r 'select(.tags != null) | .tags | join ("\n")' | sort)
    list=()
    latest=$(curl -l -k -v -u $secret \
      -H "$header" -I "$registry/v2/$image/manifests/latest" 2>/dev/null \
      | grep "Docker-Content-Digest" | awk '{ print $2 }')
    for tag in $tag_list
    do
      manifest=$(curl -l -k -v -u $secret \
        -H "$header" -I "$registry/v2/$image/manifests/$tag" 2>/dev/null \
        | grep "Docker-Content-Digest" | awk '{ print $2 }' | tr "\r" " ")
      list+=("${tag} ${manifest}")
    done
    for tag in $tag_list
    do
      LIST1=$(echo $DATE1 | tr '-' '\n')
      readarray -t lines < <(echo "$LIST1")
      DATE1=$(echo "${lines[0]}-${lines[1]}-${lines[2]}")

      DATE2="$tag"
      if [ "$DATE2" != "latest" ]; then
        LIST2=$(echo $DATE2 | tr '-' '\n')
        readarray -t lines < <(echo "$LIST2")
        DATE2=$(echo "${lines[0]}-${lines[1]}-${lines[2]}")

        DIFF=$(echo $(( ( $(date -ud $DATE1 +'%s') - $(date -ud $DATE2 +'%s') ) )))
        DIFF=$(echo $(( $DIFF )))
        echo $DATE2
        if [ $DIFF -gt $DAYS ]; then
          manifest=$(curl -l -k -v -u $secret \
            -H "$header" -I "$registry/v2/$image/manifests/$tag" 2>/dev/null \
            | grep "Docker-Content-Digest" | awk '{ print $2 }')
          check=$(echo "$manifest" | grep "$latest" | wc -l)
          if [ $check != 1 ]; then
            URL=$registry/v2/$image/manifests/$manifest
            URL=${URL%$'\r'}
            curl -k -u $secret -X DELETE $URL 2>/dev/null
            echo "$tag deleted"
          fi
        fi
      fi
    done
  done
  ;;
  *)
    echo "usage: registry.sh [-c|--catalog|-l|--list|-d|--delete] \
    ['images'] ['tags']" >&2
    echo "    -c --catalog:    list of repositories" >&2
    echo "    -l --list     list of repositories and tags" >&2
    echo "    -d --delete     list of repositories and tags" >&2
    echo "    -curator        delete x days older image" >&2
    exit 1
    ;;
esac
