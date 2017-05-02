#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <errno.h>

#include <libpq-fe.h>

PGconn *conn = NULL;

int outval4(void)
{
	int v = fgetc(stdin);
	if(v == -1) {
		PQfinish(conn);
		exit(0);
	}
	while(v == '\\' || v == 'x' || v == '\r' || v == '\n') {
		v = fgetc(stdin);
	}
	if(v >= '0' && v <= '9') {
		return v - '0';
	} else {
		return ((v - 'a')+10)&15;
	}
}

int outval8(void)
{
	int v1 = outval4();
	int v0 = outval4();
	return (v1<<4)|v0;
}

int main(int argc, char *argv[])
{
	// Connect
	conn = PQconnectdb("postgresql://postgres@localhost:5432");
	assert(conn != NULL);

	// Pipe to stdout
	int is_dispatched = PQsendQueryParams(conn,
		"select * from ampga_play_mod('test.mod', 48000);",
		0,
		NULL,
		NULL,
		NULL,
		NULL,
		1);

	assert(is_dispatched == 1);
	int is_single_row = PQsetSingleRowMode(conn);
	assert(is_single_row == 1);
	for(;;) {
		// Get next result
		PGresult *result = PQgetResult(conn);
		if(result == NULL) {
			break;
		}

		ExecStatusType err_exec = PQresultStatus(result);
		//fprintf(stderr, "%s\n", PQresStatus(err_exec));
		if(err_exec == PGRES_TUPLES_OK) {
			continue;
		}

		// Read row
		int rowlen = PQgetlength(result, 0, 0);
		assert(rowlen > 0);
		const uint8_t *pbuf = PQgetvalue(result, 0, 0);

		// Write row
		fwrite(pbuf, 1, rowlen, stdout);

		//fputc(outval8()&0xFF, stdout);
		PQclear(result);
	}

	// Clean up
	PQfinish(conn);
	return 0;
}

