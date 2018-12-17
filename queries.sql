/* Code to populate the tables with my parsed files

SET CLIENT_ENCODING TO 'utf8';

CREATE TABLE Ratings(userid NUMERIC, movieid NUMERIC, rating DOUBLE PRECISION, timestamp NUMERIC);
COPY ratings FROM 'C:/Users/claire/project/ratings.txt' DELIMITER ':';

CREATE TABLE movies(movieid NUMERIC, title TEXT, year NUMERIC);
COPY movies FROM 'C:/Users/claire/project/movies.csv' CSV HEADER;

CREATE TABLE tags(userid NUMERIC, movieid NUMERIC, tag TEXT, time NUMERIC);
COPY tags FROM 'C:/Users/claire/project/tags.csv' CSV HEADER;

CREATE TABLE users(userid NUMERIC PRIMARY KEY);
INSERT INTO users SELECT DISTINCT userid FROM ratings;
INSERT INTO users SELECT DISTINCT userid FROM tags ON CONFLICT DO NOTHING;

CREATE TABLE has_genre(movieid NUMERIC, genre TEXT);
COPY has_genre FROM 'C:/Users/claire/project/hasGenres.csv' CSV HEADER;

CREATE TABLE Genres(title TEXT);
INSERT INTO Genres SELECT DISTINCT genre FROM has_genre ORDER BY genre; */

/* Size of the tables */

SELECT count(*) FROM genres;

SELECT count(*) FROM movies;

SELECT count(*) FROM ratings;

SELECT count(*) FROM tags;

SELECT count(*) FROM users;

SELECT count(*) FROM has_genre;

/* Get distribution of movies over the decades */

SELECT dist_group, count(*)
FROM
(
SELECT case when year between 1910 and 1919 then '(1910-1919)'
when year between 1920 and 1929 then '(1920-1929)'
when year between 1930 and 1939 then '(1930-1939)'
when year between 1940 and 1949 then '(1940-1949)'
when year between 1950 and 1959 then '(1950-1959)'
when year between 1960 and 1969 then '(1960-1969)'
when year between 1970 and 1979 then '(1970-1979)'
when year between 1980 and 1989 then '(1980-1989)'
when year between 1990 and 1999 then '(1990-1999)'
when year between 2000 and 2009 then '(2000-2009)'
end AS dist_group
FROM movies
) t
GROUP BY dist_group
ORDER BY dist_group ASC;

/* alternative query for the above results */
SELECT concat(floor(year/10), 0, '-', floor(year/10), 9) AS decade, count(*)
FROM movies GROUP BY 1 ORDER BY 1 ASC;

/* Get distribution of movies per genre */

SELECT genre, count(genre)
FROM has_genre
GROUP BY genre
ORDER BY genre ASC;

/* Get distribution of ratings */

SELECT rating, count(rating)
FROM ratings
GROUP BY rating
ORDER BY rating ASC;

/* No tags, but the have ratings */

SELECT count(movieid) FROM movies
WHERE movieid
NOT IN (SELECT DISTINCT movieid FROM tags)
AND movieid IN (SELECT DISTINCT movieid FROM ratings);

/* No ratings, but they have tags */

SELECT count(movieid) FROM movies
WHERE movieid
IN (SELECT DISTINCT movieid FROM tags WHERE movieid NOT IN (SELECT DISTINCT movieid FROM ratings));

/* No tags and no ratings */

SELECT count(movieid) FROM movies
WHERE movieid
NOT IN (SELECT DISTINCT movieid FROM ratings) AND movieid NOT IN (SELECT DISTINCT movieid FROM tags);

/* Both ratings and tags */

SELECT count(movieid) FROM movies
WHERE movieid IN ((SELECT DISTINCT movieid FROM ratings) INTERSECT (SELECT DISTINCT movieid FROM tags));

/* Most reviewed movie */

SELECT movies.movieid, title, count_ratings
FROM movies
JOIN (SELECT count(*) AS count_ratings, movieid FROM ratings GROUP BY movieid ORDER BY count_ratings DESC LIMIT 1) t
ON movies.movieid = t.movieid;

/* Highest rated movie */

SELECT movies.movieid, title, count
FROM movies
JOIN (SELECT movieid, count(*) AS count FROM ratings WHERE rating = 5 GROUP BY movieid ORDER BY count DESC LIMIT 1) t
ON movies.movieid = t.movieid;

/* Movies associated with at least 4 genres */

SELECT count(*)
FROM (SELECT count(genre) AS genre_count FROM has_genre GROUP BY movieid) t
WHERE genre_count >= 4;

