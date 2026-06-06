-- ref: https://github.com/Eagoes/SparkSQL-SSB
create database ssb;
use ssb;


-- input format: txt
drop table ssb.`customer_txt` purge;
drop table ssb.`part_txt` purge;
drop table ssb.`supplier_txt` purge;
drop table ssb.`date_txt` purge;
drop table ssb.`lineorder_txt` purge;


CREATE TABLE ssb.`customer_txt`(
  `c_customerkey` INT,
  `c_name` STRING,
  `c_address` STRING,
  `c_city` STRING,
  `c_nation` STRING,
  `c_region` STRING,
  `c_phone` STRING,
  `c_mktsegment` STRING
) ROW FORMAT DELIMITED FIELDS TERMINATED BY '|';


CREATE TABLE ssb.`part_txt`(
  `p_partkey` INT,
  `p_name` STRING,
  `p_mfgr` STRING,
  `p_category` STRING,
  `p_brand` STRING,
  `p_colour` STRING,
  `p_type` STRING,
  `p_size` INT,
  `p_container` STRING
) ROW FORMAT DELIMITED FIELDS TERMINATED BY '|';


CREATE TABLE ssb.`supplier_txt`(
  `s_suppkey` INT,
  `s_name` STRING,
  `s_address` STRING,
  `s_city` STRING,
  `s_nation` STRING,
  `s_region` STRING,
  `s_phone` STRING
) ROW FORMAT DELIMITED FIELDS TERMINATED BY '|';


CREATE TABLE ssb.`date_txt`(
  `d_datekey` INT,
  `d_date` STRING,
  `d_dayofweek` STRING,
  `d_month` STRING,
  `d_year` INT,
  `d_yearmonthnum` INT,
  `d_yearmonth` STRING,
  `d_daynuminweek` INT,
  `d_daynuminmonth` INT,
  `d_daynuminyear` INT,
  `d_monthnuminyear` INT,
  `d_weeknuminyear` INT,
  `d_sellingseason` STRING,
  `d_lastdayinweekfl` INT,
  `d_lastdayInmonthfl` INT,
  `d_holidayfl` INT,
  `d_weekdayfl` INT
) ROW FORMAT DELIMITED FIELDS TERMINATED BY '|';


CREATE TABLE ssb.`lineorder_txt`(
  `lo_orderkey` INT,
  `lo_linenumber` INT,
  `lo_custkey` INT,
  `lo_partkey` INT,
  `lo_suppkey` INT,
  `lo_orderdatekey` INT,
  `lo_orderpriority` STRING,
  `lo_shippriority` STRING,
  `lo_quantity` INT,
  `lo_extendedprice` DOUBLE,
  `lo_ordtotalprice` DOUBLE,
  `lo_discount` DOUBLE,
  `lo_revenue` DOUBLE,
  `lo_supplycost` DOUBLE,
  `lo_tax` INT,
  `lo_commitdatekey` INT,
  `lo_shipmode` STRING
) ROW FORMAT DELIMITED FIELDS TERMINATED BY '|';


-- ref: https://docs.starrocks.io/zh/docs/3.4/benchmarking/SSB_Benchmarking/#%E7%94%9F%E6%88%90%E6%95%B0%E6%8D%AE
-- gen data first, then put to hdfs
LOAD DATA INPATH '/tmp/ssb_bench/customer.tbl' INTO TABLE ssb.`customer_txt`;
LOAD DATA INPATH '/tmp/ssb_bench/dates.tbl' INTO TABLE ssb.`date_txt`;
LOAD DATA INPATH '/tmp/ssb_bench/lineorder.tbl' INTO TABLE ssb.`lineorder_txt`;
LOAD DATA INPATH '/tmp/ssb_bench/part.tbl' INTO TABLE ssb.`part_txt`;
LOAD DATA INPATH '/tmp/ssb_bench/supplier.tbl' INTO TABLE ssb.`supplier_txt`;


-- input format: parquet
drop table ssb.`customer` purge;
drop table ssb.`part` purge;
drop table ssb.`supplier` purge;
drop table ssb.`date` purge;
drop table ssb.`lineorder` purge;


