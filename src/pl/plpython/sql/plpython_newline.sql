--
-- Universal Newline Support
--

CREATE OR REPLACE FUNCTION newline_lf() RETURNS integer AS
E'x = 100\ny = 23\nreturn x + y\n'
LANGUAGE plpythonu;

CREATE OR REPLACE FUNCTION newline_cr() RETURNS integer AS
E'x = 100\ry = 23\rreturn x + y\r'
LANGUAGE plpythonu;

CREATE OR REPLACE FUNCTION newline_crlf() RETURNS integer AS
E'x = 100\r\ny = 23\r\nreturn x + y\r\n'
LANGUAGE plpythonu;


SELECT newline_lf();
SELECT newline_cr();
SELECT newline_crlf();
