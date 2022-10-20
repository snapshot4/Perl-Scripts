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
my $goldConfigFile="/Users/briandoyle/scripts/mhhs/goldConfig.json";
my %removedClients;
my %addedClients;
my %currentConfig;
my %goldConfig;
my $json;
 
 
 
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
  }
}
 
sub printHeader {
  printf "\n                                                Global Cluster Summmary Report                                          \n" if ($display==0);
  printf "Cluster              Completed        Successful      Partial Failed  Missed  Active  Success Rate (%)\n" if ($display==0);
  printf "=======              =========        ==========      ======= ======  ======  ======  ================\n" if ($display==0);
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
    my $total=$clusterInfo{$cluster}{4}+$clusterInfo{$cluster}{1}+$clusterInfo{$cluster}{5}+$clusterInfo{$cluster}{6}+$clusterInfo{$cluster}{8};
    my $successRate=((($clusterInfo{$cluster}{4}+$clusterInfo{$cluster}{5})/$total)*100);
    print "total=$total\nsuccess=$clusterInfo{$cluster}{4}\npartial=$clusterInfo{$cluster}{5}\nsuccessRate=$successRate\n" if($debug=1);
    printf "\n<TR ALIGN=right><TD>$cluster</TD><TD bgcolor=$completedColor>$total</TD><TD bgcolor=$successColor>$clusterInfo{$cluster}{4}</TD><TD bgcolor=$partialColor>$clusterInfo{$cluster}{5}</TD><TD bgcolor=$failedColor>$clusterInfo{$cluster}{6}</TD><TD bgcolor=$missedColor>$clusterInfo{$cluster}{8}</TD><TD bgcolor=$activeColor>$clusterInfo{$cluster}{1}</TD><TD>%3.1f</TD></TR>\n",$successRate if ($display==1);
    $totalCompleted=$totalCompleted+$total;
    $totalSuccess=$totalSuccess+$clusterInfo{$cluster}{4};
    $totalPartial=$totalPartial+$clusterInfo{$cluster}{5};
    $totalFailed=$totalFailed+$clusterInfo{$cluster}{6};
    $totalMissed=$totalMissed+$clusterInfo{$cluster}{8};
    $totalMissed=$totalMissed+$clusterInfo{$cluster}{8};
  }
  my $totalSuccessRate=((($totalSuccess+$totalPartial)/$totalCompleted)*100);
  printf "\n<TR ALIGN=right style=color:white><TD bgcolor=$totalColor>Total</TD><TD bgcolor=$totalColor>$totalCompleted</TD><TD bgcolor=$totalColor>$totalSuccess</TD><TD bgcolor=$totalColor>$totalPartial</TD><TD bgcolor=$totalColor>$totalFailed</TD><TD bgcolor=$totalColor>$totalMissed</TD><TD bgcolor=$totalColor>$totalActive</TD><TD bgcolor=$totalColor>%3.1f</TD></TR>\n",$totalSuccessRate if ($display==1);
  printf "</TABLE><br/>\n" if ($display==1);
  strikeReport();
  printf "</TABLE><br/>\n" if ($display==1);
  clientAddRemoveReport();
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
  %clusterInfo=();
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
    while(my @rows=$sth->fetchrow_array){
      $clusterInfo{$rows[0]}{$rows[1]}{$rows[2]}=0;
      #print "ROW=$rows[0]\t$rows[1]\t\t$rows[2]\n";
    }
    $dbh->disconnect();
  }
  printf "\n                  Three Strikes Report Report                                          \n" if ($display==0);
  printf "Cluster              One Strike       Two Strike      Three Strikes" if ($display==0);
  printf "=======              ==========       ==========      =============\n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'><B>Strike Summary</B></TD></TR>" if ($display==1);
  printf "<TR ALIGN=center BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>One Strike</TD><TD>Two Strikes</TD><TD>Three Strikes</TD></TR>" if ($display==1);
  my (%threeStrikes,%twoStrikes,%oneStrike);
  foreach my $cluster (sort keys %clusterInfo){
    print "cluster=$cluster\n" if($debug==2);
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
    my %started;
    while(my @rows=$sth->fetchrow_array){
      $rows[1]=~s/^k//;
      $started{$rows[0]}{$rows[1]}{$rows[2]}{$rows[3]}{$rows[4]}{POSIX::strftime('%m/%d/%Y',localtime($rows[5]/1000/1000))}=POSIX::strftime('%m/%d/%Y',localtime($rows[6]/1000/1000));
    }
    $dbh->disconnect();
    foreach my $cluster (sort keys %started){
      foreach my $type (sort keys %{$started{$cluster}}){
        foreach my $client (sort keys %{$started{$cluster}{$type}}){
          foreach my $protectionGroup (sort keys %{$started{$cluster}{$type}{$client}}){
            foreach my $status (sort keys %{$started{$cluster}{$type}{$client}{$protectionGroup}}){
              foreach (sort keys %{$started{$cluster}{$type}{$client}{$protectionGroup}{$status}}){
          print "<TR ALIGN=left><TD>$cluster</TD><TD>$type</TD><TD>$client</TD><TD>$protectionGroup</TD><TD>$status</TD><TD>$_</TD><TD>$started{$cluster}{$type}{$client}{$protectionGroup}{$status}{$_}</TD></TR>\n" if($display==1);
              }
            }
          }
        }
      }
    }
  }
}

