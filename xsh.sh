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
# - The module/manager names must not contain ' ', ':' or ';' characters.
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

# shellcheck shell=sh disable=SC1090 disable=SC1007
XSH_VERSION='0.1.0'

# Figure out the name of the current shell.
XSHELL="${ZSH_NAME:-${0##*/}}"
XSHELL="${XSHELL#-}" # remove leading '-' for login shells

# A simple framework for shell configuration management.
#
# Usage: xsh [options...] <command> [args...]
# Commands:
#   bootstrap                        Bootstrap xsh for the current or specified shells.
#   help [command]                   Display help information.
#   init                             Source the xsh init file for the current shell.
#   list [unit-type]                 List registered units.
#   load <module> [runcom]           Source a module runcom.
#   manager <manager> [runcoms] ...  Register plugin manager units.
#   module <module> [runcoms] ...    Register module units.
#   runcom [runcom]                  Source all units registered with a runcom.
# Try 'xsh help [command]' for more information about a specific command.
# Options:
#   -h, --help             Display help information for xsh or the current command.
#   -s, --shells <shells>  Set XSH_SHELLS, see below.
#   -b, --benchmark        Set XSH_BENCHMARK, see below.
#   -v, --verbose          Set XSH_VERBOSE, see below.
# Globals:
#   XSH_DIR            Base xsh repository directory (default: ~/.config/xsh).
#   XSH_CONFIG_DIR     Base xsh configuration directory (default: $XSH_DIR).
#   XSH_RUNCOM_PREFIX  Prefix for module runcom files (default: @).
#   XSH_SHELLS         Colon-separated list of shell candidates to lookup for units.
#   XSH_BENCHMARK      Enable benchmarking the loading time of runcoms and units.
#   XSH_VERBOSE        Enable logging the loaded units. If XSH_BENCHMARK is also set,
#                      the loading time for each unit is printed.
xsh() {
  # Restrict changes to global options to local scope.
  local XSH_DIR="${XSH_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/xsh}"
  local XSH_CONFIG_DIR="${XSH_CONFIG_DIR:-$XSH_DIR}"
  local XSH_RUNCOM_PREFIX="${XSH_RUNCOM_PREFIX:-@}"
  local XSH_SHELLS="${XSH_SHELLS:-$XSHELL}"
  local XSH_BENCHMARK="${XSH_BENCHMARK}"
  local XSH_VERBOSE="${XSH_VERBOSE}"
  # Internal local parameters.
  local XSH_COMMAND=
  local XSH_LOAD_UNITS=
  local err=0 begin= elapsed=

  # Replace 'sh' by 'posix' if it is the current shell.
  # This is not done post option processing since AFAIK it would require
  # to use both sed and command substitution, which would have a significant
  # performance impact. User-supplied values must use 'posix' instead of 'sh'.
  [ "$XSH_SHELLS" = 'sh' ] && XSH_SHELLS='posix'

  # Enter the "real" posix zone.
  # In the scope of the current function, zsh emulation is not active so
  # we must make sure that the code executed here is compliant with the POSIX
  # specification and zsh's default options.
  _xsh_run "$@" || err=1

  # Begin runcom benchmark.
  if [ "$XSH_BENCHMARK" ] && [ "$XSH_COMMAND" = 'runcom' ]; then
    [ "$ZSH_NAME" ] && typeset -F SECONDS=0 || begin=$(date '+%s%3N')
  fi

  # Source all units marked for loading during xsh execution.
  # This is done separately to avoid propagating the posix emulation to the
  # sourced units, which can be written in any shell dialect.
  eval "$XSH_LOAD_UNITS" || err=1

  # End runcom benchmark.
  if [ "$XSH_BENCHMARK" ] && [ "$XSH_COMMAND" = 'runcom' ]; then
    [ "$ZSH_NAME" ] \
      && elapsed="${$(( SECONDS * 1000 ))%.*}" \
      || elapsed=$(( $(date +%s%3N) - begin ))
    _xsh_log "$XSH_RUNCOM runcom [${elapsed}ms]"
  fi

  # Set the root XSH_LEVEL after the init unit has been sourced to log it at runcom level.
  [ "$XSH_COMMAND" = 'init' ] && XSH_LEVEL='+'
  return $err
}

