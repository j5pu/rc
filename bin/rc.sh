#!/bin/sh

#
# Generates .env.sh

set -eu

cd "$(dirname "$0")/.."

#
# Force creation of .env.sh
: "${RC_FORCE=0}"

: "${RC_TRACE=0}"; [ "${RC_TRACE}" -eq 0 ] || set -x


# TODO: Faltaría el SH y las variables de system.sh y probarlo un poco y los comandos de alias
# TODO: install
# TODO: simplificar
# TODO: test

add() {
  if test -d "${1:-.}"; then
    arguments="$(realpath -e "${1:-.}")"
    alias="${arguments##*/}"
    command="cd"
    file="dirs.sh"
    prefix="."
    supported="${2:-${HOSTNAME}}"
  else
    arguments="$1"
    alias="$1"
    command="sudo"
    file="sudo.sh"
    prefix=""
    supported="${2:-${UNAME}}"
  fi

  supported "${supported}"
  dest="${RC_GENERATED_RC_D}/${supported}/${file}"

  value="${command} ${arguments}"
  if aliases | grep -q "^${prefix}${alias}="; then
    existing="$(aliases | grep "^${prefix}${alias}=" | awk -F= '{ print $2 }')"
    if [ "'${value}'" = "${existing}" ]; then
      >&2 echo "Already exists: $(grep -R "alias ${prefix}${alias}=" "${RC_GENERATED_RC_D}" "${RC_ETC_ALIASES}")"
      exit 1
    else
      >&2 echo "Alias ${alias} already exists with value: ${existing}"
      >&2 printf "%s" "Do you want to use a different alias name or delete? [y/N/D] "
      read -r yes
      if [ "${yes}" = "y" ]; then
        >&2 printf "%s" "New alias name: "
        read -r alias
      elif [ "${yes}" = "D" ]; then
        del "${prefix}${alias}"
      else
        return 0
      fi

    fi
  fi
  tmp="$(mktemp)"
  line="alias ${prefix}${alias}=\"${value}\""
  { cat "${dest}"; echo "${line}"; } | sort -u > "${tmp}"
  mv "${tmp}" "${dest}"
  >&2 echo "${line} => ${dest}"
  sync "$*"
}

add_var() { RC_VARS="${RC_VARS:+${RC_VARS} }$1"; }

aliases() { env -i ENV="${_RC_FILE}" sh -li -c alias 2>/dev/null | sort -u; }

alias_exists() { grep -R -l "alias ${1}" "${RC_GENERATED_RC_D}"; }

clean() {
  tmp="$(mktemp)"
  set --
  for supported in 00-common "${HOSTNAME}" "${ID_LIKE}" "${UNAME}"; do
    file="${RC_GENERATED_RC_D}/${supported}/dirs.sh"
    test -f "${file}" || continue
    set -- "${file}" "$@"
  done

  find "$@" -type f -name dirs.sh -exec grep -EH "alias .*=" "{}" \; | sed 's|alias ||g; s|"cd ||g; s|"$||g' |
    while IFS=":=" read -r file alias value; do
      ! test -d "${value}" || continue
      del "${alias}"
    done
  sync clean
}

