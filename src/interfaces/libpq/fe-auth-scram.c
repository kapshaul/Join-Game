/*-------------------------------------------------------------------------
 *
 * fe-auth-scram.c
 *	   The front-end (client) implementation of SCRAM authentication.
 *
 * Portions Copyright (c) 1996-2018, PostgreSQL Global Development Group
 * Portions Copyright (c) 1994, Regents of the University of California
 *
 * IDENTIFICATION
 *	  src/interfaces/libpq/fe-auth-scram.c
 *
 *-------------------------------------------------------------------------
 */

#include "postgres_fe.h"

#include "common/base64.h"
#include "common/saslprep.h"
#include "common/scram-common.h"
#include "fe-auth.h"

/* These are needed for getpid(), in the fallback implementation */
#ifndef HAVE_STRONG_RANDOM
#include <sys/types.h>
#include <unistd.h>
#endif

/*
 * Status of exchange messages used for SCRAM authentication via the
 * SASL protocol.
 */
typedef enum
{
	FE_SCRAM_INIT,
	FE_SCRAM_NONCE_SENT,
	FE_SCRAM_PROOF_SENT,
	FE_SCRAM_FINISHED
} fe_scram_state_enum;

typedef struct
{
	fe_scram_state_enum state;

	/* These are supplied by the user */
	PGconn	   *conn;
	char	   *password;
	char	   *sasl_mechanism;

	/* We construct these */
	uint8		SaltedPassword[SCRAM_KEY_LEN];
	char	   *client_nonce;
	char	   *client_first_message_bare;
	char	   *client_final_message_without_proof;

	/* These come from the server-first message */
	char	   *server_first_message;
	char	   *salt;
	int			saltlen;
	int			iterations;
	char	   *nonce;

	/* These come from the server-final message */
	char	   *server_final_message;
	char		ServerSignature[SCRAM_KEY_LEN];
} fe_scram_state;

static bool read_server_first_message(fe_scram_state *state, char *input);
static bool read_server_final_message(fe_scram_state *state, char *input);
static char *build_client_first_message(fe_scram_state *state);
static char *build_client_final_message(fe_scram_state *state);
static bool verify_server_signature(fe_scram_state *state);
static void calculate_client_proof(fe_scram_state *state,
					   const char *client_final_message_without_proof,
					   uint8 *result);
static bool pg_frontend_random(char *dst, int len);

/*
 * Initialize SCRAM exchange status.
 */
void *
pg_fe_scram_init(PGconn *conn,
				 const char *password,
				 const char *sasl_mechanism)
{
	fe_scram_state *state;
	char	   *prep_password;
	pg_saslprep_rc rc;

	Assert(sasl_mechanism != NULL);

	state = (fe_scram_state *) malloc(sizeof(fe_scram_state));
	if (!state)
		return NULL;
	memset(state, 0, sizeof(fe_scram_state));
	state->conn = conn;
	state->state = FE_SCRAM_INIT;
	state->sasl_mechanism = strdup(sasl_mechanism);

	if (!state->sasl_mechanism)
	{
		free(state);
		return NULL;
	}

	/* Normalize the password with SASLprep, if possible */
	rc = pg_saslprep(password, &prep_password);
	if (rc == SASLPREP_OOM)
	{
		free(state->sasl_mechanism);
		free(state);
		return NULL;
	}
	if (rc != SASLPREP_SUCCESS)
	{
		prep_password = strdup(password);
		if (!prep_password)
		{
			free(state->sasl_mechanism);
			free(state);
			return NULL;
		}
	}
	state->password = prep_password;

	return state;
}

/*
 * Free SCRAM exchange status
 */
