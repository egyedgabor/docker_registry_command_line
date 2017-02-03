#!/bin/bash
uname=$(cat .secret | grep "DOCKER_REGISTRY_USER" \
        | tr "=" " " | awk '{print $2}')
pass=$(cat .secret | grep "DOCKER_REGISTRY_PASSWORD" \
        | tr "=" " " | awk '{print $2}')
registry=$(cat .secret | grep "DOCKER_REGISTRY_PASSWORD" \
        | tr "=" " " | awk '{print $2}')
secret=$uname:$pass

catalog=$(curl -s -u $secret -X GET "$registry/v2/_catalog" \
| tr ",[,],}" "\n" | sed 's/"//g' | grep -v repositories | tr "\n" " ")

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
    for image in $catalog
    do
      tag_list=$(curl -s -u $secret -X GET "$registry/v2/$image/tags/list" \
        | tr "," "\n" | sed 's/[\(,"}]//g' | sed 's/]//g' | tr "[" "\n" | grep -v 'name\|tags')
      error="$tag_list | grep NAME_UNKNOWN | wc -l"
      if [ "$2" != "" ] && [ "$error" != "0" ]; then
        echo "Image is not exists"
        exit 1
      else
        echo $image
        for tag in $tag_list
        do
        manifest=$(curl -l -k -v -u $secret \
          -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -I \
          "$registry/v2/$image/manifests/$tag" 2>/dev/null \
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
    for tag in $tags
    do
      manifest=$(curl -l -k -v -u $secret \
        -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -I \
        "$registry/v2/$image/manifests/$tag" 2>/dev/null \
        | grep "Docker-Content-Digest" | awk '{ print $2 }')
      if [ "$manifest" = "" ]; then
        echo "invalid tag or image"
        exit
      else
        tag_list=$(curl -s -u $secret -X GET "$registry/v2/$image/tags/list" \
          | tr "," "\n" | sed 's/[\(,"}]//g' | sed 's/]//g' | tr "[" "\n" | grep -v 'name\|tags')
        error="$tag_list | grep NAME_UNKNOWN | wc -l"
        if [ "$2" != "" ] && [ "$error" != "0" ]; then
          echo "Image is not exists"
          exit 1
        else
          for tag in $tag_list
          do
          manifest=$(curl -l -k -v -u $secret \
            -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' -I \
            "$registry/v2/$image/manifests/$tag" 2>/dev/null \
            | grep "Docker-Content-Digest" | awk '{ print $2 }' | tr "\r" " ")
            echo "$manifest $tag |  grep $manifest |  awk '{ print $2 }'"
          done
          echo ""
          exit 1
        fi
      fi
      URL=$registry/v2/$image/manifests/$manifest
      URL=${URL%$'\r'}
      curl -u $secret -X DELETE $URL 2>/dev/null
      echo $image
      echo "$tag deleted"
    done
  done
  ;;
  *)
    echo "usage: registry.sh [-c|--catalog|-l|--list|-d|--delete] \
    ['images'] ['tags']" >&2
    echo "    -c --catalog:    list of repositories" >&2
    echo "    -l --list     list of repositories and tags" >&2
    echo "    -d --delete     list of repositories and tags" >&2
    exit 1
    ;;
esac