# Internal xsh entrypoint, scope of posix emulation for zsh.
_xsh_run() {
  # Enter zsh posix compatibility mode, mainly for field splitting.
  [ "$ZSH_NAME" ] && emulate -L sh

  local args=
  while [ $# -gt 0 ]; do
    case "$1" in
    -h|--help)
      _xsh_help "$XSH_COMMAND"
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
      [ ! "$XSH_COMMAND" ] \
        && XSH_COMMAND="$1" \
        || args="${args:+$args }$1"
      ;;
    esac
    shift
  done

  # Show help if no command is provided.
  if [ ! "$XSH_COMMAND" ]; then
    _xsh_help
    return 1
  fi

  case "$XSH_COMMAND" in
    bootstrap|help|init|list|load|manager|module|runcom) eval "_xsh_$XSH_COMMAND $args" ;;
    *) _xsh_error "invalid command '$XSH_COMMAND'" '' ;;
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

    # If the shell directory doesn't exist, create it and fallback to posix runcoms.
    if [ ! -d "$XSH_CONFIG_DIR/$sh" ]; then
      _xsh_log "[$sh] creating directory: $XSH_CONFIG_DIR/$sh"
      command mkdir -p "$XSH_CONFIG_DIR/$sh" || { err=1; continue; }
    fi
    [ ! -d "$XSH_DIR/$sh/runcom" ] && rcsh='posix'

    # Link shell runcoms to the user's home directory.
    _xsh_log "[$sh] linking shell runcoms"
    for rc in "$XSH_DIR/$rcsh/runcom"/*; do
      if [ $rc = "$XSH_DIR/$rcsh/runcom/*" ]; then
        echo "xsh: bootstrap: no runcoms found for shell '$rcsh'" >&2
        continue 2
      fi

      [ "$sh" = 'zsh' ] && rcpath="${ZDOTDIR:-$HOME}" || rcpath="$HOME"
      if [ "$(readlink "$rcpath/.${rc##*/}")" != "$rc" ]; then
        command ln -vs --backup=numbered "$rc" "$rcpath/.${rc##*/}" || err=1
      fi
    done

    # Create a default init file and module for the shell, if needed.
    _xsh_bootstrap_init_file "$sh" || err=1
    _xsh_bootstrap_module "$sh" || err=1
  done
  return $err
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
  # Reset the internal global state.
  # This is done here to lead the user into using a single init file for each shell,
  # using XSH_SHELLS to specify fallbacks explicitly and with more granularity.
  XSH_MANAGERS=''
  XSH_MODULES=''
  XSH_RUNCOM=''
  XSH_LEVEL=''

  _xsh_load_unit 'init' || {
    # Override XSH_SHELLS in the outer scope so that 'posix' is used as the default shell
    # even in the context of the init file.
    [ "$XSHELL" != 'sh' ] && [ "$XSH_SHELLS" = "$XSHELL" ] \
      && XSH_SHELLS='posix' && _xsh_load_unit 'init'
  } || {
    _xsh_error "init: failed to load for '$XSH_SHELLS'"
    return 1
  }
}

# List the registered managers and/or modules for the current shell.
#
# Usage: xsh list [unit-type]
# Arguments:
#   unit-type  The optional type of unit to list, either 'manager' or 'module'.
_xsh_list() {
  local skip_mng= skip_mod=
  [ ! "$XSH_MANAGERS" ] && skip_mng=1
  case "$1" in
    mng|manager|managers) skip_mod=1 ;;
    mod|module|modules) skip_mng=1 ;;
    ?*)
      _xsh_error "list: invalid unit type '$1'"
      return 1
      ;;
  esac

  [ ! "$skip_mng" ] \
    && echo "$XSH_MANAGERS" | tr ' ' '\n' | column -s ';' -t -N MANAGER,SHELLS,RUNCOMS \
    && [ ! "$skip_mod" ] && echo
  [ ! "$skip_mod" ] \
    && echo "$XSH_MODULES" | tr ' ' '\n' | column -s ';' -t -N MODULE,SHELLS,RUNCOMS
  return 0
}

