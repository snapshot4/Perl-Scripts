#!/usr/local/bin/perl
our $version=1.0.1;
 
# Author: Brian Doyle
# Name: globalObjectSummary.pl
# Description: This script was written for a Cohesity cluster to give better visibility into a large multisite deployment.  #
# 2.0.0
 
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
my $debug=2; #(0-No log messages, 1-Info messages, 2-Debug messages)
my $hoursAgo=24;
my $title="Daily Object Report";
my @clusters=clusterInfo::clusterList();
my @data;
my @failure;
my @warning;
my @success;
 
 
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
  printf "\n                                                Daily Object Report                                          \n" if ($display==0);
  printf "Client               Cluster             Status    Level      Size       Started   Duration  Expires\n" if ($display==0);
  printf "======               =======             ======    =====      ====       =======   ========  ======= \n" if ($display==0);
  printf "<TABLE BORDER=1 ALIGN=center><TR BGCOLOR=lightgreen><TD ALIGN=center colspan='10'>Daily Object Report</TD></TR>" if ($display==1);
  printf "<TR BGCOLOR=lightgreen align=center><TD>Client</TD><TD>Cluster</TD><TD>Status</TD><TD>Level</TD><TD>Size (GB)</TD><TD>Data Read (GB)</TD><TD>Started</TD><TD>Duration</TD><TD>Expires</TD></TR>" if ($display==1);
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
    my $sql = "SELECT le.entity_name,
                c.cluster_name,
                jrs.status_name,
                st.name,
                pjre.source_logical_size_bytes,
		pjre.source_delta_size_bytes,
                pjre.start_time_usecs,
                pjre.duration_usecs,
                pjr.snapshot_expiry_time_usecs
                FROM reporting.protection_job_run_entities pjre,
                reporting.cluster c,
                reporting.leaf_entities le,
                reporting.protection_job_runs pjr,
                reporting.protection_jobs pj,
                reporting.backup_schedule bs,
                reporting.schedule_type st,
                reporting.job_run_status jrs
                WHERE pjre.start_time_usecs >= $startTimeUsecs AND
                pjre.entity_id = le.entity_id AND
                pjre.cluster_id = c.cluster_id AND
                pjre.job_run_id = pjr.job_run_id AND
                pjre.job_id = pj.job_id AND
                pj.policy_id = bs.policy_id AND
                pjre.status = jrs.status_id AND
                bs.schedule_type = st.id AND
                pjre.entity_env_type IN (1,2,6,13,17) AND
                pjre.status IN (4,5,6)
                ORDER BY le.entity_name, pjre.start_time_usecs";
    my $sth = $dbh->prepare($sql);
    print "Executing Query\n" if ($debug>=2);
    $sth->execute() or die DBI::errstr;
    while(my @rows=$sth->fetchrow_array){
      print "ROW=$rows[0]\t$rows[1]\t\t$rows[2]\t$rows[3]\t$rows[4]\t$rows[5]\t$rows[6]\t$rows[7]\t$rows[8]\n" if ($debug>=2);
      if($rows[2] eq "Failure"){
        push(@failure, "$rows[0],$rows[1],$rows[2],$rows[3],$rows[4],$rows[5],$rows[6],$rows[7],$rows[8]");
      } elsif($rows[2] eq "Success"){
        push(@success, "$rows[0],$rows[1],$rows[2],$rows[3],$rows[4],$rows[5],$rows[6],$rows[7],$rows[8]");
      } else {
        push(@warning, "$rows[0],$rows[1],$rows[2],$rows[3],$rows[4],$rows[5],$rows[6],$rows[7],$rows[8]");
      }
    }
    $dbh->disconnect();
  }
  foreach(@failure,@warning,@success){
    push(@data, $_);
  }
}
 
sub printReport {
  printf "<HTML><HEAD></HEAD><BODY><Center><H1>$title</H1></CENTER>" if ($display==1);
  printHeader();
  foreach(@data){
    print "Data Line: $_\n" if ($debug==2);
    my @cols=split(",",$_);
    print "Cols Line: $cols[0],$cols[1],$cols[2],$cols[3],$cols[4],$cols[5],$cols[6],$cols[7],$cols[8]\n" if($debug==2);
    my $bgColor;
    my $textColor;
    if($cols[2] eq "Success"){
      #$bgColor='"lightgreen"';
      $bgColor='2ED51A';
      $textColor='black';
    } elsif($cols[2] eq "Failure") {
      #$bgColor='"red"';
      $bgColor='FF3355';
      $textColor='white';
    } else {
      $bgColor='"yellow"';
      $textColor='black';
    }
    my $startTime=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($cols[6]/1000/1000));
    my $expireTime=POSIX::strftime('%m/%d/%Y %I:%M:%S %p',localtime($cols[8]/1000/1000));
    my $expireYear=POSIX::strftime('%m/%d/%Y',localtime($cols[8]/1000/1000));
    if($expireYear == "12/31/1969"){
      $expireTime="Job Running"
    }
    my $duration=int($cols[7]/1000/1000);
    my $hours;
    my $minutes;
    my $seconds;
    if($duration >= 3600){
      $hours=int($duration/3600);
      if($duration-($hours*3600) >= 60){
        $minutes=int(($duration-($hours*3600))/60);
      } else {
        $minutes=0;
      }
      $seconds=int($duration-($hours*3600)-($minutes*60));
    } elsif($duration >= 60){
      $hours=0;
      if($duration >= 60){
        $minutes=int($duration/60);
      } else {
        $minutes=0;
      }
      $seconds=$duration-($minutes*60);
    } else {
      $hours=0;
      $minutes=0;
      $seconds=$duration;
    }
    $cols[4]=$cols[4]/1024/1024/1024;
    $cols[5]=$cols[5]/1024/1024/1024;
    printf "<TR bgcolor=".$bgColor." style=color:".$textColor."><TD>$cols[0]</TD><TD>$cols[1]</TD><TD>$cols[2]</TD><TD>$cols[3]</TD><TD>%d</TD><TD>%d</TD><TD>$startTime</TD><TD>%d Hours %d Minutes %d Seconds</TD><TD>$expireTime</TD></TR>\n",$cols[4],$cols[5],$hours,$minutes,$seconds if ($display==1);
  }
  printf "</TABLE><br/>\n" if ($display==1);
  printf "</BODY></HTML>\n" if ($display==1);
}
 
 
# Main
getToken();
getDbInfo();
gatherData();
printReport();
