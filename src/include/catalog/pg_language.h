/*-------------------------------------------------------------------------
 *
 * pg_language.h
 *	  definition of the "language" system catalog (pg_language)
 *
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/catalog/pg_language.h
 *
 * NOTES
 *	  The Catalog.pm module reads this file and derives schema
 *	  information.
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_LANGUAGE_H
#define PG_LANGUAGE_H

#include "catalog/genbki.h"
#include "catalog/pg_language_d.h"

/* ----------------
 *		pg_language definition.  cpp turns this into
 *		typedef struct FormData_pg_language
 * ----------------
 */
CATALOG(pg_language,2612,LanguageRelationId)
{
	/* Language name */
	NameData	lanname;

	/* Language's owner */
	Oid			lanowner BKI_DEFAULT(PGUID);

	/* Is a procedural language */
	bool		lanispl BKI_DEFAULT(f);

	/* PL is trusted */
	bool		lanpltrusted BKI_DEFAULT(f);

	/* Call handler, if it's a PL */
	Oid			lanplcallfoid BKI_DEFAULT(0) BKI_LOOKUP(pg_proc);

	/* Optional anonymous-block handler function */
	Oid			laninline BKI_DEFAULT(0) BKI_LOOKUP(pg_proc);

	/* Optional validation function */
	Oid			lanvalidator BKI_DEFAULT(0) BKI_LOOKUP(pg_proc);

#ifdef CATALOG_VARLEN			/* variable-length fields start here */
	/* Access privileges */
	aclitem		lanacl[1] BKI_DEFAULT(_null_);
#endif
} FormData_pg_language;

/* ----------------
 *		Form_pg_language corresponds to a pointer to a tuple with
 *		the format of pg_language relation.
 * ----------------
 */
typedef FormData_pg_language *Form_pg_language;

#endif							/* PG_LANGUAGE_H */