void
pg_fe_scram_free(void *opaq)
{
	fe_scram_state *state = (fe_scram_state *) opaq;

	if (state->password)
		free(state->password);
	if (state->sasl_mechanism)
		free(state->sasl_mechanism);

	/* client messages */
	if (state->client_nonce)
		free(state->client_nonce);
	if (state->client_first_message_bare)
		free(state->client_first_message_bare);
	if (state->client_final_message_without_proof)
		free(state->client_final_message_without_proof);

	/* first message from server */
	if (state->server_first_message)
		free(state->server_first_message);
	if (state->salt)
		free(state->salt);
	if (state->nonce)
		free(state->nonce);

	/* final message from server */
	if (state->server_final_message)
		free(state->server_final_message);

	free(state);
}

/*
 * Exchange a SCRAM message with backend.
 */
void
pg_fe_scram_exchange(void *opaq, char *input, int inputlen,
					 char **output, int *outputlen,
					 bool *done, bool *success)
{
	fe_scram_state *state = (fe_scram_state *) opaq;
	PGconn	   *conn = state->conn;

	*done = false;
	*success = false;
	*output = NULL;
	*outputlen = 0;

	/*
	 * Check that the input length agrees with the string length of the input.
	 * We can ignore inputlen after this.
	 */
	if (state->state != FE_SCRAM_INIT)
	{
		if (inputlen == 0)
		{
			printfPQExpBuffer(&conn->errorMessage,
							  libpq_gettext("malformed SCRAM message (empty message)\n"));
			goto error;
		}
		if (inputlen != strlen(input))
		{
			printfPQExpBuffer(&conn->errorMessage,
							  libpq_gettext("malformed SCRAM message (length mismatch)\n"));
			goto error;
		}
	}

	switch (state->state)
	{
		case FE_SCRAM_INIT:
			/* Begin the SCRAM handshake, by sending client nonce */
			*output = build_client_first_message(state);
			if (*output == NULL)
				goto error;

			*outputlen = strlen(*output);
			*done = false;
			state->state = FE_SCRAM_NONCE_SENT;
			break;

		case FE_SCRAM_NONCE_SENT:
			/* Receive salt and server nonce, send response. */
			if (!read_server_first_message(state, input))
				goto error;

			*output = build_client_final_message(state);
			if (*output == NULL)
				goto error;

			*outputlen = strlen(*output);
			*done = false;
			state->state = FE_SCRAM_PROOF_SENT;
			break;

		case FE_SCRAM_PROOF_SENT:
			/* Receive server signature */
			if (!read_server_final_message(state, input))
				goto error;

			/*
			 * Verify server signature, to make sure we're talking to the
			 * genuine server.  XXX: A fake server could simply not require
			 * authentication, though.  There is currently no option in libpq
			 * to reject a connection, if SCRAM authentication did not happen.
			 */
			if (verify_server_signature(state))
				*success = true;
			else
			{
				*success = false;
				printfPQExpBuffer(&conn->errorMessage,
								  libpq_gettext("incorrect server signature\n"));
			}
			*done = true;
			state->state = FE_SCRAM_FINISHED;
			break;

		default:
			/* shouldn't happen */
			printfPQExpBuffer(&conn->errorMessage,
							  libpq_gettext("invalid SCRAM exchange state\n"));
			goto error;
	}
	return;

error:
	*done = true;
	*success = false;
	return;
}

/*
 * Read value for an attribute part of a SCRAM message.
 */
static char *
read_attr_value(char **input, char attr, PQExpBuffer errorMessage)
{
	char	   *begin = *input;
	char	   *end;

	if (*begin != attr)
	{
		printfPQExpBuffer(errorMessage,
						  libpq_gettext("malformed SCRAM message (attribute \"%c\" expected)\n"),
						  attr);
		return NULL;
	}
	begin++;

	if (*begin != '=')
	{
		printfPQExpBuffer(errorMessage,
						  libpq_gettext("malformed SCRAM message (expected character \"=\" for attribute \"%c\")\n"),
						  attr);
		return NULL;
	}
	begin++;

	end = begin;
	while (*end && *end != ',')
		end++;

	if (*end)
	{
		*end = '\0';
		*input = end + 1;
	}
	else
		*input = end;

	return begin;
}

