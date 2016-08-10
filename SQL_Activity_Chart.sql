----------------------------------------
--SQL Activity Chart.
--Version 1.0.1
--Copyright (C) 2016. This program is licensed under the LGPLv3.
--
--How to use:
--  1. Change sample times and time_chunks in the "configuration" table below
--  2. Run the query and view results in a fixed-width font.
--This query may take a while to finish, depending on the time period.
----------------------------------------
with configuration as
(
	select
		timestamp '2016-06-21 12:00:00' sample_start_time,
		timestamp '2016-06-21 16:00:00' sample_end_time,
		100 time_chunks
	from dual
)
----------------------------------------
--(Do not change anything below this line)
select chart
from
(
	--#1: Header.
	select -5 interval_number, 'SQL Activity chart.' chart from dual union all
	select -4 interval_number, 'Generated for '||(select global_name from global_name)||' on '||to_char(sysdate, 'YYYY-MM-DD HH24:MI')||'.' chart from dual union all
	select -3 interval_number, '' chart from dual union all
	select -2 interval_number, '  Sample Period    SQL (one case-sensitive letter per active session, see SQL Key at bottom)' chart from dual union all
	select -1 interval_number, '                 ---------------------------------------------------------------' chart from dual
	union all
	--#2: Chart.
	select time_intervals.interval_number, to_char(begin_time, 'YYYY-MM-DD HH24:MI') || ' | ' || letters chart
	from
	(
		--Time intervals.
		select
			min_begin, max_end
			,min_begin + ((level-1) * time_interval) begin_time
			,min_begin + ((level) * time_interval) - interval '1' second end_time
			,level interval_number, samples_per_interval
		from
		(
			--Times and chunk size.
			select
				max(end_interval_time) max_end,
				min(begin_interval_time) min_begin,
				(max(end_interval_time) - min(begin_interval_time)) / max((select time_chunks from configuration)) time_interval,
				(cast(max(end_interval_time) as date) - cast(min(begin_interval_time) as date))
				/ max((select time_chunks from configuration)) /*chunks*/ *24*60*60 /*convert to seconds*/ / 10 /*sample every 10 seconds*/ samples_per_interval,
				max((select time_chunks from configuration)) time_chunks
			from dba_hist_snapshot
			where begin_interval_time between (select sample_start_time from configuration) and (select sample_end_time from configuration)
		) times
		connect by level <= time_chunks
	) time_intervals
	left join
	(
		--Events per interval.
		select interval_number, listagg(letter) within group (order by letter) letters
		from
		(
			--Combine letters and OTHER.
			select
				interval_number, min_begin, max_end, begin_time, end_time, username, sql_id, sql_text, counts_per_user_and_sql, event_counts,
				case
					when is_other = 0 then round(avg_events_per_sample)
					when is_other = 1 then unrepresented_sessions
				end avg_events_per_sample,
				case
					when is_other = 0 then letter
					when is_other = 1 then '~'
				end letter
			from
			(
				--Add "OTHER" logic.
				select
					interval_number, min_begin, max_end, begin_time, end_time, average_events.username, average_events.sql_id, sql_text, counts_per_user_and_sql, event_counts,
					letter,avg_events_per_sample,
					--Total activity minus activity that is represented by a letter and has more than 0.5 average events per sample. 
					round
					(
						sum(avg_events_per_sample) over (partition by interval_number)
						-
						sum(case when avg_events_per_sample >= 0.5 and letter is not null then round(avg_events_per_sample) else 0 end) over (partition by interval_number)
					) unrepresented_sessions,
					case when avg_events_per_sample < 0.5 or letter is null then 1 else 0 end is_other,
					row_number() over (partition by interval_number order by case when avg_events_per_sample < 0.5 or letter is null then 0 else 1 end, 1) other_rownumber
					--DEBUG
					--average_events.*, sql_key.*
				from
				(
					--Average events per sample.
					select min_begin, max_end, begin_time, end_time, interval_number, username, sql_id
						,count(*) / samples_per_interval avg_events_per_sample
					from
					(
						--Time intervals.
						select /*+ cardinality(50) */
							min_begin, max_end
							,min_begin + ((level-1) * time_interval) begin_time
							,min_begin + ((level) * time_interval) - interval '1' second end_time
							,level interval_number, samples_per_interval
						from
						(
							--Times and chunk size.
							select
								max(end_interval_time) max_end,
								min(begin_interval_time) min_begin,
								(max(end_interval_time) - min(begin_interval_time)) / max((select time_chunks from configuration)) time_interval,
								(cast(max(end_interval_time) as date) - cast(min(begin_interval_time) as date))
								/ max((select time_chunks from configuration)) /*chunks*/ *24*60*60 /*convert to seconds*/ / 10 /*sample every 10 seconds*/ samples_per_interval,
								max((select time_chunks from configuration)) time_chunks
							from dba_hist_snapshot
							where begin_interval_time between (select sample_start_time from configuration) and (select sample_end_time from configuration)
						) times
						connect by level <= time_chunks
					) time_intervals
					left join
					(
						--Events
						select username, sql_id, sample_time
						from dba_hist_active_sess_history
						join dba_users on dba_hist_active_sess_history.user_id = dba_users.user_id
						where dbid = (select dbid from v$database) --For the partition pruning.
							and snap_id in
							(
								select /*+ cardinality(24) */ snap_id
								from dba_hist_snapshot
								where begin_interval_time between (select sample_start_time from configuration) and (select sample_end_time from configuration)
							)
							and sql_id is not null
					) events
						on events.sample_time between time_intervals.begin_time and time_intervals.end_time
					group by min_begin, max_end, begin_time, end_time, interval_number, username, sql_id, samples_per_interval
					order by interval_number
				) average_events
				left join
				(
					--SQL Key - sums and key for the top 52 SQL IDs.
					--Top user and SQL, with text, counts, and a KEY letter
					select rownumber, letter, username, count_per_user_sql_w_rownum.sql_id, cast(substr(sql_text, 1, 100) as varchar2(100)) sql_text, counts_per_user_and_sql, event_counts
					from
					(
						--Count per user and SQL, with rownum
						select username, sql_id, event_counts, counts_per_user_and_sql, rownum rownumber
						from
						(
							--Count per user and SQL.
							select username, sql_id
								,listagg(event||' ('||event_count||')', ',') within group (order by event_count desc) event_counts
								,sum(event_count) counts_per_user_and_sql
							from
							(
								--Count per user, SQL, and event.
								select username, sql_id, nvl(event, 'CPU') event, count(*) event_count
								from dba_hist_active_sess_history
								join dba_users on dba_hist_active_sess_history.user_id = dba_users.user_id
								where dbid = (select dbid from v$database)
									and snap_id in
									(
										select /*+ cardinality(24) */ snap_id
										from dba_hist_snapshot
										where begin_interval_time between (select sample_start_time from configuration) and (select sample_end_time from configuration)
									)
									and sql_id is not null
								group by username, sql_id, event
							) count_per_user_sql_event
							group by username, sql_id
							order by counts_per_user_and_sql desc
						) count_per_user_sql
					) count_per_user_sql_w_rownum
					join
					(
						--Letters.
						select /*+ cardinality(52) */
							level letter_number,
							chr(64+case when level <= 26 then level else level + 6 end) letter
						from dual
						connect by level <= 52
					) letters
						on count_per_user_sql_w_rownum.rownumber = letters.letter_number
					left join
					(
						select sql_id, sql_text
						from dba_hist_sqltext
						where dbid = (select dbid from v$database)
					) sqltext
						on count_per_user_sql_w_rownum.sql_id = sqltext.sql_id
				) sql_key
					on average_events.username = sql_key.username
					and average_events.sql_id = sql_key.sql_id
				order by interval_number
			) add_others
			--Include the regular rows and only one of the "OTHER" rows.
			where is_other = 0 or (is_other = 1 and other_rownumber = 1)
		) combine_letter_and_other
		join
		(
			--Duplicator.
			--H: Isn't that your transmogrifier?
			--C: It WAS. But I made some modifications. See, the box is on its side now. It's a duplicator!
			select level duplicator_number
			from dual
			--Realistically there will never be more than 200 events per sample.
			connect by level <= 200
		)
			on avg_events_per_sample >= duplicator_number
		group by interval_number
	) events_per_interval
		on time_intervals.interval_number = events_per_interval.interval_number
	----------------------------------------
	union all
	--#3: Key header.
	select 10001 interval_number, '                 ---------------------------------------------------------------' chart from dual union all
	select 10002 interval_number, '' chart from dual union all
	select 10003 interval_number, 'SQL Key - Statements are ordered by most active first' chart from dual union all
	select 10004 interval_number, '==============================================================================================================================================================================================================================================================================' chart from dual union all
	select 10005 interval_number, '| ID| Username                       | SQL_ID        | SQL Text                                           | Samples | Sample counts per event  (ordered by most common events first)                                                                                         |' chart from dual union all
	select 10006 interval_number, '==============================================================================================================================================================================================================================================================================' chart from dual
	----------------------------------------
	union all
	--#4: Key.
	select
		20000 + rownumber interval_number
		,'| '||letter||' | '||rpad(username, 30, ' ')||' | '||sql_id||' | '||rpad(replace(replace(replace(nvl(sql_text, ' '), chr(10), null), chr(13), null), chr(9), ' '), 50, ' ')||' | '||nvl(lpad(counts_per_user_and_sql, 7, ' '), '       ')||' | '||rpad(event_counts, 150, ' ')||' |' chart
	from
	(
		--SQL Key - sums and key for the top 52 SQL IDs.
		--Top user and SQL, with text, counts, and a KEY letter
		select rownumber, letter, username, count_per_user_sql_w_rownum.sql_id, cast(substr(sql_text, 1, 1000) as varchar2(1000)) sql_text, counts_per_user_and_sql, event_counts
		from
		(
			--Count per user and SQL, with rownum
			select username, sql_id, event_counts, counts_per_user_and_sql, rownum rownumber
			from
			(
				--Count per user and SQL.
				select username, sql_id
					,listagg(event||' ('||event_count||')', ',') within group (order by event_count desc) event_counts
					,sum(event_count) counts_per_user_and_sql
				from
				(
					--Count per user, SQL, and event.
					select username, sql_id, nvl(event, 'CPU') event, count(*) event_count
					from dba_hist_active_sess_history
					join dba_users on dba_hist_active_sess_history.user_id = dba_users.user_id
					where dbid = (select dbid from v$database)
						and snap_id in
						(
							select /*+ cardinality(24) */ snap_id
							from dba_hist_snapshot
							where begin_interval_time between (select sample_start_time from configuration) and (select sample_end_time from configuration)
						)
						and sql_id is not null
					group by username, sql_id, event
				) count_per_user_sql_event
				group by username, sql_id
				order by counts_per_user_and_sql desc
			) count_per_user_sql
		) count_per_user_sql_w_rownum
		join
		(
			--Letters.
			select /*+ cardinality(52) */
				level letter_number,
				chr(64+case when level <= 26 then level else level + 6 end) letter
			from dual
			connect by level <= 52
		) letters
			on count_per_user_sql_w_rownum.rownumber = letters.letter_number
		left join
		(
			select sql_id, sql_text
			from dba_hist_sqltext
			where dbid = (select dbid from v$database)
		) sqltext
			on count_per_user_sql_w_rownum.sql_id = sqltext.sql_id
		--Add "OTHER" statements.
		union all
		select 999 rownumber, '~' letter, 'other' username, 'other        ' sql_id
			,'activity not caused by one of the Top N queries' SQL_TEXT, null counts_per_user_and_sql, ' ' event_counts
		from dual
	) sql_key
	----------------------------------------
	union all
	--#5: Key footer.
	select 30000 interval_number, '==============================================================================================================================================================================================================================================================================' chart from dual
)
order by interval_number;
