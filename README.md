# docker_registry_command_line

dependens:
  - jq

Install
Ubuntu:
  apt-get install jq

usage: registry.sh [-c|--catalog|-l|--list|-d|--delete] ['images'] ['tags']
    -c --catalog:    list of repositories
    -l --list     list of repositories and tags
    -d --delete     list of repositories and tags
