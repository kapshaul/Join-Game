/*
 *	string.h
 *		string handling helpers
 *
 *	Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 *	Portions Copyright (c) 1994, Regents of the University of California
 *
 *	src/include/common/string.h
 */
#ifndef COMMON_STRING_H
#define COMMON_STRING_H

extern bool pg_str_endswith(const char *str, const char *end);
extern int strtoint(const char *pg_restrict str, char **pg_restrict endptr,
		 int base);

#endif							/* COMMON_STRING_H */
