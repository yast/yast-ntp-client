#!/usr/bin/perl -w

use ycp;
use Data::Dumper;

open (IN, "ntp_servers.ycp");
my $ok = 0;
my $failed = 0;
my @ok = ();
my @failed = ();
while ($line = <IN>)
{
    chop ($line);
    if ($line =~ /\"address\".*:.*\"(.+)\"/) 
    {
	my $server = $1;
	my $status = system ("sudo /usr/sbin/ntpdate -q $server");
	if ($status == 0)
	{
	    print "$server is accessible.\n";
	    $ok = $ok + 1;
	    push @ok, $server;
	}
	else
	{
	    print "!!! $server is not accessible!!!!!!!!!!!!!!!!!!!!!!!!!!!\n";
	    $failed = $failed + 1;
	    push @failed, $server;
	}
    }
}
close (IN);
print ("$ok servers succeeded.\n");
print ("$failed servers failed.\n");
print ("Passed servers: @ok\n");
print ("Failed servers: @failed\n");


#ycp::Return (\@servers, 1);