/* Most popular genre */

SELECT genre, count(genre)
FROM has_genre
GROUP BY genre
ORDER BY count DESC LIMIT 1;

/* Genres with more high ratings than low ratings*/

SELECT genre, high_ratings, low_ratings FROM
((SELECT genre,count(*) AS high_ratings FROM has_genre NATURAL JOIN ratings WHERE rating >= 4 GROUP BY genre) AS high
NATURAL JOIN
(SELECT genre,count(*) AS low_ratings FROM has_genre NATURAL JOIN ratings WHERE rating < 4 GROUP BY genre) AS low)
WHERE high_ratings > low_ratings;

/* Genres with more old than new movies */
SELECT genre, recent, old FROM
((SELECT genre,count(*) AS recent FROM has_genre NATURAL JOIN movies WHERE year >= 2000 GROUP BY genre) AS recent
NATURAL JOIN
(SELECT genre,count(*) AS old FROM has_genre NATURAL JOIN movies WHERE year < 2000 GROUP BY genre) AS old)
WHERE recent > old;

/* Create ratings_with_diff table */

DROP TABLE IF EXISTS ratings_with_diff;

CREATE TABLE ratings_with_diff AS TABLE ratings;
ALTER TABLE ratings_with_diff ADD COLUMN avg_rating DOUBLE PRECISION;
ALTER TABLE ratings_with_diff ADD COLUMN difference DOUBLE PRECISION;

/* Helper table - avg_ratings, populate with averages by movie */

DROP TABLE IF EXISTS avg_ratings;
CREATE TABLE avg_ratings(movieid NUMERIC, avg_rating DOUBLE PRECISION);
INSERT INTO avg_ratings SELECT movieid, AVG(rating) AS avg_rating FROM ratings GROUP BY movieid;

/* Insert averages into ratings_with_diff */

UPDATE ratings_with_diff SET avg_rating = avg_ratings.avg_rating
FROM avg_ratings
WHERE ratings_with_diff.movieid = avg_ratings.movieid;

/* Find difference */

UPDATE ratings_with_diff SET difference = rating - avg_rating;

/* Update ratings where |difference| > 3 */

UPDATE ratings_with_diff r
SET rating = (SELECT avg_rating FROM avg_ratings WHERE r.movieid = avg_ratings.movieid)
WHERE @difference > 3;

/* Make new table with new averages */
DROP TABLE IF EXISTS avg_ratings2;
CREATE TABLE avg_ratings2(movieid NUMERIC, avg_rating DOUBLE PRECISION);
INSERT INTO avg_ratings2 SELECT movieid, AVG(rating) AS avg_rating FROM ratings_with_diff GROUP BY movieid;

/* Update ratings_with_diff with new averages */
UPDATE ratings_with_diff
SET avg_rating = avg_ratings2.avg_rating
FROM avg_ratings2
WHERE ratings_with_diff.movieid = avg_ratings2.movieid;

/* Find new difference */

UPDATE ratings_with_diff SET difference = rating - avg_rating;

/* Second update ratings where |difference| > 3 */

UPDATE ratings_with_diff r
SET rating = (SELECT avg_rating FROM avg_ratings2 WHERE r.movieid = avg_ratings2.movieid)
WHERE @difference > 3;

/* Find 10 most biased movies */

SELECT movieid, title, original, debiased, @original-debiased AS bias FROM
(SELECT movieid, title FROM movies) t1
NATURAL JOIN
(SELECT movieid, avg_rating AS original FROM avg_ratings) t2
NATURAL JOIN
(SELECT movieid, AVG(rating) AS debiased FROM ratings_with_diff GROUP BY movieid) t3
ORDER BY bias DESC LIMIT 10;

/* Find most biased user - approach #1 */

SELECT userid, count(*) FROM
(SELECT userid, movieid, rating AS original FROM ratings_with_diff) t1
NATURAL JOIN
(SELECT userid, movieid, rating AS debiased FROM ratings) t2
WHERE original <> debiased
GROUP BY userid
ORDER BY count(*) DESC
LIMIT 1;

/* Find most biased user - approach #2 */

SELECT userid, original, debiased, @original-debiased AS bias FROM
(SELECT userid, AVG(rating) AS original FROM ratings GROUP BY userid) t2
NATURAL JOIN
(SELECT userid, AVG(rating) AS debiased FROM ratings_with_diff GROUP BY userid) t3
ORDER BY bias DESC LIMIT 1;