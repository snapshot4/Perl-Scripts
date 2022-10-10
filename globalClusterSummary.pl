#!/usr/local/bin/perl
our $version=1.0.1;

# Author: Brian Doyle
# Name: globalClusterSummary.pl
# Description: This script was written for a Cohesity cluster to give better visibility into a large multisite deployment.  #
# 1.0.0

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
  printf "Cluster              Version  # of Nodes  Raw(TB)  Useable(TB)  Used(TB)  Pct Used  Ratio  Daily Growth(TB)  Predicted 80%\n" if ($display==0);
  printf "=======              =======  ==========  =======  ===========  ========  ========  =====  ================  =============\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'>$_[0] Report</TD></TR>" if ($display==1);
  printf "<TR BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Version</TD><TD># of Nodes</TD><TD>Raw(TB)</TD><TD>Useable(TB)</TD><TD>Used(TB)</TD><TD>Pct Used</TD><TD>Ratio</TD><TD>Daily Growth</TD><TD>Predicted 80%</TD></TR>" if ($display==1);
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
    my $sth=$dbh->prepare("select COUNT(node_id) FROM reporting.nodes");
    $sth->execute() or die DBI::errstr;
    my $numOfNodes=$sth->fetch()->[0];
    $sth->finish();
    my $sql = "SELECT cluster_name, software_version FROM reporting.cluster";
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

sub printReport {
  printf "<HTML><HEAD></HEAD><BODY><Center><H1>$title</H1></CENTER>" if ($display==1);
  printHeader();
  my $predictStatus="green"; 
  my $versionStatus="green"; 
  my $pctStatus="green"; 
  my $growthStatus="green"; 
  foreach my $clusterName (sort keys %clusterInfo){
    my @cols=split(',', $clusterInfo{$clusterName});
    my @temp=split('_',$cols[0]);
    my $version=$temp[0];
    if("$version" eq "$currentLTS" || "$version" eq "$currentFeature"){
      $versionStatus="green";
    } else {
      $versionStatus="orange";
    }

    my $physicalCap=$cols[2]/1024/1024/1024/1024;
    my $usedCap=$cols[8]/1024/1024/1024/1024;
    my $minUseableCap=$cols[3]/1024/1024/1024/1024;
    my $avgDailyGrowth=$cols[5]/1024/1024/1024/1024;
    if($avgDailyGrowth >= $dailyGrowthCritical){
      $growthStatus="red"
    } elsif($avgDailyGrowth < $dailyGrowthCritical && $avgDailyGrowth >= $dailyGrowthWarning){
      $growthStatus="orange"
    }

    my $pctUsedCap=($cols[4]);
    if($pctUsedCap >= $pctCapacityCritical){
      $pctStatus="red";
    } elsif ($pctUsedCap < $pctCapacityCritical && $pctUsedCap >= $pctCapacityWarning){
      $pctStatus="orange";
    }

    my $capDate;
    my $curDate=time;
    my $predictDateUsecs=$cols[6]/1000;
    my $criticalDate=$curDate+($capacityDaysCritical*86400); 
    my $warningDate=$curDate+($capacityDaysWarning*86400);
    if($cols[6]!="-"){
      $capDate = strftime("%m/%d/%Y", localtime($cols[6]/1000));
    } else {
      $capDate="-";
    }
    if($predictDateUsecs <= $criticalDate && $predictDateUsecs > $curDate && $predictDateUsecs != 0){
      $predictStatus="red";
    } elsif($predictDateUsecs > $criticalDate && $predictDateUsecs <= $warningDate && $predictDateUsecs > $curDate){
      $predictStatus="orange";
    } else {
      $predictStatus="green";
    }
    printf "%-20s  %-7s  %5d  %10.1f  %9.1f  %9.1f  %8.1f  %7.1f %12.2f %19s\n",$clusterName,$version,$cols[1],$physicalCap,$minUseableCap,$usedCap,$pctUsedCap,$cols[7],$avgDailyGrowth,$capDate if ($display==0);
    printf "<TR><TD ALIGN=center>%s</TD><TD ALIGN=center bgcolor=$versionStatus><FONT color=white>%s</FONT></TD><TD ALIGN=center>%d</TD><TD ALIGN=right>%.1f</TD><TD ALIGN=right>%.1f</TD><TD ALIGN=right>%.1f</TD><TD ALIGN=right bgcolor=$pctStatus><FONT color=white>%.1f\%</FONT></TD><TD ALIGN=center>%.1f</TD><TD ALIGN=right bgcolor=$growthStatus><FONT color=white>%.2f</FONT></TD><TD ALIGN=right bgcolor=$predictStatus><FONT color=white>%s</FONT></TD></TR>",$clusterName,$version,$cols[1],$physicalCap,$minUseableCap,$usedCap,$pctUsedCap,$cols[7],$avgDailyGrowth,$capDate if ($display==1);
  }
  printf "</TABLE><br/>\n" if ($display==1);
  printf "</BODY></HTML>\n" if ($display==1);
}  


# Main
getToken();
getDbInfo();
gatherData();
printReport();