# Load a runcom of a module in the current shell.
# The runcom argument, if any, must be one of: env, login, interactive, logout.
# By default the current runcom is used, or 'interactive' if that is not set.
#
# Usage: xsh load <module> [runcom]
# Arguments:
#   module  The name of the module to load.
#   runcom  The runcom file of the module to load.
# Globals:
#   XSH_CONFIG_DIR     Used as the base directory to find the module.
#   XSH_RUNCOM_PREFIX  Used as the prefix for module runcom files.
#   XSH_SHELLS         Used as the list of shell candidates to lookup for the module.
_xsh_load() {
  local mod="$1"
  local rc="${2:-${XSH_RUNCOM:-interactive}}"

  if [ ! "$mod" ]; then
    _xsh_list module
    return 1
  fi

  _xsh_load_unit "module/$mod/$XSH_RUNCOM_PREFIX$rc" || {
    _xsh_error "load: failed to load runcom '$rc' of module '$mod' for '$XSH_SHELLS'"
    return 1
  }
}

# Register plugin manager(s) to be installed and loaded by the current shell.
# Valid values for the runcoms argument are: env, login, interactive, logout.
# Multiple values can be specified separated by colons (e.g. login:interactive).
# By default or with the special value '-', the 'interactive' runcom is used.
# Multiple managers can be specified, in which case the runcom argument is required
# between each manager name (use '-' to keep the default behavior).
#
# Usage: xsh manager <manager> [runcoms] ...
# Arguments:
#   manager  The name of the manager to install or load.
#   runcoms  A colon-separated list of runcoms for which the manager should be loaded.
# Globals:
#   XSH_SHELLS  Used as the list of shell candidates to lookup for the manager.
_xsh_manager() {
  local mng="$1"
  local rcs="$2"
  { [ ! "$rcs" ] || [ "$rcs" = '-' ]; } && rcs='interactive'

  if [ ! "$mng" ]; then
    _xsh_error "manager: missing required name"
    return 1
  fi

  XSH_MANAGERS="${XSH_MANAGERS:+$XSH_MANAGERS }$mng;$XSH_SHELLS;$rcs"
  if [ $# -le 2 ]; then
    return 0
  fi

  shift 2 && _xsh_manager "$@"
}

# Register module(s) to be loaded by the current shell.
# Valid values for the runcoms argument are: env, login, interactive, logout.
# Multiple values can be specified separated by colons (e.g. env:login).
# By default or with the special value '-', the module is registered for all runcoms.
# Multiple modules can be specified, in which case the runcom argument is required
# between each module name (use '-' to keep the default behavior).
#
# Usage: xsh module <module> [runcoms] ...
# Arguments:
#   module   The name of the module to load.
#   runcoms  A colon-separated list of runcoms provided by the module.
# Globals:
#   XSH_SHELLS  Used as the list of shell candidates to lookup for the module.
_xsh_module() {
  local mod="$1"
  local rcs="$2"
  { [ ! "$rcs" ] || [ "$rcs" = '-' ]; } && rcs='env:login:interactive:logout'

  if [ ! "$mod" ]; then
    _xsh_error "module: missing required name"
    return 1
  fi

  XSH_MODULES="${XSH_MODULES:+$XSH_MODULES }$mod;$XSH_SHELLS;$rcs"
  if [ $# -le 2 ]; then
    return 0
  fi

  shift 2 && _xsh_module "$@"
}

# Load the managers registered with the given runcom, then load the
# corresponding runcom of registered modules.
# The runcom argument, if any, must be one of: env, login, interactive, logout.
# By default the current runcom is used, or 'interactive' if that is not set.
#
# Usage: xsh runcom [runcom]
# Arguments:
#   runcom  The name of the runcom to load.
# Globals:
#   XSH_CONFIG_DIR  Used as the base directory to find units.
_xsh_runcom() {
  XSH_RUNCOM="${1:-${XSH_RUNCOM:-interactive}}"

  # Load registered plugin managers for the selected runcom.
  _xsh_load_registered manager
  # Load the selected runcom of registered modules.
  _xsh_load_registered module
}

#
# Backend functions
#

# Load all managers or modules for the current runcom in the current shell.
# The units are loaded only if they are registered for the current runcom.
#
# Usage: _xsh_load_registered <unit-type>
# Arguments:
#   unit-type  The type of unit to load, either 'manager' or 'module'.
# Globals:
#   XSH_CONFIG_DIR     Used as the base directory to find units.
#   XSH_RUNCOM_PREFIX  Used as the prefix for module runcom files.
_xsh_load_registered() {
  local utype="$1"
  local unit= rcs=

  # Assign the units as positional parameters.
  # shellcheck disable=SC2086
  {
    set -o noglob
    case "$utype" in
      manager) set -- $XSH_MANAGERS ;;
      module) set -- $XSH_MODULES ;;
    esac
    set +o noglob
  }

  # Load units that are registered for the current runcom.
  for unit in "$@"; do
    rcs="${unit##*;}"
    case $rcs in (*"$XSH_RUNCOM"*)
      unit="${unit%;*}"        # remove runcoms from list entry
      XSH_SHELLS="${unit#*;}"  # extract shells from list entry
      unit="$utype/${unit%;*}" # extract name from list entry

      [ "$utype" = 'module' ] && unit="$unit/$XSH_RUNCOM_PREFIX$XSH_RUNCOM"
      _xsh_load_unit "$unit"
    esac
  done
  return 0
}