create_dirs_and_files() {
  for _gen_rc_dir in ${RC_SUPPORTED}; do
    find "${RC_GENERATED}" -mindepth 1 -maxdepth 1 -type d | while read -r _gen_rc_dir_generated; do
      _gen_rc_dir_generated_absolute="${_gen_rc_dir_generated}/${_gen_rc_dir}"
        case "${_gen_rc_dir}" in
          rhel|rhel_fedora)
            cd "${_gen_rc_dir_generated}"
            if [ "${_gen_rc_dir_generated##*/}" = rc.d ]; then
             ! test -e "${_gen_rc_dir}" || rm -r "${_gen_rc_dir}"
             ln -s fedora "${_gen_rc_dir}"
            else
             ! test -e "${_gen_rc_dir}.sh" || rm -r "${_gen_rc_dir}.sh"
             ln -s fedora.sh "${_gen_rc_dir}.sh"
            fi
            ;;
          *)
            if [ "${_gen_rc_dir_generated##*/}" = rc.d ]; then
              mkdir -p "${_gen_rc_dir_generated_absolute}"
              touch "${_gen_rc_dir_generated_absolute}/dirs.sh"
              touch "${_gen_rc_dir_generated_absolute}/sudo.sh"
            else
              touch "${_gen_rc_dir_generated_absolute}.sh"
            fi
            ;;
        esac
    done

    { find "${RC_ETC}" -mindepth 2 -maxdepth 2 -type d -not -path "${RC_ETC_FUNCTIONS}/*";
      echo "${RC_ETC_FUNCTIONS}"; } | while read -r _gen_rc_dir_etc; do
        _gen_rc_dir_etc_absolute="${_gen_rc_dir_etc}/${_gen_rc_dir}"
        case "${_gen_rc_dir}" in
          rhel|rhel_fedora)
            cd "${_gen_rc_dir_etc}"
            ! test -e "${_gen_rc_dir}" || rm -r "${_gen_rc_dir}"
            ln -s fedora "${_gen_rc_dir}"
            ;;
          *)
            mkdir -p "${_gen_rc_dir_etc_absolute}"
            if [ "${_gen_rc_dir_etc##*/}" = hooks.d ]; then
              for _gen_rc_dir_etc_shell in sh bash bash-4 zsh; do
                _gen_rc_dir_etc_absolute="${_gen_rc_dir_etc}/${_gen_rc_dir}/${_gen_rc_dir_etc_shell}"
                case "${_gen_rc_dir}" in
                  rhel|rhel_fedora) : ;;
                  *)
                    mkdir -p "${_gen_rc_dir_etc_absolute}"
                    touch "${_gen_rc_dir_etc_absolute}/.gitkeep"
                    ;;
                esac
              done
            else
              touch "${_gen_rc_dir_etc_absolute}/.gitkeep"
            fi
            ;;
        esac
    done
  done

  for _gen_rc_dir_home in completions profile.d rc.d; do
    _gen_rc_dir_home_absolute="${RC_CUSTOM}/${_gen_rc_dir_home}"
    if ! test -f "${_gen_rc_dir_home_absolute}/.gitkeep"; then
      mkdir -p "${_gen_rc_dir_home_absolute}"
      touch "${_gen_rc_dir_home_absolute}/.gitkeep"
    fi

    cd "${RC_COMPLETIONS}"
    find "../../bash_completion.d" -mindepth 1 -maxdepth 1 -type f -name "*.bash" | while read -r completion; do
      rm -f "${completion##*/}"
      ln -s "${completion}" "${completion##*/}"
    done

    dir="../../bash_completion.d/${UNAME}"
    if test -d "${dir}"; then
      find "${dir}" -mindepth 1 -maxdepth 1 -type f -name "*.bash" | while read -r completion; do
        rm -f "${completion##*/}"
        ln -s "${completion}" "${completion##*/}"
      done
    fi
  done
}

del() {
  tmp="$(mktemp)"
  found="$(grep -R "alias ${1}" "${RC_GENERATED_RC_D}" | while IFS=: read -r file line; do
    [ "${line-}" ] || continue
    grep -v "${line}" "${file}" > "${tmp}" 2>/dev/null || true
    mv -v "${tmp}" "${file}"
  done)"
  if [ "${found-}" ]; then
    >&2 echo "${1}: Alias deleted from: $(echo "${found}" | awk '{ print $3 }')"
  else
    if aliases | grep -q "^${1}="; then
      add="; however alias that can not be deleted found in: $(grep -R -l "alias ${1}=" "${RC_ETC}")"
    fi
    >&2 echo "${1}: Alias not found in: ${RC_GENERATED_RC_D}${add-}"
    return 1
  fi
  sync "del: $1"
 }

echo_rc_source_dir() { while read -r i; do echo "  ${1-}rc_source_dir \"${i}\""; done; }

echo_files_to_source() {
  find "$1" -type f \
    \( \
      -path "*/00-common/*" \
      -or -path "*/${HOSTNAME}/*" \
      -or -path "*/${ID_LIKE}/*" \
      -or -path "*/${UNAME}/*" \
      -or -name "00-common.*" \
      -or -name "${HOSTNAME}.*" \
      -or -name "${ID_LIKE}.*" \
      -or -name "${UNAME}.*" \
    \) \
    -exec echo "  ${2-}. \"{}\"" \; | sort -n
}

find_dirs_to_source() {
  find "$1" -mindepth "$2" -maxdepth "$2" -type d \
    \( \
      -path "*/00-common/*" \
      -or -path "*/${HOSTNAME}/*" \
      -or -path "*/${ID_LIKE}/*" \
      -or -path "*/${UNAME}/*" \
      -or -name "00-common" \
      -or -name "${HOSTNAME}" \
      -or -name "${ID_LIKE}" \
      -or -name "${UNAME}" \
    \) | sort -n
}

