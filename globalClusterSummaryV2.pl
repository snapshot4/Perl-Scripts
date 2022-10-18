#!/usr/local/bin/perl
our $version=2.0.0;

# Author: Brian Doyle
# Name: globalClusterSummaryV2.pl
# Description: This script was written for a Cohesity cluster to give better visibility into a large multisite deployment.  #
# 2.0.0 - This is to add additional reports to this same program (3 Strike, Add and Removed Clients and Unsuccessful Clients)

# Modules
use strict;
use DBI; 
use REST::Client;
use JSON;
use Time::HiRes;
use POSIX qw( strftime );
use clusterInfo;

# Global Variables
my $display=1; #(0-Standard Display, 1-HTML)
my $debug=0; #(0-No log messages, 1-Info messages, 2-Debug messages)
my $hoursAgo=24;
#my $title="Global Cohesity Cluster Summary";
my @clusters=clusterInfo::clusterList();
my %clusterInfo;
my @data;



#Set Environment Variable to no verify certs
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;


# Sub Routines
sub getToken {
  foreach my $href (@clusters){
    my $cluster=$href->{'cluster'};
    my $username=$href->{'username'};
    my $password=$href->{'password'};
    my $domain=$href->{'domain'};
    printf "Getting Token for: $cluster\n" if ($debug>=1);
    my $client=REST::Client->new();
    $client->setHost("https://$cluster"); 
    $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
    $client->POST('/irisservices/api/v1/public/accessTokens','{"domain" : "'.$domain.'","username" : "'.$username.'","password" : "'.$password.'"}');
    die $client->responseContent() if( $client->responseCode() >= 300 );
    my $response=decode_json($client->responseContent());
    printf "ResponseCode: ".$client->responseCode()."\n" if ($debug>=2);
    $href->{'tokenType'} = $response->{'tokenType'};
    $href->{'token'} = $response->{'accessToken'};
  }
}

sub getDbInfo {
  foreach my $href (@clusters){
    my $cluster=$href->{'cluster'};
    printf "Getting DB Info for Cluster: $cluster\n" if ($debug>=1);
    my $client=REST::Client->new();
    $client->setHost("https://$cluster"); 
    $client->addHeader("Accept", "application/json");
    $client->addHeader("Authorization", "$href->{'tokenType'} $href->{'token'}"); #Authorize request
    $client->GET('/irisservices/api/v1/public/postgres');
    my $response=decode_json($client->responseContent());
    $href->{'nodeId'}="$response->[0]->{'nodeId'}";
    $href->{'nodeIp'}="$response->[0]->{'nodeIp'}";
    $href->{'port'}="$response->[0]->{'port'}";
    $href->{'defaultUsername'}="$response->[0]->{'defaultUsername'}";
    $href->{'defaultPassword'}="$response->[0]->{'defaultPassword'}";
    getCapacityReport($cluster,$href);
  }
}

sub getCapacityReport {
  my $cluster=$_[0];
  my $href=$_[1];
  my $client=REST::Client->new();
  $client->setHost("https://$cluster"); 
  $client->addHeader("Accept", "application/json");
  $client->addHeader("Authorization", "$href->{'tokenType'} $href->{'token'}"); #Authorize request
  $client->GET('/irisservices/api/v1/reports/cluster/storage');
  my $response=decode_json($client->responseContent());
  $href->{'physicalCapacityBytes'}="$response->{'physicalCapacityBytes'}";
  $href->{'minUsablePhysicalCapacityBytes'}="$response->{'minUsablePhysicalCapacityBytes'}";
  $href->{'usedPct'}="$response->{'usedPct'}";
  $href->{'avgDailyGrowthRate'}="$response->{'avgDailyGrowthRate'}";
  $href->{'physicalUsageBytes'}="$response->{'physicalUsageBytes'}->[6]";
  $href->{'dataReductionRatio'}="$response->{'dataReductionRatio'}->[6]";
  if($href->{'avgDailyGrowthRate'} > 0){
    $href->{'pctDateMsecs'}="$response->{'pctDateMsecs'}";
  } else {
    $href->{'pctDateMsecs'}="-";
  }
  #print "Growth Rate: $href->{'avgDailyGrowthRate'}\nUsed Pct: $href->{'usedPct'}\nPhysical Capacity: $href->{'physicalCapacityBytes'}\nCapacity Date: $href->{'pctDateMsecs'}\n\n\n";
}

