-- AmPGa - an Amiga 4-channel mod player for PostgreSQL
--
-- Copyright (C) 2017 Chen Thread
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to
-- deal in the Software without restriction, including without limitation the
-- rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
-- sell copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
-- IN THE SOFTWARE.

-- vim: sts=2:sw=2:et:syntax=pgsql:
-- Clean up database
drop table if exists ampga_mod_samples;
drop table if exists ampga_mod_pattern_cells;
drop table if exists ampga_mod_orders;

-- Create tables
create table ampga_mod_samples (
    id int primary key not null,
    smp_name text not null,
    smp_len int not null,
    smp_ft int not null,
    smp_vol int not null,
    smp_lpbeg int not null,
    smp_lplen int not null,
    smp_data bytea not null);
create table ampga_mod_pattern_cells (
    id serial primary key not null,
    pat_idx int not null,
    pat_row int not null,
    pat_col int not null,
    pat_period int not null,
    pat_sample_id int not null,
    pat_eff_type int not null,
    pat_eff_val int not null);
create table ampga_mod_orders (
    id int primary key not null,
    pattern_id int not null);

-- Create indexes
-- (probably slightly overkill here)
create index ampga_mod_pattern_by_idx
  on ampga_mod_pattern_cells
  (pat_idx);
create index ampga_mod_pattern_by_row
  on ampga_mod_pattern_cells
  (pat_idx, pat_row);

--
-- FUNCTIONS
--
drop function if exists ampga_intern_read_str(instr bytea);
create or replace function ampga_intern_read_str(instr bytea) returns text as $$
  declare
    s text;
    c int;
    i int;
  begin
    s := '';
    for i in 0..(octet_length(instr)-1) loop
      c := get_byte(instr, i);
      if c >= 32 and c < 127 then
        s := s || chr(c);
      end if;
    end loop;
    return s;
  end
$$ language plpgsql;