/*
 * Build the first exchange message sent by the client.
 */
static char *
build_client_first_message(fe_scram_state *state)
{
	PGconn	   *conn = state->conn;
	char		raw_nonce[SCRAM_RAW_NONCE_LEN + 1];
	char	   *result;
	int			channel_info_len;
	int			encoded_len;
	PQExpBufferData buf;

	/*
	 * Generate a "raw" nonce.  This is converted to ASCII-printable form by
	 * base64-encoding it.
	 */
	if (!pg_frontend_random(raw_nonce, SCRAM_RAW_NONCE_LEN))
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("could not generate nonce\n"));
		return NULL;
	}

	state->client_nonce = malloc(pg_b64_enc_len(SCRAM_RAW_NONCE_LEN) + 1);
	if (state->client_nonce == NULL)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("out of memory\n"));
		return NULL;
	}
	encoded_len = pg_b64_encode(raw_nonce, SCRAM_RAW_NONCE_LEN, state->client_nonce);
	state->client_nonce[encoded_len] = '\0';

	/*
	 * Generate message.  The username is left empty as the backend uses the
	 * value provided by the startup packet.  Also, as this username is not
	 * prepared with SASLprep, the message parsing would fail if it includes
	 * '=' or ',' characters.
	 */

	initPQExpBuffer(&buf);

	/*
	 * First build the gs2-header with channel binding information.
	 */
	if (strcmp(state->sasl_mechanism, SCRAM_SHA_256_PLUS_NAME) == 0)
	{
		Assert(conn->ssl_in_use);
		appendPQExpBuffer(&buf, "p=tls-server-end-point");
	}
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
	else if (conn->ssl_in_use)
	{
		/*
		 * Client supports channel binding, but thinks the server does not.
		 */
		appendPQExpBuffer(&buf, "y");
	}
#endif
	else
	{
		/*
		 * Client does not support channel binding.
		 */
		appendPQExpBuffer(&buf, "n");
	}

	if (PQExpBufferDataBroken(buf))
		goto oom_error;

	channel_info_len = buf.len;

	appendPQExpBuffer(&buf, ",,n=,r=%s", state->client_nonce);
	if (PQExpBufferDataBroken(buf))
		goto oom_error;

	/*
	 * The first message content needs to be saved without channel binding
	 * information.
	 */
	state->client_first_message_bare = strdup(buf.data + channel_info_len + 2);
	if (!state->client_first_message_bare)
		goto oom_error;

	result = strdup(buf.data);
	if (result == NULL)
		goto oom_error;

	termPQExpBuffer(&buf);
	return result;

oom_error:
	termPQExpBuffer(&buf);
	printfPQExpBuffer(&conn->errorMessage,
					  libpq_gettext("out of memory\n"));
	return NULL;
}

/*
 * Build the final exchange message sent from the client.
 */
