#!/usr/bin/perl -w

#
# gen_qsort_tuple.pl
#
# This script generates specialized versions of the quicksort algorithm for
# tuple sorting.  The quicksort code is derived from the NetBSD code.  The
# code generated by this script runs significantly faster than vanilla qsort
# when used to sort tuples.  This speedup comes from a number of places.
# The major effects are (1) inlining simple tuple comparators is much faster
# than jumping through a function pointer and (2) swap and vecswap operations
# specialized to the particular data type of interest (in this case, SortTuple)
# are faster than the generic routines.
#
#	Modifications from vanilla NetBSD source:
#	  Add do ... while() macro fix
#	  Remove __inline, _DIAGASSERTs, __P
#	  Remove ill-considered "swap_cnt" switch to insertion sort,
#	  in favor of a simple check for presorted input.
#	  Take care to recurse on the smaller partition, to bound stack usage.
#
#     Instead of sorting arbitrary objects, we're always sorting SortTuples.
#     Add CHECK_FOR_INTERRUPTS().
#
# CAUTION: if you change this file, see also qsort.c and qsort_arg.c
#

use strict;

my $SUFFIX;
my $EXTRAARGS;
my $EXTRAPARAMS;
my $CMPPARAMS;

emit_qsort_boilerplate();

$SUFFIX      = 'tuple';
$EXTRAARGS   = ', SortTupleComparator cmp_tuple, Tuplesortstate *state';
$EXTRAPARAMS = ', cmp_tuple, state';
$CMPPARAMS   = ', state';
emit_qsort_implementation();

$SUFFIX      = 'ssup';
$EXTRAARGS   = ', SortSupport ssup';
$EXTRAPARAMS = ', ssup';
$CMPPARAMS   = ', ssup';
print <<'EOM';

#define cmp_ssup(a, b, ssup) \
	ApplySortComparator((a)->datum1, (a)->isnull1, \
						(b)->datum1, (b)->isnull1, ssup)

EOM
emit_qsort_implementation();

sub emit_qsort_boilerplate
{
	print <<'EOM';
/*
 * autogenerated by src/backend/utils/sort/gen_qsort_tuple.pl, do not edit!
 *
 * This file is included by tuplesort.c, rather than compiled separately.
 */

/*	$NetBSD: qsort.c,v 1.13 2003/08/07 16:43:42 agc Exp $	*/

/*-
 * Copyright (c) 1992, 1993
 *	The Regents of the University of California.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *	  notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *	  notice, this list of conditions and the following disclaimer in the
 *	  documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the University nor the names of its contributors
 *	  may be used to endorse or promote products derived from this software
 *	  without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/*
 * Qsort routine based on J. L. Bentley and M. D. McIlroy,
 * "Engineering a sort function",
 * Software--Practice and Experience 23 (1993) 1249-1265.
 *
 * We have modified their original by adding a check for already-sorted input,
 * which seems to be a win per discussions on pgsql-hackers around 2006-03-21.
 *
 * Also, we recurse on the smaller partition and iterate on the larger one,
 * which ensures we cannot recurse more than log(N) levels (since the
 * partition recursed to is surely no more than half of the input).  Bentley
 * and McIlroy explicitly rejected doing this on the grounds that it's "not
 * worth the effort", but we have seen crashes in the field due to stack
 * overrun, so that judgment seems wrong.
 */

static void
swapfunc(SortTuple *a, SortTuple *b, size_t n)
{
	do
	{
		SortTuple 	t = *a;
		*a++ = *b;
		*b++ = t;
	} while (--n > 0);
}

#define swap(a, b)						\
	do { 								\
		SortTuple t = *(a);				\
		*(a) = *(b);					\
		*(b) = t;						\
	} while (0);

#define vecswap(a, b, n) if ((n) > 0) swapfunc(a, b, n)

EOM

	return;
}