CREATE TABLE ssb.`customer`(
  `c_customerkey` INT,
  `c_name` STRING,
  `c_address` STRING,
  `c_city` STRING,
  `c_nation` STRING,
  `c_region` STRING,
  `c_phone` STRING,
  `c_mktsegment` STRING
) STORED AS PARQUET;


CREATE TABLE ssb.`part`(
  `p_partkey` INT,
  `p_name` STRING,
  `p_mfgr` STRING,
  `p_category` STRING,
  `p_brand` STRING,
  `p_colour` STRING,
  `p_type` STRING,
  `p_size` INT,
  `p_container` STRING
) STORED AS PARQUET;


CREATE TABLE ssb.`supplier`(
  `s_suppkey` INT,
  `s_name` STRING,
  `s_address` STRING,
  `s_city` STRING,
  `s_nation` STRING,
  `s_region` STRING,
  `s_phone` STRING
) STORED AS PARQUET;


CREATE TABLE ssb.`date`(
  `d_datekey` INT,
  `d_date` STRING,
  `d_dayofweek` STRING,
  `d_month` STRING,
  `d_year` INT,
  `d_yearmonthnum` INT,
  `d_yearmonth` STRING,
  `d_daynuminweek` INT,
  `d_daynuminmonth` INT,
  `d_daynuminyear` INT,
  `d_monthnuminyear` INT,
  `d_weeknuminyear` INT,
  `d_sellingseason` STRING,
  `d_lastdayinweekfl` INT,
  `d_lastdayInmonthfl` INT,
  `d_holidayfl` INT,
  `d_weekdayfl` INT
) STORED AS PARQUET;


CREATE TABLE ssb.`lineorder`(
  `lo_orderkey` INT,
  `lo_linenumber` INT,
  `lo_custkey` INT,
  `lo_partkey` INT,
  `lo_suppkey` INT,
  `lo_orderdatekey` INT,
  `lo_orderpriority` STRING,
  `lo_shippriority` STRING,
  `lo_quantity` INT,
  `lo_extendedprice` DOUBLE,
  `lo_ordtotalprice` DOUBLE,
  `lo_discount` DOUBLE,
  `lo_revenue` DOUBLE,
  `lo_supplycost` DOUBLE,
  `lo_tax` INT,
  `lo_commitdatekey` INT,
  `lo_shipmode` STRING
) STORED AS PARQUET;


insert into ssb.`customer` select * from ssb.`customer_txt`;
insert into ssb.`part` select * from ssb.`part_txt`;
insert into ssb.`supplier` select * from ssb.`supplier_txt`;
insert into ssb.`date` select * from ssb.`date_txt`;
insert into ssb.`lineorder` select * from ssb.`lineorder_txt`;


-- Q1.1
select sum(lo_extendedprice * lo_discount) as revenue
  from lineorder
  join date on lo_orderdatekey = d_datekey
  where d_year = 1993
  and lo_discount between 1 and 3
  and lo_quantity < 25;


-- Q1.2
select sum(lo_extendedprice*lo_discount) as revenue
  from lineorder 
  join date on lo_orderdatekey = d_datekey where
  d_yearmonthnum = 199401
  and lo_discount between 4 and 6
  and lo_quantity between 26 and 35;


-- Q1.3
select sum(lo_extendedprice*lo_discount) as revenue
  from lineorder
  join date on lo_orderdatekey = d_datekey
  where d_weeknuminyear = 6
  and d_year = 1994
  and lo_discount between 5 and 7
  and lo_quantity between 26 and 35


-- Q2.1
select sum(lo_revenue), d_year, p_brand
  from lineorder
  join date
  on lo_orderdatekey = d_datekey
  join part
  on lo_partkey = p_partkey
  join supplier
  on lo_suppkey = s_suppkey
  where 
  p_category = 'MFGR#12'
  and s_region = 'AMERICA'
  group by d_year, p_brand
  order by d_year, p_brand;