static char *
build_client_final_message(fe_scram_state *state)
{
	PQExpBufferData buf;
	PGconn	   *conn = state->conn;
	uint8		client_proof[SCRAM_KEY_LEN];
	char	   *result;

	initPQExpBuffer(&buf);

	/*
	 * Construct client-final-message-without-proof.  We need to remember it
	 * for verifying the server proof in the final step of authentication.
	 *
	 * The channel binding flag handling (p/y/n) must be consistent with
	 * build_client_first_message(), because the server will check that it's
	 * the same flag both times.
	 */
	if (strcmp(state->sasl_mechanism, SCRAM_SHA_256_PLUS_NAME) == 0)
	{
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
		char	   *cbind_data = NULL;
		size_t		cbind_data_len = 0;
		size_t		cbind_header_len;
		char	   *cbind_input;
		size_t		cbind_input_len;

		/* Fetch hash data of server's SSL certificate */
		cbind_data =
			pgtls_get_peer_certificate_hash(state->conn,
											&cbind_data_len);
		if (cbind_data == NULL)
		{
			/* error message is already set on error */
			termPQExpBuffer(&buf);
			return NULL;
		}

		appendPQExpBuffer(&buf, "c=");

		/* p=type,, */
		cbind_header_len = strlen("p=tls-server-end-point,,");
		cbind_input_len = cbind_header_len + cbind_data_len;
		cbind_input = malloc(cbind_input_len);
		if (!cbind_input)
		{
			free(cbind_data);
			goto oom_error;
		}
		memcpy(cbind_input, "p=tls-server-end-point,,", cbind_header_len);
		memcpy(cbind_input + cbind_header_len, cbind_data, cbind_data_len);

		if (!enlargePQExpBuffer(&buf, pg_b64_enc_len(cbind_input_len)))
		{
			free(cbind_data);
			free(cbind_input);
			goto oom_error;
		}
		buf.len += pg_b64_encode(cbind_input, cbind_input_len, buf.data + buf.len);
		buf.data[buf.len] = '\0';

		free(cbind_data);
		free(cbind_input);
#else
		/*
		 * Chose channel binding, but the SSL library doesn't support it.
		 * Shouldn't happen.
		 */
		termPQExpBuffer(&buf);
		printfPQExpBuffer(&conn->errorMessage,
						  "channel binding not supported by this build\n");
		return NULL;
#endif							/* HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH */
	}
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
	else if (conn->ssl_in_use)
		appendPQExpBuffer(&buf, "c=eSws");	/* base64 of "y,," */
#endif
	else
		appendPQExpBuffer(&buf, "c=biws");	/* base64 of "n,," */

	if (PQExpBufferDataBroken(buf))
		goto oom_error;

	appendPQExpBuffer(&buf, ",r=%s", state->nonce);
	if (PQExpBufferDataBroken(buf))
		goto oom_error;

	state->client_final_message_without_proof = strdup(buf.data);
	if (state->client_final_message_without_proof == NULL)
		goto oom_error;

	/* Append proof to it, to form client-final-message. */
	calculate_client_proof(state,
						   state->client_final_message_without_proof,
						   client_proof);

	appendPQExpBuffer(&buf, ",p=");
	if (!enlargePQExpBuffer(&buf, pg_b64_enc_len(SCRAM_KEY_LEN)))
		goto oom_error;
	buf.len += pg_b64_encode((char *) client_proof,
							 SCRAM_KEY_LEN,
							 buf.data + buf.len);
	buf.data[buf.len] = '\0';

	result = strdup(buf.data);
	if (result == NULL)
		goto oom_error;

	termPQExpBuffer(&buf);
	return result;

oom_error:
	termPQExpBuffer(&buf);
	printfPQExpBuffer(&conn->errorMessage,
					  libpq_gettext("out of memory\n"));
	return NULL;
}

/*
 * Read the first exchange message coming from the server.
 */
