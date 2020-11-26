<div align="center">

# Xsh

A simple framework for shell configuration management.

[Concept](#design--concepts) • [Installation](#installation) • [Usage](#usage)

![Xsh directory structure](../assets/screenshot.png)

</div>

<!-- doctoc --title '## Table of Contents' --maxlevel 3 README.md -->
<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

## Table of Contents

- [Introduction](#introduction)
- [Dependencies](#dependencies)
- [Supported shells](#supported-shells)
- [Design & Concepts](#design--concepts)
  - [Shells](#shells)
  - [Modules](#modules)
  - [Runcoms](#runcoms)
  - [Managers](#managers)
- [Installation](#installation)
  - [Clone the repository](#clone-the-repository)
  - [Bootstrap the desired shell(s)](#bootstrap-the-desired-shells)
  - [Migrating you existing configuration](#migrating-you-existing-configuration)
  - [Start a new xsh-powered shell](#start-a-new-xsh-powered-shell)
- [Usage](#usage)
  - [Shell initialization file](#shell-initialization-file)
  - [Module runcoms](#module-runcoms)
  - [Managers](#managers-1)
  - [Debugging & Benchmarking](#debugging--benchmarking)
  - [Tips & Tricks](#tips--tricks)
  - [Known limitations](#known-limitations)
- [Updating](#updating)
- [Repositories using xsh](#repositories-using-xsh)
- [References & Credits](#references--credits)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Introduction

The primary goal of xsh is to provide a uniform, consistent and modular
structure for organizing shell configuration.

Each type of shell comes with its own set of startup files and initialization
rules. Xsh abstracts away the complexity, allowing users to focus on
configuration by avoiding the most common traps and pitfalls. Its modular
configuration interface also encourages users to keep their configuration
structured, for the sake of maintainability and readability.

## Dependencies

- GNU `coreutils`
- GNU `sed`
- A POSIX-compatible shell that is [supported](#supported-shells).

I haven't tried to run xsh on macOS or any other platform using the BSD
implementations of `coreutils` and `sed`, so this is uncharted territory.
If anyone is willing to try that, I'll be grateful for any provided feedback.
What is expected is that benchmarking will not work with the BSD implementation
of `date` (except for `zsh` which uses a more efficient method).

On macOS at least it is possible to install the GNU versions of `coreutils` and
`sed`, so that could be a workaround for users on this platform, although
compatibility with both implementations would be preferred. Please open
an issue if you find that it is not the case.

## Supported shells

Due to [my refusal to forfeit the use of `local`](#posix-compatibility), xsh is
not _strictly_ POSIX-compatible. However most of the widely used shells derived
from the historical Bourne Shell are supported (which is what really matters):

- `ash`
- `dash`
- `bash` and its `sh` emulation
- `ksh` implementations that support `local`
- `mksh`
- `zsh` and its `sh` and `ksh` emulations

Feel free to open an issue if you'd like another shell to be supported.

## Design & Concepts

The design of xsh is built around four main concepts: **shells**, **modules**,
**runcoms** and **managers**.

### Shells

Shells are the first class citizens of xsh. Configuration for specific shells
resides in a directory under `$XSH_CONFIG_DIR` matching that shell's name.
The default value of `XSH_CONFIG_DIR` is `$XSH_DIR`, which must point to the
location of the xsh repository. The default location is `~/.config/xsh`.
This document uses `<shell>` to refer to shell directories.

Each shell directory must contain an initialization file named `init.<ext>`.
If the initialization file for a shell isn't found when the shell starts up,
xsh will fallback to the initialization file for posix shells instead
(`posix/init.sh`). This _special_ shell is precisely meant to be used as the
default fallback, but it is not required to bootstrap it if one doesn't need
that behavior.

### Modules

Modules are simply pluggable pieces of configuration for a given shell.
Practically speaking, modules are directories in `<shell>/module/`.
Each module directory contains the runcoms that should be loaded by xsh,
as well as any additional files you would like to put there.

### Runcoms

#### Definitions

Some disambiguation is needed here to avoid confusion between **shell runcoms**,
**xsh runcoms** and **module runcoms**.

Shell runcoms are the shell-specific initialization files that are abstracted
away by xsh. When a shell starts or exits, it will load these files according
to its own set of rules, which xsh translates into a uniform and consistent
behavior for all shells. You normally don't need to worry about these, but for
reference the implementation for each shell can be found in `<shell>/runcom`.

Xsh runcoms, or simply runcoms in the context of this document, are the
resulting abstract concept. They can be seen as layers of configuration that
are loaded by the shell in different contexts.
There are conventionally 4 types of runcoms:

- `env`: Always loaded regardless of how the shell is invoked.
- `login`: Loaded for login shells only.
- `interactive`: Loaded for interactive shells only.
- `logout`: Loaded for login shells on logout.

Module runcoms are the files loaded by xsh during shell initialization.
They always belong to a module and should be written in the language of that
module's shell. Each module should define at least one of the four runcoms.

To summarize, when a shell starts or exits, it loads its own specific shell
runcoms. From the context of these files, xsh determines the abstract runcoms
and attempts to load the corresponding module runcoms for each registered
module.

#### Loading order

Runcoms are always loaded in the following order:

- Shell startup: `env -> login -> interactive`
- Shell shutdown: `logout`

This naturally means that all `env` module runcoms will run before all `login`
module runcoms, etc. Note that login-shells are not necessarily interactive,
and the reverse is also true. So during shell startup you can also have
`env -> login` and `env -> interactive`.

There is also the notable exception that the `sh` shell doesn't source any file
for non-login, non-interactive shells. This is the only case where the `env`
runcom won't be loaded.

#### Naming scheme

To differentiate module runcoms from other files and to emphasize the special
role of these files in module directories, they must respect the following
naming scheme: `@<runcom>.<ext>`.

For example, the file representing the `login` runcom for the `core` module of
the `bash` shell must be `bash/module/core/@login.bash`.
Note that for the (somewhat special) `posix` shell, the extension is `.sh` and
not `.posix`

You can change the special character for runcom files by setting the environment
variable `XSH_RUNCOM_PREFIX` (default `@`). Like `XSH_DIR` this should be set
before you user's login shell is started. Alternatively, it can be set on a
per-shell basis in the [xsh initialization file](#shell-initialization-file)
for that shell.

### Managers

Managers are meant to represent installation/configuration modules for external
plugin managers. Technically, they are simply a special kind of module that
are only registered for a single runcom (`interactive` by default).
Managers are always loaded before the modules registered for that same runcom.
Each manager is a single file in `<shell>/manager/`.

Managers should only be used to:

- Automatically install third-party plugin managers or frameworks.
- Automatically patch the installed software, if needed.
- Load and/or configure the installed software.

The need for a differentiation between managers and modules emerged as it
seemed wrong to integrate external plugin managers as regular modules, since
they also provide their own concept of "modules" (or "plugins").
As such, they are used to bring in third-party modules that can be loaded
and/or configured by specific xsh modules as an additional configuration layer.

This differentiation provides the following benefits:

- Installed third-party plugin managers are made explicit.
- Third-party modules can be loaded and/or configured in different xsh modules.
- Modules can rely on the facilities from installed managers since they are
  always loaded after.

Managers can also be used to automatically install plugin managers or frameworks
for software other than your shell, such as the
[tmux plugin manager](https://github.com/tmux-plugins/tpm/),
[doom-emacs](https://github.com/hlissner/doom-emacs/), etc.

## Installation

### Clone the repository

```sh
git clone https://github.com/sgleizes/xsh ~/.config/xsh
```

The default location of the `xsh` directory is
`${XDG_CONFIG_HOME:-$HOME/.config}/xsh`. If you wish to use a different location,
the `XSH_DIR` environment variable must be set to that location before your
user's login shell is started, for instance in `~/.pam_environment`.

Also if you want to store your shell configuration at a different location than
in the xsh repository (the default), you can set the `XSH_CONFIG_DIR` environment
variable. This must also be set before your user's login shell is started.

### Bootstrap the desired shell(s)

First, xsh must be made available in the current shell:

```sh
source "${XSH_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/xsh}/xsh.sh"
```

Note that sourcing the script at this point will warn you that the
initialization file for the current shell could not be found:

```
xsh: init: failed to load for 'posix'
xsh: try 'xsh help init' for more information
```

This is expected and can be safely ignored since we haven't bootstrapped any
shell yet. You can now use the `xsh` function to bootstrap the current shell:

```sh
xsh bootstrap
```

Or, to bootstrap multiple shells at once:

```sh
xsh bootstrap --shells posix:bash:zsh
```

If you already have any of the shell runcoms in your `$HOME`, the bootstrap
command will automatically back them up so that the links to xsh runcoms can be
created.

The bootstrap command also creates a default initialization file and a `core`
module for the target shell(s).

### Migrating you existing configuration

Your existing configuration should have been automatically backed-up during the
bootstrap operation. For simple cases it can be quickly migrated into the
default module by using commands from the following snippet:

```sh
XSH_CONFIG_DIR="${XSH_CONFIG_DIR:-${XSH_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/xsh}}"

# For POSIX shells
mv "$HOME/.profile.~1~" "$XSH_CONFIG_DIR/posix/module/core/@login.sh"
mv "$HOME/.shrc.~1~"    "$XSH_CONFIG_DIR/posix/module/core/@interactive.sh"

# For bash
mv "$HOME/.bash_profile.~1~" "$XSH_CONFIG_DIR/bash/module/core/@login.bash"
mv "$HOME/.bashrc.~1~"       "$XSH_CONFIG_DIR/bash/module/core/@interactive.bash"
mv "$HOME/.bash_logout.~1~"  "$XSH_CONFIG_DIR/bash/module/core/@logout.bash"

# For zsh
mv "${ZDOTDIR:-$HOME}/.zshenv.~1~"  "$XSH_CONFIG_DIR/zsh/module/core/@env.zsh"
mv "${ZDOTDIR:-$HOME}/.zlogin.~1~"  "$XSH_CONFIG_DIR/zsh/module/core/@login.zsh"
mv "${ZDOTDIR:-$HOME}/.zshrc.~1~"   "$XSH_CONFIG_DIR/zsh/module/core/@interactive.zsh"
mv "${ZDOTDIR:-$HOME}/.zlogout.~1~" "$XSH_CONFIG_DIR/zsh/module/core/@logout.zsh"
```

Note that this is not exactly equivalent to your original setup, as the subtle
differences between the original runcoms are now abstracted away. This is only
meant as a quick way to start.

### Start a new xsh-powered shell

You can check that xsh is working properly by invoking your favorite shell with
`XSH_VERBOSE=1`:

```sh
XSH_VERBOSE=1 zsh
```

This will print every unit that xsh sources during the shell startup process.
You should at the very least see the xsh initialization file for the target
shell be loaded.
If an error occurs, it probably means that
[your shell is not supported](#supported-shells).

Otherwise, everything should be ready for you to start playing around with
your modules. See below for the next steps.

## Usage

Assuming `xsh bootstrap` was run (see [Installation](#Installation)), the
[xsh source file](xsh.sh) will be read and executed whenever your shell starts,
at which point two things happen:

- The shell function `xsh` is sourced. All xsh commands are available through
  this function.

  Documentation about available commands and options can be shown by invoking
  `xsh` with no arguments. Use `xsh help <command>` to get more detailed
  information about a specific command.

- The command `xsh init` is executed. This will source the initialization file
  for the current shell. See below.

### Shell initialization file

Each type of shell must have a dedicated xsh initialization file located at
`<shell>/init.<ext>`

This file should merely register the manager(s) and modules to be loaded by
each runcom (`env`, `login`, `interactive`, `logout`).
The order in which the modules are registered defines the order in which
they will be loaded.

#### Loading modules

Modules can be registered using the `xsh module` command. Note that registering
a module doesn't directly execute that module's runcoms.

The default and most minimal xsh initialization file registers a single module:

```sh
xsh module core
```

This will simply register the `core` module for all runcoms of the current
shell. For example, when xsh loads the `env` runcom, it will look for the
corresponding runcom file `<shell>/module/core/@env.<ext>`.

You can also register a module from another shell, if that other shell's
language can be properly interpreted by the executing shell (e.g. loading a zsh
module from a posix shell is not a good idea). For example:

> File: **`bash/init.bash`**

```sh
xsh module core -s posix
```

This will look for the runcoms of the core module in `posix/module/core`
instead of `bash/module/core`.

Additionally, in the following situation:

```
posix/module/core/
  @env.sh
  @interactive.sh
bash/module/core/
  @login.bash
```

One might want to load the module runcoms from the posix shell if they don't
exist in the current shell's module. The following achieves that behavior:

> File: **`bash/init.bash`**

```sh
xsh module core -s bash:posix
```

Note that if a module runcom doesn't exist for a registered module, xsh will
ignore it silently. If you like, you can explicitly specify which runcoms should
be loaded when registering a module:

> File: **`bash/init.bash`**

```sh
xsh module core interactive:env:login
```

This has the benefit of making the initialization file explicit about which
modules contribute to each runcom. This also affects `xsh list` and avoids
performing unnecessary file lookup every time a shell starts up.

See also `xsh help` and `xsh help module`.

#### Loading managers

Managers can be registered using the `xsh manager` command.
Since they are always loaded before the modules of the same runcom, for clarity
they should be registered first in the initialization file.

> File: **`zsh/init.zsh`**

```sh
xsh manager zinit
xsh module core
```

This will register the `zinit` manager for the `interactive` runcom.
When xsh loads the `interactive` runcom, it will look for the files to load in
this order:

- `zsh/manager/zinit.zsh`
- `zsh/module/core/@interactive.zsh`.

If you want to register a manager for a different runcom than the default
`interactive`, the syntax is the same than for modules:

```sh
xsh manager doom-emacs login
```

See also `xsh help` and `xsh help manager`.

### Module runcoms

The module contents and organization is entirely up to you. During this design
process, you might find a need to express dependencies between modules, or to
have a module runcom conditionally loaded by another module.

You can achieve this by using the `xsh load` command.
For example, in the following situation:

```
posix/module/core/
  @env.sh
  @interactive.sh
bash/module/core/
  @interactive.bash
```

Even if you register the `core` module using `xsh module core -s bash:posix`,
the interactive runcom of the posix module would not be loaded, as it is found
in the bash module directory first.
You can load that runcom from the bash module as a dependency:

> File: **`bash/module/core/@interactive.bash`**

```sh
xsh load core -s posix
```

This will load `posix/module/core/@interactive.sh` directly.

That command can also be used to load a runcom of a different module as part
of a module's configuration. This is usually needed if loading the dependee
module is conditionally based on a predicate from the dependent module:

> File: **`bash/module/core/@interactive.bash`**

```sh
if some_predicate; then
  xsh load other
fi
```

This will load `bash/module/other/@interactive.bash` directly.

See also `xsh help` and `xsh help load`.

### Managers

The specific implementation for integrating each external plugin managers
depends on their design and might be tricky in some cases.

I might add a library of example managers to this repository in the future,
for now you can refer to
[the ones I use](https://github.com/sgleizes/dotfiles/tree/master/.config/xsh/zsh/manager).

### Debugging & Benchmarking

The list of managers and/or modules registered in the current shell can be
displayed:

```sh
xsh list
```

You can also see which modules are loaded by xsh and in which order:

```sh
XSH_VERBOSE=1 zsh
```

Xsh can also benchmark the loading time for each runcom:

```sh
XSH_BENCHMARK=1 zsh
```

Combining both options will show the loading time for each module runcom:

```sh
XSH_VERBOSE=1 XSH_BENCHMARK=1 zsh
```

Note that benchmarking for all shells other than `zsh` adds a significant
overhead (see [benchmarking limitations](#benchmarking)), and so does not
accurately reflect the real loading time of your entire configuration.
It can still be useful to compare the loading times between different runcoms
and modules though.

### Tips & Tricks

#### In which runcom do I put...

It can be troublesome at first to figure out in which runcom a particular piece
of configuration should reside.
[This section of the Zsh FAQ](http://zsh.sourceforge.net/FAQ/zshfaq03.html#l19)
is a good place to start.

The `env` runcom should be kept as minimal as possible, as it defines the
environment for non-login, non-interactive shells. It directly affects the
execution of scripts and should never produce any output.
It can for example set common environment variables like `EDITOR`, `PAGER`, etc.

The `login` runcom runs when your user's session starts, it defines the
environment that will be inherited by all processes from that session. It can
also be used to perform specific tasks at login-time, or to avoid performing a
particular task every time you start an interactive shell. It is a good place
to alter your `PATH`, start an `ssh-agent`, set the `umask`, etc.

The `interactive` runcom is for everything else, this is where most of your
configuration should reside.

The `logout` runcom runs when your login shell is about to exit. You can use it
to display a friendly goodbye message, or to cleanup old files from the trash,
etc.

#### Using `posix` as a common base

I have personally gone for that approach where I have a common set of
"essential" interactive settings (mostly aliases) defined for the `posix` shell,
that are loaded from other shells using `xsh load`.

This is so that I don't feel lost or frustrated whenever I need to use another
shell. I also use it as a way to clearly distinguish basic, generic shell
configuration from the more advanced, shell-specific configuration. It allows
basic configuration to be factorized in a single place while being effective
for all shells.

Naturally it implies that these common settings are written in a posixly
correct manner. Some people might find that it adds clutter and complexity
for little benefit.

#### Using a different directory for user configuration

If you use `git` to version your shell configuration, keeping it inside the xsh
repository would be problematic. Or maybe you just want a separation of
concerns.

You can specify the location of your shell configuration using the
`XSH_CONFIG_DIR` environment variable. Note that this must be set before your
user's login shell is started (e.g. in `~/.pam_environment`).

Setting it to `$XDG_CONFIG_HOME` or `$HOME/.config` will result in a
XDG-compliant configuration structure, with the configuration for each shell
residing in `~/.config/<shell>`.

#### Removing unused shells from the directory tree

If you use xsh as a configuration framework for a single shell, you might want
to cleanup `XSH_DIR` and get rid of the unused shells. You could simply remove
them, but they will then show-up in `git status`. A cleaner solution would be
to use `git sparse-checkout`.

Let's say, you are a `zsh` user and _never_ use any other shell (interactively).
You can get rid of the `bash` and `posix` directories with the following:

```sh
git sparse-checkout set '/*' '!/bash' '!/posix'
```

You should make sure that none of these shells are bootstrapped first.
Note that if you remove the `posix` shell, you won't be able to bootstrap any
shell using the same runcoms (e.g. `dash`, `mksh`, ...).

### Known limitations

#### Argument parsing

- Command arguments containing spaces, tabs or newlines are split in separate arguments.
- The module/manager names must not contain ' ', ':' or ';' characters.

#### POSIX compatibility

The use of `local` is not strictly POSIX-compatible. However, it is widely
supported even by the most primitive POSIX-compliant shells (`dash`, `ash` and
some `ksh` implementations). Since xsh will probably be of little interest to
the people using shells even more primitive than this, support for these shells
will probably never be added.
See [this post](https://stackoverflow.com/a/18600920/3469781).

It should be noted that there are differences between the implementations,
e.g. local variables in `dash` and `ash` inherit their value in the parent scope
by default. To enforce truly distinct variables the form `local var=` is used to
preserve compatibility with these shells.

#### Benchmarking

Benchmarking uses the `date +%N` command (except for zsh), which is not
supported by all implementations of 'date' and also incurs a significant
performance impact due to the outer process and command substitution, which
is a shame when it comes to benchmarking...

#### OS-specific behaviors

Unfortunately, the invocation of bash runcoms is dependent on patches added
by OS distributors and compile-time options. The implementation for the runcoms
of each shell has not been tested on a variety of OS distributions so far, so
please open an issue if you find that xsh if not behaving like it should on your
distribution.

## Updating

Xsh is not expected to go through any major updates at this point, and all
changes will (try to) be non-breaking.

Updating should only require to `git pull` from the xsh directory.

## Repositories using xsh

My dotfiles repository includes an
[extensive xsh-powered configuration](https://github.com/sgleizes/dotfiles/tree/master/.config/xsh)
that could help illustrating the benefits of a modular configuration.

If you decide to migrate your dotfiles to xsh, please add the `xsh` tag to your
repository so that we can all see the results of your hard work and be inspired
from it!

[Browse xsh repositories.](https://github.com/topics/xsh)

## References & Credits

- The inspiration for creating this thing originated from
  [this blog post](https://blog.flowblok.id.au/2013-02/shell-startup-scripts.html).
- A little bit of
  [shell history](https://krixano.github.io/ShellHistory-Unix.pdf).
- The
  [POSIX shell specification](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html).