# Mark a manager or module runcom for loading in the current shell.
# The unit argument is the shell-agnostic path to the unit to load:
# it must be relative to the shell directory and without extension.
#
# Usage: _xsh_load_unit <unit>
# Arguments:
#   unit  The shell-agnostic path to the unit to load.
# Globals:
#   XSH_CONFIG_DIR  Used as the base directory to find the unit.
#   XSH_SHELLS      Used as the list of shell candidates to lookup for the unit.
_xsh_load_unit() {
  local unit="$1"
  local sh= ext= unitpath=

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
    unitpath="$XSH_CONFIG_DIR/$sh/$unit.$ext"
    if [ ! -r "$unitpath" ]; then
      continue
    fi

    XSH_LOAD_UNITS="${XSH_LOAD_UNITS:+$XSH_LOAD_UNITS; }_xsh_source_unit '$unitpath'"
    return 0
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
  local begin= elapsed= ext= err= errstatus=
  XSH_LEVEL="$XSH_LEVEL+"

  # Begin unit benchmark.
  if [ "$XSH_BENCHMARK" ] && [ "$XSH_VERBOSE" ]; then
    [ "$ZSH_NAME" ] && typeset -F SECONDS=0 || begin=$(date '+%s%3N')
  fi

  # Source the unit or select the appropriate emulation mode for zsh.
  ext="${1##*.}"
  if [ "$ZSH_NAME" ] && [ "$ext" != 'zsh' ]; then
    case "$ext" in
      ksh|csh) emulate "$ext" -c ". $1" ;;
      *) emulate sh -c ". $1" ;;
    esac
  else
    . "$1"
  fi
  err=$?

  # Status/benchmark report.
  if [ "$XSH_VERBOSE" ]; then
    [ $err -ne 0 ] && errstatus=" [ret: $err]"

    # End unit benchmark.
    if [ "$XSH_BENCHMARK" ]; then
      [ "$ZSH_NAME" ] \
        && elapsed="${$(( SECONDS * 1000 ))%.*}" \
        || elapsed=$(( $(date +%s%3N) - begin ))
      _xsh_log "${1#$XSH_CONFIG_DIR/} [${elapsed}ms]$errstatus"
    else
      _xsh_log "${1#$XSH_CONFIG_DIR/}$errstatus"
    fi
  fi

  XSH_LEVEL="${XSH_LEVEL%*+}"
  return $err
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
    _xsh_log "[$sh] creating default init file: ${init#$XSH_CONFIG_DIR/}"
    command cat >"$init" <<EOF
#
# This file is sourced automatically by xsh if the current shell $desc.
#
# It should merely register the manager(s) and modules to be loaded by
# each runcom (env, login, interactive, logout).
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
  rc="$XSH_CONFIG_DIR/$sh/module/core/${XSH_RUNCOM_PREFIX}interactive.$ext"

  if [ ! -d "$sh/module" ]; then
    _xsh_log "[$sh] creating default module runcom: ${rc#$XSH_CONFIG_DIR/}"
    command mkdir -p "${rc%/*}"
    command cat >"$rc" <<EOF
#
# Core configuration module.
#

alias reload='exec "\$XSHELL"' # reload the current shell configuration
EOF
  fi
}

# Print a log message with a prefix corresponding to the xsh nesting level.
#
# Usage: _xsh_log <message...>
# Arguments:
#   message  The error message to print.
_xsh_log() {
  printf '%s %s\n' "$XSH_LEVEL" "$1"
}

# Print an error message with a tip for help.
#
# Usage: _xsh_error <message> [command]
# Arguments:
#   message  The error message to print.
#   command  The optional command hint.
_xsh_error() {
  local cmd="${2-$XSH_COMMAND}"

  echo "xsh: $1"
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