static bool
read_server_first_message(fe_scram_state *state, char *input)
{
	PGconn	   *conn = state->conn;
	char	   *iterations_str;
	char	   *endptr;
	char	   *encoded_salt;
	char	   *nonce;

	state->server_first_message = strdup(input);
	if (state->server_first_message == NULL)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("out of memory\n"));
		return false;
	}

	/* parse the message */
	nonce = read_attr_value(&input, 'r',
							&conn->errorMessage);
	if (nonce == NULL)
	{
		/* read_attr_value() has generated an error string */
		return false;
	}

	/* Verify immediately that the server used our part of the nonce */
	if (strlen(nonce) < strlen(state->client_nonce) ||
		memcmp(nonce, state->client_nonce, strlen(state->client_nonce)) != 0)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("invalid SCRAM response (nonce mismatch)\n"));
		return false;
	}

	state->nonce = strdup(nonce);
	if (state->nonce == NULL)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("out of memory\n"));
		return false;
	}

	encoded_salt = read_attr_value(&input, 's', &conn->errorMessage);
	if (encoded_salt == NULL)
	{
		/* read_attr_value() has generated an error string */
		return false;
	}
	state->salt = malloc(pg_b64_dec_len(strlen(encoded_salt)));
	if (state->salt == NULL)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("out of memory\n"));
		return false;
	}
	state->saltlen = pg_b64_decode(encoded_salt,
								   strlen(encoded_salt),
								   state->salt);
	if (state->saltlen < 0)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("malformed SCRAM message (invalid salt)\n"));
		return false;
	}

	iterations_str = read_attr_value(&input, 'i', &conn->errorMessage);
	if (iterations_str == NULL)
	{
		/* read_attr_value() has generated an error string */
		return false;
	}
	state->iterations = strtol(iterations_str, &endptr, 10);
	if (*endptr != '\0' || state->iterations < 1)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("malformed SCRAM message (invalid iteration count)\n"));
		return false;
	}

	if (*input != '\0')
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("malformed SCRAM message (garbage at end of server-first-message)\n"));

	return true;
}

/*
 * Read the final exchange message coming from the server.
 */
static bool
read_server_final_message(fe_scram_state *state, char *input)
{
	PGconn	   *conn = state->conn;
	char	   *encoded_server_signature;
	char	   *decoded_server_signature;
	int			server_signature_len;

	state->server_final_message = strdup(input);
	if (!state->server_final_message)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("out of memory\n"));
		return false;
	}

	/* Check for error result. */
	if (*input == 'e')
	{
		char	   *errmsg = read_attr_value(&input, 'e',
											 &conn->errorMessage);

		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("error received from server in SCRAM exchange: %s\n"),
						  errmsg);
		return false;
	}

	/* Parse the message. */
	encoded_server_signature = read_attr_value(&input, 'v',
											   &conn->errorMessage);
	if (encoded_server_signature == NULL)
	{
		/* read_attr_value() has generated an error message */
		return false;
	}

	if (*input != '\0')
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("malformed SCRAM message (garbage at end of server-final-message)\n"));

	server_signature_len = pg_b64_dec_len(strlen(encoded_server_signature));
	decoded_server_signature = malloc(server_signature_len);
	if (!decoded_server_signature)
	{
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("out of memory\n"));
		return false;
	}

	server_signature_len = pg_b64_decode(encoded_server_signature,
										 strlen(encoded_server_signature),
										 decoded_server_signature);
	if (server_signature_len != SCRAM_KEY_LEN)
	{
		free(decoded_server_signature);
		printfPQExpBuffer(&conn->errorMessage,
						  libpq_gettext("malformed SCRAM message (invalid server signature)\n"));
		return false;
	}
	memcpy(state->ServerSignature, decoded_server_signature, SCRAM_KEY_LEN);
	free(decoded_server_signature);

	return true;
}

/*
 * Calculate the client proof, part of the final exchange message sent
 * by the client.
 */
static void
calculate_client_proof(fe_scram_state *state,
					   const char *client_final_message_without_proof,
					   uint8 *result)
{
	uint8		StoredKey[SCRAM_KEY_LEN];
	uint8		ClientKey[SCRAM_KEY_LEN];
	uint8		ClientSignature[SCRAM_KEY_LEN];
	int			i;
	scram_HMAC_ctx ctx;

	/*
	 * Calculate SaltedPassword, and store it in 'state' so that we can reuse
	 * it later in verify_server_signature.
	 */
	scram_SaltedPassword(state->password, state->salt, state->saltlen,
						 state->iterations, state->SaltedPassword);

	scram_ClientKey(state->SaltedPassword, ClientKey);
	scram_H(ClientKey, SCRAM_KEY_LEN, StoredKey);

	scram_HMAC_init(&ctx, StoredKey, SCRAM_KEY_LEN);
	scram_HMAC_update(&ctx,
					  state->client_first_message_bare,
					  strlen(state->client_first_message_bare));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->server_first_message,
					  strlen(state->server_first_message));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  client_final_message_without_proof,
					  strlen(client_final_message_without_proof));
	scram_HMAC_final(ClientSignature, &ctx);

	for (i = 0; i < SCRAM_KEY_LEN; i++)
		result[i] = ClientKey[i] ^ ClientSignature[i];
}

