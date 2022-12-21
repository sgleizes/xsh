#
# xsh: A simple framework for shell configuration management.
#
# This file defines the core functions of xsh and tries to be posixly correct.
# It is meant to be sourced by the startup files of each shell (~/.profile,
# ~/.bash_profile, ~/.zprofile, ...) to abstract away the subtleties/bashisms
# and provide a coherent and uniform configuration interface.
#
# Known limitations:
# - Command arguments containing spaces, tabs or newlines are split in separate arguments.
#
# - The module names must not contain ' ', ':' or ';' characters.
#
# - Benchmarking uses the 'date +%N' command (except for zsh), which is not supported by
#   all implementations of 'date' and also incurs a significant performance impact due to
#   the outer process and command substitution, which is a shame when it comes to benchmarking...
#
# - The use of 'local' is not strictly POSIX-compatible. However, it is widely supported even by
#   the most primitive POSIX-compliant shells (dash, ash and some ksh implementations). Since xsh
#   will probably be of little interest to the people using shells even more primitive than this,
#   support for these shells will probably never be added.
#   See https://stackoverflow.com/a/18600920/3469781.
#
#   It should be noted that there are differences between the implementations, e.g. local variables
#   in 'dash' and 'ash' inherit their value in the parent scope by default. To enforce truly
#   distinct variables the form `local var=` is used to preserve compatibility with these shells.
#

# shellcheck shell=sh disable=SC1090 disable=SC1007 disable=SC3043
XSH_VERSION='0.4.1'

# Figure out the name of the current shell.
XSHELL="${ZSH_NAME:-${0##*/}}"
XSHELL="${XSHELL#-}" # remove leading '-' for login shells

# Set default values for exportable global options.
# This should not be set at the local xsh scope as it would shadow the exported
# global value, if any. This would prevent processes started from xsh units to
# properly inherit the global value.
XSH_DIR="${XSH_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/xsh}"
XSH_CONFIG_DIR="${XSH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/shell}"
XSH_RUNCOM_PREFIX="${XSH_RUNCOM_PREFIX:-@}"

# A simple framework for shell configuration management.
#
# Usage: xsh [options...] <command> [args...]
# Commands:
#   bootstrap                      Bootstrap xsh for the current or specified shells.
#   create <module> [runcoms]      Create new module runcoms.
#   help [command]                 Display help information.
#   init                           Source the xsh init file for the current shell.
#   list                           List registered modules.
#   load <module> [runcom]         Source a module runcom.
#   module <module> [runcoms] ...  Register modules for automatic loading.
#   runcom [runcom]                Source a runcom of each registered module.
# Try 'xsh help [command]' for more information about a specific command.
# Options:
#   -h, --help             Display help information for xsh or the current command.
#   -s, --shells <shells>  Set XSH_SHELLS, see below.
#   -b, --benchmark        Set XSH_BENCHMARK, see below.
#   -v, --verbose          Set XSH_VERBOSE, see below.
# Globals:
#   XSH_DIR            Base xsh repository directory (default: ~/.config/xsh).
#   XSH_CONFIG_DIR     Base xsh configuration directory (default: ~/.config/shell).
#   XSH_RUNCOM_PREFIX  Prefix for module runcom files (default: @).
#   XSH_SHELLS         Colon-separated list of shell candidates to lookup for units.
#   XSH_BENCHMARK      Enable benchmarking the loading time of runcoms and units.
#   XSH_VERBOSE        Enable logging the loaded units. If XSH_BENCHMARK is also set,
#                      the loading time for each unit is printed.
xsh() {
  # Restrict changes of unexportable global options to local scope.
  local XSH_SHELLS="${XSH_SHELLS:-$XSHELL}"
  local XSH_BENCHMARK="${XSH_BENCHMARK}"
  local XSH_VERBOSE="${XSH_VERBOSE}"
  # Internal local parameters.
  # NOTE: Variables in this scope are exposed to sourced units and are prefixed
  # with '_' to avoid potential conflicts.
  local _XSH_COMMAND=
  local _XSH_LOAD_UNITS=
  local _err=0 _oldifs= _begin= _elapsed=

  # Replace 'sh' by 'posix' if it is the current shell.
  # This is not done post option processing since AFAIK it would require
  # to use both sed and command substitution, which would have a significant
  # performance impact. User-supplied values must use 'posix' instead of 'sh'.
  [ "$XSH_SHELLS" = 'sh' ] && XSH_SHELLS='posix'

  # Save IFS value and prevent it from propagating to sourced units.
  _oldifs="$IFS"; ${IFS+':'} unset _oldifs
  unset IFS

  # Enter the "real" posix zone.
  # In the scope of the current function, zsh emulation is not active so
  # we must make sure that the code executed here is compliant with the POSIX
  # specification and zsh's default options.
  _xsh_run "$@" || _err=1

  # Begin runcom benchmark.
  if [ "$XSH_BENCHMARK" ] && [ "$_XSH_COMMAND" = 'runcom' ]; then
    # shellcheck disable=SC3044
    [ "$ZSH_NAME" ] && typeset -F SECONDS=0 || _begin=$(_xsh_time)
  fi

  # Source all units marked for loading during xsh execution.
  # This is done separately to avoid propagating the posix emulation to the
  # sourced units, which can be written in any shell dialect.
  eval "$_XSH_LOAD_UNITS" || _err=1

  # End runcom benchmark.
  if [ "$XSH_BENCHMARK" ] && [ "$_XSH_COMMAND" = 'runcom' ]; then
    # shellcheck disable=SC3028
    [ "$ZSH_NAME" ] \
      && _elapsed="${$(( SECONDS * 1000 ))%.*}" \
      || _elapsed=$(( $(_xsh_time) - _begin ))
    _xsh_log "$_XSH_RUNCOM runcom [${_elapsed}ms]"
  fi

  # Restore original IFS value.
  IFS="$_oldifs"; ${_oldifs+':'} unset IFS

  # Set the root _XSH_LEVEL after the init unit has been sourced to log it at runcom level.
  [ "$_XSH_COMMAND" = 'init' ] && _XSH_LEVEL='+'
  return $_err
}

