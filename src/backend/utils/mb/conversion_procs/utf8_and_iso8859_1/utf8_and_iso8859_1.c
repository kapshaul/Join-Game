/*-------------------------------------------------------------------------
 *
 *	  ISO8859_1 <--> UTF8
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/backend/utils/mb/conversion_procs/utf8_and_iso8859_1/utf8_and_iso8859_1.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres.h"
#include "fmgr.h"
#include "mb/pg_wchar.h"

PG_MODULE_MAGIC;

PG_FUNCTION_INFO_V1(iso8859_1_to_utf8);
PG_FUNCTION_INFO_V1(utf8_to_iso8859_1);

/* ----------
 * conv_proc(
 *		INTEGER,	-- source encoding id
 *		INTEGER,	-- destination encoding id
 *		CSTRING,	-- source string (null terminated C string)
 *		CSTRING,	-- destination string (null terminated C string)
 *		INTEGER		-- source string length
 * ) returns VOID;
 * ----------
 */

Datum
iso8859_1_to_utf8(PG_FUNCTION_ARGS)
{
	unsigned char *src = (unsigned char *) PG_GETARG_CSTRING(2);
	unsigned char *dest = (unsigned char *) PG_GETARG_CSTRING(3);
	int			len = PG_GETARG_INT32(4);
	unsigned short c;

	CHECK_ENCODING_CONVERSION_ARGS(PG_LATIN1, PG_UTF8);

	while (len > 0)
	{
		c = *src;
		if (c == 0)
			report_invalid_encoding(PG_LATIN1, (const char *) src, len);
		if (!IS_HIGHBIT_SET(c))
			*dest++ = c;
		else
		{
			*dest++ = (c >> 6) | 0xc0;
			*dest++ = (c & 0x003f) | HIGHBIT;
		}
		src++;
		len--;
	}
	*dest = '\0';

	PG_RETURN_VOID();
}

Datum
utf8_to_iso8859_1(PG_FUNCTION_ARGS)
{
	unsigned char *src = (unsigned char *) PG_GETARG_CSTRING(2);
	unsigned char *dest = (unsigned char *) PG_GETARG_CSTRING(3);
	int			len = PG_GETARG_INT32(4);
	unsigned short c,
				c1;

	CHECK_ENCODING_CONVERSION_ARGS(PG_UTF8, PG_LATIN1);

	while (len > 0)
	{
		c = *src;
		if (c == 0)
			report_invalid_encoding(PG_UTF8, (const char *) src, len);
		/* fast path for ASCII-subset characters */
		if (!IS_HIGHBIT_SET(c))
		{
			*dest++ = c;
			src++;
			len--;
		}
		else
		{
			int			l = pg_utf_mblen(src);

			if (l > len || !pg_utf8_islegal(src, l))
				report_invalid_encoding(PG_UTF8, (const char *) src, len);
			if (l != 2)
				report_untranslatable_char(PG_UTF8, PG_LATIN1,
										   (const char *) src, len);
			c1 = src[1] & 0x3f;
			c = ((c & 0x1f) << 6) | c1;
			if (c >= 0x80 && c <= 0xff)
			{
				*dest++ = (unsigned char) c;
				src += 2;
				len -= 2;
			}
			else
				report_untranslatable_char(PG_UTF8, PG_LATIN1,
										   (const char *) src, len);
		}
	}
	*dest = '\0';

	PG_RETURN_VOID();
}