gnu_completions() {
  $MACOS || return 0

  brew_bin="$(brew --prefix)/bin"
  cmds="$(find "$(brew --prefix coreutils)/bin" "$(brew --prefix findutils)/bin" -type f -name "g*" \
    | sed -e 's|.*/bin/g||g' | grep -v "\[")"
  dest="$(brew --prefix bash-completion@2)/share/bash-completion/completions"

  cd "${dest}"

  bash -li -c '
  while read -r cmd; do
    if test -f "${cmd}"; then
      ! test -L "${cmd}" || continue
      value="$(awk "!/#/ && /complete/ {\$1=\$1;print}" "${cmd}")"
      new_value="$(echo "${value}" | sed "s| ${cmd}$| g${cmd}|g")"
      sed "s|${value}|${new_value}|" "${cmd}" > "g${cmd}"
    else
      value="$(complete -p ${cmd} 2>/dev/null | sed "s| ${cmd}$| g${cmd}|g")"
      [ ! "${value-}" ] || echo "${value}" > "g${cmd}"
    fi
  done < <(find "$(brew --prefix coreutils)/bin" "$(brew --prefix findutils)/bin" -type f -name "g*" \
    | sed -e "s|.*/bin/g||g" | grep -v "\[")
  '
}

#######################################
# show usage
# Arguments:
#   1
#######################################
help() {
  >&2 cat <<EOF
usage: ${0##*/}
   or: ${0##*/} [--force] [add|clean|del|hook|install|supported|sync] [option]
   or: ${0##*/} [-h|--help|help]
   or: ${0##*/} --force
   or: ${0##*/} add [directory|command] [<supported directories/OS/host]
   or: ${0##*/} add
   or: ${0##*/} add .
   or: ${0##*/} add . 00-common
   or: ${0##*/} clean
   or: ${0##*/} del <alias_name>
   or: ${0##*/} hook
   or: ${0##*/} hook --force
   or: ${0##*/} --force hook
   or: ${0##*/} install
   or: ${0##*/} install --force
   or: ${0##*/} --force install
   or: ${0##*/} sync
   or: ${0##*/} sync <message>

generates \$ENV file and manages rc repository, with no options creates the static \$ENV file ".${0}.sh"

Commands:
   -h, --help, help   display this help and exit.
   --force            force updating static \$ENV file ".${0}.sh" (valid with not commands, hook, install or supported)
   add                to add a new alias to rc generated directory "${RC_GENERATED_RC_D}":
                      - if argument is a directory ".basename" (default: cwd) will be
                        added to dirs.sh (default: "${HOSTNAME}" directory)
                      - it is added to sudo.sh if it is not a directory (default: "${UNAME}" directory).
   clean              to clean directory aliases which directory does not exist
   del                deletes an alias from rc generated directory "${RC_GENERATED_RC_D}"
   hook               shows the path to \$ENV file ".${0}.sh"
   list               show list of commands available and exit
   install            to install hooks into /etc/profile, ~/.profile, ~/.bashrc, ~/.bash_profile for user and root
   supported          show list of supported directories to add aliases "${RC_SUPPORTED}"
   sync               will push or pull repository based on status

Globals:
   RC_FORCE           to force updating static \$ENV file ".${0}.sh", similar to --force

EOF
  exit "${1:-1}"
}

hooks() { find_dirs_to_source "${1}" 3 | grep -E "/sh$|/${SH:-bash}$" | echo_rc_source_dir ""; }

hooks_no() { find_dirs_to_source "$1" 2 | grep -v "/hooks.d/" | echo_rc_source_dir; }

install() { :; }

write_compats() {
  cat >> "${_RC_TMP}" <<EOF

#
# Homebrew profile.d has been sourced already
: "\${HOMEBREW_PROFILE_D_SOURCED=0}"

if test -d "\${HOMEBREW_PREFIX}/etc/profile.d" && [ "\${HOMEBREW_PROFILE_D_SOURCED}" -eq 0 ]; then
  HOMEBREW_PROFILE_D_SOURCED=1
  rc_source_dir "\${HOMEBREW_PREFIX}/etc/profile.d"
fi
EOF
}

write_functions() {
  cat > "${_RC_TMP}" <<EOF
# shellcheck shell=sh

#
# System-wide POSIX profile
# Generated by $0

unset ENV

: "\${RC_TRACE=0}"; [ "\${RC_TRACE}" -eq 0 ] || set -x

if ! command -v resh >/dev/null; then
  . "${RC_ETC_FUNCTIONS}/${0##*/}.sh"

$(find_dirs_to_source "${RC_ETC_FUNCTIONS}" 1 | echo_rc_source_dir)
fi
EOF
}

write_profile() {
  cat >> "${_RC_TMP}" <<EOF

#
# RC: profile.d for interactive shells has been sourced already
: "\${RC_PROFILE_D_SOURCED=0}"; export RC_PROFILE_D_SOURCED

if [ "\${RC_PROFILE_D_SOURCED}" -eq 0 ]; then
  RC_PROFILE_D_SOURCED=1

$(for var in $(echo "${RC_VARS}" | tr ' ' '\n' | sort); do
  echo "  export ${var}=\"$(eval echo "\$${var}")\""
done)

  unset INFOPATH MANPATH
  if \$MACOS; then
    eval "\$(/usr/libexec/path_helper -s)"
    PATH="\${PATH}:\${CLT}/usr/bin"
  else
    PATH="/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  fi
  ! has brew || eval "\$(brew shellenv)"
  export PATH="${RC_TOP}/bin:\${PATH}"

  : "\${HOSTNAME=\$(hostname)}"; export HOSTNAME

$(hooks_no "${RC_ETC_PROFILE_D}")

$(hooks "${RC_ETC_PROFILE_D}")

$(echo_files_to_source "${RC_GENERATED_PROFILE_D}")

  rc_source_dir "${RC_CUSTOM_PROFILE_D}"
fi
EOF
}

write_rc() {
  cat >> "${_RC_TMP}" <<EOF

#
# RC: rc.d for interactive shells has been sourced already
: "\${RC_RC_D_SOURCED=0}"

if { [ "\${PS1-}" ] || echo "\$-" | grep -q i; } && [ "\${RC_RC_D_SOURCED}" -eq 0 ]; then
  RC_RC_D_SOURCED=1

  unalias cp egrep fgrep grep l l. la ll lld ls mv rm xzegrep xzfgrep xzgrep zegrep zfgrep zgrep 2>/dev/null

$(hooks_no "${RC_ETC_RC_D}")

$(hooks "${RC_ETC_RC_D}")

$(echo_files_to_source "${RC_ETC_ALIASES}")

$(echo_files_to_source "${RC_GENERATED_RC_D}" | grep "/dirs.sh\"$")

  if [ "\${SUDO-}" ]; then
$(echo_files_to_source "${RC_GENERATED_RC_D}" "  " | grep "/sudo.sh\"$")
  fi

  rc_source_dir "${RC_CUSTOM_RC_D}"
fi

export ENV="${_RC_FILE}"

[ "\${RC_TRACE}" -eq 0 ] || set +x
EOF
}

set_vars() {
  RC_TOP="$(pwd -P)" && add_var RC_TOP
  PATH="${RC_TOP}/bin:${PATH}"

  HOSTNAME="${HOSTNAME=$(hostname)}"
  ID_LIKE="$(! test -f /etc/os-release || grep "^ID_LIKE=" /etc/os-release \
      || grep "^ID=" /etc/os-release | cut -d= -f2 | tr ' ' '_')" && add_var ID_LIKE
  MACOS="$(if test "$(uname -s)" = "Darwin"; then echo true; else echo false; fi)" && add_var MACOS
  SUDO="$(if test -x /usr/bin/sudo; then echo /usr/bin/sudo; else echo ""; fi)" && add_var SUDO
  UNAME="$(uname -s)" && add_var UNAME

  HOSTNAME_UPPER="$(echo "${HOSTNAME}" | tr '[:lower:]' '[:upper:]')"
echo "$HOSTNAME_UPPER"
  VGA=1 && add_var VGA
  if $MACOS; then
    CLT="/Library/Developer/CommandLineTools" && add_var CLT
    eval "${HOSTNAME_UPPER}_IP=\$(ipconfig getifaddr en0 || ipconfig getifaddr en2)" && add_var "${HOSTNAME_UPPER}_IP"
  else
    eval "${HOSTNAME_UPPER}_IP=\$(hostname -I | awk '{ print \$1 }')" && add_var "${HOSTNAME_UPPER}_IP"
    lspci 2>/dev/null | grep -q VGA || VGA=""
  fi
  [ ! "${GITHUB_RUN_ID-}" ] || VGA=""
  HOSTS="book imac mini1 mini512 msi pro"
  _RC_FILE="${RC_TOP}/.${0##*/}.sh"
  _RC_TMP="$(mktemp)"
  RC_CUSTOM="${RC_TOP}/custom" && add_var RC_CUSTOM
  RC_CUSTOM_PROFILE_D="${RC_CUSTOM}/profile.d" && add_var RC_CUSTOM_PROFILE_D
  RC_CUSTOM_RC_D="${RC_CUSTOM}/rc.d" && add_var RC_CUSTOM_RC_D
  RC_ETC="${RC_TOP}/etc" && add_var RC_ETC
  RC_ETC_ALIASES="${RC_ETC}/aliases.d" && add_var RC_ETC_ALIASES
  RC_ETC_FUNCTIONS="${RC_ETC}/functions.d" && add_var RC_ETC_FUNCTIONS
  RC_ETC_PROFILE_D="${RC_ETC}/profile.d" && add_var RC_ETC_PROFILE_D
  RC_ETC_RC_D="${RC_ETC}/rc.d" && add_var RC_ETC_RC_D
  RC_GENERATED="${RC_TOP}/generated" && add_var RC_GENERATED
  RC_GENERATED_PROFILE_D="${RC_GENERATED}/profile.d" && add_var RC_GENERATED_PROFILE_D
  RC_GENERATED_RC_D="${RC_GENERATED}/rc.d" && add_var RC_GENERATED_RC_D
  RC_SEARCH="00-common ${HOSTNAME}${ID_LIKE:+ ${ID_LIKE}} ${UNAME}"; add_var RC_SEARCH
  RC_SUPPORTED="00-common arch Darwin debian fedora Linux rhel rhel_fedora ${HOSTNAME}" && add_var RC_SUPPORTED

  # Adds dinamically completions with __load_completion()/_completion_loader
  # /completions is added by __load_completions(
  BASH_COMPLETION_USER_DIR="${RC_CUSTOM}" && add_var BASH_COMPLETION_USER_DIR
  RC_COMPLETIONS="${RC_CUSTOM}/completions" && add_var RC_COMPLETIONS
}

sync() {
  if git status  | grep -q "have diverged"; then
    >&2 echo "${0##*/}: Diverged"
    exit 1
  elif git status | grep -q "Your branch is behind" && test -n "$(git status --porcelain)"; then
    >&2 echo "${0##*/}: Behind remote & directory is not clean"
    exit 1
  elif git status | grep -q "Your branch is behind"; then
    git pull --quiet --tags
    exit 0
  elif test -n "$(git status --porcelain)"; then
    git add -A
    git commit --quiet -a -m "${0##*/}${1:+: ${*}}"
  fi

  ! git status | grep -q "Your branch is ahead" || git push --quiet
}

supported() { 
  echo "${RC_SUPPORTED}" | tr " " "\n" | grep -q "^${1}\$" || { >&2 echo "${0##*/}: Unsupported: ${1}"; exit 1; }
}

main() {
  [ "${ENV-}" ] || set_vars

  action=false; hook=false; supported=false
  for arg; do
    case "${arg}" in
      -h|--help|help) help 0;;
      --force) RC_FORCE=1; shift  ;;
      add|aliases|clean|del|install|sync)
        if ! $action; then
          function="${arg}"; action=true; shift
        fi
        ;;
      list) printf "%s\n" add clean del hook install "${arg}" supported sync; exit ;;
      supported) supported=true; shift ;;
      hook) hook=true; shift ;;
      -*)
        >&2 echo "${0##*/}: Unknown argument: ${arg}"
        >&2 echo
        >&2 help
        ;;
    esac
  done

  [ "${RC_FORCE}" -eq 0 ] || [ "${function-}" != "install" ] || [ "${function-}" ]|| \
    { >&2 echo "${0##*/}: --force can not be used with ${function}"; exit 1; }

  if ! test -f "${ENV:-${_RC_FILE}}" || [ "${RC_FORCE}" -eq 1 ]; then
    [ "${_RC_FILE-}" ] || set_vars
    # shellcheck disable=SC2010
    ls -la "${_RC_FILE}" | \
      grep -q " ${USER} " || >&2 echo "${0##*/}: ${_RC_FILE} is not owned by: ${USER}"

    create_dirs_and_files

    write_functions
    write_profile
    write_compats
    write_rc


    mv "${_RC_TMP}" "${_RC_FILE}"
    sync "$@"

    gnu_completions
  fi

  if $hook; then
    echo "${ENV:-${_RC_FILE}}"
  elif $supported; then
    echo "${RC_SUPPORTED}"
  elif [ "${function-}" ]; then
    "${function}" "$@"
  fi

}

main "$@"