# Internal xsh entrypoint, scope of posix emulation for zsh.
_xsh_run() {
  # Enter zsh posix compatibility mode, mainly for field splitting.
  [ "$ZSH_NAME" ] && emulate -L sh

  local args=
  while [ $# -gt 0 ]; do
    case "$1" in
    -h|--help)
      _xsh_help "$_XSH_COMMAND"
      return
      ;;
    -s|--shells)
      if [ ! "$2" ]; then
        _xsh_error "missing argument for option '$1'" ''
        return 1
      fi
      XSH_SHELLS="$2"
      shift
      ;;
    -b|--benchmark)
      XSH_BENCHMARK=1
      ;;
    -v|--verbose)
      XSH_VERBOSE=1
      ;;
    *)
      [ ! "$_XSH_COMMAND" ] \
        && _XSH_COMMAND="$1" \
        || args="${args:+$args }$1"
      ;;
    esac
    shift
  done

  # Show help if no command is provided.
  if [ ! "$_XSH_COMMAND" ]; then
    _xsh_help
    return 1
  fi

  case "$_XSH_COMMAND" in
    bootstrap|create|help|init|list|load|module|runcom) eval "_xsh_$_XSH_COMMAND $args" ;;
    *) _xsh_error "invalid command '$_XSH_COMMAND'" '' ;;
  esac
}

#
# Frontend commands
#

# Bootstrap xsh for the current or specified shells.
# Effectively creates symbolic links in $HOME for the runcom files specific to each shell.
#
# Usage: xsh bootstrap
# Globals:
#   XSH_SHELLS  Used as the list of shells to bootstrap.
_xsh_bootstrap() {
  local err=0 sh= rcsh= rc= rcpath=

  # Assign the shells as positional parameters.
  # shellcheck disable=SC2086
  {
    IFS=:
    set -o noglob
    set -- $XSH_SHELLS
    set +o noglob
    unset IFS
  }

  for sh in "$@"; do
    rcsh="$sh"

    # If the shell directory doesn't exist, create it.
    if [ ! -d "$XSH_CONFIG_DIR/$sh" ]; then
      _xsh_log "[$sh] creating directory: $XSH_CONFIG_DIR/$sh"
      command mkdir -p "$XSH_CONFIG_DIR/$sh" || { err=1; continue; }
    fi
    # Fallback to posix runcoms.
    [ ! -d "$XSH_DIR/runcom/$sh" ] && rcsh='posix'

    # Link shell runcoms to the user's home directory.
    _xsh_log "[$sh] linking shell runcoms"
    for rc in "$XSH_DIR/runcom/$rcsh"/*; do
      if [ "$rc" = "$XSH_DIR/runcom/$rcsh/*" ]; then
        _xsh_error "no runcoms found for shell '$rcsh'" -
        continue 2
      fi

      [ "$sh" = 'zsh' ] && rcpath="${ZDOTDIR:-$HOME}" || rcpath="$HOME"
      if [ "$(readlink "$rcpath/.${rc##*/}")" != "$rc" ]; then
        _xsh_link "$rc" "$rcpath/.${rc##*/}" || err=1
      fi
    done

    # Create a default init file and module for the shell, if needed.
    _xsh_bootstrap_init_file "$sh" || err=1
    _xsh_bootstrap_module "$sh" || err=1
  done
  return $err
}

