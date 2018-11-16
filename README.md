SQL Activity Chart - 1.2.0
============

SQL Activity Chart is an Oracle SQL query that displays all SQL activity for a database for a configurable amount of time.  It's sort of a cross between an AWR report and an ASH report.

The text-only format makes it less pretty than other tuning tools.  But the text format also allows it to fit much more data on a single page, and makes it easier to share.


##Example##

The example below shows all the sections and features.  Reports are usually a few hundred lines long.  For brevity, some of the large sections with "`...`".


    SQL Activity chart.

    Generated for TESTDB on 2016-06-21 16:18.
    
      Sample Period    SQL (one case-sensitive letter per active session, see SQL Key at bottom)
                     ---------------------------------------------------------------
    2016-06-21 12:00 | AAAAAAAB
    2016-06-21 12:03 | AAAAAA
    2016-06-21 12:05 | AC
    2016-06-21 12:08 | D
    2016-06-21 12:10 | D~           
    ...
    2016-06-21 15:57 | A
                     ---------------------------------------------------------------
    
    SQL Key - Statements are ordered by most active first
    =================================================================================================================================================================
    | ID| Username | SQL_ID        | SQL Text                                           | Samples | Sample counts per event  (ordered by most common events first)  |
    =================================================================================================================================================================
    | A | ALICE    | gwnkpgwbyfmuc | UPDATE  /*+ parallel(4) */ ALICE.SOME_TABLE ...    |    1364 | CPU (1364)                                                      |
    | B | BOB      | 7nwq7d737vgj4 | INSERT INTO BOB.SOME_TABLE ...                     |      22 | CPU (16),db file sequential read (6)                            |
    | C | ALICE    | 1qngyg2nhh7b2 | SELECT /*+ parallel(4)*/ SUM(BYTES) AS TOTAL_BYTES |      20 | db file sequential read (17),CPU (3)                            |
    | D | SYS      | 196mqnmxgxpv1 | select ...                                         |      17 | control file sequential read (15),CPU (2)                       |
    ...
    | ~ | other    | other         | activity not caused by one of the Top N queries    |         |                                                                 |
    =================================================================================================================================================================


## How to Install and Run

Copy and paste the entire query into an IDE.  Modify the time stamps and the number of time chunks in the configuration table at the top of the query.  Run the whole query and view the results in a fixed-width editor.


## License
This program is licensed under the LGPLv3.