sub printHeader {
  printf "\n                                                Global Cluster Summmary Report                                          \n" if ($display==0);
  printf "Cluster              Completed	Successful	Partial	Failed	Missed	Active	Success Rate (%)\n" if ($display==0);
  printf "=======              =========	==========	=======	======	======	======	================\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'><B>Global Cluster Summary Report</B></TD></TR>" if ($display==1);
  printf "<TR ALIGN=center BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Completed</TD><TD>Successful</TD><TD>Partial</TD><TD>Failed</TD><TD>Missed</TD><TD>Active</TD><TD>Success Rate (%)</TD></TR>" if ($display==1);
}

sub gatherData{
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  foreach my $href (@clusters){
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    # Gather Total Jobs Information
    my $sql = "SELECT c.cluster_name,
		le.entity_name,
		pj.job_name,
		pjre.status
		FROM 
		reporting.protection_job_run_entities pjre,
		reporting.protection_jobs pj,
		reporting.cluster c,
		reporting.leaf_entities le
		WHERE pjre.start_time_usecs >= 1665610762000000 AND
		pjre.cluster_id = c.cluster_id AND
		pjre.entity_id = le.entity_id AND
		pjre.job_id = pj.job_id AND
		pjre.status IN (1,4,5,6,8)";
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    @data=$sth->fetchrow_array;
    while(my @rows=$sth->fetchrow_array){
      print "ROW=$rows[0]\t$rows[1]\t\t$rows[2]" if ($debug>=2);
      $clusterInfo{$rows[0]}{$rows[3]}=$clusterInfo{$rows[0]}{$rows[1]}{$rows[3]}++; 
    }
    $dbh->disconnect();
  }
}

sub printReport {
  printf "<HTML><HEAD></HEAD><BODY><Center></CENTER>" if ($display==1);
  printHeader();
  my $completedColor="F7D596";
  my $successColor="92D14F";
  my $partialColor="FEFD61";
  my $failedColor="D75757";
  my $missedColor="F0B15A";
  my $totalColor="0000F3";
  my $activeColor="737273";
  my ($totalCompleted, $totalSuccess, $totalPartial, $totalFailed, $totalMissed, $totalActive, $totalSuccessRate) = (0,0,0,0,0,0);
  foreach my $cluster (sort keys %clusterInfo){
    foreach my $status (1,4,5,6,8){
      if (not exists ($clusterInfo{$cluster}{$status})){
        $clusterInfo{$cluster}{$status}=0; 
      }
    } 
    my $successRate=($clusterInfo{$cluster}{6}/($clusterInfo{$cluster}{4}+$clusterInfo{$cluster}{5}));
    my $total=$clusterInfo{$cluster}{4}+$clusterInfo{$cluster}{1}+$clusterInfo{$cluster}{5}+$clusterInfo{$cluster}{6}+$clusterInfo{$cluster}{8};
    printf "\n<TR ALIGN=right><TD>$cluster</TD><TD bgcolor=$completedColor>$total</TD><TD bgcolor=$successColor>$clusterInfo{$cluster}{4}</TD><TD bgcolor=$partialColor>$clusterInfo{$cluster}{5}</TD><TD bgcolor=$failedColor>$clusterInfo{$cluster}{6}</TD><TD bgcolor=$missedColor>$clusterInfo{$cluster}{8}</TD><TD bgcolor=$activeColor>$clusterInfo{$cluster}{1}</TD><TD>%2.1f</TD></TR>\n",$successRate if ($display==1);
    $totalCompleted=$totalCompleted+$total;
    $totalSuccess=$totalSuccess+$clusterInfo{$cluster}{4};
    $totalPartial=$totalPartial+$clusterInfo{$cluster}{5};
    $totalFailed=$totalFailed+$clusterInfo{$cluster}{6};
    $totalMissed=$totalMissed+$clusterInfo{$cluster}{8};
    $totalMissed=$totalMissed+$clusterInfo{$cluster}{8};
  }
  my $totalSuccessRate=($totalFailed/($totalSuccess+$totalPartial));
  printf "\n<TR ALIGN=right style=color:white><TD bgcolor=$totalColor>Total</TD><TD bgcolor=$totalColor>$totalCompleted</TD><TD bgcolor=$totalColor>$totalSuccess</TD><TD bgcolor=$totalColor>$totalPartial</TD><TD bgcolor=$totalColor>$totalFailed</TD><TD bgcolor=$totalColor>$totalMissed</TD><TD bgcolor=$totalColor>$totalActive</TD><TD bgcolor=$totalColor>%2.1f</TD></TR>\n",$totalSuccessRate if ($display==1);
  printf "</TABLE><br/>\n" if ($display==1);
  strikeReport();
  printf "</TABLE><br/>\n" if ($display==1);
  failedCliients();
  printf "</TABLE><br/>\n" if ($display==1);
  printf "</BODY></HTML>\n" if ($display==1);
}  