/*
 * Validate the server signature, received as part of the final exchange
 * message received from the server.
 */
static bool
verify_server_signature(fe_scram_state *state)
{
	uint8		expected_ServerSignature[SCRAM_KEY_LEN];
	uint8		ServerKey[SCRAM_KEY_LEN];
	scram_HMAC_ctx ctx;

	scram_ServerKey(state->SaltedPassword, ServerKey);

	/* calculate ServerSignature */
	scram_HMAC_init(&ctx, ServerKey, SCRAM_KEY_LEN);
	scram_HMAC_update(&ctx,
					  state->client_first_message_bare,
					  strlen(state->client_first_message_bare));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->server_first_message,
					  strlen(state->server_first_message));
	scram_HMAC_update(&ctx, ",", 1);
	scram_HMAC_update(&ctx,
					  state->client_final_message_without_proof,
					  strlen(state->client_final_message_without_proof));
	scram_HMAC_final(expected_ServerSignature, &ctx);

	if (memcmp(expected_ServerSignature, state->ServerSignature, SCRAM_KEY_LEN) != 0)
		return false;

	return true;
}

/*
 * Build a new SCRAM verifier.
 */
char *
pg_fe_scram_build_verifier(const char *password)
{
	char	   *prep_password;
	pg_saslprep_rc rc;
	char		saltbuf[SCRAM_DEFAULT_SALT_LEN];
	char	   *result;

	/*
	 * Normalize the password with SASLprep.  If that doesn't work, because
	 * the password isn't valid UTF-8 or contains prohibited characters, just
	 * proceed with the original password.  (See comments at top of file.)
	 */
	rc = pg_saslprep(password, &prep_password);
	if (rc == SASLPREP_OOM)
		return NULL;
	if (rc == SASLPREP_SUCCESS)
		password = (const char *) prep_password;

	/* Generate a random salt */
	if (!pg_frontend_random(saltbuf, SCRAM_DEFAULT_SALT_LEN))
	{
		if (prep_password)
			free(prep_password);
		return NULL;
	}

	result = scram_build_verifier(saltbuf, SCRAM_DEFAULT_SALT_LEN,
								  SCRAM_DEFAULT_ITERATIONS, password);

	if (prep_password)
		free(prep_password);

	return result;
}

/*
 * Random number generator.
 */
static bool
pg_frontend_random(char *dst, int len)
{
#ifdef HAVE_STRONG_RANDOM
	return pg_strong_random(dst, len);
#else
	int			i;
	char	   *end = dst + len;

	static unsigned short seed[3];
	static int	mypid = 0;

	pglock_thread();

	if (mypid != getpid())
	{
		struct timeval now;

		gettimeofday(&now, NULL);

		seed[0] = now.tv_sec ^ getpid();
		seed[1] = (unsigned short) (now.tv_usec);
		seed[2] = (unsigned short) (now.tv_usec >> 16);
	}

	for (i = 0; dst < end; i++)
	{
		uint32		r;
		int			j;

		/*
		 * pg_jrand48 returns a 32-bit integer.  Fill the next 4 bytes from
		 * it.
		 */
		r = (uint32) pg_jrand48(seed);

		for (j = 0; j < 4 && dst < end; j++)
		{
			*(dst++) = (char) (r & 0xFF);
			r >>= 8;
		}
	}

	pgunlock_thread();

	return true;
#endif
}
