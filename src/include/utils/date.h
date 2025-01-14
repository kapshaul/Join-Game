/*-------------------------------------------------------------------------
 *
 * date.h
 *	  Definitions for the SQL "date" and "time" types.
 *
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * src/include/utils/date.h
 *
 *-------------------------------------------------------------------------
 */
#ifndef DATE_H
#define DATE_H

#include <math.h>

#include "fmgr.h"
#include "pgtime.h"
#include "datatype/timestamp.h"

typedef int32 DateADT;

typedef int64 TimeADT;

typedef struct
{
	TimeADT		time;			/* all time units other than months and years */
	int32		zone;			/* numeric time zone, in seconds */
} TimeTzADT;

/*
 * Infinity and minus infinity must be the max and min values of DateADT.
 */
#define DATEVAL_NOBEGIN		((DateADT) PG_INT32_MIN)
#define DATEVAL_NOEND		((DateADT) PG_INT32_MAX)

#define DATE_NOBEGIN(j)		((j) = DATEVAL_NOBEGIN)
#define DATE_IS_NOBEGIN(j)	((j) == DATEVAL_NOBEGIN)
#define DATE_NOEND(j)		((j) = DATEVAL_NOEND)
#define DATE_IS_NOEND(j)	((j) == DATEVAL_NOEND)
#define DATE_NOT_FINITE(j)	(DATE_IS_NOBEGIN(j) || DATE_IS_NOEND(j))

/*
 * Macros for fmgr-callable functions.
 *
 * For TimeADT, we make use of the same support routines as for int64.
 * Therefore TimeADT is pass-by-reference if and only if int64 is!
 */
#define MAX_TIME_PRECISION 6

#define DatumGetDateADT(X)	  ((DateADT) DatumGetInt32(X))
#define DatumGetTimeADT(X)	  ((TimeADT) DatumGetInt64(X))
#define DatumGetTimeTzADTP(X) ((TimeTzADT *) DatumGetPointer(X))

#define DateADTGetDatum(X)	  Int32GetDatum(X)
#define TimeADTGetDatum(X)	  Int64GetDatum(X)
#define TimeTzADTPGetDatum(X) PointerGetDatum(X)

#define PG_GETARG_DATEADT(n)	 DatumGetDateADT(PG_GETARG_DATUM(n))
#define PG_GETARG_TIMEADT(n)	 DatumGetTimeADT(PG_GETARG_DATUM(n))
#define PG_GETARG_TIMETZADT_P(n) DatumGetTimeTzADTP(PG_GETARG_DATUM(n))

#define PG_RETURN_DATEADT(x)	 return DateADTGetDatum(x)
#define PG_RETURN_TIMEADT(x)	 return TimeADTGetDatum(x)
#define PG_RETURN_TIMETZADT_P(x) return TimeTzADTPGetDatum(x)


/* date.c */
extern int32 anytime_typmod_check(bool istz, int32 typmod);
extern double date2timestamp_no_overflow(DateADT dateVal);
extern void EncodeSpecialDate(DateADT dt, char *str);
extern DateADT GetSQLCurrentDate(void);
extern TimeTzADT *GetSQLCurrentTime(int32 typmod);
extern TimeADT GetSQLLocalTime(int32 typmod);
extern int	time2tm(TimeADT time, struct pg_tm *tm, fsec_t *fsec);
extern int	timetz2tm(TimeTzADT *time, struct pg_tm *tm, fsec_t *fsec, int *tzp);

#endif							/* DATE_H */