sub strikeReport {
  my $oneStrikeColor="FFFF99";
  my $twoStrikesColor="F0B15B";
  my $threeStrikesColor="D75757";
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  foreach my $href (@clusters){
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    my $sql = 'SELECT c.cluster_name,
		le.entity_name,
		date_part($$day$$, to_timestamp(pjre.start_time_usecs/1000000)) AS "Day"
		FROM 
		reporting.cluster c,
		reporting.protection_job_run_entities pjre,
		reporting.leaf_entities le
		WHERE 
		pjre.status=6 AND
		to_timestamp(pjre.start_time_usecs/1000000) > NOW() - interval $$4 days$$ AND
		pjre.entity_id = le.entity_id AND
		pjre.cluster_id = c.cluster_id
		GROUP BY
		c.cluster_name,
		le.entity_name,
		"Day"
		ORDER BY c.cluster_name ASC, le.entity_name ASC;';
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    %clusterInfo=();
    while(my @rows=$sth->fetchrow_array){
      $clusterInfo{$rows[0]}{$rows[1]}{$rows[2]}=0;
      print "ROW=$rows[0]\t$rows[1]\t\t$rows[2]\n" if($debug==2);
    }
    $dbh->disconnect();
  }
  printf "\n                  Three Strikes Report Report                                          \n" if ($display==0);
  printf "Cluster              One Strike	Two Strike	Three Strikes" if ($display==0);
  printf "=======              ==========	==========	=============\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'><B>Strike Summary</B></TD></TR>" if ($display==1);
  printf "<TR ALIGN=center BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>One Strike</TD><TD>Two Strikes</TD><TD>Three Strikes</TD></TR>" if ($display==1);
  my (%threeStrikes,%twoStrikes,%oneStrike);
  foreach my $cluster (sort keys %clusterInfo){
    $threeStrikes{$cluster}=0;
    $twoStrikes{$cluster}=0;
    $oneStrike{$cluster}=0;
    foreach my $object (sort keys %{ $clusterInfo{$cluster} }){
      #print "object=$object\n";
      my $daysFailed=0;
      foreach(sort keys %{ $clusterInfo{$cluster}{$object} }){
        $daysFailed++; 
      }
      if($daysFailed >= 4){
        $threeStrikes{$cluster}++;
      } elsif ($daysFailed == 3){
        $twoStrikes{$cluster}++;
      } elsif ($daysFailed == 2){
        $oneStrike{$cluster}++;
      }
    }
    print "<TR ALIGN=right><TD>$cluster</TD><TD bgcolor=$oneStrikeColor>$oneStrike{$cluster}</TD><TD bgcolor=$twoStrikesColor>$twoStrikes{$cluster}</TD><TD bgcolor=$threeStrikesColor>$threeStrikes{$cluster}</TD></TR>\n" if($display==1);
  }
}

sub clientAddRemoveReport {
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
}

sub failedCliients {
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'><B>Unsuccessful Clients</B></TD></TR>" if ($display==1);
  printf "<TR ALIGN=center BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Client Type</TD><TD>Client</TD><TD>Protection Group</TD><TD>Status</TD><TD>Started</TD><TD>Finished</TD></TR>" if ($display==1);
  foreach my $href (@clusters){
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    my $sql = 'SELECT c.cluster_name,
		et.env_name,
		le.entity_name,
		pj.job_name,
		jrs.status_name,
		pjre.start_time_usecs,
		pjre.end_time_usecs
		FROM 
		reporting.cluster c,
		reporting.protection_job_run_entities pjre,
		reporting.leaf_entities le,
		reporting.protection_jobs pj,
		reporting.job_run_status jrs,
		reporting.environment_types et
		WHERE 
		pjre.status=6 AND
		to_timestamp(pjre.start_time_usecs/1000000) > NOW() - interval $$24 Hours$$ AND
		pjre.entity_id = le.entity_id AND
		pjre.cluster_id = c.cluster_id AND
		pjre.job_id = pj.job_id AND
		pjre.status = jrs.status_id AND
		pjre.entity_env_type = et.env_id
		ORDER BY c.cluster_name ASC, le.entity_name ASC,pjre.start_time_usecs DESC';
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while(my @rows=$sth->fetchrow_array){
      $rows[1]=~s/^k//;
      my $started=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($rows[5]/1000/1000));
      my $finished=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($rows[6]/1000/1000));
      print "<TR ALIGN=left><TD>$rows[0]</TD><TD>$rows[1]</TD><TD>$rows[2]</TD><TD>$rows[3]</TD><TD>$rows[4]</TD><TD>$started</TD><TD>$finished</TD></TR>\n";
    }
    $dbh->disconnect();
  }
}

# Main
getToken();
getDbInfo();
gatherData();
printReport();