-- Q2.2
select sum(lo_revenue), d_year, p_brand
  from lineorder
  join date
    on lo_orderdatekey = d_datekey
  join part
    on lo_partkey = p_partkey
  join supplier
    on lo_suppkey = s_suppkey
  where 
  p_brand between 'MFGR#2221' and 'MFGR#2228'
  and s_region = 'ASIA'
  group by d_year, p_brand
  order by d_year, p_brand;


-- Q2.3
select sum(lo_revenue), d_year, p_brand
  from lineorder
  join date
    on lo_orderdatekey = d_datekey
  join part
    on lo_partkey = p_partkey
  join supplier
    on lo_suppkey = s_suppkey
  where 
    p_brand= 'MFGR#2239'
    and s_region = 'EUROPE'
    group by d_year, p_brand
  order by d_year, p_brand;


-- Q3.1
select c_nation, s_nation, d_year,
  sum(lo_revenue) as revenue
  from customer
  join lineorder
     on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join date
    on lo_orderdatekey = d_datekey
  where
  c_region = 'ASIA'
  and s_region = 'ASIA'
  and d_year >= 1992 and d_year <= 1997
  group by c_nation, s_nation, d_year
  order by d_year asc, revenue desc;


-- Q3.2
select c_city, s_city, d_year, sum(lo_revenue)
  as revenue
  from customer
  join lineorder
    on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join date
    on lo_orderdatekey = d_datekey
  where
  c_nation = 'UNITED STATES'
  and s_nation = 'UNITED STATES'
  and d_year >= 1992 and d_year <= 1997
  group by c_city, s_city, d_year
  order by d_year asc, revenue desc;


-- Q3.3
select c_city, s_city, d_year, sum(lo_revenue)
  as revenue
  from customer
  join lineorder
    on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join date
    on lo_orderdatekey = d_datekey
  where
  (c_city='UNITED KI1' or c_city='UNITED KI5')
  and (s_city='UNITED KI1' or s_city='UNITED KI5')
  and d_year >= 1992 and d_year <= 1997
  group by c_city, s_city, d_year
  order by d_year asc, revenue desc;


-- Q3.4
select c_city, s_city, d_year, sum(lo_revenue)
  as revenue
  from customer
  join lineorder
    on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join date
    on lo_orderdatekey = d_datekey
  where
  (c_city='UNITED KI1' or c_city='UNITED KI5')
  and (s_city='UNITED KI1' or s_city='UNITED KI5')
  and d_yearmonth = 'Dec1997'
  group by c_city, s_city, d_year
  order by d_year asc, revenue desc;


-- Q4.1
select d_year, c_nation,
  sum(lo_revenue - lo_supplycost) as profit
  from lineorder
  join date 
    on lo_orderdatekey = d_datekey
  join customer
    on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join part
    on lo_partkey = p_partkey
  where
    c_region = 'AMERICA'
  and s_region = 'AMERICA'
  and (p_mfgr = 'MFGR#1'
  or p_mfgr = 'MFGR#2')
  group by d_year, c_nation
  order by d_year, c_nation;


-- Q4.2
select d_year, s_nation, p_category,
  sum(lo_revenue - lo_supplycost) as profit
  from lineorder
  join date 
    on lo_orderdatekey = d_datekey
  join customer
    on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join part
    on lo_partkey = p_partkey
  where
  c_region = 'AMERICA'
  and s_region = 'AMERICA'
  and (d_year = 1997 or d_year = 1998)
  and (p_mfgr = 'MFGR#1'
  or p_mfgr = 'MFGR#2')
  group by d_year, s_nation, p_category
  order by d_year, s_nation, p_category;


-- Q4.3
select d_year, s_city, p_brand,
  sum(lo_revenue - lo_supplycost) as profit
  from lineorder
  join date 
    on lo_orderdatekey = d_datekey
  join customer
    on lo_custkey = c_customerkey
  join supplier
    on lo_suppkey = s_suppkey
  join part
    on lo_partkey = p_partkey
  where
  s_nation = 'UNITED STATES'
  and (d_year = 1997 or d_year = 1998)
  and p_category = 'MFGR#14'
  group by d_year, s_city, p_brand
  order by d_year, s_city, p_brand;


