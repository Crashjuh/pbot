#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::c99;
use parent 'Languages::_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Wextra -Wall -Wno-unused-parameter -pedantic -Wfloat-equal -Wshadow -std=c99 -lm -Wfatal-errors -fsanitize=alignment,undefined';
  $self->{options_paste}   = '-fdiagnostics-show-caret';
  $self->{options_nopaste} = '-fno-diagnostics-show-caret';
  $self->{cmdline}         = 'gcc -gdwarf-2 -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <complex.h>
#include <math.h>
#include <tgmath.h>
#include <limits.h>
#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <ctype.h>
#include <inttypes.h>
#include <float.h>
#include <errno.h>
#include <time.h>
#include <assert.h>
#include <locale.h>
#include <wchar.h>
#include <fenv.h>
#include <iso646.h>
#include <setjmp.h>
#include <signal.h>
#include <prelude.h>

END
}

1;
