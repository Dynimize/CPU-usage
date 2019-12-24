#!/bin/bash -x 

#This script uses the loadtest http benchmarking tool, 
#due to it's ability to run fixed rate workloads:
#https://www.npmjs.com/package/loadtest
#https://github.com/alexfernandez/loadtest

measureTime=600
marginTime=15
warmupTime=600
restTime=10
results="./results/"
cmd="--rps 80 -c 8 http://127.0.0.1/blog/"

#We'll be removing the first and last marginTime seconds in case they 
#contain noise or top and loadtest don't fully overlap
measureTime=$(($measureTime + 2*$marginTime)) 

function warmup
	{
	echo Performing warmup...
	sleep 2
	dyni -status
 	loadtest -t $warmupTime $cmd > /dev/null 2>&1
	echo Warmup complete
	dyni -status
	}

function run 
	{
	prefix=$1-wp
	topLog=$results$prefix-top.log
	loadtestLog=$results$prefix.log
	cpuUsageCsv=$results$prefix.csv

	sleep $restTime 

	timeout $measureTime top -b -d 1 | grep --line-buffered  mysqld > $topLog &  
        loadtest -t $warmupTime $cmd > $loadtestLog 

	sleep $restTime 

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
	service mysql restart
	dyni -start
	warmup 
	dyni -stop
	run dyni 

	sleep $restTime

        echo RUN WITHOUT DYNIMIZE
        service mysql restart
        warmup 
        run noDyni
	}

dyni -stop
mkdir -p $results
runAndPlot 
echo FINISHED
