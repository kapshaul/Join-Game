/*-------------------------------------------------------------------------
 *
 * pg_largeobject_metadata.h
 *	  definition of the "large object metadata" system catalog
 *	  (pg_largeobject_metadata)
 *
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/catalog/pg_largeobject_metadata.h
 *
 * NOTES
 *	  The Catalog.pm module reads this file and derives schema
 *	  information.
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_LARGEOBJECT_METADATA_H
#define PG_LARGEOBJECT_METADATA_H

#include "catalog/genbki.h"
#include "catalog/pg_largeobject_metadata_d.h"

/* ----------------
 *		pg_largeobject_metadata definition. cpp turns this into
 *		typedef struct FormData_pg_largeobject_metadata
 * ----------------
 */
CATALOG(pg_largeobject_metadata,2995,LargeObjectMetadataRelationId)
{
	Oid			lomowner;		/* OID of the largeobject owner */

#ifdef CATALOG_VARLEN			/* variable-length fields start here */
	aclitem		lomacl[1];		/* access permissions */
#endif
} FormData_pg_largeobject_metadata;

/* ----------------
 *		Form_pg_largeobject_metadata corresponds to a pointer to a tuple
 *		with the format of pg_largeobject_metadata relation.
 * ----------------
 */
typedef FormData_pg_largeobject_metadata *Form_pg_largeobject_metadata;

#endif							/* PG_LARGEOBJECT_METADATA_H */