drop function if exists ampga_play_mod(fname text, mixfreq int);
create or replace function ampga_play_mod(fname text, mixfreq int) returns setof bytea as $$
  declare
    r record;
    r2 ampga_mod_samples;

    i int not null default 0;
    j int not null default 0;
    k int not null default 0;
    u int not null default 0;
    v int not null default 0;
    acc int;
    outbuf bytea;
    outbuf_len int;
    outbuf_len_prev int;

    time_limiter int;

    -- Data
    fdata bytea;
    order_count int;
    pattern_count int;

    -- Runtime
    mod_speed int;
    mod_tempo int;
    mod_tick int;
    mod_ord int;
    mod_pat int;
    mod_row int;
    mod_new_row int;

    -- Channels
    chn_smp int[4];
    chn_offs int[4];
    chn_suboffs int[4];
    chn_per int[4];
    chn_freq int[4];
    chn_vol int[4];
    chn_len int[4];
    chn_lplen int[4];
    chn_data ampga_mod_samples[4];

    -- Pattern cells
    l_pat_period int;
    l_pat_sample_id int;
    l_pat_eff_type int;
    l_pat_eff_val int;
  begin
    -- Read file
    fdata := (select pg_read_binary_file(fname));
    raise notice 'File length: % bytes', octet_length(fdata);
    raise notice 'Mod name: "%"',
      ampga_intern_read_str(substring(fdata from 1 for 20));
    raise notice '';
    raise notice 'Creating tables!';
    raise notice '';

    -- Clear tables
    delete from ampga_mod_samples;
    delete from ampga_mod_pattern_cells;
    delete from ampga_mod_orders;

    -- Read order table
    --
    for i in 0..127 loop
      insert into ampga_mod_orders (id, pattern_id)
        values (i, get_byte(fdata, 20+30*31+2+i));
    end loop;

    -- Get order count
    order_count := get_byte(fdata, 20+30*31+0);

    -- Calculate pattern count
    pattern_count := (select max(pattern_id) from ampga_mod_orders)+1;
    raise notice 'Order count: %', order_count;
    raise notice 'Pattern count: %', pattern_count;

    -- Calculate start of sample data
    acc := 20+(30*31)+2+128+4 + ((64*4*4)*pattern_count);

    -- Read sample info
    --
    --  0..21: Name
    -- 22..23: Length (in 2-byte words)
    --     24: Finetune
    --     25: Volume
    -- 26..27: Loop start (in 2-byte words)
    -- 28..29: Loop length (1 = no loop) (in 2-byte words)
    --
    -- All big-endian.
    --
    -- We predouble everything here.
    --
    for i in 0..30 loop
      j := ((get_byte(fdata, 20+30*i+22)<<8) + get_byte(fdata, 20+30*i+23))*2;
      insert into ampga_mod_samples
          (id, smp_name, smp_len, smp_ft, smp_vol, smp_lpbeg, smp_lplen, smp_data)
        values (
          i+1,
          ampga_intern_read_str(substring(fdata from (1+20+30*i) for 22)),
          ((get_byte(fdata, 20+30*i+22)<<8) + get_byte(fdata, 20+30*i+23))*2,
          get_byte(fdata, 20+30*i+24),
          get_byte(fdata, 20+30*i+25),
          ((get_byte(fdata, 20+30*i+26)<<8) + get_byte(fdata, 20+30*i+27))*2,
          ((get_byte(fdata, 20+30*i+28)<<8) + get_byte(fdata, 20+30*i+29))*2,
          substring(fdata from (acc+1) for j));
      acc := acc + j;
    end loop;
    for i in 0..30 loop
      raise notice 'Sample % header: %', i+1,
        substring(fdata from (1+20+30*i) for 30);
    end loop;

    -- Read pattern data
    acc := 20+(30*31)+2+128+4;
    for i in 0..pattern_count loop
      for j in 0..63 loop
        for k in 0..3 loop
          insert into ampga_mod_pattern_cells
              (pat_idx, pat_row, pat_col,
                pat_period, pat_sample_id, pat_eff_type, pat_eff_val)
            values (i, j, k+1,
              ((get_byte(fdata, acc+0)<<8) + get_byte(fdata, acc+1)) & 4095,
              (get_byte(fdata, acc+0) & 16) + (get_byte(fdata, acc+2)>>4),
              (get_byte(fdata, acc+2) & 15),
              (get_byte(fdata, acc+3)));
          acc := acc + 4;
        end loop;
      end loop;
    end loop;

    -- Prepare runtime
    mod_speed := 6;
    mod_tempo := 125;
    mod_tick := 0;
    mod_ord := -1;
    mod_pat := 0;
    mod_row := 64;
    mod_new_row := 64;

    -- Prepare channels
    chn_smp[1] := 0; chn_smp[2] := 0; chn_smp[3] := 0; chn_smp[4] := 0;
    chn_offs[1] := -1; chn_offs[2] := -1; chn_offs[3] := -1; chn_offs[4] := -1;
    chn_suboffs[1] := 0; chn_suboffs[2] := 0; chn_suboffs[3] := 0; chn_suboffs[4] := 0;
    chn_per[1] := 0; chn_per[2] := 0; chn_per[3] := 0; chn_per[4] := 0;
    chn_freq[1] := 0; chn_freq[2] := 0; chn_freq[3] := 0; chn_freq[4] := 0;
    chn_vol[1] := 0; chn_vol[2] := 0; chn_vol[3] := 0; chn_vol[4] := 0;

    --
    -- BEGIN MAIN LOOP
    --
    outbuf_len_prev := -1;

    --for time_limiter in 0..(6*64*256) loop
    for time_limiter in 0..(6*64*8) loop

      -- Handle next tick
      if mod_tick <= 0 then
        mod_tick := mod_speed-1;

        --
        -- TICK 0 LOGIC
        --

        -- Fetch new row
        mod_row := mod_new_row;
        if mod_row >= 64 then
          mod_row := 0;

          -- Fetch new pattern
          mod_ord := mod_ord + 1;
          if mod_ord >= order_count then
            mod_ord := 0;
          end if;

          mod_pat := (select pattern_id
            from ampga_mod_orders
            where id = mod_ord
            limit 1);
        end if;
        mod_new_row := mod_row + 1;

        -- Actually fetch said row
        for r in (select pat_col, pat_period, pat_sample_id, pat_eff_type, pat_eff_val
              from ampga_mod_pattern_cells
              where pat_idx = mod_pat
                and pat_row = mod_row) loop
          l_pat_period := r.pat_period;
          l_pat_sample_id := r.pat_sample_id;
          l_pat_eff_type := r.pat_eff_type;
          l_pat_eff_val := r.pat_eff_val;
          j := r.pat_col;

          -- TODO: make this logic not suck
          if l_pat_period <> 0 and l_pat_sample_id <> 0 then
            chn_smp[j] := l_pat_sample_id;
            chn_per[j] := l_pat_period;
            chn_offs[j] := 0;

            --raise notice 'load sample % for channel %', l_pat_sample_id, j;
            for r2 in (select *
                from ampga_mod_samples
                where id = l_pat_sample_id
                limit 1) loop

              chn_data[j] := r2;
              -- TODO: factor in loop start
              chn_len[j] := r2.smp_len;
              chn_lplen[j] := r2.smp_lplen;
              chn_vol[j] := r2.smp_vol;
            end loop;

            chn_vol[j] := coalesce(chn_vol[j], 64);
          elsif l_pat_sample_id <> 0 then
            for r2 in (select *
                from ampga_mod_samples
                where id = l_pat_sample_id
                limit 1) loop

              -- TODO: recall what happens when the sample number changes
              chn_vol[j] := r2.smp_vol;
            end loop;

            chn_vol[j] := coalesce(chn_vol[j], 64);
          end if;

          -- TODO: more than just this hack
          case l_pat_eff_type
            when 12 then
              chn_vol[j] := l_pat_eff_val;
              if chn_vol[j] > 64 then
                chn_vol[j] := 64;
              end if;
            when 13 then
              mod_new_row := 64;
            else
              mod_row := mod_row;
          end case;
        end loop;

      else
        mod_tick := mod_tick - 1;

        --
        -- OTHER TICK LOGIC
        --
        for r in (select pat_col, pat_period, pat_sample_id, pat_eff_type, pat_eff_val
              from ampga_mod_pattern_cells
              where pat_idx = mod_pat
                and pat_row = mod_row) loop
          l_pat_period := r.pat_period;
          l_pat_sample_id := r.pat_sample_id;
          l_pat_eff_type := r.pat_eff_type;
          l_pat_eff_val := r.pat_eff_val;
          j := r.pat_col;

          case l_pat_eff_type
            when 10 then
              if (l_pat_eff_val & 15) = 0 then
                chn_vol[j] := chn_vol[j] + (l_pat_eff_val >> 4);
                if chn_vol[j] > 64 then
                  chn_vol[j] := 64;
                end if;
              elsif (l_pat_eff_val >> 4) = 0 then
                chn_vol[j] := chn_vol[j] - (l_pat_eff_val & 15);
                if chn_vol[j] < 0 then
                  chn_vol[j] := 0;
                end if;
              end if;
            else
              mod_row := mod_row;
          end case;
        end loop;

      end if;

      -- Reset output buffer if necessary
      outbuf_len := mixfreq*10/(mod_tempo*4);
      if outbuf_len <> outbuf_len_prev then
        outbuf := E'';
        for i in 0..(outbuf_len - 1) loop
          outbuf := outbuf || E'\\000';
        end loop;
        outbuf_len_prev := outbuf_len;
      end if;

      -- Calculate channel frequencies
      for j in 1..4 loop
        -- Skip various cases
        continue when chn_smp[j] = 0;
        continue when chn_per[j] = 0;

        chn_freq[j] = (8363*428)/chn_per[j];
        chn_freq[j] = (4096*chn_freq[j])/mixfreq;
      end loop;

      -- Fill output buffer
      for i in 0..(outbuf_len - 1) loop
        v := 0;

        -- Mix each channel
        for j in 1..4 loop
          -- Skip various cases
          continue when chn_smp[j] = 0;
          continue when chn_per[j] = 0;
          continue when chn_offs[j] = -1;

          u := coalesce(get_byte(chn_data[j].smp_data, chn_offs[j]),0);
          v := v + (((u+128)&255)-128)*coalesce(chn_vol[j], 64);
          chn_suboffs[j] := chn_suboffs[j] + chn_freq[j];
          chn_offs[j] := chn_offs[j] + (chn_suboffs[j]>>12);
          chn_suboffs[j] := chn_suboffs[j] & 4095;
          if chn_offs[j] >= chn_len[j] then
            if chn_lplen[j] > 2 then
              chn_offs[j] := chn_offs[j] - chn_lplen[j];
              if chn_offs[j] >= chn_len[j] or chn_offs[j] < 0 then
                chn_offs[j] := -1;
              end if;
            else
              chn_offs[j] := -1;
            end if;
          end if;
        end loop;

        -- Clamp
        v := v / 100;
        v := v + 128;
        if v > 255 then v = 255; end if;
        if v < 0   then v = 0  ; end if;

        -- Set byte
        outbuf := set_byte(outbuf, i, v);
      end loop;

      -- Output!
      return next outbuf;
    end loop;

  end
$$ language plpgsql;