sub clientAddRemoveReport {
  print "Connecting to Database $_[1]\n" if ($debug>=2);
  my $hoursAgoUsecs=($hoursAgo*3600000000);
  my $curTime=time*1000*1000;
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'><B>Client Configuration Changes</B></TD></TR>" if ($display==1);
  printf "<TR ALIGN=center BGCOLOR=lightgreen><TD>Cohesity Cluster</TD><TD>Protection Group</TD><TD>Client</TD><TD>Change</TD><TD>Noted</TD></TR>" if ($display==1);
  foreach my $href (@clusters){
    my $dbh = DBI -> connect("dbi:Pg:dbname=$href->{'databaseName'};host=$href->{'nodeIp'};port=$href->{'port'}",$href->{'defaultUsername'},$href->{'defaultPassword'}) or die $DBI::errstr;
    my $sql = 'SELECT
                c.cluster_name,
		pj.job_name,
		le.entity_name
		FROM 
		reporting.protection_job_entities pje,
		reporting.protection_jobs pj,
		reporting.leaf_entities le,
                reporting.cluster c
		WHERE
		pje.entity_id = le.entity_id AND
		pje.job_id = pj.job_id AND
		pj.cluster_id = c.cluster_id AND
		pj.job_env_type IN (1,2,6,13,17)
		ORDER BY pj.job_name, le.entity_name;';
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while(my @rows=$sth->fetchrow_array){
      $currentConfig{$rows[0]}{$rows[1]}{$rows[2]}=POSIX::strftime('%m/%d/%Y',localtime($curTime/1000/1000));
    } 
  }
  #Opening the file for read
  if (-e $goldConfigFile){
    if(-z $goldConfigFile){
      open(FH, '>:encoding(UTF-8)', $goldConfigFile);
      $json=encode_json \%currentConfig;
      close(FH);
    }
  } else {
    open(FH, '>:encoding(UTF-8)', $goldConfigFile);
    $json=encode_json \%currentConfig;
    print FH "$json"; 
    close(FH);
  }
  $json=do{open(FH, '<:encoding(UTF-8)', $goldConfigFile); <FH>};
  my $jsonText=decode_json($json);
  close(FH);
  foreach my $cluster (sort keys %{$jsonText}){
    foreach my $groupName (sort keys %{$jsonText->{$cluster}}){
      foreach my $client (sort keys %{$jsonText->{$cluster}{$groupName}}){
        if (not exists ($currentConfig{$cluster}{$groupName}{$client})){
          $removedClients{$cluster}{$groupName}{$client}=$jsonText->{$cluster}{$groupName}{$client};
        }   
      }
    }
  }
  foreach my $cluster (sort keys %currentConfig){
    foreach my $groupName (sort keys %{$currentConfig{$cluster}}){
      foreach my $client (sort keys %{$currentConfig{$cluster}{$groupName}}){
        if (not exists ($jsonText->{$cluster}{$groupName}{$client})){
          $addedClients{$cluster}{$groupName}{$client}=$currentConfig{$cluster}{$groupName}{$client};
        }
      }
    }
  }
  my $removedColor="EFB15A";
  my $addedColor="92D150";
  foreach my $cluster (sort keys %removedClients){
    foreach my $groupName (sort keys %{$removedClients{$cluster}}){
      foreach my $client (sort keys %{$removedClients{$cluster}{$groupName}}){
        print "<TR bgcolor=$removedColor><TD>$cluster</TD><TD>$groupName</TD><TD>$client</TD><TD>Deleted</TD><TD>$removedClients{$cluster}{$groupName}{$client}</TD></TD>";
      }
    }
  }
  foreach my $cluster (sort keys %addedClients){
    foreach my $groupName (sort keys %{$addedClients{$cluster}}){
      foreach my $client (sort keys %{$addedClients{$cluster}{$groupName}}){
        print "<TR bgcolor=$addedColor><TD>$cluster</TD><TD>$groupName</TD><TD>$client</TD><TD>Added</TD><TD>$removedClients{$cluster}{$groupName}{$client}</TD></TD>";
      }
    }
  }
  open(FH, '>:encoding(UTF-8)', $goldConfigFile);
  $json=encode_json \%currentConfig;
  print FH "$json"; 
  close(FH);
}
 
# Main
getToken();
getDbInfo();
gatherData();
printReport();