# Create new module runcoms for the current or specified shells.
# Typical values for the runcoms argument are: env, login, interactive, logout.
# Multiple values can be specified separated by colons (e.g. env:login).
# By default the module is registered for the interactive runcom.
#
# Usage: xsh create <module> [runcoms]
# Arguments:
#   module   The name of the module to create.
#   runcoms  A colon-separated list of runcoms to create for the module.
# Globals:
#   XSH_SHELLS  Used as the list of shells for which to create the modules.
_xsh_create() {
  local mod="$1"
  local rcs="$2"
  [ ! "$rcs" ] && rcs='interactive'

  if [ ! "$mod" ]; then
    _xsh_error "missing required name"
    return 1
  fi

  # Assign the shells as positional parameters.
  # shellcheck disable=SC2086
  {
    IFS=:
    set -o noglob
    set -- $XSH_SHELLS
    set +o noglob
    unset IFS
  }

  for sh in "$@"; do
    _xsh_create_module "$sh" "$mod" "$rcs"
  done
}

# Display help information for xsh or a given command.
#
# Usage: xsh help [command]
# Arguments:
#   command  The xsh command to get help for.
# Globals:
#   XSH_DIR  Used as the base xsh directory to extract documentation.
_xsh_help() {
  local func='xsh'
  [ "$1" ] && func="_xsh_$1"

  # Sed script that extracts and formats the documentation of a shell function.
  local prog='
    # On function line, format and print hold space.
    /^'$func'\(\)/ {
      g
      s/(^|\n)# ?/\1/g
      s/([^\n])(\n\w+:)/\1\n\2/g
      p;q
    }
    # While the function is not found, append to hold space.
    H
    # On empty line, advance to next line and clear hold space.
    /^$/ {
      n;h
    }
  '

  [ "$func" = 'xsh' ] && echo "xsh $XSH_VERSION"
  sed -En "$prog" "$XSH_DIR/xsh.sh"
}

# Source the xsh init file for the current shell.
# If that is not found, source the init file for posix shells.
#
# Usage: xsh init
# Globals:
#   XSH_SHELLS  Used as the list of shell candidates to lookup for the xsh init file.
_xsh_init() {
  local sh="$XSH_SHELLS"

  # Reset the internal global state.
  # This is done here to lead the user into using a single init file for each shell,
  # using XSH_SHELLS to specify fallbacks explicitly and with more granularity.
  _XSH_MODULES=''
  _XSH_RUNCOM=''
  _XSH_LEVEL=''

  _xsh_load_units 'init' || {
    # Override XSH_SHELLS in the outer scope so that 'posix' is used as the default shell
    # even in the context of the init file.
    [ "$XSHELL" != 'sh' ] && [ "$XSH_SHELLS" = "$XSHELL" ] \
      && XSH_SHELLS='posix' && _xsh_load_units 'init'
  } || {
    _xsh_error "no configuration found for '$sh'" -
    return 1
  }
}

# List the registered modules for the current shell.
#
# Usage: xsh list
_xsh_list() {
  echo "MODULE;SHELLS;RUNCOMS ${_XSH_MODULES}" | tr ' ' '\n' | column -s ';' -t
  return 0
}

