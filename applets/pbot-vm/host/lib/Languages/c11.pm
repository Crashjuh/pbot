#!/usr/bin/perl

# SPDX-FileCopyrightText: 2021 Pragmatic Software <pragma78@gmail.com>
# SPDX-License-Identifier: MIT

use warnings;
use strict;

package Languages::c11;
use parent 'Languages::_c_base';

sub initialize {
  my ($self, %conf) = @_;

  $self->{sourcefile}      = 'prog.c';
  $self->{execfile}        = 'prog';
  $self->{default_options} = '-Wextra -Wall -Wno-unused-parameter -pedantic -Wfloat-equal -Wshadow -std=c11 -lm -Wfatal-errors -fsanitize=alignment,undefined -fsanitize-address-use-after-scope -fno-omit-frame-pointer';
  $self->{options_paste}   = '-fdiagnostics-show-caret';
  $self->{options_nopaste} = '-fno-diagnostics-show-caret';
  $self->{cmdline}         = 'gcc -gdwarf-2 -g3 $sourcefile $options -o $execfile';

  $self->{prelude} = <<'END';
#define _XOPEN_SOURCE 9001
#define __USE_XOPEN
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <limits.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdarg.h>
#include <stdnoreturn.h>
#include <stdalign.h>
#include <ctype.h>
#include <inttypes.h>
#include <float.h>
#include <errno.h>
#include <time.h>
#include <assert.h>
#include <complex.h>
#include <setjmp.h>
#include <wchar.h>
#include <wctype.h>
#include <tgmath.h>
#include <fenv.h>
#include <locale.h>
#include <iso646.h>
#include <signal.h>
#include <uchar.h>
#include <stdint.h>
#include <unistd.h>
#include <sys/types.h>
#include <prelude.h>

END
}

1;
