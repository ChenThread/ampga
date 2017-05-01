#include <assert.h>
#include <string.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <errno.h>

int outval4(void)
{
	int v = fgetc(stdin);
	if(v == -1) {
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

int outval16(void)
{
	int v1 = outval8();
	int v0 = outval8();
	return (v1<<8)|v0;
}

int outval32(void)
{
	int v1 = outval16();
	int v0 = outval16();
	return (v1<<16)|v0;
}

int main(int argc, char *argv[])
{
	for(;;) {
		fputc(outval8()&0xFF, stdout);
	}
	return 0;
}
