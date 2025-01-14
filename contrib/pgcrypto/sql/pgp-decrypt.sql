--
-- pgp_descrypt tests
--

--  Checking ciphers
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.blowfish.sha1.mdc.s2k3.z0

jA0EBAMCfFNwxnvodX9g0jwB4n4s26/g5VmKzVab1bX1SmwY7gvgvlWdF3jKisvS
yA6Ce1QTMK3KdL2MPfamsTUSAML8huCJMwYQFfE=
=JcP+
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCci97v0Q6Z0Zg0kQBsVf5Oe3iC+FBzUmuMV9KxmAyOMyjCc/5i8f1Eest
UTAsG35A1vYs02VARKzGz6xI2UHwFUirP+brPBg3Ee7muOx8pA==
=XtrP
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes192.sha1.mdc.s2k3.z0

jA0ECAMCI7YQpWqp3D1g0kQBCjB7GlX7+SQeXNleXeXQ78ZAPNliquGDq9u378zI
5FPTqAhIB2/2fjY8QEIs1ai00qphjX2NitxV/3Wn+6dufB4Q4g==
=rCZt
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes256.sha1.mdc.s2k3.z0

jA0ECQMC4f/5djqCC1Rg0kQBTHEPsD+Sw7biBsM2er3vKyGPAQkuTBGKC5ie7hT/
lceMfQdbAg6oTFyJpk/wH18GzRDphCofg0X8uLgkAKMrpcmgog==
=fB6S
-----END PGP MESSAGE-----
'), 'foobar');

-- Checking MDC modes
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.nomdc.s2k3.z0

jA0EBwMCnv07rlXqWctgyS2Dm2JfOKCRL4sLSLJUC8RS2cH7cIhKSuLitOtyquB+
u9YkgfJfsuRJmgQ9tmo=
=60ui
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCEeP3idNjQ1Bg0kQBf4G0wX+2QNzLh2YNwYkQgQkfYhn/hLXjV4nK9nsE
8Ex1Dsdt5UPvOz8W8VKQRS6loOfOe+yyXil8W3IYFwUpdDUi+Q==
=moGf
-----END PGP MESSAGE-----
'), 'foobar');

-- Checking hashes
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.md5.mdc.s2k3.z0

jA0EBwMClrXXtOXetohg0kQBn0Kl1ymevQZRHkdoYRHgzCwSQEiss7zYff2UNzgO
KyRrHf7zEBuZiZ2AG34jNVMOLToj1jJUg5zTSdecUzQVCykWTA==
=NyLk
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCApbdlrURoWJg0kQBzHM/E0o7djY82bNuspjxjAcPFrrtp0uvDdMQ4z2m
/PM8jhgI5vxFYfNQjLl8y3fHYIomk9YflN9K/Q13iq8A8sjeTw==
=FxbQ
-----END PGP MESSAGE-----
'), 'foobar');

-- Checking S2K modes
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k0.z0

jAQEBwAC0kQBKTaLAKE3xzps+QIZowqRNb2eAdzBw2LxEW2YD5PgNlbhJdGg+dvw
Ah9GXjGS1TVALzTImJbz1uHUZRfhJlFbc5yGQw==
=YvkV
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k1.z0

jAwEBwEC/QTByBLI3b/SRAHPxKzI6SZBo5lAEOD+EsvKQWO4adL9tDY+++Iqy1xK
4IaWXVKEj9R2Lr2xntWWMGZtcKtjD2lFFRXXd9dZp1ZThNDz
=dbXm
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCEq4Su3ZqNEJg0kQB4QG5jBTKF0i04xtH+avzmLhstBNRxvV3nsmB3cwl
z+9ZaA/XdSx5ZiFnMym8P6r8uY9rLjjNptvvRHlxIReF+p9MNg==
=VJKg
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes192.sha1.mdc.s2k0.z0

jAQECAAC0kQBBDnQWkgsx9YFaqDfWmpsiyAJ6y2xG/sBvap1dySYEMuZ+wJTXQ9E
Cr3i2M7TgVZ0M4jp4QL0adG1lpN5iK7aQeOwMw==
=cg+i
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes192.sha1.mdc.s2k1.z0

