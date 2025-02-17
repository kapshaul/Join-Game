/*-------------------------------------------------------------------------
 *
 * pg_attribute_d.h
 *    Macro definitions for pg_attribute
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * NOTES
 *  ******************************
 *  *** DO NOT EDIT THIS FILE! ***
 *  ******************************
 *
 *  It has been GENERATED by src/backend/catalog/genbki.pl
 *
 *-------------------------------------------------------------------------
 */
#ifndef PG_ATTRIBUTE_D_H
#define PG_ATTRIBUTE_D_H

#define AttributeRelationId 1249
#define AttributeRelation_Rowtype_Id 75

#define Anum_pg_attribute_attrelid 1
#define Anum_pg_attribute_attname 2
#define Anum_pg_attribute_atttypid 3
#define Anum_pg_attribute_attstattarget 4
#define Anum_pg_attribute_attlen 5
#define Anum_pg_attribute_attnum 6
#define Anum_pg_attribute_attndims 7
#define Anum_pg_attribute_attcacheoff 8
#define Anum_pg_attribute_atttypmod 9
#define Anum_pg_attribute_attbyval 10
#define Anum_pg_attribute_attstorage 11
#define Anum_pg_attribute_attalign 12
#define Anum_pg_attribute_attnotnull 13
#define Anum_pg_attribute_atthasdef 14
#define Anum_pg_attribute_atthasmissing 15
#define Anum_pg_attribute_attidentity 16
#define Anum_pg_attribute_attisdropped 17
#define Anum_pg_attribute_attislocal 18
#define Anum_pg_attribute_attinhcount 19
#define Anum_pg_attribute_attcollation 20
#define Anum_pg_attribute_attacl 21
#define Anum_pg_attribute_attoptions 22
#define Anum_pg_attribute_attfdwoptions 23
#define Anum_pg_attribute_attmissingval 24

#define Natts_pg_attribute 24


#define		  ATTRIBUTE_IDENTITY_ALWAYS		'a'
#define		  ATTRIBUTE_IDENTITY_BY_DEFAULT 'd'


#endif							/* PG_ATTRIBUTE_D_H */
