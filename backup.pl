#!/usr/local/bin/perl

# Name: Backup.pl
# Description: Script to run a Cohesity backup via REST API call

use strict;
use REST::Client;
use JSON;
use Getopt::Std;

#Set Environment Variable to no verify certs
$ENV{'PERL_LWP_SSL_VERIFY_HOSTNAME'} = 0;

# Global Variables
my %opts;
my $username='admin';
my $password='Cohe$1ty';
my $domain='LOCAL';
my %jobs;
my %status;


# Subroutines
sub getOptions{
  getopts('dhj:c:', \%opts);
  if(exists $opts{h}){
    helpInfo();
    exit(0);
  }
  if(exists $opts{j} && $opts{j} ne ""){
    print "JobName=$opts{j}\n" if exists $opts{d};
  } else {
    helpInfo();
    exit(0);
  } 
  if(exists $opts{c} && $opts{c} ne ""){
    print "Cluster=$opts{c}\n" if exists $opts{d};
  } else {
    helpInfo();
    exit(0);
  }
}

sub helpInfo{
  printf "usage: $0 -j [JobName1,JobName2] -c [Cluster]
  \t(-h - Help Information)
  \t(-d - Enable Debug)\n";
}

sub getToken {
  printf "Getting Token for: $opts{c}\n" if exists $opts{d};
  my $client=REST::Client->new();
  $client->setHost("https://$opts{c}"); 
  $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
  $client->POST('/irisservices/api/v1/public/accessTokens','{"domain" : "'.$domain.'","username" : "'.$username.'","password" : "'.$password.'"}');
  die $client->responseContent() if( $client->responseCode() >= 300 );
  my $response=decode_json($client->responseContent());
  printf "ResponseCode: ".$client->responseCode()."\n" if exists $opts{d};
  printf "tokenType: ".$response->{'tokenType'}."\ntoken: ".$response->{'accessToken'}."\n" if exists $opts{d};
  return ($response->{'tokenType'}, $response->{'accessToken'});
}

sub findJobId{
  my ($tokenType,$accessToken)=($_[0],$_[1]);
  printf "TokenType: $tokenType\nAccessToken: $accessToken\n" if exists $opts{d}; 
  my $client=REST::Client->new();
  $client->setHost("https://$opts{c}"); 
  $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
  $client->addHeader("Authorization", "$tokenType $accessToken"); #Authorize request
  $client->GET('/irisservices/api/v1/public/protectionJobs?names='.$opts{j});
  die $client->responseContent() if( $client->responseCode() >= 300 );
  my $response=decode_json($client->responseContent());
  printf "ResponseCode: ".$client->responseCode()."\n" if exists $opts{d};
  foreach my $i (@{$response}){
    $jobs{$i->{name}}=$i->{id};
    printf "Job=$i->{name}\nJobId=$i->{id}\n" if exists $opts{d};
  }
}

sub executeJobs{
  my ($tokenType,$accessToken)=($_[0],$_[1]);
  printf "TokenType: $tokenType\nAccessToken: $accessToken\n" if exists $opts{d}; 
  foreach my $i (sort keys %jobs){
    my $client=REST::Client->new();
    $client->setHost("https://$opts{c}"); 
    $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
    $client->addHeader("Authorization", "$tokenType $accessToken"); #Authorize request
    $client->POST('/irisservices/api/v1/public/protectionJobs/run/'.$jobs{$i});
    die $client->responseContent() if( $client->responseCode() >= 300 );
    printf "Job $i executed...\n" if exists $opts{d};
  }
}

sub checkJobStatus{
  my ($tokenType,$accessToken)=($_[0],$_[1]);
  my $status="kAccepted";
  printf "TokenType: $tokenType\nAccessToken: $accessToken\nStatus: $status\n" if exists $opts{d};
  foreach my $i (sort keys %jobs){
    print "1 Job: $i\nStatus: $status\n" if exists $opts{d};
    while(($status eq 'kRunning') || ($status eq 'kAccepted')){
      my $client=REST::Client->new();
      $client->setHost("https://$opts{c}"); 
      $client->addHeader("Accept", "application/json", "Content-Type", "application/json");
      $client->addHeader("Authorization", "$tokenType $accessToken"); #Authorize request
      $client->GET('/irisservices/api/v1/public/protectionRuns?jobId='.$jobs{$i}.'&excludeTasks=true');
      die $client->responseContent() if( $client->responseCode() >= 300 );
      my $response=decode_json($client->responseContent());
      $status=$response->[0]->{'backupRun'}->{'status'};
      print "2 Job: $i\nStatus: $status\n" if exists $opts{d};
      if(($status eq 'kRunning') || ($status eq 'kAccepted')){
        sleep(10);
      }
      print "3 Job: $i\nStatus: $status\n" if exists $opts{d};
    }
  }
}

#Main
getOptions();
my ($tokenType,$accessToken)=getToken();
findJobId($tokenType,$accessToken);
executeJobs($tokenType,$accessToken);
sleep(15);
checkJobStatus($tokenType,$accessToken);

exit(0);