# Load a runcom of a module in the current shell.
# The runcom argument, if any, is typically one of: env, login, interactive, logout.
# By default the current runcom is used, or 'interactive' if that is not set.
#
# Usage: xsh load <module> [runcom]
# Arguments:
#   module  The name of the module to load.
#   runcom  The runcom to load for the given module.
# Globals:
#   XSH_CONFIG_DIR     Used as the base directory to find the module.
#   XSH_RUNCOM_PREFIX  Used as the prefix for module runcom files.
#   XSH_SHELLS         Used as the list of shell candidates to lookup for the module.
_xsh_load() {
  local mod="$1"
  local rc="${2:-${_XSH_RUNCOM:-interactive}}"

  if [ ! "$mod" ]; then
    _xsh_list
    return 1
  fi

  _xsh_load_units "$XSH_RUNCOM_PREFIX$rc" "$mod" || {
    _xsh_error "failed to load runcom '$rc' of module '$mod' for '$XSH_SHELLS'"
    return 1
  }
}

# Register module(s) to be loaded by the current shell.
# Typical values for the runcoms argument are: env, login, interactive, logout.
# Multiple values can be specified separated by colons (e.g. env:login).
# By default or with the special value '-', the module is registered for all runcoms.
# Multiple modules can be specified, in which case the runcom argument is required
# between each module name (use '-' to keep the default behavior).
#
# Usage: xsh module <module> [runcoms] ...
# Arguments:
#   module   The name of the module to register.
#   runcoms  A colon-separated list of runcoms provided by the module.
# Globals:
#   XSH_SHELLS  Used as the list of shell candidates to lookup for the module.
_xsh_module() {
  local mod="$1"
  local rcs="$2"
  { [ ! "$rcs" ] || [ "$rcs" = '-' ]; } && rcs='env:login:interactive:logout'

  if [ ! "$mod" ]; then
    _xsh_error "missing required name"
    return 1
  fi

  _XSH_MODULES="${_XSH_MODULES:+$_XSH_MODULES }$mod;$XSH_SHELLS;$rcs"
  if [ $# -le 2 ]; then
    return 0
  fi

  shift 2 && _xsh_module "$@"
}

# Load the given runcom of each registered module.
# The runcom argument, if any, is typically one of: env, login, interactive, logout.
# By default the current runcom is used, or 'interactive' if that is not set.
#
# Usage: xsh runcom [runcom]
# Arguments:
#   runcom  The name of the runcom to load.
# Globals:
#   XSH_CONFIG_DIR  Used as the base directory to find units.
_xsh_runcom() {
  _XSH_RUNCOM="${1:-${_XSH_RUNCOM:-interactive}}"

  _xsh_load_registered
}

#
# Backend functions
#

# Load all registered units for the current runcom in the current shell.
# The units are only loaded if they are registered for the current runcom.
#
# Usage: _xsh_load_registered
# Globals:
#   XSH_CONFIG_DIR     Used as the base directory to find units.
#   XSH_RUNCOM_PREFIX  Used as the prefix for module runcom files.
_xsh_load_registered() {
  local mod= rcs=

  # Assign the units as positional parameters.
  # shellcheck disable=SC2086
  {
    set -o noglob
    set -- $_XSH_MODULES
    set +o noglob
  }

  # Load units that are registered for the current runcom.
  for mod in "$@"; do
    rcs="${mod##*;}"
    case $rcs in (*"$_XSH_RUNCOM"*)
      mod="${mod%;*}"         # remove runcoms from list entry
      XSH_SHELLS="${mod#*;}"  # extract shells from list entry
      mod="${mod%;*}"         # extract name from list entry

      _xsh_load_units "$XSH_RUNCOM_PREFIX$_XSH_RUNCOM" "$mod"
    esac
  done
  return 0
}

# Find and mark units for loading in the current shell.
# Arguments are shell-agnostic so that units can be searched in multiple shells.
#
# Usage: _xsh_load_units <name> <path>
# Arguments:
#   name  The filename suffix of the unit(s) to load, without extension.
#   path  The optional path to the unit(s) to load, relative to shell directories.
# Globals:
#   XSH_CONFIG_DIR  Used as the base directory to find units.
#   XSH_SHELLS      Used as the list of shell candidates to lookup for units.
_xsh_load_units() {
  local name="$1"
  local path="${2+${2%/}/}"  # ensure path ends with a /, if specified
  local sh= ext= unit= found=

  # Assign the shells as positional parameters.
  # shellcheck disable=SC2086
  {
    IFS=:
    set -o noglob
    set -- $XSH_SHELLS
    set +o noglob
    unset IFS
  }

  for sh in "$@"; do
    [ "$sh" = 'posix' ] && ext='sh' || ext="$sh"

    # All matched units are sorted according to the collating sequence in effect
    # in the current locale (LC_COLLATE) and loaded in that deterministic order.
    # NOTE: Workaround the edge case of XSH_RUNCOM_PREFIX=. where POSIX pathname expansion
    # rules prevents hidden files from being matched.
    for unit in "$XSH_CONFIG_DIR/$sh/$path$name.$ext" \
                "$XSH_CONFIG_DIR/$sh/$path"*?"$name.$ext"; do
      # No distinction is made between a failed glob and a non-readable file.
      # Both cases are skipped.
      if [ -r "$unit" ]; then
        found=1
        _XSH_LOAD_UNITS="${_XSH_LOAD_UNITS:+$_XSH_LOAD_UNITS; }_xsh_source_unit '$unit'"
      fi
    done

    [ "$found" ] && return 0
  done
  return 1
}

# Source a unit marked for loading.
#
# Usage: _xsh_source_unit <file>
# Arguments:
#   file  The path to the unit file to source.
# Globals:
#   XSH_BENCHMARK  Used to enable benchmarking the loading time of the unit.
#   XSH_VERBOSE    Used to enable logging the loaded unit.
_xsh_source_unit() {
  # NOTE: Variables in this scope are exposed to sourced units and are prefixed
  # with '_' to avoid potential conflicts.
  # Even if they are modified, there are no dangerous side effects.
  local _begin= _elapsed= _ext= _err= _errstatus=
  _XSH_LEVEL="$_XSH_LEVEL+"

  # Begin unit benchmark.
  if [ "$XSH_BENCHMARK" ] && [ "$XSH_VERBOSE" ]; then
    # shellcheck disable=SC3044
    [ "$ZSH_NAME" ] && typeset -F SECONDS=0 || _begin=$(_xsh_time)
  fi

  # Source the unit or select the appropriate emulation mode for zsh.
  _ext="${1##*.}"
  if [ "$ZSH_NAME" ] && [ "$_ext" != 'zsh' ]; then
    case "$_ext" in
      ksh|csh) emulate "$_ext" -c ". $1" ;;
      *) emulate sh -c ". $1" ;;
    esac
  else
    . "$1"
  fi
  _err=$?

  # Status/benchmark report.
  if [ "$XSH_VERBOSE" ]; then
    [ $_err -ne 0 ] && _errstatus=" [ret: $_err]"

    # End unit benchmark.
    if [ "$XSH_BENCHMARK" ]; then
      # shellcheck disable=SC3028
      [ "$ZSH_NAME" ] \
        && _elapsed="${$(( SECONDS * 1000 ))%.*}" \
        || _elapsed=$(( $(_xsh_time) - _begin ))
      _xsh_log "${1#"$XSH_CONFIG_DIR"/} [${_elapsed}ms]$_errstatus"
    else
      _xsh_log "${1#"$XSH_CONFIG_DIR"/}$_errstatus"
    fi
  fi

  _XSH_LEVEL="${_XSH_LEVEL%*+}"
  return $_err
}