jAwECAECruOfyNDFiTnSRAEVoGXm4A9UZKkWljdzjEO/iaE7mIraltIpQMkiqCh9
7h8uZ2u9uRBOv222fZodGvc6bvq/4R4hAa/6qSHtm8mdmvGt
=aHmC
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes192.sha1.mdc.s2k3.z0

jA0ECAMCjFn6SRi3SONg0kQBqtSHPaD0m7rXfDAhCWU/ypAsI93GuHGRyM99cvMv
q6eF6859ZVnli3BFSDSk3a4e/pXhglxmDYCfjAXkozKNYLo6yw==
=K0LS
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes256.sha1.mdc.s2k0.z0

jAQECQAC0kQB4L1eMbani07XF2ZYiXNK9LW3v8w41oUPl7dStmrJPQFwsdxmrDHu
rQr3WbdKdY9ufjOE5+mXI+EFkSPrF9rL9NCq6w==
=RGts
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes256.sha1.mdc.s2k1.z0

jAwECQECKHhrou7ZOIXSRAHWIVP+xjVQcjAVBTt+qh9SNzYe248xFTwozkwev3mO
+KVJW0qhk0An+Y2KF99/bYFl9cL5D3Tl43fC8fXGl3x3m7pR
=SUrU
-----END PGP MESSAGE-----
'), 'foobar');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes256.sha1.mdc.s2k3.z0

jA0ECQMCjc8lwZu8Fz1g0kQBkEzjImi21liep5jj+3dAJ2aZFfUkohi8b3n9z+7+
4+NRzL7cMW2RLAFnJbiqXDlRHMwleeuLN1up2WIxsxtYYuaBjA==
=XZrG
-----END PGP MESSAGE-----
'), 'foobar');

-- Checking longer passwords
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCx6dBiuqrYNRg0kQBEo63AvA1SCslxP7ayanLf1H0/hlk2nONVhTwVEWi
tTGup1mMz6Cfh1uDRErUuXpx9A0gdMu7zX0o5XjrL7WGDAZdSw==
=XKKG
-----END PGP MESSAGE-----
'), '0123456789abcdefghij');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCBDvYuS990iFg0kQBW31UK5OiCjWf5x6KJ8qNNT2HZWQCjCBZMU0XsOC6
CMxFKadf144H/vpoV9GA0f22keQgCl0EsTE4V4lweVOPTKCMJg==
=gWDh
-----END PGP MESSAGE-----
'), '0123456789abcdefghij2jk4h5g2j54khg23h54g2kh54g2khj54g23hj54');

select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCqXbFafC+ofVg0kQBejyiPqH0QMERVGfmPOjtAxvyG5KDIJPYojTgVSDt
FwsDabdQUz5O7bgNSnxfmyw1OifGF+W2bIn/8W+0rDf8u3+O+Q==
=OxOF
-----END PGP MESSAGE-----
'), 'x');

