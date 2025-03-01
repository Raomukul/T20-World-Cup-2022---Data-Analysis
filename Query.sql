-- 1. Top Run-Scorers: Identify the top 10 batsmen with the highest total runs scored across all matches.
SELECT batsmanName, SUM(runs) AS run
FROM batting_summary_cleaned
GROUP BY batsmanName
ORDER BY run DESC 
LIMIT 10;

-- this is giving only 42 rows data but total matches are 45 in the world cup so 3 matches a washed out due to rain without a ball bowled those are:
-- New Zealand vs Afghanistan - This match was abandoned without a ball bowled.
-- Afghanistan vs Ireland - match abandoned without a ball bowled.
-- England vs Australia - match abandoned without a ball bowled

-- 2. Best Bowling Economy: Find bowlers with the lowest economy rate across all matches.
SELECT bowlerName,
ROUND((SUM(runs) / NULLIF(SUM(overs), 0)),2)AS economy_rate
FROM bowling_summary_cleaned 
GROUP BY bowlerName
ORDER BY economy_rate ASC
LIMIT 10;

-- 3. **Frequent Boundaries**: List players who scored the most fours and sixes.
SELECT batsmanName, SUM(4s) AS fours,SUM(6s) AS sixes 
FROM batting_summary_cleaned 
GROUP BY batsmanName
ORDER BY fours DESC,sixes DESC 
LIMIT 10

-- 4. **Match Winners**: Count the number of matches won by each team.
SELECT winner, COUNT(*) AS wins
FROM match_summary_cleaned
WHERE winner NOT IN ( 'abandoned','no result')
GROUP BY winner
ORDER BY wins DESC

-- 5. **Player Roles**: Display the total number of players in each playing role (e.g., Wicketkeeper, Allrounder).
SELECT playingRole, COUNT(name) total_players
FROM player_information
GROUP BY playingRole
ORDER BY total_players DESC
-- TO update the wicketkeeper
SET SQL_SAFE_UPDATES = 0;

UPDATE player_information
SET playingRole = 'Wicketkeeper Batter'
WHERE playingRole = 'Wicketkeeper';

SET SQL_SAFE_UPDATES = 1;

-- 6. **High Strike Rate Batsmen**: Find batsmen with the highest strike rate who have faced at least 50 balls in total.
SELECT batsmanName,ROUND((SUM(runs)/SUM(balls))*100,2) AS strike
FROM batting_summary_cleaned
GROUP BY batsmanName
HAVING SUM(balls)>50
ORDER BY strike DESC
LIMIT 10;

-- 7. **Consistent Bowlers**: List bowlers with the highest number of maidens and their corresponding teams.
SELECT bowlerName,bowlingTeam,SUM(maiden) AS maiden_overs
FROM bowling_summary_cleaned
GROUP BY bowlerName,bowlingTeam
HAVING SUM(maiden)>0
ORDER BY maiden_overs DESC

-- 8. **Team Margin of Victory**: Identify the largest margin of victory by runs and by wickets for each team.
SELECT winner AS team,
       COALESCE(MAX(CASE WHEN margin LIKE '%runs' THEN CAST(SUBSTRING_INDEX(margin, ' ', 1) AS UNSIGNED) END), 0) AS largest_run_margin,
       COALESCE(MAX(CASE WHEN margin LIKE '%wickets' THEN CAST(SUBSTRING_INDEX(margin, ' ', 1) AS UNSIGNED) END), 0) AS largest_wicket_margin
FROM match_summary_cleaned
WHERE winner NOT IN ('abandoned', 'no result')
GROUP BY winner
ORDER BY team;

-- 9. **Player's Contribution in Wins**: For each match-winning team,
-- find the batsman with the highest runs and the bowler with the most wickets.
WITH topbatsman AS (
	SELECT match_id,teamInnings AS team,batsmanName,MAX(runs) AS highest_run
    FROM batting_summary_cleaned 
    GROUP BY match_id,team,batsmanName
),
distinct_batsman AS (
	SELECT match_id,team,batsmanName,highest_run,
    ROW_NUMBER() OVER(PARTITION BY match_id,team ORDER BY highest_run DESC) as rn
    FROM topbatsman
),
topbowler AS (
	SELECT match_id,bowlingTeam AS team,bowlerName,MAX(wickets) AS highest_wicket
    FROM bowling_summary_cleaned 
    GROUP BY match_id,team,bowlerName
),
distinct_topbowler AS (
    SELECT match_id, team, bowlerName, highest_wicket,
           ROW_NUMBER() OVER (PARTITION BY match_id, team ORDER BY highest_wicket DESC) AS row_num
    FROM topbowler
)
SELECT m.match_id,m.winner,tb.batsmanName,tb.highest_run,tw.bowlerName,tw.highest_wicket
FROM match_summary_cleaned AS m
LEFT JOIN distinct_batsman AS tb 
ON m.match_id=tb.match_id AND m.winner=tb.team AND rn=1
LEFT JOIN distinct_topbowler tw 
ON m.match_id=tw.match_id AND m.winner=tw.team AND row_num=1
WHERE m.winner NOT IN ('abandoned','no result')
ORDER BY m.match_id

