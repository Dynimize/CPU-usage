#!/bin/bash -x 

#This script is meant to be run with Sysbench 1.0

#Set the following 6 variables as required, and maybe also change $test if 
#necesary.
###########################################
tableSize=30000000
numTables=10
dbName="sbTest"
user="root"
measureTime=1800
marginTime=15
warmupTime=1800
restTime=10
paretoH=1
pathToLuas="/usr/share/sysbench"
dataDir="/var/lib/mysql"
results="./results/"
backup="/var/lib/mysql.setup"
oltp_point_select_test="$pathToLuas/oltp_point_select.lua"

#We'll be removing the first and last marginTime seconds in case they contain noise or top and sysbench don't fully overlap
measureTime=$(($measureTime + 2*$marginTime)) 

#Warmup done without --rate= otherwise transaction queue will fill up and sysbench will stop 
function warmup
	{
	echo Performing warmup...
	sleep 2
	dyni -status
	
        sysbench $pathToLuas/oltp_point_select.lua \
         --table-size=$tableSize \
         --tables=$numTables \
         --mysql-db=$dbName \
         --mysql-user=$user \
         --mysql-password='' \
         --time=$warmupTime \
         --threads=16 \
         --rand-type=pareto \
	 --rand-pareto-h=$paretoH \
         --db-driver=mysql \
         --report-interval=10 \
         --max-requests=0 \
         run > /dev/null 2>&1

	echo Warmup complete
	dyni -status
	}

function copyDataRestart
	{
	service mysql stop
	rm -rf $dataDir
	cp -r $backup $dataDir 
	chown -R mysql:mysql $dataDir 
	service mysql start
	}

#Becauase we are running a fixed rate workload, we need to set --report-interval
#to a large number so that the transaction queue doesn't fill up
function run 
	{
	name=$3
	test=$2
	prefix=$1-$name
	topLog=$results$prefix-top.log
	sysbenchLog=$results$prefix.log
	cpuUsageCsv=$results$prefix.csv

	warmup
	dyni -stop
	sleep 5

	timeout $measureTime top -b -d 1 | grep --line-buffered  mysqld > $topLog &  

	sysbench $test \
         --table-size=$tableSize \
         --tables=$numTables \
         --mysql-db=$dbName \
         --mysql-user=$user \
         --mysql-password='' \
         --time=$measureTime \
         --threads=16 \
         --rand-type=pareto \
	 --rand-pareto-h=$paretoH \
         --db-driver=mysql \
         --rate=25000 \
         --report-interval=100 \
         --max-requests=0 \
         run > $sysbenchLog

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
	test=$1
	name=$2

	echo RUN WITH DYNIMIZE
	copyDataRestart
	dyni -start
	run dyni $test $name
	dyni -stop

	sleep $restTime

        echo RUN WITHOUT DYNIMIZE
	copyDataRestart
        run noDyni $test $name

	sleep $restTime 
	}

dyni -stop
mkdir -p $results
runAndPlot $oltp_point_select_test "oltp_point_select"
