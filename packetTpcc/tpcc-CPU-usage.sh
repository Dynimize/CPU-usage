#!/bin/bash -x 

#This script is meant to be run with Sysbench 1.0

#Set the following 6 variables as required, and maybe also change $test if 
#necesary.
###########################################
scale=100
numTables=10
dbName="tpcc"
user="root"
measureTime=1800
reportInterval=10
dyniWarmupTime=180
threads=56
marginTime=15
warmupTime=1800
rate=7500
restTime=10
dataDir="/var/lib/mysql"
results="./results/"
backup="/mnt/drive/mysql.setup"
nvme="/mnt/drive/mysql"
variant="mariadb"

#We'll be removing the first and last marginTime seconds in case they contain noise or top and sysbench don't fully overlap
measureTime=$(($measureTime + 2*$marginTime)) 

function warmup
	{
	echo Performing warmup...
	sleep 2
	dyni -status

	./tpcc.lua --mysql-user=$user \
	       	--mysql-db=$dbName \
		--time=$1 \
		--threads=$threads \
		--report-interval=$reportInterval \
		--tables=$numTables \
		--scale=$scale \
		--db-driver=mysql run > /dev/null 2>&1

	echo Warmup complete
	dyni -status
	}

function warmupRate
        {
        echo Performing warmup...
        sleep 2
        dyni -status

        ./tpcc.lua --mysql-user=$user \
                --mysql-db=$dbName \
                --time=$1 \
		--rate=$rate \
                --threads=$threads \
                --report-interval=$reportInterval \
                --tables=$numTables \
                --scale=$scale \
                --db-driver=mysql run > /dev/null 2>&1

        echo Warmup complete
        dyni -status
        }

function copyDataRestart
	{
	service $variant stop
	rm -rf $nvme
	cp -r $backup $nvme 
	chown -R mysql:mysql $nvme
	service $variant start
	}

function run 
	{
	prefix=$1-tpcc
	topLog=$results$prefix-top.log
	sysbenchLog=$results$prefix.log
	cpuUsageCsv=$results$prefix.csv

	sleep 5

	timeout $measureTime top -b -d 1 | grep --line-buffered  mysqld > $topLog &  

        ./tpcc.lua --mysql-user=$user \
                --mysql-db=$dbName \
                --time=$measureTime \
                --threads=$threads \
                --report-interval=$reportInterval \
                --tables=$numTables \
                --scale=$scale \
		--rate=$rate \
                --db-driver=mysql run > $sysbenchLog 

	sleep 10

	#Delete first and last marginTime seconds of log to remove potential 
	#startup and exit overlap with other tasks 
	head -n -$marginTime $topLog > temp 
	tail -n +$marginTime temp > $topLog
	rm temp

	#Convert to cvs
	awk '{ print $9 }' $topLog > $cpuUsageCsv    
	}

function runAndPlot 
	{
	echo RUN WITH DYNIMIZE
	copyDataRestart
	warmup $warmupTime
	dyni -start
	warmupRate $dyniWarmupTime 
	dyni -stop
	run dyni 

	sleep $restTime

        echo RUN WITHOUT DYNIMIZE
	copyDataRestart
        warmup $warmupTime
        warmupRate $dyniWarmupTime
        run noDyni

	sleep $restTime 
	}

dyni -stop
mkdir -p $results
runAndPlot 
echo FINISHED
