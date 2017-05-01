#!/bin/sh
cc -O3 -g -o filter-output filter-output.c && \
cat ampga.pgsql | docker exec -i sql psql && \
docker exec -i sql psql -A -t -1 -c "copy (select * from ampga_play_mod('starmem.mod', 48000)) to stdout;" | ./filter-output | ffmpeg -v 0 -f u8 -ar 48000 -ac 1 -i - -f wav - 2>/dev/null | play -twav - 2>/dev/null

#docker exec -i sql psql -A -t -1 -c "copy (select * from ampga_play_mod('test.mod', 48000)) to stdout;" | ./filter-output >donk.raw


#docker exec -i sql psql -A -t -1 -c "copy (select * from ampga_play_mod('test.mod', 48000)) to stdout;" | ./filter-output | ffmpeg -v 0 -f u8 -ar 48000 -ac 1 -i - -f wav -acodec pcm_u8 - 2>/dev/null >donk.wav
#docker exec -i sql psql -A -t -1 -c "do \$\$ begin perform ampga_load_mod('test.mod'); end \$\$ language plpgsql;"
#docker exec -i sql psql -A -t -1 -c "copy (select * from ampga_play_mod(0, 48000)) to stdout;" | ffmpeg -f u8 -ar 48000 -ac 1 -i - -f wav - | play -twav -