# Create a default init file for the given shell.
#
# Usage: _xsh_bootstrap_init_file <shell>
# Arguments:
#   shell  The target shell for the init file to create.
_xsh_bootstrap_init_file() {
  local sh="$1"
  local init= desc=

  if [ "$sh" = 'posix' ]; then
    init="$XSH_CONFIG_DIR/$sh/init.sh"
    desc='has no
# dedicated initialization file'
  else
    init="$XSH_CONFIG_DIR/$sh/init.$sh"
    desc="is \`$sh\`"
  fi

  if [ ! -f "$init" ]; then
    _xsh_log "[$sh] creating default init file: ${init#"$XSH_CONFIG_DIR"/}"
    command cat >"$init" <<EOF
#
# This file is sourced automatically by xsh if the current shell $desc.
#
# It should merely register the modules to be loaded for each runcom:
# env, login, interactive and logout.
# The order in which the modules are registered defines the order in which
# they will be loaded. Try \`xsh help\` for more information.
#

xsh module core
EOF
  fi
}

# Create a default module for the given shell.
#
# Usage: _xsh_bootstrap_module <shell>
# Arguments:
#   shell  The target shell for the module to create.
_xsh_bootstrap_module() {
  local sh="$1"
  local ext= rc=

  [ "$sh" = 'posix' ] && ext='sh' || ext="$sh"
  rc="$XSH_CONFIG_DIR/$sh/core/${XSH_RUNCOM_PREFIX}interactive.$ext"

  # Check if there are existing module directories.
  if ! command ls -d "$XSH_CONFIG_DIR/$sh"/*/ >/dev/null 2>&1; then
    _xsh_log "[$sh] creating default module runcom: ${rc#"$XSH_CONFIG_DIR"/}"
    command mkdir "${rc%/*}"
    command cat >"$rc" <<EOF
#
# $(_xsh_module_header "$sh" "core")
#

alias reload='exec "\$XSHELL"' # reload the current shell configuration
EOF
  fi
}

# Create module runcoms for the given shell.
#
# Usage: _xsh_create_module <shell> <module> <runcoms>
# Arguments:
#   shell    The target shell for the module to create.
#   module   The name of the module to create.
#   runcoms  The module runcoms to create.
_xsh_create_module() {
  local sh="$1"
  local mod="$2"
  local rcs="$3"
  local ext= rc= rcf=
  [ "$sh" = 'posix' ] && ext='sh' || ext="$sh"

  # Assign the runcoms as positional parameters.
  # shellcheck disable=SC2086
  {
    IFS=:
    set -o noglob
    set -- $rcs
    set +o noglob
    unset IFS
  }

  # Create module directory if it does not exist.
  command mkdir -p "$XSH_CONFIG_DIR/$sh/$mod" || return 1

  for rc in "$@"; do
    rcf="$XSH_CONFIG_DIR/$sh/$mod/${XSH_RUNCOM_PREFIX}$rc.$ext"

    if [ "$rc" ] && [ ! -f "$rcf" ]; then
      _xsh_log "[$sh] creating module runcom: ${rcf#"$XSH_CONFIG_DIR"/}"
      command cat >"$rcf" <<EOF
#
# $(_xsh_module_header "$sh" "$mod")
#
EOF
    fi
  done
}

# Print the header line to include in generated module runcoms.
#
# Usage: _xsh_module_header <shell> <module>
# Arguments:
#   shell   The shell of the module.
#   module  The name of the module.
_xsh_module_header() {
  local sh="$1"
  local mod="$2"
  local sh_desc=
  [ "$sh" != 'posix' ] && sh_desc=" for $sh"

  printf '%s' "$mod" | head -c 1 | tr '[:lower:]' '[:upper:]'
  printf '%s' "$mod" | tail -c '+2' | tr '-' ' '
  printf ' configuration module%s.' "$sh_desc"
}

# Create a symbolic link, backing up the destination file if it already exists.
#
# Usage: _xsh_link <target> <dest>
# Arguments:
#   target  The link target.
#   dest    The link destination.
_xsh_link() {
  local ln='ln'
  command -v gln >/dev/null && ln='gln'

  command "$ln" -vs --backup=numbered "$@"
}

# Print the current time in milliseconds.
#
# Usage: _xsh_time
_xsh_time() {
  local date='date'
  command -v gdate >/dev/null && date='gdate'

  "$date" '+%s%3N'
}

# Print a log message with a prefix corresponding to the xsh nesting level.
#
# Usage: _xsh_log <message...>
# Arguments:
#   message  The error message to print.
_xsh_log() {
  printf '%s %s\n' "$_XSH_LEVEL" "$1"
}

# Print an error message with a tip for help.
#
# Usage: _xsh_error <message> [command]
# Arguments:
#   message  The error message to print.
#   command  The optional command hint. If '-' no tip is printed.
_xsh_error() {
  local msg="$1"
  local cmd="${2-$_XSH_COMMAND}"
  local hint=1

  if [ "$cmd" = '-' ]; then
    hint=
    cmd="$_XSH_COMMAND"
  fi

  echo "xsh: ${cmd:+$cmd: }$msg"
  [ "$hint" ] && \
    echo "xsh: try 'xsh help${cmd:+ $cmd}' for more information"
  return 1
} >&2

# Set ENV so that if shell X is used as login shell, and then `sh` is started
# as a non-login interactive shell, the runcom will correctly run.
export ENV="$HOME/.shrc"

# Similarly set BASH_ENV, which is run for *non-interactive* shells (unlike ENV).
export BASH_ENV="$HOME/.bashenv"

# Source the init file for the current shell.
xsh init