sub emit_qsort_implementation
{
	print <<EOM;
static SortTuple *
med3_$SUFFIX(SortTuple *a, SortTuple *b, SortTuple *c$EXTRAARGS)
{
	return cmp_$SUFFIX(a, b$CMPPARAMS) < 0 ?
		(cmp_$SUFFIX(b, c$CMPPARAMS) < 0 ? b :
			(cmp_$SUFFIX(a, c$CMPPARAMS) < 0 ? c : a))
		: (cmp_$SUFFIX(b, c$CMPPARAMS) > 0 ? b :
			(cmp_$SUFFIX(a, c$CMPPARAMS) < 0 ? a : c));
}

static void
qsort_$SUFFIX(SortTuple *a, size_t n$EXTRAARGS)
{
	SortTuple  *pa,
			   *pb,
			   *pc,
			   *pd,
			   *pl,
			   *pm,
			   *pn;
	size_t		d1,
				d2;
	int			r,
				presorted;

loop:
	CHECK_FOR_INTERRUPTS();
	if (n < 7)
	{
		for (pm = a + 1; pm < a + n; pm++)
			for (pl = pm; pl > a && cmp_$SUFFIX(pl - 1, pl$CMPPARAMS) > 0; pl--)
				swap(pl, pl - 1);
		return;
	}
	presorted = 1;
	for (pm = a + 1; pm < a + n; pm++)
	{
		CHECK_FOR_INTERRUPTS();
		if (cmp_$SUFFIX(pm - 1, pm$CMPPARAMS) > 0)
		{
			presorted = 0;
			break;
		}
	}
	if (presorted)
		return;
	pm = a + (n / 2);
	if (n > 7)
	{
		pl = a;
		pn = a + (n - 1);
		if (n > 40)
		{
			size_t		d = (n / 8);

			pl = med3_$SUFFIX(pl, pl + d, pl + 2 * d$EXTRAPARAMS);
			pm = med3_$SUFFIX(pm - d, pm, pm + d$EXTRAPARAMS);
			pn = med3_$SUFFIX(pn - 2 * d, pn - d, pn$EXTRAPARAMS);
		}
		pm = med3_$SUFFIX(pl, pm, pn$EXTRAPARAMS);
	}
	swap(a, pm);
	pa = pb = a + 1;
	pc = pd = a + (n - 1);
	for (;;)
	{
		while (pb <= pc && (r = cmp_$SUFFIX(pb, a$CMPPARAMS)) <= 0)
		{
			if (r == 0)
			{
				swap(pa, pb);
				pa++;
			}
			pb++;
			CHECK_FOR_INTERRUPTS();
		}
		while (pb <= pc && (r = cmp_$SUFFIX(pc, a$CMPPARAMS)) >= 0)
		{
			if (r == 0)
			{
				swap(pc, pd);
				pd--;
			}
			pc--;
			CHECK_FOR_INTERRUPTS();
		}
		if (pb > pc)
			break;
		swap(pb, pc);
		pb++;
		pc--;
	}
	pn = a + n;
	d1 = Min(pa - a, pb - pa);
	vecswap(a, pb - d1, d1);
	d1 = Min(pd - pc, pn - pd - 1);
	vecswap(pb, pn - d1, d1);
	d1 = pb - pa;
	d2 = pd - pc;
	if (d1 <= d2)
	{
		/* Recurse on left partition, then iterate on right partition */
		if (d1 > 1)
			qsort_$SUFFIX(a, d1$EXTRAPARAMS);
		if (d2 > 1)
		{
			/* Iterate rather than recurse to save stack space */
			/* qsort_$SUFFIX(pn - d2, d2$EXTRAPARAMS); */
			a = pn - d2;
			n = d2;
			goto loop;
		}
	}
	else
	{
		/* Recurse on right partition, then iterate on left partition */
		if (d2 > 1)
			qsort_$SUFFIX(pn - d2, d2$EXTRAPARAMS);
		if (d1 > 1)
		{
			/* Iterate rather than recurse to save stack space */
			/* qsort_$SUFFIX(a, d1$EXTRAPARAMS); */
			n = d1;
			goto loop;
		}
	}
}
EOM

	return;
}