-- 10. **Bowling and Batting Average Comparison**: Calculate each player's batting average (total runs divided by innings) 
-- and bowling average (runs conceded divided by wickets taken) to find all-rounders.
WITH battingaverage AS (
	SELECT batsmanName AS player,
    SUM(runs) AS total_runs,
    COUNT(*) as innings,
    ROUND(SUM(runs)/NULLIF(COUNT(*),0),2) as batting_average
    FROM batting_summary_cleaned
    GROUP BY player
),
bowlingaverage AS (
	SELECT bowlerName AS player,
    SUM(runs),
    SUM(wickets),
    ROUND(SUM(runs)/NULLIF(SUM(wickets),0),2) AS bowling_average
    FROM bowling_summary_cleaned
    GROUP BY player
)

SELECT b.player,b.batting_average,ba.bowling_average
FROM battingaverage AS b 
JOIN bowlingaverage AS ba 
ON b.player=ba.player
ORDER BY batting_average DESC, bowling_average ASC


-- 11. **Performance by Match Venue**: Analyze which players perform the best at different grounds 
-- based on runs scored and wickets taken.

WITH batperformance AS (
	SELECT m.ground AS maidaan,b.batsmanName AS player, sum(b.runs) AS run
    FROM batting_summary_cleaned AS b 
    JOIN match_summary_cleaned AS m 
    ON b.match_id=m.match_id
    GROUP BY m.ground,b.batsmanName
),
bestbat AS (
	SELECT maidaan,player,run, row_number() over(partition by maidaan order by run desc) as rn
    FROM batperformance 
),
bowlperformance AS (
	SELECT m.ground AS maidaan,bo.bowlerName AS player, SUM(wickets) AS wick
    FROM bowling_summary_cleaned AS bo
    JOIN match_summary_cleaned AS m 
    ON bo.match_id=m.match_id
    GROUP BY maidaan,player 
),
bestbowl AS (
	SELECT maidaan, player, wick, row_number() over(partition by maidaan order by wick DESC) as ren
    FROM bowlperformance 
)

SELECT bba.maidaan AS GROUND,bba.player AS BATSMAN,bba.run,bbo.player AS BOWLER,bbo.wick AS WICKETS
FROM bestbat bba
JOIN bestbowl AS bbo
ON bba.maidaan=bbo.maidaan
WHERE rn=1 AND ren=1

-- 12. **Player Performance in High-Stakes Matches**: Identify players who perform better in high-stakes matches 
-- (e.g., finals or elimination rounds) by calculating average runs and wickets in these matches.
WITH batter AS (
	SELECT teamInnings AS team,batsmanName,AVG(runs) as run_scored
    FROM batting_summary_cleaned 
    JOIN match_summary_cleaned as m
    ON batting_summary_cleaned.match_id=m.match_id
    WHERE STR_TO_DATE(m.matchDate, '%b %d, %Y') >= '2022-11-09'
    GROUP BY team,batsmanName
),
bestbatter AS (
	SELECT team,batsmanName,run_scored,ROW_NUMBER() OVER(PARTITION BY team ORDER BY run_scored DESC) AS rn
    FROM batter 
    
),
bowler AS (
	SELECT bowlingTeam AS team,bowlerName,AVG(wickets) AS wickets_taken
    FROM bowling_summary_cleaned
    JOIN match_summary_cleaned as m
    ON bowling_summary_cleaned.match_id=m.match_id
    WHERE STR_TO_DATE(m.matchDate, '%b %d, %Y') >= '2022-11-09'
    GROUP BY team,bowlerName
   
),
bestbowler AS (
	SELECT team,bowlerName,wickets_taken,ROW_NUMBER() OVER(PARTITION BY team ORDER BY wickets_taken DESC) AS ren
    FROM bowler
)
SELECT bb.team,bb.bowlerName,bb.wickets_taken,
bba.batsmanName,bba.run_scored
FROM bestbowler AS bb 
JOIN bestbatter AS bba
ON bb.team=bba.team
WHERE rn=1 AND ren=1





















