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
my $currentLTS='6.3.1e';
my $currentFeature='6.4.1a';
my $title="Global Cohesity Cluster Summary";
my $capacityDaysCritical=30; #Days until reaching 80% if within set days this will turn the cell red
my $capacityDaysWarning=60; #Days until reaching 80% if within set days this will turn the cell yellow
my $dailyGrowthCritical=10; #PCT growth rate increase this will turn that cell red
my $dailyGrowthWarning=5; #PCT growth rate increase this will turn that cell yellow
my $pctCapacityCritical=80;
my $pctCapacityWarning=70;
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
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'>Global Cluster Summary Report</TD></TR>" if ($display==1);
  printf "<TR BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Completed</TD><TD>Successful</TD><TD>Partial</TD><TD>Failed</TD><TD>Missed</TD><TD>Active</TD><TD>Success Rate (%)</TD></TR>" if ($display==1);
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
  printf "<HTML><HEAD></HEAD><BODY><Center><H1>$title</H1></CENTER>" if ($display==1);
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
    my $successRate=int(($clusterInfo{$cluster}{4}+$clusterInfo{$cluster}{5})/$clusterInfo{$cluster}{6}*100);
    my $total=$clusterInfo{$cluster}{4}+$clusterInfo{$cluster}{1}+$clusterInfo{$cluster}{5}+$clusterInfo{$cluster}{6}+$clusterInfo{$cluster}{8};
    print "\n<TR><TD>$cluster</TD><TD bgcolor=$completedColor>$total</TD><TD bgcolor=$successColor>$clusterInfo{$cluster}{4}</TD><TD bgcolor=$partialColor>$clusterInfo{$cluster}{5}</TD><TD bgcolor=$failedColor>$clusterInfo{$cluster}{6}</TD><TD bgcolor=$missedColor>$clusterInfo{$cluster}{8}</TD><TD bgcolor=$activeColor>$clusterInfo{$cluster}{1}</TD><TD>$successRate</TD></TR>\n" if ($display==1);
    $totalCompleted=$totalCompleted+$total;
    $totalSuccess=$totalSuccess+$clusterInfo{$cluster}{4};
    $totalPartial=$totalPartial+$clusterInfo{$cluster}{5};
    $totalFailed=$totalFailed+$clusterInfo{$cluster}{6};
    $totalMissed=$totalMissed+$clusterInfo{$cluster}{8};
    $totalMissed=$totalMissed+$clusterInfo{$cluster}{8};
  }
  my $totalSuccessRate=int(($totalSuccess+$totalPartial)/$totalFailed*100);
  print "\n<TR><TD bgcolor=$totalColor></TD><TD bgcolor=$totalColor>$totalCompleted</TD><TD bgcolor=$totalColor>$totalSuccess</TD><TD bgcolor=$totalColor>$totalPartial</TD><TD bgcolor=$totalColor>$totalFailed</TD><TD bgcolor=$totalColor>$totalMissed</TD><TD bgcolor=$totalColor>$totalActive</TD><TD bgcolor=$totalColor>$totalSuccessRate</TD></TR>\n" if ($display==1);
  printf "</TABLE><br/>\n" if ($display==1);
  printf "</BODY></HTML>\n" if ($display==1);
}  

sub StrikeReport {
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  print "$curTime\n" if ($debug>=2);
  my $startTimeUsecs=($curTime-$hoursAgoUsecs);
  print "$startTimeUsecs\n" if ($debug>=2);
  foreach my $href (@clusters){
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    # Gather Total Jobs Information
    my $sth=$dbh->prepare("select COUNT(node_id) FROM reporting.nodes");
    $sth->execute() or die DBI::errstr;
    my $numOfNodes=$sth->fetch()->[0];
    $sth->finish();
    my $sql = "uster";
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while(my @rows=$sth->fetchrow_array){
      $clusterInfo{$rows[0]}="$rows[1],$numOfNodes,$href->{'physicalCapacityBytes'},$href->{'minUsablePhysicalCapacityBytes'},$href->{'usedPct'},$href->{'avgDailyGrowthRate'},$href->{'pctDateMsecs'},$href->{'dataReductionRatio'},$href->{'physicalUsageBytes'}";
      print "ROW=$rows[0]\t$rows[1]\t\t$rows[2]" if ($debug>=2);
    }
    $dbh->disconnect();
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
}

# Main
getToken();
getDbInfo();
gatherData();
printReport();