-- Checking various data
select encode(digest(pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat1.aes.sha1.mdc.s2k3.z0

jA0EBwMCGJ+SpuOysINg0kQBJfSjzsW0x4OVcAyr17O7FBvMTwIGeGcJd99oTQU8
Xtx3kDqnhUq9Z1fS3qPbi5iNP2A9NxOBxPWz2JzxhydANlgbxg==
=W/ik
-----END PGP MESSAGE-----
'), '0123456789abcdefghij'), 'sha1'), 'hex');
-- expected: 0225e3ede6f2587b076d021a189ff60aad67e066

select encode(digest(pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat2.aes.sha1.mdc.s2k3.z0

jA0EBwMCvdpDvidNzMxg0jUBvj8eS2+1t/9/zgemxvhtc0fvdKGGbjH7dleaTJRB
SaV9L04ky1qECNDx3XjnoKLC+H7IOQ==
=Fxen
-----END PGP MESSAGE-----
'), '0123456789abcdefghij'), 'sha1'), 'hex');
-- expected: da39a3ee5e6b4b0d3255bfef95601890afd80709

select encode(digest(pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: dat3.aes.sha1.mdc.s2k3.z0

jA0EBwMCxQvxJZ3G/HRg0lgBeYmTa7/uDAjPyFwSX4CYBgpZWVn/JS8JzILrcWF8
gFnkUKIE0PSaYFp+Yi1VlRfUtRQ/X/LYNGa7tWZS+4VQajz2Xtz4vUeAEiYFYPXk
73Hb8m1yRhQK
=ivrD
-----END PGP MESSAGE-----
'), '0123456789abcdefghij'), 'sha1'), 'hex');
-- expected: 5e5c135efc0dd00633efc6dfd6e731ea408a5b4c

-- Checking CRLF
select encode(digest(pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: crlf mess

ww0ECQMCt7VAtby6l4Bi0lgB5KMIZiiF/b3CfMfUyY0eDncsGXtkbu1X+l9brjpMP8eJnY79Amms
a3nsOzKTXUfS9VyaXo8IrncM6n7fdaXpwba/3tNsAhJG4lDv1k4g9v8Ix2dfv6Rs
=mBP9
-----END PGP MESSAGE-----
'), 'key', 'convert-crlf=0'), 'sha1'), 'hex');
-- expected: 9353062be7720f1446d30b9e75573a4833886784

select encode(digest(pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----
Comment: crlf mess

ww0ECQMCt7VAtby6l4Bi0lgB5KMIZiiF/b3CfMfUyY0eDncsGXtkbu1X+l9brjpMP8eJnY79Amms
a3nsOzKTXUfS9VyaXo8IrncM6n7fdaXpwba/3tNsAhJG4lDv1k4g9v8Ix2dfv6Rs
=mBP9
-----END PGP MESSAGE-----
'), 'key', 'convert-crlf=1'), 'sha1'), 'hex');
-- expected: 7efefcab38467f7484d6fa43dc86cf5281bd78e2

-- check BUG #11905, problem with messages 6 less than a power of 2.
select pgp_sym_decrypt(pgp_sym_encrypt(repeat('x',65530),'1'),'1') = repeat('x',65530);
-- expected: true


-- Negative tests

-- Decryption with a certain incorrect key yields an apparent Literal Data
-- packet reporting its content to be binary data.  Ciphertext source:
-- iterative pgp_sym_encrypt('secret', 'key') until the random prefix gave
-- rise to that property.
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----

ww0EBwMCxf8PTrQBmJdl0jcB6y2joE7GSLKRv7trbNsF5Z8ou5NISLUg31llVH/S0B2wl4bvzZjV
VsxxqLSPzNLAeIspJk5G
=mSd/
-----END PGP MESSAGE-----
'), 'wrong-key', 'debug=1');

-- Routine text/binary mismatch.
select pgp_sym_decrypt(pgp_sym_encrypt_bytea('P', 'key'), 'key', 'debug=1');

-- Decryption with a certain incorrect key yields an apparent BZip2-compressed
-- plaintext.  Ciphertext source: iterative pgp_sym_encrypt('secret', 'key')
-- until the random prefix gave rise to that property.
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----

ww0EBwMC9rK/dMkF5Zlt0jcBlzAQ1mQY2qYbKYbw8h3EZ5Jk0K2IiY92R82TRhWzBIF/8cmXDPtP
GXsd65oYJZp3Khz0qfyn
=Nmpq
-----END PGP MESSAGE-----
'), 'wrong-key', 'debug=1');

-- Routine use of BZip2 compression.  Ciphertext source:
-- echo x | gpg --homedir /nonexistent --personal-compress-preferences bzip2 \
--      --personal-cipher-preferences aes --no-emit-version --batch \
--      --symmetric --passphrase key --armor
select pgp_sym_decrypt(dearmor('
-----BEGIN PGP MESSAGE-----

jA0EBwMCRhFrAKNcLVJg0mMBLJG1cCASNk/x/3dt1zJ+2eo7jHfjgg3N6wpB3XIe
QCwkWJwlBG5pzbO5gu7xuPQN+TbPJ7aQ2sLx3bAHhtYb0i3vV9RO10Gw++yUyd4R
UCAAw2JRIISttRHMfDpDuZJpvYo=
=AZ9M
-----END PGP MESSAGE-----
'), 'key', 'debug=1');
