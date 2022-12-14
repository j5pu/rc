# shellcheck shell=bash

#######################################
# rc completion
# Arguments:
#   1
#   3
# Returns:
#   0 ...
#   1 ...
#######################################
_rc() {
  _init_completion -n :=/ || return

  test "${cword}" -lt 4 || return 0

  [[ ! "${words[1]}" =~ -h|--help|help|list|sync ]] || return 0

  case "$cword" in
    1) mapfile -t \
      COMPREPLY < <(compgen -o nospace -W "-h --help --force help $(rc list)" -- "${cur}") ;;
    2)
      case "${words[1]}" in
        --force) mapfile -t COMPREPLY < <(compgen -o nospace -W "hook install supported" -- "${cur}") ;;
        add)
          mapfile -t COMPREPLY < <(compgen -A command -- "${cur}")
          _filedir -d
          ;;
        del) mapfile -t COMPREPLY < <(compgen -A alias -- "${cur}") ;;
        hook|install|supported) mapfile -t COMPREPLY < <(compgen -o nospace -W "--force" -- "${cur}")
      esac
      ;;
    3)
      if [ "${words[1]}" = "add" ]; then
        mapfile -t COMPREPLY < <(compgen -o nospace -W "${RC_SUPPORTED}" -- "${cur}")
      fi
      ;;
  esac
}

complete -F _rc rc
